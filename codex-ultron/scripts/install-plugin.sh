#!/usr/bin/env sh
set -eu

[ "$#" -eq 0 ] || { printf '%s\n' "Usage: $0" >&2; exit 2; }
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
command -v codex >/dev/null 2>&1 || { printf '%s\n' "Codex CLI was not found." >&2; exit 1; }

build_root="$package_root/.plugin-build"
for role in ultron jarvis edith; do
    plugin_root="$build_root/$role"
    skill_root="$plugin_root/skills/$role"
    reference_root="$skill_root/references"
    agent_root="$skill_root/agents"
    mkdir -p "$reference_root" "$agent_root"
    cp -f "$package_root/plugins/$role/plugin.json" "$plugin_root/plugin.json"
    cp -f "$package_root/skills/$role/SKILL.md" "$skill_root/SKILL.md"
    cp -f "$package_root/skills/$role/agents/openai.yaml" "$agent_root/openai.yaml"
    cp -f "$package_root/instructions/$role.md" "$reference_root/lead.md"
    cp -f "$package_root/skills/codex-ultron/SKILL.md" "$reference_root/workflow.md"
    cp -f "$package_root/skills/codex-ultron/references/chat-activation.md" "$reference_root/chat-activation.md"
done

sh "$script_dir/install.sh" --scope user --skip-skill
codex plugin marketplace add "$package_root" --json
for role in ultron jarvis edith; do
    codex plugin add "$role@ultron-codex" --json
done

if ! plugin_list=$(codex plugin list --json); then
    printf '%s\n' "Unable to list installed Codex plugins; the combined plugin and standalone skill were preserved." >&2
    exit 1
fi
if ! printf '%s\n' "$plugin_list" | grep -Eq '"installed"[[:space:]]*:'; then
    printf '%s\n' "Codex plugin-list JSON did not contain installed plugins; the combined plugin and standalone skill were preserved." >&2
    exit 1
fi
codex_home=${CODEX_HOME:-$HOME/.codex}
legacy_cache="$codex_home/plugins/cache/ultron-codex/codex-ultron"
if [ -d "$legacy_cache" ] || printf '%s\n' "$plugin_list" | grep -Eq '"pluginId"[[:space:]]*:[[:space:]]*"codex-ultron@ultron-codex"'; then
    codex plugin remove codex-ultron@ultron-codex --json
fi

skill_root="$HOME/.agents/skills/codex-ultron"
if [ -f "$skill_root/SKILL.md" ] && grep -Eq '^name:[[:space:]]*codex-ultron[[:space:]]*$' "$skill_root/SKILL.md"; then
    # Remove only package-owned files; preserve unrelated additions.
    rm -f "$skill_root/SKILL.md" "$skill_root/agents/openai.yaml"
fi
printf '%s\n' "Installed role plugins: ultron@ultron-codex, jarvis@ultron-codex, edith@ultron-codex. Restart Codex to load them in new chats."
