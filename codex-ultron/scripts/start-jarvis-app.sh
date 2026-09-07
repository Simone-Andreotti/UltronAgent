#!/usr/bin/env sh
set -eu

codex_home=${CODEX_HOME:-"$HOME/.codex"}
for luna_agent in luna_code_analyst.toml luna_researcher.toml luna_worker.toml; do
    [ -f "$codex_home/agents/$luna_agent" ] || { printf '%s\n' "Codex Ultron agent '$luna_agent' is not installed. Run install.sh first." >&2; exit 1; }
done
[ "$#" -le 1 ] || { printf '%s\n' "Usage: $0 [WORKSPACE]" >&2; exit 2; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
developer_instructions=$(printf 'developer_instructions="""\n%s\n"""' "$(cat "$package_root/instructions/jarvis.md")")
sandbox_mode=${CODEX_ULTRON_FULL_ACCESS:+danger-full-access}
[ "${CODEX_ULTRON_FULL_ACCESS:-true}" = "false" ] && sandbox_mode=workspace-write
[ -n "$sandbox_mode" ] || sandbox_mode=danger-full-access

exec codex app --config 'model="gpt-5.6-sol"' --config 'model_reasoning_effort="high"' --config 'model_verbosity="low"' --config 'approval_policy="never"' --config "sandbox_mode=\"$sandbox_mode\"" --config 'sandbox_workspace_write.network_access=true' --config 'web_search="live"' --config 'plugins."browser@openai-bundled".enabled=true' --config 'agents.enabled=true' --config 'agents.max_concurrent_threads_per_session=6' --config 'agents.default_subagent_model="gpt-5.6-luna"' --config 'agents.default_subagent_reasoning_effort="xhigh"' --config "$developer_instructions" "${1:-$PWD}"
