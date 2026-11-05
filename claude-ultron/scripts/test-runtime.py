"""Exercise the plugin through a real Claude Code binary against a local fake API.

Spends no tokens and touches no real configuration: it uses a dummy key and a
throwaway CLAUDE_CONFIG_DIR, and reads the routing off the requests the binary
actually sends. Rerun it after a Claude Code update, since the mod API the lead
runtime stands on is early access:

    python scripts/test-runtime.py [path-to-claude-binary]
"""
import ctypes
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time

PLUGIN = Path(__file__).resolve().parents[1] / "plugins" / "leads"
CLAUDE = sys.argv[1] if len(sys.argv) > 1 else shutil.which("claude")
assert CLAUDE, "Claude Code CLI is required"

HAIKU_ROLES = ["leads:haiku-code-analyst", "leads:haiku-researcher", "leads:haiku-worker"]
VSCODE = {"extra": {"CLAUDE_CODE_ENTRYPOINT": "claude-vscode"}, "init": {"appendSystemPrompt": "VSCODE-APPEND", "systemPromptSnapshot": True}}
DESKTOP = {"extra": {"CLAUDE_CODE_ENTRYPOINT": "claude-desktop"}, "init": {"appendSystemPrompt": "DESKTOP-APPEND", "systemPromptSnapshot": True}, "args": ["--model", "default", "--effort", "high"]}

failures = []


def check(condition, message):
    print(("  ok    " if condition else "  FAIL  ") + message)
    if not condition:
        failures.append(message)


def sse(event, data):
    return f"event: {event}\ndata: {json.dumps(data)}\n\n".encode()


