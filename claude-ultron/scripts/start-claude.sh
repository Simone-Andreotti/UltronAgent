#!/usr/bin/env sh
set -eu

agent=
working_directory=$(pwd)
prompt=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --agent) agent=$2; shift 2 ;;
        --cd) working_directory=$2; shift 2 ;;
        --) shift; prompt=$*; break ;;
        --*) echo "Unsupported launcher argument: $1. Use --agent, --cd, and an optional prompt; model and effort are fixed." >&2; exit 2 ;;
        *)
            [ -z "$prompt" ] || { echo "Quote the prompt: the launcher takes it as one argument." >&2; exit 2; }
            prompt=$1; shift ;;
    esac
done

if [ -z "$agent" ]; then
    echo "Choose a Claude lead:"
    echo "  1. Edith - simpler implementation and maintenance (Haiku 5.5)"
    echo "  2. Jarvis - medium-complexity implementation and integration (Sonnet 5.5)"
    echo "  3. Ultron - complex and architectural work (Opus 5.5)"
    printf "Lead: "
    read -r choice
    case "$choice" in
        1) agent=edith ;;
        2) agent=jarvis ;;
        3) agent=ultron ;;
        *) echo "Choose 1, 2, or 3." >&2; exit 2 ;;
    esac
fi

case "$agent" in
    edith) model=claude-haiku-5-5; effort=max; greeting="Edith at your service." ;;
    jarvis) model=claude-sonnet-5-5; effort=xhigh; greeting="Jarvis at your service." ;;
    ultron) model=claude-opus-5-5; effort=xhigh; greeting="Lowly human, let Ultron manage the rest." ;;
    *) echo "Agent must be edith, jarvis, or ultron." >&2; exit 2 ;;
esac

echo "$greeting"
cd "$working_directory"
if [ -n "$prompt" ]; then
    exec claude --agent "leads:$agent" --model "$model" --effort "$effort" --permission-mode "${CLAUDE_ULTRON_PERMISSION_MODE:-auto}" -- "$prompt"
fi
exec claude --agent "leads:$agent" --model "$model" --effort "$effort" --permission-mode "${CLAUDE_ULTRON_PERMISSION_MODE:-auto}"
