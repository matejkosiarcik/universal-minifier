#!/bin/sh
set -euf

tmpdir="$(mktemp -d)"

yq --version >/dev/null
yq --help >/dev/null

runYq() {
    printf '%s\n' "$1" >"$tmpdir/file.yml"
    (cd "$tmpdir" && yq '.' file.yml --yaml-output | sponge file.yml)

    printf '%s\n' "$1" >"$tmpdir/file.yaml"
    (cd "$tmpdir" && yq '.' file.yaml --yaml-output | sponge file.yaml)

    find "$tmpdir" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
}

runYq 'foo'
runYq '{ foo: bar }'
runYq '[foo, 123, true]'

runPyminifier() {
    printf '%s\n' "$1" >"$tmpdir/file.py"
    (cd "$tmpdir" && pyminifier --outfile=file.py file.py)

    find "$tmpdir" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
}

pyminifier --help
pyminifier --version
runPyminifier ''
runPyminifier 'foo = "123"\nprint(foo)\n'
