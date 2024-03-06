#!/usr/bin/env bash
set -eu -o pipefail

. "$(dirname $0)/build.sh"
"$(dirname $0)/../zig-out/bin/turtle"