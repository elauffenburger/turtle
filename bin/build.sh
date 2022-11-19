#!/usr/bin/env bash

warnings=(
    -Wextra \
    -Wall \
    -Wfloat-equal \
    -Wundef \
    -Wshadow \
    -Wpointer-arith \
    -Wcast-align \
    -Wstrict-prototypes \
    -Wstrict-overflow=5 \
    -Wwrite-strings \
    -Waggregate-return \
    -Wcast-qual \
    -Wswitch-default \
    -Wswitch-enum \
    -Wconversion \
    -Wunreachable-code \
    -Wno-incompatible-pointer-types-discards-qualifiers \
)

ASAN_OPTIONS=detect_leaks=1 \
clang *.c \
    -g \
    "${warnings[@]}" \
    -fcolor-diagnostics \
    -fansi-escape-codes \
    -fsanitize=address\
    $(pkg-config --cflags --libs glib-2.0 readline) \
    -o ./build/turtle
