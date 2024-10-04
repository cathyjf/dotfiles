#!/bin/bash -e

chezmoi_misc_path="$(chezmoi execute-template '{{ .chezmoi.miscDir }}')" || exit 1
source "${chezmoi_misc_path}/gpg/source/key-details"

GNUPGHOME="$(chezmoi target-path)/.gnupg"
export GNUPGHOME

# Don't decrypt the key unless we can get the primary key keygrip from chezmoi.
primary_key_keygrip="$(chezmoi execute-template '{{ .gpg.cathyPrimaryKeyKeygrip }}')" || exit 1

gpg --decrypt "$KEY_DIR/private.key.asc" | gpg --import --import-options restore

PRIMARY_KEYGRIP="${primary_key_keygrip}.key"
PRIMARY_KEY_FILE="$GNUPGHOME/private-keys-v1.d/$PRIMARY_KEYGRIP"
if [ -f "$PRIMARY_KEY_FILE" ]; then
    FILE_SIZE=$(du -s "$PRIMARY_KEY_FILE" | awk '{print $1}')
    if [ "$FILE_SIZE" -ge 5 ]; then
        truncate -s 0 "$PRIMARY_KEY_FILE"
        echo "Replaced $PRIMARY_KEYGRIP with a placeholder."
    fi
fi

MIGRATE_KEYS_BIN="$GNUPGHOME/migrate-keys"
if [ -x "$MIGRATE_KEYS_BIN" ]; then
    eval "$MIGRATE_KEYS_BIN"
fi