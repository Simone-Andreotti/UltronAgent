#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

for argument in "$@"; do
    case "$argument" in
        --agent|--agent=*|--plugin-dir|--plugin-dir=*|--model|--model=*|--reasoning-effort|--reasoning-effort=*|--effort|--effort=*)
            printf '%s\n' "Agent, plugin, model, and reasoning effort are fixed by this launcher." >&2
            exit 2
            ;;
    esac
done

permission_flags="--allow-all-tools --allow-all-urls --disallow-temp-dir"
[ "${COPILOT_ALLOW_ALL:-true}" = "true" ] && permission_flags=--allow-all

exec copilot \
    --plugin-dir "$package_root" \
    --agent ultron-orchestrator:jarvis \
    --model gpt-5.6-sol \
    --reasoning-effort high \
    $permission_flags \
    "$@"
