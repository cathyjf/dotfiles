#!/bin/bash

chezmoi_misc_path="$(chezmoi execute-template '{{ .chezmoi.miscDir }}')" || exit 1

# shellcheck source-path=SCRIPTDIR
source "${chezmoi_misc_path}/gpg/source/key-details"

gpg --armor --export-options backup --export "$KEY_ID" | \
    gpg --armor --encrypt -r "$KEY_ID" > "$KEY_DIR/public.key.asc"

gpg --armor --export-options backup --export-secret-key "$KEY_ID" | \
    gpg --armor --encrypt -r "$KEY_ID" > "$KEY_DIR/private.key.asc"