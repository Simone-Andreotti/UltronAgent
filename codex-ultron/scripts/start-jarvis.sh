#!/usr/bin/env sh
set -eu

codex_home=${CODEX_HOME:-"$HOME/.codex"}
[ -f "$codex_home/jarvis.config.toml" ] || { printf '%s\n' "Jarvis profile is not installed. Run install.sh first." >&2; exit 1; }

for argument in "$@"; do
    case "$argument" in
        -m|-m=*|-m?*|--model|--model=*|-p|-p=*|-p?*|--profile|--profile=*|-c|-c=*|-c?*|--config|--config=*|--oss|--local-provider|--local-provider=*)
            printf '%s\n' "Profile, model, provider, and reasoning effort are fixed by this launcher." >&2
            exit 2
            ;;
    esac
done

live_search_flag=--search
full_access_flag=
[ "${CODEX_ULTRON_LIVE_SEARCH:-true}" = "false" ] && live_search_flag=
[ "${CODEX_ULTRON_FULL_ACCESS:-false}" = "true" ] && full_access_flag=--dangerously-bypass-approvals-and-sandbox

printf '%s\n' "Jarvis at your service."
exec codex --profile jarvis --model gpt-5.6-terra --config 'model_reasoning_effort="medium"' $live_search_flag $full_access_flag "$@"
