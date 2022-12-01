#!/usr/bin/env bash

usage() {
    echo "usage: $0 [--no-build]"
}

t() {
    name=$1
    shift

    expected=$(bash -c "$@" 2>&1)
    expected_exit_code="$?"

    actual=$(./build/turtle -c "$@" 2>&1)
    actual_exit_code="$?"

    local outputs_match
    [[ "$actual" == "$expected" ]] && outputs_match=true

    local status_codes_match
    [[ "$actual_exit_code" == "$expected_exit_code" ]] && status_codes_match=true

    if [[ "$outputs_match" == 'true' && "$status_codes_match" == 'true' ]]; then
        echo "- PASS: $name"
        return
    fi

    echo "- FAIL: $name"

    if [[ "$status_codes_match" != 'true' ]]; then
        echo "  - expected exit code: $expected_exit_code"
        echo "  - actual exit code: $actual_exit_code"
    fi

    if [[ "$status_codes_match" != 'true' ]]; then
        echo "  - expected: '$expected'"
        echo "  - actual: '$actual'"
    fi
}

tests() {
    t 'vars' 'foo=bar; echo $foo'
    t 'vars - env' 'foo=bar echo $foo'
    t 'pipes' 'echo world | xargs -I{} echo "hello {}!"'
    t 'comments' 'echo foo bar baz #foo bar'
    t 'command sub' 'echo $(echo foo) $(echo bar)'
    t 'proc sub' 'cat <(echo foo bar)'
    t 'dot source' ". <(echo 'echo foo')"
    t 'multiple stmts' 'echo foo; echo bar;'
}

main() {
    skip_build=
    while :; do
        case $1 in
        '--no-build')
            skip_build=true
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

    if [[ "$skip_build" != 'true' ]]; then
        # Build turtle.
        echo "building..."
        build_output=$(./bin/build.sh 2>&1)
        if [[ $? != 0 ]]; then
            echo 'build failed'
            echo "$build_output"
            exit 1
        fi
    fi

    tests
}

main "$@"
