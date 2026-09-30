"""Exercise the desktop role plugins through the installed Codex CLI and app server."""
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import tempfile
import threading
import tomllib

source_package = Path(__file__).resolve().parents[1]
codex = shutil.which("codex")
assert codex, "Codex CLI is required"
roles = ("ultron", "jarvis", "edith")
display_names = {role: role.title() for role in roles}

with tempfile.TemporaryDirectory(prefix="codex-ultron-plugin-") as temporary:
    temporary_root = Path(temporary)
    package = temporary_root / "package"
    shutil.copytree(source_package, package, ignore=shutil.ignore_patterns(".plugin-build", "__pycache__"))
    home = temporary_root / "home"
    codex_home = home / ".codex"
    codex_home.mkdir(parents=True)
    env = dict(os.environ, CODEX_HOME=str(codex_home))

    def run(*args):
        result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=45)
        assert result.returncode == 0, result.stderr + result.stdout
        return result.stdout

    if os.name == "nt":
        install = ["pwsh", "-NoProfile", "-File", str(package / "scripts/install.ps1"), "-HomePath", str(home)]
        plugin_install = ["pwsh", "-NoProfile", "-File", str(package / "scripts/install-plugin.ps1"), "-HomePath", str(home), "-CodexCommand", codex]
    else:
        env["HOME"] = str(home)
        install = ["sh", str(package / "scripts/install.sh")]
        plugin_install = ["sh", str(package / "scripts/install-plugin.sh")]
    run(*install)
    skill = home / ".agents/skills/codex-ultron"
    (skill / "personal-notes.txt").write_text("preserve", encoding="utf-8")
    personal_agent = codex_home / "agents/personal.toml"
    personal_agent.write_text('name = "personal"\ndescription = "Personal agent"\ndeveloper_instructions = "Read only"\n', encoding="utf-8")

    # Register the old combined plugin against this same disposable package root.
    # The next installer run replaces its catalog with the three current entries.
    marketplace_path = package / ".agents/plugins/marketplace.json"
    current_marketplace = marketplace_path.read_bytes()
    legacy_root = package / ".legacy-plugin"
    legacy_skill = legacy_root / "skills/codex-ultron"
    legacy_skill.mkdir(parents=True)
    (legacy_root / "plugin.json").write_text(json.dumps({
        "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
        "name": "codex-ultron",
        "version": "1.1.0",
        "description": "Legacy combined Codex workflow",
        "extensions": {"com.openai": {"interface": {
            "displayName": "Ultron for Codex",
            "defaultPrompt": ["Use the combined Ultron workflow."],
        }}},
    }), encoding="utf-8")
    (legacy_skill / "SKILL.md").write_text("---\nname: codex-ultron\ndescription: Legacy combined workflow\n---\n", encoding="utf-8")
    personal_marketplace_root = temporary_root / "personal-marketplace"
    personal_root = personal_marketplace_root / "plugin"
    personal_skill = personal_root / "skills/personal"
    personal_skill.mkdir(parents=True)
    (personal_root / "plugin.json").write_text(json.dumps({
        "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
        "name": "personal",
        "version": "0.1.0",
        "description": "Unrelated user plugin",
    }), encoding="utf-8")
    (personal_skill / "SKILL.md").write_text("---\nname: personal\ndescription: User plugin\n---\n", encoding="utf-8")
    (personal_marketplace_root / ".agents/plugins").mkdir(parents=True)
    (personal_marketplace_root / ".agents/plugins/marketplace.json").write_text(json.dumps({
        "name": "personal-test",
        "plugins": [{
            "name": "personal",
            "source": {"source": "local", "path": "./plugin"},
            "policy": {"installation": "AVAILABLE"},
        }],
    }), encoding="utf-8")
    marketplace_path.write_text(json.dumps({
        "name": "ultron-codex",
        "plugins": [{
            "name": "codex-ultron",
            "source": {"source": "local", "path": "./.legacy-plugin"},
            "policy": {"installation": "AVAILABLE"},
        }],
    }), encoding="utf-8")
    run(codex, "plugin", "marketplace", "add", str(package), "--json")
    run(codex, "plugin", "add", "codex-ultron@ultron-codex", "--json")
    run(codex, "plugin", "marketplace", "add", str(personal_marketplace_root), "--json")
    run(codex, "plugin", "add", "personal@personal-test", "--json")
    legacy_listing = json.loads(run(codex, "plugin", "list", "--marketplace", "ultron-codex", "--json"))
    assert {entry["pluginId"] for entry in legacy_listing["installed"]} == {"codex-ultron@ultron-codex"}
    marketplace_path.write_bytes(current_marketplace)

    run(*plugin_install)
    legacy_cache = codex_home / "plugins/cache/ultron-codex/codex-ultron"
    assert not legacy_cache.exists(), "The legacy combined plugin cache was not removed"
    config_path = codex_home / "config.toml"
    assert config_path.is_file(), "Codex did not write its plugin configuration"
    plugin_config = tomllib.loads(config_path.read_text(encoding="utf-8")).get("plugins", {})
    assert "codex-ultron@ultron-codex" not in plugin_config, "The legacy plugin configuration stanza was not removed"
    assert "personal@personal-test" in plugin_config, "Migration removed unrelated plugin configuration"
    run(*plugin_install)
    assert not (skill / "SKILL.md").exists(), "Standalone skill was not migrated"
    assert (skill / "personal-notes.txt").read_text(encoding="utf-8") == "preserve"
    assert personal_agent.read_text(encoding="utf-8").startswith('name = "personal"')

    listing = json.loads(run(codex, "plugin", "list", "--json"))
    installed = listing["installed"]
    installed_ids = {entry["pluginId"] for entry in installed}
    assert "codex-ultron@ultron-codex" not in installed_ids, "The legacy combined plugin was not removed"
    assert "personal@personal-test" in installed_ids, "Migration removed an unrelated installed plugin"
    plugins = [entry for entry in installed if entry["pluginId"] in {f"{role}@ultron-codex" for role in roles}]
    assert {entry["pluginId"] for entry in plugins} == {f"{role}@ultron-codex" for role in roles}
    assert len(plugins) == 3 and all(entry["enabled"] for entry in plugins)
    assert {entry["name"] for entry in plugins} == set(roles)
    assert all(entry["version"] == "1.2.0" for entry in plugins)

    cache_root = codex_home / "plugins/cache/ultron-codex"
    for role in roles:
        build = package / ".plugin-build" / role
        version = json.loads((build / "plugin.json").read_text(encoding="utf-8"))["version"]
        cache = cache_root / role / version
        skill_path = build / "skills" / role / "SKILL.md"
        references_root = skill_path.parent / "references"
        assert skill_path.is_file()
        assert [path.relative_to(build).as_posix() for path in build.rglob("SKILL.md")] == [f"skills/{role}/SKILL.md"]
        assert (cache / "plugin.json").read_bytes() == (build / "plugin.json").read_bytes()
        for relative, canonical in (
            ("lead.md", package / "instructions" / f"{role}.md"),
            ("workflow.md", package / "skills/codex-ultron/SKILL.md"),
            ("chat-activation.md", package / "skills/codex-ultron/references/chat-activation.md"),
        ):
            generated = references_root / relative
            cache_reference = cache / "skills" / role / "references" / relative
            assert generated.read_bytes() == canonical.read_bytes(), f"Generated reference differs from canonical source: {role}/{relative}"
            assert cache_reference.read_bytes() == canonical.read_bytes(), f"Installed reference differs from canonical source: {role}/{relative}"
        for local_reference in re.findall(r'\]\(([^)]+)\)', skill_path.read_text(encoding="utf-8")):
            if "://" not in local_reference and not local_reference.startswith("#"):
                assert (skill_path.parent / local_reference.split("#", 1)[0]).is_file(), f"Broken local reference in {role}: {local_reference}"

    for source in (package / "agents").glob("*.toml"):
        assert (codex_home / "agents" / source.name).read_bytes() == source.read_bytes()
    assert tomllib.loads((codex_home / "agents/sol_worker.toml").read_text(encoding="utf-8"))["model"] == "gpt-6.1-sol"

    process = subprocess.Popen([codex, "app-server", "--listen", "stdio://"], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    messages = queue.Queue()
    threading.Thread(target=lambda: [messages.put(line) for line in process.stdout], daemon=True).start()

    def request(identifier, method, params):
        process.stdin.write(json.dumps({"id": identifier, "method": method, "params": params}) + "\n")
        process.stdin.flush()
        while True:
            message = json.loads(messages.get(timeout=30))
            if message.get("id") == identifier:
                assert "error" not in message, message
                return message["result"]

    try:
        request(1, "initialize", {"clientInfo": {"name": "ultron_plugin_test", "version": "1.0.0"}, "capabilities": {"experimentalApi": True}})
        process.stdin.write('{"method":"initialized"}\n')
        process.stdin.flush()
        for index, role in enumerate(roles, start=2):
            detail = request(index, "plugin/read", {"pluginName": role, "marketplacePath": str(marketplace_path)})
            plugin = detail["plugin"]
            assert plugin["summary"]["enabled"]
            assert len(plugin["skills"]) == 1, f"Plugin must contain one role skill: {role}"
            interface = plugin["summary"]["interface"]
            assert interface["displayName"] == display_names[role]
            assert not interface.get("defaultPrompt"), f"Plugin read exposed a default prompt: {role}"

        result = request(5, "skills/list", {"cwds": [str(package)], "forceReload": True})
        skills = [entry for scope in result["data"] for entry in scope["skills"]]
        for role in roles:
            entries = [entry for entry in skills if entry["name"] == f"{role}:{role}"]
            assert len(entries) == 1, f"Role was not discovered exactly once: {role}"
            entry = entries[0]
            assert entry["enabled"] and entry["interface"]["displayName"] == display_names[role], entry
            assert not entry["interface"].get("defaultPrompt"), f"Skill list exposed a default prompt: {role}"
            assert Path(entry["path"]).resolve() == (cache_root / role / "1.2.0" / "skills" / role / "SKILL.md").resolve()
            metadata = cache_root / role / "1.2.0" / "skills" / role / "agents/openai.yaml"
            assert re.search(r"allow_implicit_invocation:\s*true", metadata.read_text(encoding="utf-8")), role
    finally:
        process.terminate()
        process.wait(timeout=10)

print("Codex role plugin registration, repeat install, migration, and app-server discovery passed.")
