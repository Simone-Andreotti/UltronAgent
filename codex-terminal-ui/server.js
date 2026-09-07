const fs = require("node:fs");
const fsp = require("node:fs/promises");
const { spawn } = require("node:child_process");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const readline = require("node:readline");
const pty = require("node-pty");
const { WebSocketServer, WebSocket } = require("ws");

const APP_ROOT = __dirname;
const LAUNCHER_ROOT = path.resolve(APP_ROOT, "..");
const SESSION_ROOT = path.join(process.env.CODEX_HOME || path.join(os.homedir(), ".codex"), "sessions");
const HOST = "127.0.0.1";
const PORT = Number(process.env.PORT || 4317);
const AGENTS = new Set(["edith", "jarvis", "ultron"]);
const MIME = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".map": "application/json",
  ".woff2": "font/woff2"
};
const ASSETS = new Map([
  ["/vendor/xterm.css", path.join(APP_ROOT, "node_modules", "@xterm", "xterm", "css", "xterm.css")],
  ["/vendor/xterm.js", path.join(APP_ROOT, "node_modules", "@xterm", "xterm", "lib", "xterm.js")],
  ["/vendor/xterm-fit.js", path.join(APP_ROOT, "node_modules", "@xterm", "addon-fit", "lib", "addon-fit.js")]
]);

function clamp(value, min, max, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.min(max, Math.max(min, Math.round(number))) : fallback;
}

function validateAgent(agent) {
  if (!AGENTS.has(agent)) throw new Error("Unknown agent");
  return agent;
}

function validateWorkspace(value) {
  if (typeof value !== "string" || !value.trim() || !path.isAbsolute(value)) throw new Error("Choose an absolute workspace folder");
  let workspace;
  try { workspace = fs.realpathSync.native(path.resolve(value)); } catch { throw new Error("Workspace is unavailable"); }
  if (!fs.statSync(workspace).isDirectory()) throw new Error("Workspace must be a folder");
  return workspace;
}

function workspaceRoots() {
  if (process.platform !== "win32") return [path.parse(os.homedir()).root];
  return Array.from({ length: 26 }, (_, index) => `${String.fromCharCode(65 + index)}:\\`).filter((root) => fs.existsSync(root));
}

async function listDirectories(value) {
  if (!value) return { path: null, parent: null, roots: workspaceRoots(), directories: [] };
  const workspace = validateWorkspace(value);
  let entries;
  try { entries = await fsp.readdir(workspace, { withFileTypes: true }); } catch { throw new Error("Folder cannot be read"); }
  const directories = [];
  for (const entry of entries) {
    if (entry.isDirectory()) directories.push(entry.name);
    else if (entry.isSymbolicLink()) {
      try { if ((await fsp.stat(path.join(workspace, entry.name))).isDirectory()) directories.push(entry.name); } catch {}
    }
  }
  directories.sort((left, right) => left.localeCompare(right, undefined, { sensitivity: "base" }));
  const parent = path.dirname(workspace);
  return { path: workspace, parent: parent === workspace ? null : parent, roots: workspaceRoots(), directories };
}

function normalizeStatus(info, eventLimits) {
  const limits = eventLimits || info?.rate_limits;
  if (!limits) return null;
  const map = (value) => value && ({
    used: value.used_percent,
    available: Math.max(0, 100 - value.used_percent),
    windowMinutes: value.window_minutes,
    resetsAt: value.resets_at
  });
  return {
    plan: limits.plan_type || "unknown",
    context: info.model_context_window ? {
      used: info.total_token_usage?.total_tokens || 0,
      size: info.model_context_window
    } : null,
    primary: map(limits.primary),
    secondary: map(limits.secondary),
    credits: limits.credits || null,
    updatedAt: Date.now()
  };
}

function normalizeLiveStatus(result) {
  const limits = result?.rateLimitsByLimitId?.codex || result?.rateLimits;
  if (!limits) return null;
  const map = (value) => value && ({
    used: value.usedPercent,
    available: Math.max(0, 100 - value.usedPercent),
    windowMinutes: value.windowDurationMins,
    resetsAt: value.resetsAt
  });
  const resetCredits = result.rateLimitResetCredits;
  const expiries = resetCredits?.credits?.filter((credit) => credit.status === "available" && credit.expiresAt).map((credit) => credit.expiresAt) || [];
  return {
    plan: limits.planType || "unknown",
    context: null,
    primary: map(limits.primary),
    secondary: map(limits.secondary),
    credits: limits.credits || null,
    resetsAvailable: resetCredits?.availableCount ?? null,
    resetsExpireAt: expiries.length ? Math.min(...expiries) : null,
    updatedAt: Date.now()
  };
}

