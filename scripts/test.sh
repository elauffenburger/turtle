#!/usr/bin/env bash

TURTLE_BIN="$(dirname "$0")/../zig-out/bin/turtle"

SKIP_BUILD=
PROFILE=

usage() {
    cat <<EOF
usage: $0 [ARGS...]

ARGS:
    --no-build  skips the build step
EOF
    exit 1
}

t() {
    NAME="$1"
    shift

    TEMP_FILE=$(mktemp)
    echo "$*" >"$TEMP_FILE"

    EXPECTED_WITH_TIME=$(/usr/bin/env bash -c "time /usr/bin/env bash <(cat $TEMP_FILE)" 2>&1)
    EXPECTED=$(ghead -n -3 <<<"$EXPECTED_WITH_TIME")
    EXPECTED_TIME=$(gtail -n -3 <<<"$EXPECTED_WITH_TIME" | tr '\n' ' ')
    EXPECTED_EXIT_CODE="$?"

    ACTUAL_WITH_TIME=$(/usr/bin/env bash -c "time $TURTLE_BIN <(cat $TEMP_FILE)" 2>&1)
    ACTUAL=$(ghead -n -3 <<<"$ACTUAL_WITH_TIME")
    ACTUAL_TIME=$(gtail -n -3 <<<"$ACTUAL_WITH_TIME" | tr '\n' ' ')
    ACTUAL_EXIT_CODE="$?"

    OUTPUTS_MATCH=
    [[ "$ACTUAL" == "$EXPECTED" ]] && OUTPUTS_MATCH=1

    STATUS_CODES_MATCH=
    [[ "$ACTUAL_EXIT_CODE" == "$EXPECTED_EXIT_CODE" ]] && STATUS_CODES_MATCH=1

    if [[ "$OUTPUTS_MATCH" == 1 && "$STATUS_CODES_MATCH" == 1 ]]; then
        echo "- PASS: $NAME"

        if [[ "$PROFILE" == 1 ]]; then
            echo "  - expected time: $EXPECTED_TIME"
            echo "  - actual time  : $ACTUAL_TIME"
        fi

        return
    fi

    echo "- FAIL: $NAME"

    if [[ "$STATUS_CODES_MATCH" != 1 ]]; then
        echo "  - expected exit code: $EXPECTED_EXIT_CODE"
        echo "  - actual exit code  : $ACTUAL_EXIT_CODE"
    fi

    if [[ "$OUTPUTS_MATCH" != 1 ]]; then
        echo "  - expected: $EXPECTED"
        echo "  - actual  : $ACTUAL"
    fi
}

main() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        '--no-build')
            SKIP_BUILD=1
            ;;

        '--profile')
            PROFILE=1
            ;;
        *)
            echo "unknown flag $1"
            usage
            ;;
        esac

        shift
    done

    if [[ "$SKIP_BUILD" != 1 ]]; then
        # Build turtle.
        echo "building..."
        BUILD_OUTPUT=$($(dirname "$0")/build.sh 2>&1)
        if [[ "$?" != 0 ]]; then
            echo 'build failed'
            echo "$BUILD_OUTPUT"
            exit 1
        fi

        echo "built"
    fi

    tests
}

tests() {
    t 'vars' 'foo=bar; echo $FOO'
    t 'vars - env' 'foo=bar echo $FOO'
    t 'pipes' 'echo world | xargs -I{} echo "hello {}!"'
    t 'comments' 'echo foo bar baz #foo bar'
    t 'command sub' 'echo $(echo foo) $(echo bar)'
    t 'proc sub' 'cat <(echo foo bar)'
    t 'multiple stmts' 'echo foo; echo bar;'
    t 'and - true' 'true && echo foo'
    t 'and - false' 'false && echo foo'
    t 'or - true' 'true || echo foo'
    t 'or - false' 'false || echo foo'
    t 'dot source' '. <(echo "echo foo")'
    t 'strings' 'echo "foo"'
}

main "$@"
