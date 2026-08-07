#!/usr/bin/env sh
set -eu

codex_home=${CODEX_HOME:-"$HOME/.codex"}
[ -f "$codex_home/edith.config.toml" ] || { printf '%s\n' "Edith profile is not installed. Run install.sh first." >&2; exit 1; }

for argument in "$@"; do
    case "$argument" in
        -m|-m=*|-m?*|--model|--model=*|-p|-p=*|-p?*|--profile|--profile=*|-c|-c=*|-c?*|--config|--config=*|--oss|--local-provider|--local-provider=*)
            printf '%s\n' "Profile, model, provider, and reasoning effort are fixed by this launcher." >&2
            exit 2
            ;;
    esac
done

exec codex --profile edith --model gpt-5.6-luna --config 'model_reasoning_effort="high"' "$@"