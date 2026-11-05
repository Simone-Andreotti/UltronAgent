#!/usr/bin/env sh
set -eu

exec sh "$(dirname -- "$0")/start-claude.sh" --agent edith "$@"
