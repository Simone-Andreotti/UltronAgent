#!/usr/bin/env sh
set -eu

scope="user"
project_path="$PWD"
force="false"

usage() {
    printf '%s\n' "Usage: $0 [--scope user|project] [--project-path PATH] [--force]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --scope)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            scope="$2"
            shift 2
            ;;
        --project-path)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            project_path="$2"
            shift 2
            ;;
        --force)
            force="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
source_agents="$package_root/agents"
source_prompts="$package_root/prompts"

copy_package_file() {
    source_file=$1
    destination=$2

    mkdir -p "$(dirname -- "$destination")"
    cp "$source_file" "$destination"
}

check_destination() {
    destination=$1
    if [ -e "$destination" ] && [ "$force" != "true" ]; then
        printf "Refusing partial install because '%s' exists. Re-run with --force to replace existing files.\n" "$destination" >&2
        exit 1
    fi
}

case "$scope" in
    user)
        skill_root="$HOME/.copilot/skills/ultron-orchestrator"
        cli_agent_root="$HOME/.copilot/agents"
        case "$(uname -s)" in
            Darwin)
                vscode_agent_root="$HOME/Library/Application Support/Code/User/prompts"
                ;;
            Linux)
                vscode_agent_root="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/prompts"
                ;;
            *)
                printf 'User installation supports Linux and macOS. Use install.ps1 on Windows.\n' >&2
                exit 1
                ;;
        esac
        agent_roots="$cli_agent_root
$vscode_agent_root"
        prompt_roots="$vscode_agent_root"
        ;;
    project)
        [ -d "$project_path" ] || { printf "Project path does not exist: %s\n" "$project_path" >&2; exit 1; }
        resolved_project=$(CDPATH= cd -- "$project_path" && pwd)
        skill_root="$resolved_project/.github/skills/ultron-orchestrator"
        agent_roots="$resolved_project/.github/agents"
        prompt_roots="$resolved_project/.github/prompts"
        ;;
    *)
        printf 'Invalid scope: %s\n' "$scope" >&2
        usage >&2
        exit 2
        ;;
esac

check_destination "$skill_root/SKILL.md"

printf '%s\n' "$agent_roots" | while IFS= read -r agent_root; do
    [ -n "$agent_root" ] || continue
    for source_agent in "$source_agents"/*.agent.md; do
        check_destination "$agent_root/$(basename -- "$source_agent")"
    done
done

printf '%s\n' "$prompt_roots" | while IFS= read -r prompt_root; do
    [ -n "$prompt_root" ] || continue
    for source_prompt in "$source_prompts"/*.prompt.md; do
        check_destination "$prompt_root/$(basename -- "$source_prompt")"
    done
done

copy_package_file "$package_root/skills/ultron-orchestrator/SKILL.md" "$skill_root/SKILL.md"

printf '%s\n' "$agent_roots" | while IFS= read -r agent_root; do
    [ -n "$agent_root" ] || continue
    for source_agent in "$source_agents"/*.agent.md; do
        copy_package_file "$source_agent" "$agent_root/$(basename -- "$source_agent")"
    done
done

printf '%s\n' "$prompt_roots" | while IFS= read -r prompt_root; do
    [ -n "$prompt_root" ] || continue
    for source_prompt in "$source_prompts"/*.prompt.md; do
        copy_package_file "$source_prompt" "$prompt_root/$(basename -- "$source_prompt")"
    done
done

printf "Installed Copilot Ultron package for scope '%s'.\n" "$scope"