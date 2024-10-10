#!/bin/bash
set -efu -o pipefail

fastfail() {
    "${@}" || {
        /bin/kill -- "-$(/bin/ps -o pgid= "${$}")" "${$}" > /dev/null 2>&1
    }
}

if [[ ${__DO_NOT_RECURSE:-0} -ne 1 ]]; then
    exec /usr/bin/sudo -u "$(fastfail /usr/bin/id -nu "${SUDO_UID:-${UID}}")" \
        --login __DO_NOT_RECURSE=1 /bin/bash "$(fastfail /bin/realpath "${0}")"
fi

# Do not run the remainder of this code as root.
[[ -n ${UID} && ${UID} -ne 0 ]] || {
    # Under normal circumstances, it should be impossible to reach this exit.
    # However, this will protect us against certain unintended uses of this script.
    exit 1
}

printf 'gpg_bin=%s\n' "$(fastfail command -v gpg)"
printf 'gnupghome=%s\n' "$(fastfail gpgconf --list-dirs homedir)"
printf 'brew_root=%s\n' "$(fastfail chezmoi execute-template '{{ template "brew-root" . }}')"
printf 'chezmoi_target=%s\n' "$(fastfail chezmoi target-path)"