#!/usr/bin/env sh
set -eu

usage() {
    printf '%s\n' "Usage: $0 [--agent edith|jarvis|ultron] [codex options]"
}

agent=""
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
        -m|-m=*|-m?*|--model|--model=*|-p|-p=*|-p?*|--profile|--profile=*|-c|-c=*|-c?*|--config|--config=*|--oss|--local-provider|--local-provider=*)
            printf '%s\n' "Profile, model, provider, and config routing are fixed by this launcher." >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [ -z "$agent" ]; then
    printf '%s\n' "Choose a Codex lead:" "  1. Edith - simpler implementation and maintenance" "  2. Jarvis - medium-complexity implementation and integration" "  3. Ultron - complex and architectural work"
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
    edith) profile="edith"; model="gpt-5.6-luna"; effort="xhigh"; greeting="Edith at your service." ;;
    jarvis) profile="jarvis"; model="gpt-5.6-terra"; effort="medium"; greeting="Jarvis at your service." ;;
    ultron) profile="ultron"; model="gpt-5.6-sol"; effort="high"; greeting="Lowly human, let Ultron manage the rest." ;;
    *) printf 'Unknown lead: %s\n' "$agent" >&2; exit 2 ;;
esac

codex_home=${CODEX_HOME:-"$HOME/.codex"}
[ -f "$codex_home/$profile.config.toml" ] || { printf '%s\n' "$profile profile is not installed. Run install.sh first." >&2; exit 1; }

live_search_flag=--search
full_access_flag=
[ "${CODEX_ULTRON_LIVE_SEARCH:-true}" = "false" ] && live_search_flag=
[ "${CODEX_ULTRON_FULL_ACCESS:-false}" = "true" ] && full_access_flag=--dangerously-bypass-approvals-and-sandbox

printf '%s\n' "$greeting"
exec codex --profile "$profile" --model "$model" --config "model_reasoning_effort=\"$effort\"" $live_search_flag $full_access_flag "$@"
