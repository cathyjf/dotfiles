#!/bin/bash
set -efuC -o pipefail

echo 'Finished application of public dotfiles.'

chezmoi_target_path="${CHEZMOI_HOME_DIR:?}"
chezmoi_misc_path="$(chezmoi execute-template '{{ .chezmoi.miscDir }}')" || exit 1
readonly chezmoi_target_path chezmoi_misc_path

source "${chezmoi_misc_path}/tools/set-common-variables.sh"
: "${chezmoi_encrypted_files_excluded:?}"

BREW_ROOT=$(chezmoi execute-template '{{ template "brew-root" . }}') || exit 1
readonly BREW_ROOT

# We will invoke `tput` if and only if stdout is a terminal.
# Otherwise, replace `tput` with a no-op.
if [[ ! -t 1 ]]; then
    tput() { :; }
fi

# Disable automatic line wrap until this script exits. This is required for the
# fancy cursor manipulation in `apply_operation` to work correctly.
tput rmam
trap 'tput smam' 0

declare __lines_printed
__echo_increment() {
    : $(( ++__lines_printed ))
    echo -E "${@:-}"
}

__printfln_wrap() {
    local text width lines=1
    # shellcheck disable=SC2059
    printf -v text "${@}"
    if [[ -t 1 ]]; then
        width=$(tput cols)
        lines=$(( ${#text} / width + ((${#text} % width) ? 1 : 0) ))
    fi
    if [[ ${lines} -eq 1 ]]; then
        __echo_increment "${text}"
    else
        local i
        for ((i = 0; i < lines; ++i)) do
            __echo_increment "${text:$(( i * width )):${width}}"
        done
    fi
}

# shellcheck disable=SC2312
__indent_text_inner() {
    local -r IFS=''
    local -r include_final_newline=$1
    local line
    __lines_printed=0
    while read -r line; do
        __printfln_wrap '    %s' "${line}"
    done < <(
        local exit_status=0
        "${@:2}" 2>&1 || exit_status="${?}"
        if [[ ${exit_status} -ne 0 ]]; then
            printf '[!] Operation failed (exit status %d).\n' "${exit_status}"
        fi
    )
    if [[ ${include_final_newline} -eq 1 && ${__lines_printed} -gt 0 ]]; then
        __echo_increment
    fi
}

indent_text_with_final_newline() {
    __indent_text_inner 1 "${@}"
}

indent_text() {
    __indent_text_inner 0 "${@}"
}

unix_epoch() {
    # The `gdate` command is provided by the brew `coreutils` formula.
    gdate +%s.%N
}

apply_operation() {
    local initial_time
    initial_time="$(unix_epoch)"
    printf 'Running operation: %s.\n' "${@}"
    indent_text_with_final_newline "${@}"

    # Move the cursor up by `__lines_printed + 1` lines.
    # See https://stackoverflow.com/a/53820485/1976484.
    tput cuu $(( __lines_printed + 1 ))

    tput el # Clear the line to the right of the cursor.
    printf 'Completed operation: %s (%.2f s).\n' "${@}" \
        "$(bc <<< "$(unix_epoch) - ${initial_time}")"

    # Move the cusor back down by `__lines_printed` lines.
    if [[ ${__lines_printed} -gt 0 ]]; then
        tput cud $(( __lines_printed ))
    fi
    # If stdout isn't a terminal, print an extra newline.
    if [[ ! -t 1 ]]; then
        printf '\n'
    fi
}

make_windows_file_history() {
    if ! make install -q -C "${chezmoi_misc_path}/unlock-windows-file-history"; then
        make install DRYRUN=1 -C "${chezmoi_misc_path}/unlock-windows-file-history"
    fi
}

maybe_test_gpg_key() {
    if [[ ${chezmoi_encrypted_files_excluded} -eq 1 ]]; then
        return
    elif ! "${chezmoi_misc_path}/gpg/is-key-different.sh"; then
        return
    fi
    echo "The GPG key on this machine may be out of date."
    echo
    echo "To import and merge the key stored in the source repository, run:"
    echo "    ${chezmoi_misc_path}/gpg/import-key.sh"
    echo
    echo "To export the newly-merged key to the source repository, run:"
    echo "    ${chezmoi_misc_path}/gpg/export-key.sh"
}

test_gpg_secret_key_backups() {
    if tmutil isexcluded "${HOME}/.gnupg/private-keys-v1.d" | grep -q "\[Excluded\]"; then
        return
    fi
    echo "Warning: Time Machine is currently backing up your GPG secret keys."
    echo "This may be undesirable."
    echo
    echo "To disable this behavior, run:"
    echo "    sudo tmutil addexclusion -p ${HOME}/.gnupg/private-keys-v1.d"
}

has_hardened_runtime() {
    codesign -d --verbose "$1" 2>&1 | grep -q "flags=0x10000(runtime)"
}

ensure_hardened_runtime() {
    if [[ -x ${1} ]] && ! has_hardened_runtime "${1}"; then
        echo "Warning: The $(basename "${1}") binary should use the hardened runtime environment but does not."
        echo "To fix this, try:"
        local identity
        identity=$(security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}")
        echo "    codesign -f --options runtime -s \"${identity}\" \"${1}\""
    fi
}

test_pinentry_symlink() {
    local pinentry_symlink="${BREW_ROOT}/opt/pinentry/bin/pinentry"
    local pinentry_mac_binary="${BREW_ROOT}/bin/pinentry-mac"
    if [[ $(readlink -- "${pinentry_symlink}") != "${pinentry_mac_binary}" ]]; then
        echo "If pinentry-touchid isn't working correctly, try:"
        echo "    ln -f -s ${pinentry_mac_binary} ${pinentry_symlink}"
    fi
}

verify_file_is_indelible() {
    # TODO: This function should verify that each parent in the directory tree is also indelible.
    if [ ! -e "$1" ]; then
        echo "Warning: File $1 should exist but does not."
        echo "This can probably be fixed by running one of the preceding suggested commands."
        return
    fi
    declare stat_data ls_data owner_change_needed permission_change_needed acl_change_needed
    declare -r IFS=' '
    # shellcheck disable=SC2207
    if ! stat_data=( $(stat -f "%u %g %p" "$1") ); then
        echo "Error: Failed to check whether $1 is indelible."
        return
    elif [ "${stat_data[*]:0:2}" != "0 0" ]; then
        # If we get here, the file is not owned by root:wheel.
        owner_change_needed=1
    fi
    # The %p field from stat contains the value of st_mode in octal but without a leading
    # zero. The result of (st_mode & 0700) gives the octal permissions of the file.
    # (For more information, see https://stackoverflow.com/a/24315637.)
    # We want to verify that the file has permissions 0600 (only owner may read or write).
    if [ "$(( (0${stat_data[2]} & 0700) == 0600 ))" -ne 1  ]; then
        # If we get here, the file's permissions are not 0600.
        permission_change_needed=1
    fi
    if ls_data=$(ls -le "$1") || ! grep -q "group:everyone deny delete" <<< "$ls_data"; then
        acl_change_needed=1
    fi
    if [ $owner_change_needed ] || [ $permission_change_needed ] || [ $acl_change_needed ]; then
        echo "Warning: File $1 should be indelible but is not."
        echo "To make $1 indelible, run:"
        if [ $owner_change_needed ]; then
            echo "    sudo chown root:wheel $1"
        fi
        if [ $permission_change_needed ]; then
            echo "    sudo chmod 600 $1"
        fi
        if [ $acl_change_needed ]; then
            echo "    sudo chmod +a \"group:everyone deny delete\" $1"
        fi
    fi
}

diff_puppet_chezmoi() {
    local chezmoi_puppet_path apply_path
    echo 'Computing the Puppet diff will take several seconds.'
    echo 'Puppet wants to apply the following changes (if any) to root configuration files:'
    chezmoi_puppet_path="$(chezmoi execute-template '{{ .chezmoi.puppetDir }}')" || return 1
    apply_path="${chezmoi_puppet_path}"/apply.sh
    indent_text "${apply_path}" --without-root --noop --show_diff --suppress-explanations --no-color
    echo 'To apply the Puppet manifests (if needed), run:'
    echo "    ${apply_path}"
}

maybe_apply_private_dotfiles() {
    [[ ${chezmoi_encrypted_files_excluded} -ne 0 ]] && return
    : "${chezmoi_arg_array:?}"
    echo 'This will require decrypting files contained within the chezmoi repository, so you'
    echo 'will be prompted to use your GPG key, unless gpg-agent has your key cached because'
    echo 'you used the key recently for something else.'
    "${chezmoi_target_path}/.config/cathy/chezmoi-private.sh" "${chezmoi_arg_array[@]:1}"
}

apply_finder_defaults() {
    # Enable hidden files in finder, unless they're already enabled.
    # shellcheck disable=SC2155
    local hidden_files="$(defaults read com.apple.finder AppleShowAllFiles 2> /dev/null || echo 0)"
    if [[ "${hidden_files}" -ne 1 ]]; then
        defaults write com.apple.finder AppleShowAllFiles -bool true
        echo 'Finder has been configured to show hidden files and will now restart.'
        osascript -e 'quit app "Finder"'
    fi
}

# Samba server.
# TODO: Make this indelibility test actually be useful.
# apply_operation verify_file_is_indelible "$BREW_ROOT"/etc/smb.conf

apply_operation maybe_apply_private_dotfiles
apply_operation make_windows_file_history

# TODO: This check for whether the GPG key is out of date is far too sensitive
#       and it frequently triggers when nothing meaningful has changed. This
#       test should be improved.
apply_operation maybe_test_gpg_key
# apply_operation test_gpg_secret_key_backups
apply_operation test_pinentry_symlink
apply_operation apply_finder_defaults

# TODO: Hardening these runtimes is currently not a particularly large security improvement.
#       I need to come up with a bettter solution for this.
# apply_operation ensure_hardened_runtime "$BREW_ROOT/bin/pinentry-touchid"
# apply_operation ensure_hardened_runtime "$BREW_ROOT/bin/pinentry-tty"
# apply_operation ensure_hardened_runtime "$BREW_ROOT/bin/pinentry-mac"

apply_operation diff_puppet_chezmoi