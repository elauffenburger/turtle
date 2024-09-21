#!/usr/bin/env bash
set -eu -o pipefail

ROOT_DIR="$(dirname "$0")/.."

main() {
    # If zig-out doesn't exist already, assume this is the first build
    # and try to install deps.
    if [[ ! -d "$ROOT_DIR/zig-out" ]]; then
        brew install readline
        brew install glib
    fi

    # Apply patches to libraries.
    patch -sN || true <<EOF "$ROOT_DIR/vendor/zig-tracy/build.zig"
58c58
<         .root_source_file = .{ .path = "./src/tracy.zig" },
---
>         .root_source_file = b.path("./src/tracy.zig"),
EOF

    zig build
}

main "$@"
