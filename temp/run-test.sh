#!/usr/bin/env bash
set -eu -o pipefail

"$(dirname "$0")/../scripts/build.sh"
cat <(./zig-out/bin/turtle -o command -c 'echo world | sed "s/o/a/" || true' | ghead -n -1) <(echo '}') | yq -p json -o yaml -I 1 | tee ./temp/out.yaml