#!/bin/sh
set -euf

tmpdir="$(mktemp -d)"

sh "${BINPREFIX:-}Minify.sh"
