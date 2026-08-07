#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

for argument in "$@"; do
    case "$argument" in
        --agent|--agent=*|--plugin-dir|--plugin-dir=*|--model|--model=*|--context|--context=*|--reasoning-effort|--reasoning-effort=*|--effort|--effort=*)
            printf '%s\n' "Agent, plugin, model, reasoning effort, and context are fixed by this launcher." >&2
            exit 2
            ;;
    esac
done

exec copilot \
    --plugin-dir "$package_root" \
    --agent ultron-orchestrator:ultron \
    --model gpt-5.6-sol \
    --reasoning-effort xhigh \
    --context default \
    "$@"