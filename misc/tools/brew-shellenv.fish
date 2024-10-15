#!/usr/bin/env fish --no-config

test -n "$CHEZMOI_HOME_DIR" || begin
    echo 'This script must be invoked by chezmoi. Aborting.' >&2
    exit 1
end

/usr/bin/env -i HOME=$CHEZMOI_HOME_DIR \
    (chezmoi execute-template '{{ template `brew-root` . }}')/bin/brew shellenv fish