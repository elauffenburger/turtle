#!/usr/bin/env bash

set -m

usage() {
    echo "usage: $0 [--duration duration [samplingInterval]] [--file output-file]"
}

main() {
    duration=30
    file='./build/perf.txt'

    while :; do
        case "$!" in
        '--duration')
            shift
            duration="$1"

            break
            ;;

        '--help')
            usage
            exit 0
            ;;

        '--file')
            shift
            file="$1"

            break
            ;;

        '')
            break
            ;;

        *)
            usage
            exit 1
            ;;
        esac

        shift

    done

    ./bin/build.sh

    # Start turtle in the background.
    ./build/turtle &
    turtle_pid="$!"

    # Start sampling in the background.
    sample "$turtle_pid" "$duration" -f "$file" 2>/dev/null &
    sample_pid="$!"

    # Bring turtle to the foreground.
    fg %1 >/dev/null
}

main "$@"
