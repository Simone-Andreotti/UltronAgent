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
    managed=${2:-false}
    if [ -e "$destination" ] && [ "$force" != "true" ] && [ "$managed" != "true" ]; then
        printf "Refusing partial install because '%s' exists. Re-run with --force to replace existing files.\n" "$destination" >&2
        exit 1
    fi
}

is_managed_name() {
    root=$1
    marker_name=$2
    candidate_name=$3
    legacy_kind=$4
    marker_path="$root/$marker_name"

    if [ -f "$marker_path" ]; then
        tr -d '\r' < "$marker_path" | grep -Fqx "$candidate_name"
        return
    fi

    [ "$skill_identifies_package" = "true" ] || return 1
    case "$legacy_kind:$candidate_name" in
        agent:edith.agent.md|agent:jarvis.agent.md|agent:luna-code-analyst.agent.md|agent:luna-researcher.agent.md|agent:luna-worker.agent.md|agent:ultron.agent.md|prompt:explain.prompt.md)
            return 0
            ;;
    esac
    return 1
}

validate_marker() {
    marker_path=$1

    [ -f "$marker_path" ] || return 0
    while IFS= read -r managed_name || [ -n "$managed_name" ]; do
        managed_name=$(printf '%s' "$managed_name" | tr -d '\r')
        case "$managed_name" in
            ""|.|..|*/*|*\\*)
                printf "Unsafe managed file entry '%s' in '%s'.\n" "$managed_name" "$marker_path" >&2
                exit 1
                ;;
        esac
    done < "$marker_path"
}

remove_managed_files() {
    root=$1
    marker_name=$2
    marker_path="$root/$marker_name"

    [ -f "$marker_path" ] || return 0
    while IFS= read -r managed_name || [ -n "$managed_name" ]; do
        managed_name=$(printf '%s' "$managed_name" | tr -d '\r')
        case "$managed_name" in
            ""|.|..|*/*|*\\*)
                printf "Unsafe managed file entry '%s' in '%s'.\n" "$managed_name" "$marker_path" >&2
                exit 1
                ;;
        esac
        rm -f "$root/$managed_name"
    done < "$marker_path"
}

write_agent_marker() {
    root=$1
    marker_path="$root/$agent_marker_name"
    : > "$marker_path"
    for source_agent in "$source_agents"/*.agent.md; do
        basename -- "$source_agent" >> "$marker_path"
    done
}

write_prompt_marker() {
    root=$1
    marker_path="$root/$prompt_marker_name"
    : > "$marker_path"
    for source_prompt in "$source_prompts"/*.prompt.md; do
        basename -- "$source_prompt" >> "$marker_path"
    done
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

agent_marker_name=".ultron-orchestrator-agents"
prompt_marker_name=".ultron-orchestrator-prompts"
skill_identifies_package="false"
if [ -f "$skill_root/SKILL.md" ] && grep -Eq '^name:[[:space:]]*ultron-orchestrator[[:space:]]*$' "$skill_root/SKILL.md"; then
    skill_identifies_package="true"
fi

printf '%s\n' "$agent_roots" | while IFS= read -r agent_root; do
    [ -n "$agent_root" ] || continue
    validate_marker "$agent_root/$agent_marker_name"
done
printf '%s\n' "$prompt_roots" | while IFS= read -r prompt_root; do
    [ -n "$prompt_root" ] || continue
    validate_marker "$prompt_root/$prompt_marker_name"
done

check_destination "$skill_root/SKILL.md" "$skill_identifies_package"

printf '%s\n' "$agent_roots" | while IFS= read -r agent_root; do
    [ -n "$agent_root" ] || continue
    for source_agent in "$source_agents"/*.agent.md; do
        agent_name=$(basename -- "$source_agent")
        managed="false"
        if is_managed_name "$agent_root" "$agent_marker_name" "$agent_name" agent; then
            managed="true"
        fi
        check_destination "$agent_root/$agent_name" "$managed"
    done
done

printf '%s\n' "$prompt_roots" | while IFS= read -r prompt_root; do
    [ -n "$prompt_root" ] || continue
    for source_prompt in "$source_prompts"/*.prompt.md; do
        prompt_name=$(basename -- "$source_prompt")
        managed="false"
        if is_managed_name "$prompt_root" "$prompt_marker_name" "$prompt_name" prompt; then
            managed="true"
        fi
        check_destination "$prompt_root/$prompt_name" "$managed"
    done
done

if { [ "$skill_identifies_package" = "true" ] || [ "$force" = "true" ]; } && [ -d "$skill_root" ]; then
    rm -rf "$skill_root"
fi

printf '%s\n' "$agent_roots" | while IFS= read -r agent_root; do
    [ -n "$agent_root" ] || continue
    remove_managed_files "$agent_root" "$agent_marker_name"
done

printf '%s\n' "$prompt_roots" | while IFS= read -r prompt_root; do
    [ -n "$prompt_root" ] || continue
    remove_managed_files "$prompt_root" "$prompt_marker_name"
done

copy_package_file "$package_root/skills/ultron-orchestrator/SKILL.md" "$skill_root/SKILL.md"

printf '%s\n' "$agent_roots" | while IFS= read -r agent_root; do
    [ -n "$agent_root" ] || continue
    for source_agent in "$source_agents"/*.agent.md; do
        copy_package_file "$source_agent" "$agent_root/$(basename -- "$source_agent")"
    done
    write_agent_marker "$agent_root"
done

printf '%s\n' "$prompt_roots" | while IFS= read -r prompt_root; do
    [ -n "$prompt_root" ] || continue
    for source_prompt in "$source_prompts"/*.prompt.md; do
        copy_package_file "$source_prompt" "$prompt_root/$(basename -- "$source_prompt")"
    done
    write_prompt_marker "$prompt_root"
done

printf "Installed Copilot Ultron package for scope '%s'.\n" "$scope"