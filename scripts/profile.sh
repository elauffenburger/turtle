#!/usr/bin/env bash
set -eu -o pipefail

usage() {
    echo "usage: $0 [--duration duration [samplingInterval]] [--file output-file]"
    exit 1
}

main() {
    SAMPLE_DURATION_SEC=30
    FILE='./build/perf.txt'

    while [[ "$#" -gt 0 ]]; do
        case "$!" in
        '--duration')
            shift
            SAMPLE_DURATION_SEC="$1"
            ;;

        '--help')
            usage
            ;;

        '--file')
            shift
            FILE="$1"
            ;;

        *)
            echo "unknown flag $1"
            usage
            ;;
        esac

        shift
    done

    ./bin/build.sh

    # Start turtle in the background.
    ./build/turtle &
    TURTLE_PID="$!"

    # Start sampling in the background.
    sample "$TURTLE_PID" "$SAMPLE_DURATION_SEC" -f "$FILE" 2>/dev/null &
    SAMPLE_PID="$!"
    trap 'kill $SAMPLE_PID' EXIT

    # Bring turtle to the foreground.
    fg %1 >/dev/null
}

main "$@"