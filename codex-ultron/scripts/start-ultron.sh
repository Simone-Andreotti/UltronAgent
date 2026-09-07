#!/usr/bin/env sh
set -eu

codex_home=${CODEX_HOME:-"$HOME/.codex"}
[ -f "$codex_home/ultron.config.toml" ] || { printf '%s\n' "Ultron profile is not installed. Run install.sh first." >&2; exit 1; }

for argument in "$@"; do
    case "$argument" in
        -m|-m=*|-m?*|--model|--model=*|-p|-p=*|-p?*|--profile|--profile=*|-c|-c=*|-c?*|--config|--config=*|--oss|--local-provider|--local-provider=*)
            printf '%s\n' "Profile, model, provider, and reasoning effort are fixed by this launcher." >&2
            exit 2
            ;;
    esac
done

live_search_flag=--search
full_access_flag=--dangerously-bypass-approvals-and-sandbox
sandbox_mode_args=
[ "${CODEX_ULTRON_LIVE_SEARCH:-true}" = "false" ] && live_search_flag=
[ "${CODEX_ULTRON_FULL_ACCESS:-true}" = "false" ] && { full_access_flag=; sandbox_mode_args='--config sandbox_mode="workspace-write"'; }

printf '%s\n' "Lowly human, let Ultron manage the rest."
exec codex --profile ultron --model gpt-6-astra --config 'model_reasoning_effort="medium"' $live_search_flag $full_access_flag $sandbox_mode_args "$@"
