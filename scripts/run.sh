#!/usr/bin/env bash
set -eu -o pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")

. "$SCRIPT_DIR/build.sh"
"$SCRIPT_DIR/../zig-out/bin/turtle" "$@"