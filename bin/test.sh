#!/usr/bin/env bash

usage() {
    echo "usage: $0 [--no-build]"
}

t() {
    name=$1
    shift

    args=()
    for arg in "$@"; do
        args+=("$arg")
    done

    arg_n=${#args[@]}
    expected=${args[$(($arg_n - 1))]}
    expected=${expected:1:-1}
    unset args[$(($arg_n - 1))]
    unset arg_n

    actual=$(./build/turtle -c "${args[*]}")

    if [[ "$expected" != "$actual" ]]; then
        echo "- FAIL: $name"
        echo "  - expected: '$expected'"
        echo "  - actual: '$actual'"
    else
        echo "- PASS: $name"
    fi
}

tests() {
    t 'vars' 'foo=bar; echo $foo' "'bar'"
    t 'vars - env' 'foo=bar echo $foo' ""
    t 'comments' 'echo foo bar baz #foo bar' "'foo bar baz'"
    t 'process sub' 'echo $(echo foo) $(echo bar)' "'foo bar'"
    t 'dot source' ". <(echo 'echo foo')" "'foo'"
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