function readLiveUsage(timeoutMs = 12000) {
  return new Promise((resolve, reject) => {
    const processHandle = spawn(process.platform === "win32" ? "codex.exe" : "codex", ["app-server", "--stdio"], {
      cwd: LAUNCHER_ROOT,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true
    });
    const lines = readline.createInterface({ input: processHandle.stdout });
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      lines.close();
      processHandle.kill();
      error ? reject(error) : resolve(value);
    };
    const timer = setTimeout(() => finish(new Error("Codex usage request timed out")), timeoutMs);
    processHandle.once("error", (error) => finish(error));
    processHandle.once("exit", (code) => { if (!settled) finish(new Error(`Codex usage process exited (${code})`)); });
    lines.on("line", (line) => {
      let message;
      try { message = JSON.parse(line); } catch { return; }
      if (message.id === 1 && message.result) {
        processHandle.stdin.write('{"method":"initialized"}\n');
        processHandle.stdin.write('{"id":2,"method":"account/rateLimits/read"}\n');
      } else if (message.id === 2) {
        if (message.error) finish(new Error(message.error.message || "Codex usage request failed"));
        else finish(null, normalizeLiveStatus(message.result));
      }
    });
    processHandle.stdin.write('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-terminal-ui","version":"1.0.0"},"capabilities":{"experimentalApi":true}}}\n');
  });
}

function contentText(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.map((part) => part?.text || part?.input_text || part?.output_text || "").filter(Boolean).join("\n");
}

function sessionLabel(value) {
  const label = String(value || "").replace(/\s+/g, " ").trim();
  return !label || /^# AGENTS\.md instructions\b/i.test(label) ? "" : label;
}

function eventLog(entry) {
  const payload = entry?.payload || {};
  if (entry?.type === "response_item") {
    if (payload.type === "message") {
      const text = contentText(payload.content);
      return text ? `${payload.role === "assistant" ? "‹" : "›"} ${text}` : "";
    }
    if (payload.type === "custom_tool_call") return `› ${payload.name || "tool"}`;
    if (payload.type === "custom_tool_call_output") {
      const output = typeof payload.output === "string" ? payload.output : payload.output?.text;
      return output ? String(output).slice(0, 6000) : "";
    }
  }
  if (entry?.type === "event_msg" && payload.type === "agent_message") return payload.message || "";
  return "";
}

function sourceDetails(source, fallback) {
  const subagent = source?.subagent;
  if (!subagent) return { name: fallback, role: "subagent" };
  const raw = typeof subagent === "string" ? subagent : JSON.stringify(subagent);
  const spawn = subagent.thread_spawn || {};
  const role = spawn.agent_role || ["luna_code_analyst", "luna_researcher", "luna_worker"].find((value) => raw.includes(value)) || "subagent";
  return { name: spawn.agent_nickname || fallback, role };
}

async function readFirstLine(file) {
  const handle = await fsp.open(file, "r");
  try {
    const buffer = Buffer.alloc(65536);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    return buffer.toString("utf8", 0, bytesRead).split(/\r?\n/, 1)[0];
  } finally {
    await handle.close();
  }
}

