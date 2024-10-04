#!/bin/bash

chezmoi_misc_path="$(chezmoi execute-template '{{ .chezmoi.miscDir }}')" || exit 1
source "${chezmoi_misc_path}/gpg/source/key-details"

LOCAL_KEY_HASH=$(gpg --quiet --export --export-options backup "$KEY_ID" | gpg --list-packets | sha256sum)
SOURCE_KEY_HASH=$(gpg --quiet --decrypt "$KEY_DIR/public.key.asc" | gpg --list-packets | sha256sum)

[ "$LOCAL_KEY_HASH" != "$SOURCE_KEY_HASH" ]