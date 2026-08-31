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

permission_flags="--allow-all-tools --allow-all-urls --disallow-temp-dir"
sandbox_flag=--sandbox
[ "${COPILOT_SANDBOX:-true}" = "false" ] && sandbox_flag=
[ "${COPILOT_ALLOW_ALL:-false}" = "true" ] && permission_flags=--allow-all && sandbox_flag=--no-sandbox

exec copilot \
    --plugin-dir "$package_root" \
    --agent ultron-orchestrator:ultron \
    --model gpt-5.6-sol \
    --reasoning-effort high \
    --context default \
    $sandbox_flag \
    $permission_flags \
    "$@"
