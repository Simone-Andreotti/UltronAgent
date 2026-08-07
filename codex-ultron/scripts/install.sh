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

case "$scope" in
    user)
        codex_home=${CODEX_HOME:-"$HOME/.codex"}
        agent_root="$codex_home/agents"
        skill_root="$HOME/.agents/skills/codex-ultron"
        ;;
    project)
        [ -d "$project_path" ] || { printf "Project path does not exist: %s\n" "$project_path" >&2; exit 1; }
        resolved_project=$(CDPATH= cd -- "$project_path" && pwd)
        agent_root="$resolved_project/.codex/agents"
        skill_root="$resolved_project/.agents/skills/codex-ultron"
        ;;
    *)
        printf 'Invalid scope: %s\n' "$scope" >&2
        usage >&2
        exit 2
        ;;
esac

check_destination() {
    if [ -e "$1" ] && [ "$force" != "true" ]; then
        printf "Refusing partial install because '%s' exists. Re-run with --force to replace existing files.\n" "$1" >&2
        exit 1
    fi
}

copy_package_file() {
    mkdir -p "$(dirname -- "$2")"
    cp "$1" "$2"
}

check_destination "$skill_root/SKILL.md"
check_destination "$skill_root/agents/openai.yaml"
for source_agent in "$package_root"/agents/*.toml; do
    check_destination "$agent_root/$(basename -- "$source_agent")"
done

if [ "$scope" = "user" ]; then
    for source_profile in "$package_root"/profiles/*.config.toml; do
        check_destination "$codex_home/$(basename -- "$source_profile")"
    done
else
    check_destination "$resolved_project/.codex/config.toml"
fi

copy_package_file "$package_root/skills/codex-ultron/SKILL.md" "$skill_root/SKILL.md"
copy_package_file "$package_root/skills/codex-ultron/agents/openai.yaml" "$skill_root/agents/openai.yaml"
for source_agent in "$package_root"/agents/*.toml; do
    copy_package_file "$source_agent" "$agent_root/$(basename -- "$source_agent")"
done

if [ "$scope" = "user" ]; then
    for source_profile in "$package_root"/profiles/*.config.toml; do
        copy_package_file "$source_profile" "$codex_home/$(basename -- "$source_profile")"
    done
else
    copy_package_file "$package_root/config/codex-config.example.toml" "$resolved_project/.codex/config.toml"
fi

printf "Installed Codex Ultron package for scope '%s'.\n" "$scope"