async function sessionFiles(days = 2) {
  const files = [];
  for (let offset = 0; offset < days; offset += 1) {
    const date = new Date(Date.now() - offset * 86400000);
    const dir = path.join(
      SESSION_ROOT,
      String(date.getFullYear()),
      String(date.getMonth() + 1).padStart(2, "0"),
      String(date.getDate()).padStart(2, "0")
    );
    try {
      for (const name of await fsp.readdir(dir)) if (name.endsWith(".jsonl")) files.push(path.join(dir, name));
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  return files;
}

async function history(workspaceValue) {
  if (!workspaceValue) return [];
  const workspace = validateWorkspace(workspaceValue);
  const candidates = await sessionFiles(14);
  const rows = [];
  for (const file of candidates) {
    try {
      const stat = await fsp.stat(file);
      rows.push({ file, stat });
    } catch {}
  }
  rows.sort((a, b) => b.stat.mtimeMs - a.stat.mtimeMs);
  const result = [];
  for (const { file } of rows.slice(0, 80)) {
    try {
      const raw = await fsp.readFile(file, "utf8");
      const lines = raw.split(/\r?\n/);
      const meta = JSON.parse(lines[0]).payload;
      if (meta.thread_source !== "user" || path.resolve(meta.cwd || "") !== workspace) continue;
      let label = "Untitled session";
      for (const line of lines.slice(1)) {
        if (!line) continue;
        const item = JSON.parse(line);
        const payload = item.payload || {};
        if (item.type === "response_item" && payload.type === "message" && payload.role === "user") {
          const candidate = sessionLabel(contentText(payload.content));
          if (candidate) { label = candidate; break; }
        }
        if (item.type === "event_msg" && payload.type === "user_message") {
          const candidate = sessionLabel(payload.message);
          if (candidate) { label = candidate; break; }
        }
      }
      result.push({ id: meta.id || meta.session_id, label: label.slice(0, 72), timestamp: meta.timestamp });
      if (result.length === 14) break;
    } catch {}
  }
  return result;
}

async function latestUsage() {
  const rows = [];
  for (const file of await sessionFiles(14)) {
    try { rows.push({ file, modified: (await fsp.stat(file)).mtimeMs }); } catch {}
  }
  rows.sort((a, b) => b.modified - a.modified);
  for (const { file } of rows.slice(0, 20)) {
    try {
      const lines = (await fsp.readFile(file, "utf8")).split(/\r?\n/);
      for (let index = lines.length - 1; index >= 0; index -= 1) {
        if (!lines[index].includes('"type":"token_count"')) continue;
        const entry = JSON.parse(lines[index]);
        const status = normalizeStatus(entry.payload?.info, entry.payload?.rate_limits);
        if (status) return status;
      }
    } catch {}
  }
  return null;
}

class CodexTerminal {
  constructor() {
    this.clients = new Set();
    this.process = null;
    this.agent = null;
    this.workspace = null;
    this.startedAt = 0;
    this.parentFile = null;
    this.parentId = null;
    this.status = null;
    this.resetsAvailable = null;
    this.textProbe = "";
    this.backlog = "";
    this.tails = new Map();
    this.subagents = new Map();
    this.refreshing = null;
    this.timer = setInterval(() => this.poll().catch(() => {}), 2500);
    this.timer.unref();
    this.refresh().catch(() => {});
  }

  send(client, value) {
    if (client.readyState === WebSocket.OPEN) client.send(JSON.stringify(value));
  }

  broadcast(value) {
    for (const client of this.clients) this.send(client, value);
  }

  snapshot(client) {
    this.send(client, {
      type: "snapshot",
      running: Boolean(this.process),
      agent: this.agent,
      workspace: this.workspace,
      output: this.backlog,
      status: this.status,
      subagents: [...this.subagents.values()].map(({ file, offset, partial, ...agent }) => agent)
    });
  }

  start(agent, cols, rows, resumeId, workspaceValue) {
    validateAgent(agent);
    if (this.process) throw new Error("Terminal already running");
    const workspace = validateWorkspace(workspaceValue);
    const launcher = path.join(LAUNCHER_ROOT, "codex-ultron", "scripts", process.platform === "win32" ? "start-codex.ps1" : "start-codex.sh");
    if (!fs.existsSync(launcher)) throw new Error("Codex Ultron launcher is unavailable");
    let command;
    let args;
    if (resumeId) {
      if (!/^[0-9a-f-]{36}$/i.test(resumeId)) throw new Error("Invalid session id");
      command = process.platform === "win32" ? "codex.exe" : "codex";
      args = ["resume", resumeId, "--profile", agent, "--cd", workspace, "--search", "--dangerously-bypass-approvals-and-sandbox"];
    } else if (process.platform === "win32") {
      command = "powershell.exe";
      args = ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", launcher, "-Agent", agent, "-WorkingDirectory", workspace];
    } else {
      command = "/bin/sh";
      args = [launcher, "--agent", agent];
    }
    this.agent = agent;
    this.workspace = workspace;
    this.startedAt = Date.now();
    this.parentFile = null;
    this.parentId = resumeId || null;
    this.status = this.status && { ...this.status, context: null, resetsAvailable: this.resetsAvailable };
    this.backlog = "";
    this.tails.clear();
    this.subagents.clear();
    this.filesAtStart = new Set(fs.existsSync(SESSION_ROOT) ? fs.readdirSync(SESSION_ROOT, { recursive: true }).filter((name) => name.endsWith(".jsonl")).map((name) => path.join(SESSION_ROOT, name)) : []);
    this.process = pty.spawn(command, args, {
      name: "xterm-256color",
      cols: clamp(cols, 40, 320, 120),
      rows: clamp(rows, 12, 120, 36),
      cwd: workspace,
      env: { ...process.env, TERM: "xterm-256color", COLORTERM: "truecolor" }
    });
    this.process.onData((data) => {
      this.backlog = (this.backlog + data).slice(-1000000);
      this.textProbe = (this.textProbe + data.replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, "").replace(/\x1b\[[0-?]*[ -\/]*[@-~]/g, "")).slice(-20000);
      const resets = this.textProbe.match(/You have (\d+) usage limit resets? available/i);
      if (resets && Number(resets[1]) !== this.resetsAvailable) {
        this.resetsAvailable = Number(resets[1]);
        this.status = { ...this.status, resetsAvailable: this.resetsAvailable, updatedAt: Date.now() };
        this.broadcast({ type: "status", status: this.status });
      }
      this.broadcast({ type: "output", data });
    });
    this.process.onExit(({ exitCode }) => {
      this.process = null;
      this.broadcast({ type: "state", running: false, agent: this.agent, exitCode });
    });
    this.broadcast({ type: "state", running: true, agent });
  }

  input(data) {
    if (this.process && typeof data === "string" && data.length <= 65536) this.process.write(data);
  }

  resize(cols, rows) {
    if (this.process) this.process.resize(clamp(cols, 40, 320, 120), clamp(rows, 12, 120, 36));
  }

  async refresh() {
    if (this.refreshing) return this.refreshing;
    this.refreshing = (async () => {
      const account = await readLiveUsage().catch(() => latestUsage());
      if (account) {
        this.resetsAvailable = account.resetsAvailable ?? this.resetsAvailable;
        this.status = { ...account, context: this.status?.context || account.context, resetsAvailable: this.resetsAvailable };
        this.broadcast({ type: "status", status: this.status });
      }
      await this.poll();
    })().finally(() => { this.refreshing = null; });
    return this.refreshing;
  }

  async readTail(file, onEntry) {
    const state = this.tails.get(file) || { offset: 0, partial: "" };
    const stat = await fsp.stat(file);
    if (stat.size < state.offset) Object.assign(state, { offset: 0, partial: "" });
    if (stat.size === state.offset) return;
    const handle = await fsp.open(file, "r");
    const buffer = Buffer.alloc(stat.size - state.offset);
    try {
      await handle.read(buffer, 0, buffer.length, state.offset);
    } finally {
      await handle.close();
    }
    state.offset = stat.size;
    const lines = (state.partial + buffer.toString("utf8")).split(/\r?\n/);
    state.partial = lines.pop() || "";
    this.tails.set(file, state);
    for (const line of lines) {
      if (!line) continue;
      try { onEntry(JSON.parse(line)); } catch {}
    }
  }

  async findParent(files) {
    const matches = [];
    for (const file of files) {
      try {
        const stat = await fsp.stat(file);
        if (stat.mtimeMs < this.startedAt - 5000) continue;
        const meta = JSON.parse(await readFirstLine(file)).payload;
        const id = meta.id || meta.session_id;
        const belongsToLaunch = this.parentId ? id === this.parentId : !this.filesAtStart?.has(file);
        if (belongsToLaunch && meta.thread_source === "user" && path.resolve(meta.cwd || "") === this.workspace) {
          matches.push({ file, meta, stat });
        }
      } catch {}
    }
    matches.sort((a, b) => b.stat.mtimeMs - a.stat.mtimeMs);
    if (matches[0]) {
      this.parentFile = matches[0].file;
      this.parentId = matches[0].meta.id || matches[0].meta.session_id;
    }
  }

  async poll() {
    if (!this.startedAt) return;
    const files = await sessionFiles(this.parentId && !this.parentFile ? 14 : 2);
    if (!this.parentFile) await this.findParent(files);
    if (!this.parentFile) return;
    await this.readTail(this.parentFile, (entry) => {
      if (entry.type === "event_msg" && entry.payload?.type === "token_count") {
        this.status = normalizeStatus(entry.payload.info, entry.payload.rate_limits);
        if (this.status) this.status.resetsAvailable = this.resetsAvailable;
        if (this.status) this.broadcast({ type: "status", status: this.status });
      }
    });
    for (const file of files) {
      if (file === this.parentFile) continue;
      let agent = this.subagents.get(file);
      if (!agent) {
        try {
          const meta = JSON.parse(await readFirstLine(file)).payload;
          if (meta.parent_thread_id !== this.parentId || meta.thread_source !== "subagent") continue;
          const details = sourceDetails(meta.source, `Agent ${this.subagents.size + 1}`);
          agent = {
            file,
            id: meta.id || meta.session_id,
            name: details.name,
            role: details.role,
            status: "running",
            startedAt: Date.parse(meta.timestamp) || Date.now(),
            log: ""
          };
          this.subagents.set(file, agent);
          this.broadcast({ type: "subagents", subagents: [...this.subagents.values()].map(({ file: _, ...item }) => item) });
        } catch { continue; }
      }
      await this.readTail(file, (entry) => {
        const line = eventLog(entry);
        if (line) agent.log = `${agent.log}${agent.log ? "\n\n" : ""}${line}`.slice(-120000);
        const kind = entry.payload?.type;
        if (entry.type === "event_msg" && ["task_complete", "turn_complete"].includes(kind)) agent.status = "complete";
        if (entry.type === "event_msg" && ["turn_aborted", "error"].includes(kind)) agent.status = "error";
        if (line || agent.status !== "running") this.broadcast({ type: "subagent", subagent: (({ file: _, ...item }) => item)(agent) });
      });
    }
  }
}

function safePublicPath(urlPath) {
  if (ASSETS.has(urlPath)) return ASSETS.get(urlPath);
  const clean = urlPath === "/" ? "index.html" : decodeURIComponent(urlPath.slice(1));
  if (!/^[a-zA-Z0-9._/-]+$/.test(clean)) return null;
  const target = path.resolve(APP_ROOT, "public", clean);
  return target.startsWith(path.join(APP_ROOT, "public") + path.sep) || target === path.join(APP_ROOT, "public", "index.html") ? target : null;
}

function createApp() {
  const terminal = new CodexTerminal();
  const server = http.createServer(async (request, response) => {
    response.setHeader("Content-Security-Policy", "default-src 'self'; connect-src 'self' ws://127.0.0.1:*; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:");
    response.setHeader("X-Content-Type-Options", "nosniff");
    const url = new URL(request.url, `http://${HOST}`);
    if (url.pathname === "/api/history") {
      response.setHeader("Content-Type", "application/json");
      try { response.end(JSON.stringify(await history(url.searchParams.get("workspace")))); }
      catch (error) { response.writeHead(400).end(JSON.stringify({ error: error.message })); }
      return;
    }
    if (url.pathname === "/api/folders") {
      response.setHeader("Content-Type", "application/json");
      try { response.end(JSON.stringify(await listDirectories(url.searchParams.get("path")))); }
      catch (error) { response.writeHead(400).end(JSON.stringify({ error: error.message })); }
      return;
    }
    const target = safePublicPath(url.pathname);
    if (!target) {
      response.writeHead(404).end();
      return;
    }
    try {
      response.setHeader("Content-Type", MIME[path.extname(target)] || "application/octet-stream");
      fs.createReadStream(target).on("error", () => response.writeHead(404).end()).pipe(response);
    } catch { response.writeHead(404).end(); }
  });
  const sockets = new WebSocketServer({ server, maxPayload: 65536 });
  sockets.on("connection", (client, request) => {
    if (request.socket.remoteAddress !== "127.0.0.1" && request.socket.remoteAddress !== "::1") return client.close(1008, "Loopback only");
    terminal.clients.add(client);
    terminal.snapshot(client);
    client.on("message", (raw) => {
      try {
        const message = JSON.parse(raw.toString());
        if (message.type === "start") terminal.start(message.agent, message.cols, message.rows, message.resumeId, message.workspace);
        else if (message.type === "input") terminal.input(message.data);
        else if (message.type === "resize") terminal.resize(message.cols, message.rows);
        else if (message.type === "refresh") terminal.refresh().catch(() => {});
      } catch (error) { terminal.send(client, { type: "error", message: error.message }); }
    });
    client.on("close", () => terminal.clients.delete(client));
  });
  return { server, terminal };
}

if (require.main === module) {
  const { server, terminal } = createApp();
  server.listen(PORT, HOST, () => process.stdout.write(`Codex UI: http://${HOST}:${PORT}\nChoose a workspace in the browser.\n`));
  process.once("SIGINT", () => {
    terminal.process?.kill();
    server.close(() => process.exit(0));
  });
}

module.exports = { clamp, contentText, createApp, eventLog, history, latestUsage, listDirectories, normalizeLiveStatus, normalizeStatus, readLiveUsage, safePublicPath, sessionLabel, sourceDetails, validateAgent, validateWorkspace, workspaceRoots };