class FakeApi:
    """Answers `OK`, or one scripted reply when a rule's text is in the last messages.

    `worker_delay` holds every worker's answers, so a test can act while workers run.
    """

    def __init__(self, rules=(), worker_delay=0):
        self.requests, self.rules, self.fired = [], list(rules), set()
        self.worker_delay = worker_delay
        self.lock = threading.Lock()
        fake = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
                if "count_tokens" not in self.path:
                    fake.requests.append(body)
                payload = fake.reply(body)
                tools = body.get("tools") or []
                if fake.worker_delay and tools and not any(t.get("name") == "Agent" for t in tools):
                    time.sleep(fake.worker_delay)
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.send_header("content-length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def do_GET(self):
                self.send_response(200)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", "2")
                self.end_headers()
                self.wfile.write(b"{}")

            def log_message(self, *args):
                pass

        class Server(http.server.ThreadingHTTPServer):
            daemon_threads = True

            def handle_error(self, *args):
                pass

        self.server = Server(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def reply(self, body):
        recent = json.dumps(body.get("messages", [])[-2:])
        rule = None
        if body.get("tools"):
            is_worker = not any(t.get("name") == "Agent" for t in body["tools"])
            with self.lock:
                for index, candidate in enumerate(self.rules):
                    if index not in self.fired and candidate["match"] in recent and candidate.get("worker", False) == is_worker:
                        self.fired.add(index)
                        rule = candidate
                        break
        spawns = rule.get("spawn", []) if rule else []
        calls = [{"name": "Agent", "input": {"prompt": "go", "description": "t", **spawn}} for spawn in spawns] + (rule.get("calls", []) if rule else [])
        stop = "tool_use" if calls else "end_turn"
        out = sse("message_start", {"type": "message_start", "message": {"id": "msg_fake", "type": "message", "role": "assistant", "model": body.get("model"), "content": [], "stop_reason": None, "stop_sequence": None, "usage": {"input_tokens": 1, "output_tokens": 1}}})
        blocks = calls or [None]
        for index, call in enumerate(blocks):
            if call is None:
                out += sse("content_block_start", {"type": "content_block_start", "index": index, "content_block": {"type": "text", "text": ""}})
                out += sse("content_block_delta", {"type": "content_block_delta", "index": index, "delta": {"type": "text_delta", "text": "OK"}})
            else:
                out += sse("content_block_start", {"type": "content_block_start", "index": index, "content_block": {"type": "tool_use", "id": f"toolu_{index}", "name": call["name"], "input": {}}})
                out += sse("content_block_delta", {"type": "content_block_delta", "index": index, "delta": {"type": "input_json_delta", "partial_json": json.dumps(call["input"])}})
            out += sse("content_block_stop", {"type": "content_block_stop", "index": index})
        out += sse("message_delta", {"type": "message_delta", "delta": {"stop_reason": stop, "stop_sequence": None}, "usage": {"output_tokens": 1}})
        return out + sse("message_stop", {"type": "message_stop"})

    def main_requests(self):
        return [r for r in self.requests if any(t.get("name") == "Agent" for t in r.get("tools", []))]

    def worker_requests(self, model):
        return [r for r in self.requests if r.get("model") == model and r.get("tools") and not any(t.get("name") == "Agent" for t in r["tools"])]

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def effort(request):
    return (request.get("output_config") or {}).get("effort")


def newly_listed(request):
    """The agents a request says just became available, apart from text that merely names them."""
    blocks = [block.get("text", "") for message in request.get("messages", []) if isinstance(message.get("content"), list) for block in message["content"] if isinstance(block, dict)]
    return "\n".join(text for text in blocks if "New agent types are now available" in text)


def tool_results(request):
    results = []
    for message in request.get("messages", []):
        if isinstance(message.get("content"), list):
            for block in message["content"]:
                if block.get("type") == "tool_result":
                    content = block.get("content")
                    results.append(content if isinstance(content, str) else " ".join(x.get("text", "") for x in content or []))
    return results


class Harness:
    def __init__(self, root):
        self.config = root / "config"
        self.cwd = root / "work"
        self.config.mkdir()
        self.cwd.mkdir()
        (self.config / ".claude.json").write_text(json.dumps({"customApiKeyResponses": {"rejected": [], "approved": ["dummy-not-a-real-key"]}, "hasCompletedOnboarding": True}), encoding="utf-8")

    def session(self, fake, messages, args=(), init=None, extra=None, timeout=90, wait=2.0):
        env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "ANTHROPIC"))}
        env.update(CLAUDE_CONFIG_DIR=str(self.config), ANTHROPIC_BASE_URL=f"http://127.0.0.1:{fake.port}", ANTHROPIC_API_KEY="dummy-not-a-real-key", CLAUDE_CODE_MAX_RETRIES="0", DISABLE_TELEMETRY="1", **(extra or {}))
        command = [CLAUDE, "--output-format", "stream-json", "--verbose", "--input-format", "stream-json", "--permission-prompt-tool=stdio", "--setting-sources", "user,project,local", "--replay-user-messages", "--no-chrome", "--permission-mode", "acceptEdits", "--plugin-dir", str(PLUGIN), *args]
        process = subprocess.Popen(command, cwd=self.cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, encoding="utf-8", errors="replace")
        session_id, finished = [None], threading.Semaphore(0)

        def send(message):
            process.stdin.write(json.dumps(message) + "\n")
            process.stdin.flush()

        def reader():
            for line in process.stdout:
                try:
                    message = json.loads(line)
                except ValueError:
                    continue
                if message.get("type") == "system" and message.get("subtype") == "init":
                    session_id[0] = message.get("session_id")
                elif message.get("type") == "result":
                    finished.release()
                elif message.get("type") == "control_request" and message.get("request", {}).get("subtype") == "can_use_tool":
                    send({"type": "control_response", "response": {"subtype": "success", "request_id": message["request_id"], "response": {"behavior": "allow", "updatedInput": message["request"].get("input")}}})

        threading.Thread(target=reader, daemon=True).start()
        send({"type": "control_request", "request_id": "init", "request": {"subtype": "initialize", "hooks": None, **(init or {})}})
        time.sleep(0.5)
        for index, message in enumerate(messages):
            if isinstance(message, dict) and "sleep" in message:
                time.sleep(message["sleep"])
                continue
            if isinstance(message, dict) and "queued" in message:
                send({"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": message["queued"]}]}, "parent_tool_use_id": None, "session_id": ""})
                continue
            if isinstance(message, dict) and "subtype" in message:
                send({"type": "control_request", "request_id": f"c{index}", "request": message})
                time.sleep(1)
                continue
            content = message["content"] if isinstance(message, dict) else [{"type": "text", "text": message}]
            send({"type": "user", "message": {"role": "user", "content": content}, "parent_tool_use_id": None, "session_id": ""})
            if not finished.acquire(timeout=timeout):
                check(False, f"no result for {message!r}")
                break
        time.sleep(wait)
        try:
            process.stdin.close()
        except OSError:
            pass
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
        return session_id[0]

    def terminal(self, fake, args, text, settle=9):
        """Type one prompt into a real REPL, and let its turn and any workers finish."""
        env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "ANTHROPIC"))}
        env.update(CLAUDE_CONFIG_DIR=str(self.config), ANTHROPIC_BASE_URL=f"http://127.0.0.1:{fake.port}", ANTHROPIC_API_KEY="dummy-not-a-real-key", CLAUDE_CODE_MAX_RETRIES="0", DISABLE_TELEMETRY="1", DISABLE_AUTOUPDATER="1", TERM="xterm-256color")
        terminal = ConPty([CLAUDE, "--plugin-dir", str(PLUGIN), "--permission-mode", "acceptEdits", *args], self.cwd, env)
        try:
            for _ in range(160):
                if any("for shortcuts" in chunk for chunk in terminal.output) or len("".join(terminal.output)) > 2000:
                    break
                time.sleep(0.25)
            time.sleep(3)
            for character in text:
                terminal.send(character)
                time.sleep(0.02)
            time.sleep(0.3)
            terminal.send("\r")
            time.sleep(settle)
        finally:
            terminal.close()


