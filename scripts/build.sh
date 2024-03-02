#!/usr/bin/env bash

main() {
    brew install readline
    brew install glib

    zig build
}

main "$@"
