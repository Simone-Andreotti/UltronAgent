#!/usr/bin/env sh
set -eu

codex_home=${CODEX_HOME:-"$HOME/.codex"}
[ -f "$codex_home/agents/luna_worker.toml" ] || { printf '%s\n' "Codex Ultron agents are not installed. Run install.sh first." >&2; exit 1; }
[ "$#" -le 1 ] || { printf '%s\n' "Usage: $0 [WORKSPACE]" >&2; exit 2; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
developer_instructions=$(printf 'developer_instructions="""\n%s\n"""' "$(cat "$package_root/instructions/edith.md")")

exec codex app --config 'model="gpt-5.6-luna"' --config 'model_reasoning_effort="high"' --config "$developer_instructions" "${1:-$PWD}"