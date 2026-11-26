#!/bin/sh
# A script ShellCheck has nothing to say about: the image-contract check runs
# the binary against it and requires a silent exit 0.
set -eu

greet() {
    printf 'hello, %s\n' "$1"
}

greet "${1:-world}"
