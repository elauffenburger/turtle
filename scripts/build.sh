#!/usr/bin/env bash

main() {
    # If zig-out doesn't exist already, assume this is the first build
    # and try to install deps.
    if [[ ! -d "$(dirname $0)/../zig-out" ]]; then
        brew install readline
        brew install glib
    fi

    zig build
}

main "$@"