class ConPty:
    """A real terminal for a process, through Windows' pseudo console: nothing else starts the REPL."""

    def __init__(self, argv, cwd, env):
        from ctypes import wintypes as w

        kernel32 = self.kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

        class Coord(ctypes.Structure):
            _fields_ = [("X", w.SHORT), ("Y", w.SHORT)]

        class StartupInfo(ctypes.Structure):
            _fields_ = [("cb", w.DWORD), ("lpReserved", w.LPWSTR), ("lpDesktop", w.LPWSTR), ("lpTitle", w.LPWSTR), ("dwX", w.DWORD), ("dwY", w.DWORD), ("dwXSize", w.DWORD), ("dwYSize", w.DWORD), ("dwXCountChars", w.DWORD), ("dwYCountChars", w.DWORD), ("dwFillAttribute", w.DWORD), ("dwFlags", w.DWORD), ("wShowWindow", w.WORD), ("cbReserved2", w.WORD), ("lpReserved2", ctypes.c_void_p), ("hStdInput", w.HANDLE), ("hStdOutput", w.HANDLE), ("hStdError", w.HANDLE), ("lpAttributeList", ctypes.c_void_p)]

        class ProcessInfo(ctypes.Structure):
            _fields_ = [("hProcess", w.HANDLE), ("hThread", w.HANDLE), ("dwProcessId", w.DWORD), ("dwThreadId", w.DWORD)]

        kernel32.CreatePseudoConsole.argtypes = [Coord, w.HANDLE, w.HANDLE, w.DWORD, ctypes.POINTER(ctypes.c_void_p)]
        kernel32.CreatePseudoConsole.restype = ctypes.c_long
        kernel32.ClosePseudoConsole.argtypes = [ctypes.c_void_p]
        kernel32.ClosePseudoConsole.restype = None
        kernel32.CreatePipe.argtypes = [ctypes.POINTER(w.HANDLE), ctypes.POINTER(w.HANDLE), ctypes.c_void_p, w.DWORD]
        kernel32.InitializeProcThreadAttributeList.argtypes = [ctypes.c_void_p, w.DWORD, w.DWORD, ctypes.POINTER(ctypes.c_size_t)]
        kernel32.UpdateProcThreadAttribute.argtypes = [ctypes.c_void_p, w.DWORD, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p]
        kernel32.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, w.BOOL, w.DWORD, ctypes.c_void_p, w.LPCWSTR, ctypes.c_void_p, ctypes.POINTER(ProcessInfo)]
        kernel32.ReadFile.argtypes = [w.HANDLE, ctypes.c_void_p, w.DWORD, ctypes.POINTER(w.DWORD), ctypes.c_void_p]
        kernel32.WriteFile.argtypes = [w.HANDLE, ctypes.c_void_p, w.DWORD, ctypes.POINTER(w.DWORD), ctypes.c_void_p]
        kernel32.CloseHandle.argtypes = [w.HANDLE]
        kernel32.TerminateProcess.argtypes = [w.HANDLE, w.UINT]
        kernel32.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
        in_read, self.in_write, self.out_read, out_write = w.HANDLE(), w.HANDLE(), w.HANDLE(), w.HANDLE()
        assert kernel32.CreatePipe(ctypes.byref(in_read), ctypes.byref(self.in_write), None, 0)
        assert kernel32.CreatePipe(ctypes.byref(self.out_read), ctypes.byref(out_write), None, 0)
        self.console = ctypes.c_void_p()
        assert kernel32.CreatePseudoConsole(Coord(140, 45), in_read, out_write, 0, ctypes.byref(self.console)) == 0
        kernel32.CloseHandle(in_read)
        kernel32.CloseHandle(out_write)
        size = ctypes.c_size_t()
        kernel32.InitializeProcThreadAttributeList(None, 1, 0, ctypes.byref(size))
        attributes = ctypes.create_string_buffer(size.value)
        assert kernel32.InitializeProcThreadAttributeList(attributes, 1, 0, ctypes.byref(size))
        assert kernel32.UpdateProcThreadAttribute(attributes, 0, 0x00020016, self.console, ctypes.sizeof(ctypes.c_void_p), None, None)
        info = StartupInfo()
        info.cb = ctypes.sizeof(StartupInfo)
        info.dwFlags = 0x00000100
        info.lpAttributeList = ctypes.cast(attributes, ctypes.c_void_p)
        block = "".join(f"{k}={v}\0" for k, v in sorted(env.items())) + "\0"
        environment = ctypes.create_unicode_buffer(block, len(block))
        command = ctypes.create_unicode_buffer(subprocess.list2cmdline(argv))
        self.process = ProcessInfo()
        assert kernel32.CreateProcessW(None, command, None, None, False, 0x00080000 | 0x00000400, environment, str(cwd), ctypes.byref(info), ctypes.byref(self.process)), ctypes.get_last_error()
        self.output = []
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        buffer = ctypes.create_string_buffer(65536)
        count = ctypes.c_ulong()
        while self.kernel32.ReadFile(self.out_read, buffer, 65536, ctypes.byref(count), None) and count.value:
            self.output.append(buffer.raw[: count.value].decode("utf-8", "replace"))

    def send(self, text):
        data = text.encode("utf-8")
        self.kernel32.WriteFile(self.in_write, data, len(data), ctypes.byref(ctypes.c_ulong()), None)

    def close(self):
        self.kernel32.TerminateProcess(self.process.hProcess, 0)
        self.kernel32.WaitForSingleObject(self.process.hProcess, 3000)
        self.kernel32.ClosePseudoConsole(self.console)


