#!/usr/bin/env bash

clang -fcolor-diagnostics -fansi-escape-codes -g *.c -o ./build/turtle $(pkg-config --cflags --libs glib-2.0)