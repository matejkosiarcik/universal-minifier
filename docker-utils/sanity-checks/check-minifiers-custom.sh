#!/bin/sh
set -euf

tmpdir="$(mktemp -d)"

runYaml() {
    printf '%s\n' "$1" >"$tmpdir/file.yml"
    (cd "$tmpdir" && node "/app/dist/cli.js" --quiet .)
    find "$tmpdir" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
}

runYaml '"foo"'
runYaml 'foo:\n  - bar\n'

node "/app/dist/cli.js" --version >/dev/null 2>&1
node "/app/dist/cli.js" --help >/dev/null 2>&1
