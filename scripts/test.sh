#!/usr/bin/env bash
set -u -o pipefail

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

    EXPECTED_WITH_TIME=$(bash -c "time bash <(cat $TEMP_FILE)" 2>&1)
    EXPECTED=$(ghead -n -3 <<<"$EXPECTED_WITH_TIME")
    EXPECTED_TIME=$(gtail -n -3 <<<"$EXPECTED_WITH_TIME" | tr '\n' ' ')
    EXPECTED_EXIT_CODE="$?"

    ACTUAL_WITH_TIME=$(bash -c "time $TURTLE_BIN <(cat $TEMP_FILE)" 2>&1)
    ACTUAL=$(ghead -n -3 <<<"$ACTUAL_WITH_TIME")
    ACTUAL_TIME=$(gtail -n -3 <<<"$ACTUAL_WITH_TIME" | tr '\n' ' ')
    ACTUAL_EXIT_CODE="$?"

    OUTPUTS_MATCH=
    [[ "$ACTUAL" == "$EXPECTED" ]] && OUTPUTS_MATCH=1

    STATUS_CODES_MATCH=
    [[ "$ACTUAL_EXIT_CODE" == "$EXPECTED_EXIT_CODE" ]] && STATUS_CODES_MATCH=1

    if [[ "$OUTPUTS_MATCH" == 1 && "$STATUS_CODES_MATCH" == 1 ]]; then
        echo "PASS: $NAME"

        if [[ "$PROFILE" == 1 ]]; then
            echo " - expected time: $EXPECTED_TIME"
            echo " - actual time  : $ACTUAL_TIME"
        fi

        return
    fi

    echo "FAIL: $NAME"

    if [[ "$STATUS_CODES_MATCH" != 1 ]]; then
        echo " - expected exit code: $EXPECTED_EXIT_CODE"
        echo " - actual exit code  : $ACTUAL_EXIT_CODE"
    fi

    if [[ "$OUTPUTS_MATCH" != 1 ]]; then
        echo " - expected: $EXPECTED"
        echo " - actual  : $ACTUAL"
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
        BUILD_OUTPUT=$(mktemp)
        if ! "$(dirname "$0")/build.sh" | tee "$BUILD_OUTPUT"; then
            echo 'build failed'
            cat "$BUILD_OUTPUT"
            exit 1
        fi

        echo "built"
    fi

    tests
}

tests() {
    t 'vars' 'FOO=bar; echo $FOO'
    t 'vars - env (ignored)' 'FOO=bar echo $FOO'
    t 'vars - proc sub' 'FOO=<(echo foo bar) echo $FOO'
    t 'vars - command sub' 'FOO=$(echo foo bar) echo $FOO'
    t 'pipes' 'echo world | sed "s/o/a/"'
    t 'pipes - with ||' 'echo world | sed "s/o/a/" || true'
    t 'pipes - with &&' 'echo world | sed "s/o/a/" && true'
    t 'pipes - with || - pre' 'true || echo world | sed "s/o/a/"'
    t 'pipes - with && - pre' 'true && echo world | sed "s/o/a/"'
    t 'comments' 'echo foo bar baz #foo bar'
    t 'command sub' 'echo $(echo foo) $(echo bar)'
    t 'command sub - no space' 'echo $(echo foo)$(echo bar)'
    t 'proc sub' 'cat <(echo foo bar)'
    t 'proc sub - multiple' 'cat <(echo foo) <(echo bar)'
    t 'proc sub - with pipeline' 'cat <(echo hello world | cut -d " " -f 1) <(echo world)'
    t 'multiple stmts' 'echo foo; echo bar;'
    t 'and - true' 'true && echo foo'
    t 'and - false' 'false && echo foo'
    t 'or - true' 'true || echo foo'
    t 'or - false' 'false || echo foo'
    t 'dot source' '. <(echo "echo foo")'
    t 'strings - raw' 'echo foo bar baz'
    t 'strings - single quote' $'echo \'foo bar\' baz'
    t 'strings - single quote - vars' $'FOO=foo; echo \'$FOO bar\' baz'
    t 'strings - double quote' 'echo "foo bar" baz'
    t 'strings - single quote - vars' $'FOO=foo; echo "$FOO bar" baz'

    echo 'DONE'
}

main "$@"
