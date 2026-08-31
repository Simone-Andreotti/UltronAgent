#!/usr/bin/env sh
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--agent edith|jarvis|ultron] [WORKSPACE]"
}

agent=""
working_directory="$PWD"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --agent)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            agent="$2"
            shift 2
            ;;
        --agent=*)
            agent=${1#--agent=}
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            [ "$working_directory" = "$PWD" ] || { usage >&2; exit 2; }
            working_directory="$1"
            shift
            ;;
    esac
done
[ "$#" -eq 0 ] || { usage >&2; exit 2; }

if [ -z "$agent" ]; then
    printf '%s\n' "Choose a Codex lead for the desktop app:" "  1. Edith - simpler implementation and maintenance" "  2. Jarvis - medium-complexity implementation and integration" "  3. Ultron - complex and architectural work"
    printf '%s' "Lead: "
    IFS= read -r choice
    case "$choice" in
        1) agent="edith" ;;
        2) agent="jarvis" ;;
        3) agent="ultron" ;;
        *) printf '%s\n' "Choose 1, 2, or 3." >&2; exit 2 ;;
    esac
fi

case "$agent" in
    edith) model="gpt-5.6-luna"; effort="low"; instructions_file="edith.md" ;;
    jarvis) model="gpt-5.6-terra"; effort="medium"; instructions_file="jarvis.md" ;;
    ultron) model="gpt-5.6-sol"; effort="high"; instructions_file="ultron.md" ;;
    *) printf 'Unknown lead: %s\n' "$agent" >&2; exit 2 ;;
esac

codex_home=${CODEX_HOME:-"$HOME/.codex"}
[ -f "$codex_home/agents/luna_worker.toml" ] || { printf '%s\n' "Codex Ultron agents are not installed. Run install.sh first." >&2; exit 1; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
developer_instructions=$(printf 'developer_instructions="""\n%s\n"""' "$(cat "$package_root/instructions/$instructions_file")")

exec codex app --config "model=\"$model\"" --config "model_reasoning_effort=\"$effort\"" --config 'model_verbosity="low"' --config 'approval_policy="never"' --config 'sandbox_mode="workspace-write"' --config 'sandbox_workspace_write.network_access=true' --config 'web_search="live"' --config 'plugins."browser@openai-bundled".enabled=true' --config "$developer_instructions" "$working_directory"
