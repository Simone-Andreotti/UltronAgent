#!/usr/bin/env sh
set -eu

scope=user
project_path=$(pwd)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --scope) scope=$2; shift 2 ;;
        --project-path) project_path=$2; shift 2 ;;
        *) echo "Unsupported argument: $1. Use --scope user|project|local and --project-path." >&2; exit 2 ;;
    esac
done
case "$scope" in
    user|project|local) ;;
    *) echo "Scope must be user, project, or local." >&2; exit 2 ;;
esac

command -v claude >/dev/null 2>&1 || { echo "Claude Code CLI was not found. Install it before installing the plugin." >&2; exit 1; }
package_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# The marketplace is a local folder, so sessions read the plugin from this checkout.
# Adding it again is harmless and points it here after the checkout moves.
claude plugin marketplace add "$package_root"

cd "$project_path"
claude plugin install leads@ultron-claude --scope "$scope"

echo "Installed leads@ultron-claude at $scope scope. Run /reload-plugins or start a new session to load it."
