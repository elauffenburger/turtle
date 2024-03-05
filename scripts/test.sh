#!/usr/bin/env bash

profile=

usage() {
    echo "usage: $0 [--no-build]"
    exit 1
}

t() {
    name=$1
    shift

    temp_file=$(mktemp)
    echo "$*" >$temp_file

    expected_with_time=$(/usr/bin/env bash -c "time /usr/bin/env bash <(cat $temp_file)" 2>&1)
    expected=$(head -n -3 <<<"$expected_with_time")
    expected_time=$(tail -n -3 <<<"$expected_with_time" | tr '\n' ' ')
    expected_exit_code="$?"

    actual_with_time=$(/usr/bin/env bash -c "time ./build/turtle <(cat $temp_file)" 2>&1)
    actual=$(head -n -3 <<<"$actual_with_time")
    actual_time=$(tail -n -3 <<<"$actual_with_time" | tr '\n' ' ')
    actual_exit_code="$?"

    local outputs_match
    [[ "$actual" == "$expected" ]] && outputs_match=true

    local status_codes_match
    [[ "$actual_exit_code" == "$expected_exit_code" ]] && status_codes_match=true

    if [[ "$outputs_match" == 'true' && "$status_codes_match" == 'true' ]]; then
        echo "- PASS: $name"

        if [[ "$profile" == 1 ]]; then
            echo "  - expected time: $expected_time"
            echo "  - actual time  : $actual_time"
        fi

        return
    fi

    echo "- FAIL: $name"

    if [[ "$status_codes_match" != 'true' ]]; then
        echo "  - expected exit code: $expected_exit_code"
        echo "  - actual exit code  : $actual_exit_code"
    fi

    if [[ "$outputs_match" != 'true' ]]; then
        echo "  - expected: $expected"
        echo "  - actual  : $actual"
    fi
}

tests() {
    t 'vars' 'foo=bar; echo $foo'
    t 'vars - env' 'foo=bar echo $foo'
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
}

main() {
    skip_build=
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        '--no-build')
            skip_build=1
            ;;

        '--profile')
            profile=1
            ;;
        *)
            echo "unknown flag $1"
            usage
            ;;
        esac

        shift
    done

    if [[ "$skip_build" != 1 ]]; then
        # Build turtle.
        echo "building..."
        build_output=$(./bin/build.sh 2>&1)
        if [[ $? != 0 ]]; then
            echo 'build failed'
            echo "$build_output"
            exit 1
        fi

        echo "built"
    fi

    tests
}

main "$@"
