#!/usr/bin/env bash
set -e -o pipefail

cat <<EOF
foo: $FOO
bar: $BAR
$@
EOF