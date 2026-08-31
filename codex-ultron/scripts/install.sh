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
        config_root="$resolved_project/.codex"
        skill_root="$resolved_project/.agents/skills/codex-ultron"
        ;;
    *)
        printf 'Invalid scope: %s\n' "$scope" >&2
        usage >&2
        exit 2
        ;;
esac

check_destination() {
    destination=$1
    managed=${2:-false}
    if [ -e "$destination" ] && [ "$force" != "true" ] && [ "$managed" != "true" ]; then
        printf "Refusing partial install because '%s' exists. Re-run with --force to replace existing files.\n" "$destination" >&2
        exit 1
    fi
}

copy_package_file() {
    mkdir -p "$(dirname -- "$2")"
    cp "$1" "$2"
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
        agent:edith.toml|agent:jarvis.toml|agent:luna_code_analyst.toml|agent:luna_researcher.toml|agent:luna_worker.toml|agent:ultron.toml|profile:edith.config.toml|profile:jarvis.config.toml|profile:ultron.config.toml)
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

write_marker_from_glob() {
    root=$1
    marker_name=$2
    shift 2
    mkdir -p "$root"
    : > "$root/$marker_name"
    for source_file in "$@"; do
        basename -- "$source_file" >> "$root/$marker_name"
    done
}

agent_marker_name=".codex-ultron-agents"
profile_marker_name=".codex-ultron-profiles"
config_marker_name=".codex-ultron-config"
skill_identifies_package="false"
if [ -f "$skill_root/SKILL.md" ] && grep -Eq '^name:[[:space:]]*codex-ultron[[:space:]]*$' "$skill_root/SKILL.md"; then
    skill_identifies_package="true"
fi


validate_marker "$agent_root/$agent_marker_name"
if [ "$scope" = "user" ]; then
    validate_marker "$codex_home/$profile_marker_name"
else
    validate_marker "$config_root/$config_marker_name"
fi

check_destination "$skill_root/SKILL.md" "$skill_identifies_package"
check_destination "$skill_root/agents/openai.yaml" "$skill_identifies_package"
for source_agent in "$package_root"/agents/*.toml; do
    agent_name=$(basename -- "$source_agent")
    managed="false"
    if is_managed_name "$agent_root" "$agent_marker_name" "$agent_name" agent; then
        managed="true"
    fi
    check_destination "$agent_root/$agent_name" "$managed"
done

if [ "$scope" = "user" ]; then
    for source_profile in "$package_root"/profiles/*.config.toml; do
        profile_name=$(basename -- "$source_profile")
        managed="false"
        if is_managed_name "$codex_home" "$profile_marker_name" "$profile_name" profile; then
            managed="true"
        fi
        check_destination "$codex_home/$profile_name" "$managed"
    done
else
    managed="false"
    if is_managed_name "$config_root" "$config_marker_name" "codex-ultron.example.toml" config; then
        managed="true"
    fi
    check_destination "$config_root/codex-ultron.example.toml" "$managed"
fi

if { [ "$skill_identifies_package" = "true" ] || [ "$force" = "true" ]; } && [ -d "$skill_root" ]; then
    rm -rf "$skill_root"
fi
remove_managed_files "$agent_root" "$agent_marker_name"
if [ "$scope" = "user" ]; then
    remove_managed_files "$codex_home" "$profile_marker_name"
else
    remove_managed_files "$config_root" "$config_marker_name"
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
    write_marker_from_glob "$codex_home" "$profile_marker_name" "$package_root"/profiles/*.config.toml
else
    copy_package_file "$package_root/config/codex-config.example.toml" "$config_root/codex-ultron.example.toml"
    mkdir -p "$config_root"
    printf '%s\n' "codex-ultron.example.toml" > "$config_root/$config_marker_name"
fi

write_marker_from_glob "$agent_root" "$agent_marker_name" "$package_root"/agents/*.toml

printf "Installed Codex Ultron package for scope '%s'.\n" "$scope"