#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
plugin_name="ultron-orchestrator"
marketplace_name="ultron-agent"

command -v copilot >/dev/null 2>&1 || {
    printf '%s\n' "Copilot CLI was not found. Install it before installing the plugin." >&2
    exit 1
}

installed_plugins=$(copilot plugin list)
if printf '%s\n' "$installed_plugins" | grep -Eq '^[[:space:]]*([^[:space:]]+[[:space:]]+)?ultron-orchestrator(@[[:alnum:]._-]+)?([[:space:]]|\(|$)'; then
    copilot plugin uninstall "$plugin_name"
fi

registered_marketplaces=$(copilot plugin marketplace list)
if printf '%s\n' "$registered_marketplaces" | grep -Eq '^[[:space:]]*([^[:space:]]+[[:space:]]+)?ultron-agent([[:space:]]|\(|$)'; then
    copilot plugin marketplace remove "$marketplace_name"
fi

copilot plugin marketplace add "$package_root"
copilot plugin install "$plugin_name@$marketplace_name"
printf "Installed the current %s@%s Copilot plugin.\n" "$plugin_name" "$marketplace_name"