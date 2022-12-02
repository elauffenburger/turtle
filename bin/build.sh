#!/usr/bin/env bash

usage() {
    echo "usage: $1 [--debug]"
}

main() {
    flags=()
    debug=

    while :; do
        case "$1" in
        '--debug')
            debug=true
            ;;
        '--')
            shift
            flags+=("$*")
            ;;
        '') break ;;
        *)
            usage
            exit 1
            ;;
        esac

        shift
    done

    # Add misc. flags
    flags+=(
        -fcolor-diagnostics
        -fansi-escape-codes
    )

    # Add warnings
    flags+=(
        -Wextra
        -Wall
        -Wfloat-equal
        -Wundef
        -Wshadow
        -Wpointer-arith
        -Wcast-align
        -Wstrict-prototypes
        -Wstrict-overflow=5
        -Wwrite-strings
        -Waggregate-return
        -Wcast-qual
        -Wswitch-default
        -Wswitch-enum
        -Wconversion
        -Wunreachable-code
        -Wno-incompatible-pointer-types-discards-qualifiers
    )

    # Add optimmizations
    optimizations=()
    if [[ "$debug" == 'true' ]]; then
        flags+=(-g -fsanitize=address)
        
        export ASAN_OPTIONS=detect_leaks=1
    else
        flags+=(-O2)
    fi

    clang *.c \
        "${flags[@]}" \
        $(pkg-config --cflags --libs glib-2.0 readline) \
        -o ./build/turtle
}

main "$@"
