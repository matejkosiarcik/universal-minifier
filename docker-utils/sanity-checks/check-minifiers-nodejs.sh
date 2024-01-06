#!/bin/sh
set -euf

tmpdir="$(mktemp -d)"

terser --version >/dev/null
terser --help >/dev/null

runTerser() {
    printf '%s\n' "$1" >"$tmpdir/file.js"
    (cd "$tmpdir" && terser file.js --output file.js)
    find "$tmpdir" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
}

runTerser 'let foo = "foo"'