def main():
    print("Binary:", CLAUDE, subprocess.run([CLAUDE, "--version"], capture_output=True, text=True).stdout.strip())
    root = Path(tempfile.mkdtemp(prefix="claude-ultron-runtime-"))
    harness = Harness(root)
    try:
        print("Plain session")
        fake = FakeApi()
        harness.session(fake, ["hello"], args=["--model", "claude-opus-5-5"])
        fake.close()
        request = fake.main_requests()[0]
        text = json.dumps(request)
        check(request["model"] == "claude-opus-5-5" and "You are Ultron" not in text, "no lead is applied")
        check("leads:" + "haiku-worker" not in text and "leads:opus-specialist" not in text and "leads:ultron:" not in text, "plugin agents are not listed")
        check("Make Ultron" not in text, "lead skills add nothing to the model's context")

        print("@ultron from the VS Code shape: first-turn delegation, then a follow-up")
        fake = FakeApi([{"match": "fix the bug", "spawn": [
            {"subagent_type": "leads:haiku-worker"},
            {"subagent_type": "leads:sonnet-worker"},
            {"subagent_type": "leads:opus-specialist"},
            {"subagent_type": "leads:edith"},
            {"subagent_type": "Explore"},
            {"subagent_type": "leads:sonnet-worker", "model": "haiku"},
            {"subagent_type": "leads:haiku-worker", "effort": "low"},
            {"prompt": "fork me"},
        ]}])
        harness.session(fake, ["@ultron fix the bug", "follow up"], **VSCODE)
        fake.close()
        mains = fake.main_requests()
        check(all(r["model"] == "claude-opus-5-5" and effort(r) == "xhigh" for r in mains), "every main request is Opus 5.5 at xhigh")
        check("You are Ultron" in json.dumps(mains[0]), "the contract reaches the first request")
        check("VSCODE-APPEND" in json.dumps(mains[0].get("system")), "the host's appended prompt stays")
        results = tool_results(mains[-1])
        launched = [r for r in results if "launched" in r.lower()]
        refused = [r for r in results if "may delegate only" in r or "owns" in r]
        check(len(launched) == 3, f"the three allowed workers launch ({len(launched)})")
        check(len(refused) == 5, f"off-list, fork, and per-call model or effort are refused ({len(refused)})")
        for model, level in (("claude-haiku-5-5", "max"), ("claude-sonnet-5-5", "xhigh")):
            workers = fake.worker_requests(model)
            check(bool(workers) and all(effort(r) == level for r in workers), f"worker runs on {model} at {level}")
        specialist = [r for r in fake.requests if r.get("model") == "claude-opus-5-5" and r.get("tools") and not any(t.get("name") == "Agent" for t in r["tools"])]
        check(bool(specialist) and effort(specialist[0]) == "xhigh", "specialist runs on Opus 5.5 at xhigh without the Agent tool")
        offered = newly_listed(mains[-1])
        check("leads:haiku-researcher" in offered and "leads:opus-specialist" in offered and "leads:ultron" not in offered and "leads:edith" not in offered, "the follow-up lists the lead's workers, and no lead")

        print("Skills from the desktop shape, past its --model and --effort flags")
        fake = FakeApi([{"match": "build it", "spawn": [{"subagent_type": "leads:opus-specialist"}, {"subagent_type": "leads:sonnet-worker"}]}])
        harness.session(fake, ["/jarvis build it", "follow up", "@edith small thing", "next", "/lead-off", "plain again"], **DESKTOP)
        fake.close()
        mains = fake.main_requests()
        check("You are Jarvis" in json.dumps(mains[0]["messages"]) and "agents/jarvis.md" not in json.dumps(mains[0]["messages"]), "/jarvis carries the contract, so the model reads no files")
        models = [(r["model"], effort(r)) for r in mains]
        check(models[0] == ("claude-sonnet-5-5", "xhigh"), f"/jarvis runs on Sonnet 5.5 at xhigh ({models[0]})")
        check(("claude-haiku-5-5", "max") in models, "@edith switches to Haiku 5.5 at max")
        check(any("You are Edith" in json.dumps(r) for r in mains), "the new lead's contract arrives")
        check(models[-1][0] == "claude-opus-5-5" and models[-1][1] == "high", f"/lead-off returns to the session's model and effort ({models[-1]})")
        jarvis_results = " ".join(r for m in mains for r in tool_results(m))
        check("may delegate only" in jarvis_results and bool(fake.worker_requests("claude-sonnet-5-5")) and not fake.worker_requests("claude-opus-5-5"), "Jarvis keeps Sonnet and is refused the Opus specialist")

        print("Edith cannot reach Sonnet")
        fake = FakeApi([{"match": "tidy up", "spawn": [{"subagent_type": "leads:sonnet-worker"}, {"subagent_type": "leads:haiku-researcher"}]}])
        harness.session(fake, ["@edith tidy up"], **VSCODE)
        fake.close()
        results = tool_results(fake.main_requests()[-1])
        check(any("may delegate only" in r for r in results) and any("launched" in r.lower() for r in results), "sonnet-worker is refused and a Haiku role runs")
        check(not fake.worker_requests("claude-sonnet-5-5"), "no request reaches Sonnet")

        print("Native --agent, bare and scoped, and the agent setting")
        for name, args in (("--agent ultron", ["--agent", "ultron"]), ("--agent leads:ultron", ["--agent", "leads:ultron"]), ("agent setting", ["--settings", json.dumps({"agent": "leads:ultron"})])):
            fake = FakeApi([{"match": "go now", "spawn": [{"subagent_type": "leads:haiku-worker"}, {"subagent_type": "leads:edith"}]}])
            harness.session(fake, ["go now"], args=args)
            fake.close()
            mains = fake.main_requests()
            check(all(r["model"] == "claude-opus-5-5" and effort(r) == "xhigh" for r in mains), f"{name}: Opus 5.5 at xhigh")
            check("You are Ultron" in json.dumps(mains[0].get("system")) and "You are Ultron" not in json.dumps(mains[0]["messages"]), f"{name}: the contract is the system prompt, once")
            results = tool_results(mains[-1])
            check(any("may delegate only" in r for r in results), f"{name}: off-list agents are refused")
            check(bool(fake.worker_requests("claude-haiku-5-5")), f"{name}: allowed worker runs")

        print("Resume keeps the lead")
        fake = FakeApi()
        session_id = harness.session(fake, ["@jarvis one"], **DESKTOP)
        fake.close()
        fake = FakeApi()
        harness.session(fake, ["after resume"], args=["--resume", session_id, "--model", "default"], extra=DESKTOP["extra"], init=DESKTOP["init"])
        fake.close()
        check(fake.main_requests()[0]["model"] == "claude-sonnet-5-5", "resumed session stays on Jarvis's model")

        print("Compaction keeps the contract")
        fake = FakeApi()
        harness.session(fake, ["@edith one", "/compact", "after compact"], **VSCODE)
        fake.close()
        check("You are Edith" in json.dumps(fake.main_requests()[-1]), "the contract survives /compact")
        fake = FakeApi()
        harness.session(fake, ["/jarvis one", "/edith two", "/compact", "after compact"], **VSCODE)
        fake.close()
        last = json.dumps(fake.main_requests()[-1])
        check(last.count("You are Edith") == 1 and "You are Jarvis" not in last, "after /compact the skill route holds the active contract, once, and no stale one")

        print("A model the person picks mid-chat stands")
        fake = FakeApi()
        harness.session(fake, ["@ultron one", {"subtype": "set_model", "model": "haiku"}, "two"], **VSCODE)
        fake.close()
        check(fake.main_requests()[-1]["model"] == "claude-haiku-5-5", "the picker change is respected")

        print("Picking the lead's own model keeps its effort")
        fake = FakeApi()
        harness.session(fake, ["@ultron one", {"subtype": "set_model", "model": "claude-opus-5-5"}, "two"], args=["--model", "claude-sonnet-5-5", "--effort", "medium"])
        fake.close()
        check((fake.main_requests()[-1]["model"], effort(fake.main_requests()[-1])) == ("claude-opus-5-5", "xhigh"), "Opus 5.5 stays at xhigh")

        print("A lead started with --agent survives a bare resume and a continue")
        for name, resume in (("--resume", lambda sid: ["--resume", sid]), ("--continue", lambda sid: ["--continue"])):
            fake = FakeApi()
            session_id = harness.session(fake, ["one"], args=["--agent", "leads:ultron", "--model", "claude-opus-5-5", "--effort", "xhigh"])
            fake.close()
            fake = FakeApi([{"match": "after", "spawn": [{"subagent_type": "leads:haiku-worker"}, {"subagent_type": "Explore"}]}])
            harness.session(fake, ["after"], args=resume(session_id))
            fake.close()
            mains = fake.main_requests()
            check(all(effort(r) == "xhigh" for r in mains), f"{name}: stays at xhigh")
            results = tool_results(mains[-1])
            check(any("may delegate only" in r for r in results) and bool(fake.worker_requests("claude-haiku-5-5")), f"{name}: its worker runs and off-list agents are refused")

        print("A forked chat keeps its lead")
        for route in ("@jarvis one", "/jarvis one"):
            fake = FakeApi()
            session_id = harness.session(fake, [route], args=["--model", "claude-opus-5-5", "--effort", "high"])
            fake.close()
            fake = FakeApi([{"match": "after", "spawn": [{"subagent_type": "leads:haiku-worker"}]}])
            harness.session(fake, ["after"], args=["--resume", session_id, "--fork-session", "--model", "claude-opus-5-5", "--effort", "high"])
            fake.close()
            mains = fake.main_requests()
            check(all((r["model"], effort(r)) == ("claude-sonnet-5-5", "xhigh") for r in mains), f"{route}: the fork stays on Sonnet 5.5 at xhigh")
            check(bool(fake.worker_requests("claude-haiku-5-5")), f"{route}: the fork's worker runs")

        print("A process that only inherited the agent variable is not a lead")
        fake = FakeApi([{"match": "nested", "spawn": [{"subagent_type": "Explore"}]}])
        harness.session(fake, ["nested"], args=["--model", "claude-haiku-5-5"], extra={"CLAUDE_CODE_AGENT": "ultron"})
        fake.close()
        mains = fake.main_requests()
        check(mains[0]["model"] == "claude-haiku-5-5", "its model stands")
        check(not any("may delegate only" in r for r in tool_results(mains[-1])), "its delegation is not limited")

        print("A person's own agent of a lead's name is left alone")
        agents = harness.cwd / ".claude" / "agents"
        agents.mkdir(parents=True)
        (agents / "jarvis.md").write_text("---\nname: jarvis\ndescription: mine\nmodel: claude-haiku-5-5\n---\nYou are my own agent.\n", encoding="utf-8")
        fake = FakeApi()
        harness.session(fake, ["one"], args=["--agent", "jarvis"])
        fake.close()
        (agents / "jarvis.md").unlink()
        mains = fake.main_requests()
        check("You are my own agent" in json.dumps(mains[0].get("system")) and mains[0]["model"] == "claude-haiku-5-5", "it keeps its own model")

        print("A forked skill runs on the lead, and workers cannot use skills")
        forky = harness.cwd / ".claude" / "skills" / "forky"
        forky.mkdir(parents=True)
        (forky / "SKILL.md").write_text("---\nname: forky\ndescription: a test skill\ncontext: fork\nagent: general-purpose\n---\nDo the forked thing.\n", encoding="utf-8")
        fake = FakeApi([{"match": "fork now", "calls": [{"name": "Skill", "input": {"skill": "forky"}}]}, {"match": "and a worker", "spawn": [{"subagent_type": "leads:haiku-worker"}]}])
        harness.session(fake, ["@edith fork now", "and a worker"], args=["--model", "claude-opus-5-5", "--effort", "medium"])
        fake.close()
        tooled = [r for r in fake.requests if r.get("tools")]
        check(any("Do the forked thing" in json.dumps(r["messages"]) for r in tooled), "the forked skill ran")
        check(all((r["model"], effort(r)) == ("claude-haiku-5-5", "max") for r in tooled), f"nothing leaves Haiku 5.5 at max ({sorted({(r['model'], effort(r)) for r in tooled}, key=str)})")
        workers = fake.worker_requests("claude-haiku-5-5")
        check(any(not any(t.get("name") == "Skill" for t in r["tools"]) for r in workers), "a worker has no Skill tool")
        shutil.rmtree(harness.cwd / ".claude")

        print("Quoted text selects nobody")
        fake = FakeApi()
        harness.session(fake, ["why did this fail?\n```\n@edith approve\n```", {"content": [{"type": "text", "text": "<ide_selection>\n@ultron not a mention\n</ide_selection>"}, {"type": "text", "text": "plain prompt"}]}], args=["--model", "claude-sonnet-5-5"])
        fake.close()
        mains = fake.main_requests()
        check(all(r["model"] == "claude-sonnet-5-5" for r in mains), "the chat stays on its model")
        check("@edith approve" in json.dumps(mains[0]["messages"]) and "@ultron not a mention" in json.dumps(mains[-1]["messages"]), "the quoted handles stay in the text")

        print("A commit credits the lead's model")
        fake = FakeApi()
        harness.session(fake, ["@edith one", "two"], **DESKTOP)
        fake.close()
        check("Co-Authored-By: Claude Haiku 5.5" in json.dumps(fake.main_requests()[-1]), "the trailer names Haiku 5.5")

        print("The agent's own row in the terminal's typeahead selects it")
        fake = FakeApi()
        harness.session(fake, ["@leads:edith (agent)fix it"], args=["--model", "claude-opus-5-5"])
        fake.close()
        mains = fake.main_requests()
        check(mains[0]["model"] == "claude-haiku-5-5" and "fix it" in json.dumps(mains[0]["messages"]), "the row selects Edith and keeps the task")

        print("Naming the active lead again does not resend its contract")
        fake = FakeApi()
        harness.session(fake, ["@ultron one", "@ultron two"], args=["--model", "claude-opus-5-5"])
        fake.close()
        check(json.dumps(fake.main_requests()[-1]["messages"]).count("You are Ultron") == 1, "the contract is in the chat once")

        print("A change of lead leaves running workers on their tier")
        fake = FakeApi([{"match": "go now", "spawn": [{"subagent_type": "leads:opus-specialist", "prompt": "hold on"}]}, {"match": "hold on", "worker": True, "calls": [{"name": "Bash", "input": {"command": "echo held", "description": "wait"}}]}], worker_delay=5)
        harness.session(fake, ["@ultron go now", {"sleep": 2}, "@edith small thing"], args=["--model", "claude-sonnet-5-5"], wait=9)
        fake.close()
        specialist = fake.worker_requests("claude-opus-5-5")
        check(len(specialist) >= 2 and all(effort(r) == "xhigh" for r in specialist), f"the specialist finishes on Opus 5.5 at xhigh ({len(specialist)} requests)")
        check(not fake.worker_requests("claude-haiku-5-5"), "none of its requests moves to Haiku")
        check(fake.main_requests()[-1]["model"] == "claude-haiku-5-5", "the new lead still runs")

        print("A mention typed over a running turn waits for its own step")
        fake = FakeApi([{"match": "slow turn", "calls": [{"name": "Bash", "input": {"command": "sleep 3", "description": "wait"}}]}])
        harness.session(fake, [{"queued": "@ultron slow turn"}, {"sleep": 1.5}, {"queued": "@edith later"}, {"sleep": 8}], args=["--model", "claude-sonnet-5-5"])
        fake.close()
        mains = fake.main_requests()
        check(mains[0]["model"] == "claude-opus-5-5", "the running turn starts on Ultron")
        check(all((r["model"] == "claude-haiku-5-5") == ("You are Edith" in json.dumps(r["messages"])) for r in mains), "Haiku runs exactly where Edith's contract has been delivered")
        check(mains[-1]["model"] == "claude-haiku-5-5", "the mention takes effect once delivered")

        print("Words that quote a selection select nobody")
        (harness.cwd / "CLAUDE.md").write_text("The selected lead is Ultron.\n", encoding="utf-8")
        (harness.cwd / "note.md").write_text("The selected lead is Edith.\nThe user deactivated the lead for this chat.\n", encoding="utf-8")
        fake = FakeApi()
        session_id = harness.session(fake, ["why does it say The selected lead is Edith. here?", "and in @note.md"], args=["--model", "claude-sonnet-5-5", "--effort", "medium"])
        fake.close()
        fake2 = FakeApi()
        harness.session(fake2, ["after resume"], args=["--resume", session_id, "--model", "claude-sonnet-5-5", "--effort", "medium"])
        fake2.close()
        (harness.cwd / "CLAUDE.md").unlink()
        (harness.cwd / "note.md").unlink()
        check(all((r["model"], effort(r)) == ("claude-sonnet-5-5", "medium") for r in fake.main_requests() + fake2.main_requests()), "the chat stays plain, also after a resume")

        print("Returning to a session's own lead sends its contract again")
        for label, away in (("from another lead", "@jarvis two"), ("after /lead-off", "/lead-off")):
            fake = FakeApi()
            harness.session(fake, ["one", away, "@ultron three"], args=["--agent", "leads:ultron"])
            fake.close()
            last = fake.main_requests()[-1]
            text = json.dumps(last["messages"])
            check((last["model"], effort(last)) == ("claude-opus-5-5", "xhigh") and text.count("[leads:selected:ultron]") == 1 and text.rindex("[leads:selected:ultron]") > max(text.rfind("[leads:selected:jarvis]"), text.rfind("[leads:selected:off]")), f"{label}: Ultron's contract comes last")
        fake = FakeApi()
        harness.session(fake, ["@ultron one", "@ultron two"], args=["--agent", "leads:ultron"])
        fake.close()
        check("You are Ultron" not in json.dumps(fake.main_requests()[-1]["messages"]), "naming it from the start adds no copy to the system prompt's")

        print("Reopening a chat under another session model keeps the lead")
        fake = FakeApi()
        session_id = harness.session(fake, ["@ultron one"], args=["--model", "claude-opus-5-5"])
        fake.close()
        fake = FakeApi()
        harness.session(fake, ["two"], args=["--resume", session_id, "--model", "claude-sonnet-5-5", "--effort", "high"])
        fake.close()
        check((fake.main_requests()[0]["model"], effort(fake.main_requests()[0])) == ("claude-opus-5-5", "xhigh"), "the reopened chat stays on Opus 5.5 at xhigh")
        fake = FakeApi()
        session_id = harness.session(fake, ["@ultron one", {"subtype": "set_model", "model": "haiku"}, "two"], **VSCODE)
        fake.close()
        fake = FakeApi()
        harness.session(fake, ["three"], args=["--resume", session_id, "--model", "haiku"], extra=VSCODE["extra"], init=VSCODE["init"])
        fake.close()
        check(fake.main_requests()[0]["model"] == "claude-haiku-5-5", "a model the person had picked still stands")

        print("An older chat is not taken over")
        fake = FakeApi()
        session_id = harness.session(fake, ["plain one"], args=["--model", "claude-sonnet-5-5", "--effort", "medium"])
        fake.close()
        fake = FakeApi()
        harness.session(fake, ["two"], args=["--resume", session_id, "--model", "claude-sonnet-5-5", "--effort", "medium", "--settings", json.dumps({"agent": "leads:edith"})])
        fake.close()
        check((fake.main_requests()[0]["model"], effort(fake.main_requests()[0])) == ("claude-sonnet-5-5", "medium"), "the agent setting leaves it plain")
        fake = FakeApi()
        harness.session(fake, ["two"], args=["--resume", session_id, "--agent", "leads:ultron"])
        fake.close()
        check("You are Ultron" in json.dumps(fake.main_requests()[0]["messages"]), "an explicit --agent brings the contract along")

        print("A bare resume of a lead's chat, then /clear")
        fake = FakeApi()
        session_id = harness.session(fake, ["one"], args=["--agent", "leads:ultron", "--model", "claude-opus-5-5", "--effort", "xhigh"])
        fake.close()
        fake = FakeApi([{"match": "after", "spawn": [{"subagent_type": "leads:haiku-worker"}]}])
        harness.session(fake, ["/clear", "after"], args=["--resume", session_id])
        fake.close()
        check(effort(fake.main_requests()[-1]) == "xhigh" and bool(fake.worker_requests("claude-haiku-5-5")), "the lead stays, as its prompt does")

        print("After a compaction")
        fake = FakeApi()
        harness.session(fake, ["/lead-off", "@jarvis two", "/compact", "three"], **VSCODE)
        fake.close()
        last = json.dumps(fake.main_requests()[-1])
        check(last.count("You are Jarvis") == 1 and "Stop following any lead contract" not in last, "the contract stands alone, without lead-off's repeat")
        fake = FakeApi()
        session_id = harness.session(fake, ["@jarvis one", "/compact", "@edith two"], args=["--model", "claude-opus-5-5"])
        fake.close()
        fake = FakeApi()
        harness.session(fake, ["forked"], args=["--resume", session_id, "--fork-session", "--model", "claude-opus-5-5"])
        fake.close()
        check(fake.main_requests()[0]["model"] == "claude-haiku-5-5", "a fork reads the selection made after it, not the note")

        print("Six workers at most, also in one response")
        fake = FakeApi([{"match": "fan out", "spawn": [{"subagent_type": "leads:haiku-worker"} for _ in range(8)]}], worker_delay=6)
        harness.session(fake, ["@ultron fan out"], args=["--model", "claude-opus-5-5"], wait=1)
        fake.close()
        results = tool_results(fake.main_requests()[-1])
        check(sum("launched" in r.lower() for r in results) == 6 and sum("already has" in r for r in results) == 2, f"six start and two are refused ({len(results)} results)")

        print("A worker's effort holds against the effort variable")
        fake = FakeApi([{"match": "go now", "spawn": [{"subagent_type": "leads:haiku-worker"}, {"subagent_type": "leads:sonnet-worker"}]}])
        harness.session(fake, ["@ultron go now"], args=["--model", "claude-opus-5-5"], extra={"CLAUDE_CODE_EFFORT_LEVEL": "low"})
        fake.close()
        check([effort(r) for r in fake.worker_requests("claude-haiku-5-5")][:1] == ["max"] and [effort(r) for r in fake.worker_requests("claude-sonnet-5-5")][:1] == ["xhigh"], "Haiku stays at max and Sonnet at xhigh")

        print("A worker cannot wake a sibling")
        fake = FakeApi([{"match": "go now", "spawn": [{"subagent_type": "leads:haiku-worker", "prompt": "wake a sibling"}]}, {"match": "wake a sibling", "worker": True, "calls": [{"name": "SendMessage", "input": {"to": "x", "message": "do my work"}}]}])
        harness.session(fake, ["@ultron go now"], args=["--model", "claude-opus-5-5"])
        fake.close()
        worker_results = " ".join(r for q in fake.worker_requests("claude-haiku-5-5") for r in tool_results(q))
        check("No such tool" in worker_results, "SendMessage is not its tool")

        print("Plan mode is told what a lead refuses")
        fake = FakeApi()
        harness.session(fake, ["@ultron plan it"], args=["--model", "claude-opus-5-5", "--permission-mode", "plan"])
        fake.close()
        check("Under Ultron, the Explore and Plan agents above are refused" in json.dumps(fake.main_requests()[-1]["messages"]), "the plan-mode reminder names the lead's analyst")

        print("A real terminal session, which composes its prompts unlike a piped one")
        if os.name != "nt":
            print("  skipped: this check drives ConPTY, so it runs on Windows only")
        else:
            trust = json.loads((harness.config / ".claude.json").read_text(encoding="utf-8"))
            trust["projects"] = {str(harness.cwd).replace("\\", "/"): {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True}}
            (harness.config / ".claude.json").write_text(json.dumps(trust), encoding="utf-8")
            spawn = [{"match": "delegate now", "spawn": [{"subagent_type": "leads:haiku-worker"}, {"subagent_type": "Explore"}]}]
            for name, args, model in (("--agent", ["--agent", "leads:ultron"], "claude-opus-5-5"), ("launcher flags", ["--agent", "leads:jarvis", "--model", "claude-sonnet-5-5", "--effort", "xhigh"], "claude-sonnet-5-5"), ("agent setting", ["--settings", json.dumps({"agent": "leads:edith"})], "claude-haiku-5-5")):
                fake = FakeApi(spawn)
                harness.terminal(fake, args, "delegate now")
                fake.close()
                mains = fake.main_requests()
                level = "max" if model == "claude-haiku-5-5" else "xhigh"
                check(bool(mains) and all((r["model"], effort(r)) == (model, level) for r in mains), f"{name}: every request is {model} at {level}")
                results = tool_results(mains[-1]) if mains else []
                check(any("launched" in r.lower() for r in results) and any("may delegate only" in r for r in results), f"{name}: its worker runs and Explore is refused")
            fake = FakeApi()
            harness.terminal(fake, ["--agent", "leads:ultron"], "first")
            fake.close()
            fake = FakeApi(spawn)
            harness.terminal(fake, ["--continue"], "delegate now")
            fake.close()
            mains = fake.main_requests()
            check(bool(mains) and all(effort(r) == "xhigh" for r in mains) and any("may delegate only" in r for r in tool_results(mains[-1])), "--continue keeps the lead")
            fake = FakeApi(spawn)
            harness.terminal(fake, ["--model", "claude-sonnet-5-5"], "delegate now")
            fake.close()
            mains = fake.main_requests()
            check(bool(mains) and mains[0]["model"] == "claude-sonnet-5-5" and "You are Ultron" not in json.dumps(mains[0].get("system")) and not any("may delegate only" in r for r in tool_results(mains[-1])), "a plain session stays plain")
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print()
    if failures:
        print(f"{len(failures)} check(s) failed.")
        sys.exit(1)
    print("All runtime checks passed.")


main()
