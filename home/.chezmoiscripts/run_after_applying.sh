#!/bin/bash

chezmoi_source_path="${CHEZMOI_SOURCE_DIR:?}"
chezmoi_target_path="${CHEZMOI_HOME_DIR:?}"
chezmoi_misc_path="$(chezmoi execute-template '{{ .chezmoi.miscDir }}')" || exit 1

source "${chezmoi_misc_path}/tools/set-common-variables.sh"
: "${chezmoi_encrypted_files_excluded:?}"
if [[ ${chezmoi_encrypted_files_excluded} -eq 0 ]]; then
    echo '    This will require decrypting files contained within the chezmoi repository, so you'
    echo '    will be prompted to use your GPG key, unless gpg-agent has your key cached because'
    echo '    you used the key recently for something else.'
    "${chezmoi_target_path}/.config/cathy/chezmoi-private.sh" "${chezmoi_arg_array[@]:1}"
fi

echo 'Finished application of changes to user dotfiles.'

declare BREW_ROOT
BREW_ROOT=$(chezmoi execute-template '{{ template "brew-root" . }}')

queue() {
    local entry
    entry="$("${@}")"
    if [ -n "${entry}" ]; then
        printf "\n***\n\n%s\n" "${entry}"
    fi
}

make_windows_file_history() {
    if ! make install -q -C "${chezmoi_misc_path}/unlock-windows-file-history"; then
        make install DRYRUN=1 -C "${chezmoi_misc_path}/unlock-windows-file-history"
    fi
}

test_gpg_key() {
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
    if tmutil isexcluded "$HOME/.gnupg/private-keys-v1.d" | grep -q "\[Excluded\]"; then
        return
    fi
    echo "Warning: Time Machine is currently backing up your GPG secret keys."
    echo "This may be undesirable."
    echo
    echo "To disable this behavior, run:"
    echo "    sudo tmutil addexclusion -p $HOME/.gnupg/private-keys-v1.d"
}

has_hardened_runtime() {
    codesign -d --verbose "$1" 2>&1 | grep -q "flags=0x10000(runtime)"
}

ensure_hardened_runtime() {
    if [ -x "$1" ] && ! has_hardened_runtime "$1"; then
        echo "Warning: The $(basename "$1") binary should use the hardened runtime environment but does not."
        echo "To fix this, try:"
        local IDENTITY
        IDENTITY=$(security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}")
        echo "    codesign -f --options runtime -s \"$IDENTITY\" \"$1\""
    fi
}

test_pinentry_symlink() {
    local PINENTRY_SYMLINK="$BREW_ROOT/opt/pinentry/bin/pinentry"
    local PINENTRY_MAC_BINARY="$BREW_ROOT/bin/pinentry-mac"
    if [ "$(readlink -- "$PINENTRY_SYMLINK")" != "$PINENTRY_MAC_BINARY" ]; then
        echo "If pinentry-touchid isn't working correctly, try:"
        echo "    ln -f -s $PINENTRY_MAC_BINARY $PINENTRY_SYMLINK"
    fi
}

test_acrobat_extension() {
    local OFFICE_DIRECTORY
    OFFICE_DIRECTORY="${chezmoi_target_path}"/Library/Group\ Containers/UBF8T346G9.Office
    local ACROBAT_OFFICE_EXTENSION=$OFFICE_DIRECTORY/User\ Content.localized/Startup.localized/Word/linkCreation.dotm
    if [ -f "$ACROBAT_OFFICE_EXTENSION" ]; then
        echo "The Adobe Acrobat extension for Microsoft Office is currently installed."
        echo "This low-quality extension causes error messages to appear when loading Word documents."
        echo
        echo "There is no obvious downside to removing the extension."
        echo
        echo "To remove the Acrobat extension for Office, run:"
        echo "    rm \"$ACROBAT_OFFICE_EXTENSION\""
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
    echo "Puppet wants to apply the following changes (if any) to root configuration files:"
    chezmoi_puppet_path="$(chezmoi execute-template '{{ .chezmoi.puppetDir }}')" || exit 1
    apply_path="${chezmoi_puppet_path}"/apply.sh
    while IFS='' read -r line; do
        printf '    %s\n' "${line}"
    done < <(
        "${apply_path}" --without-root --noop --show_diff --suppress-explanations
    )
    echo 'To apply the Puppet manifests (if needed), run:'
    echo "    ${apply_path}"
}

# Enable hidden files in finder, unless they're already enabled.
if ! FINDER_HIDDEN_FILES=$(defaults read com.apple.finder AppleShowAllFiles 2> /dev/null) || \
        [ "$FINDER_HIDDEN_FILES" -ne 1 ]; then
    defaults write com.apple.finder AppleShowAllFiles -bool true
    echo "Finder has been configured to show hidden files."
    while true; do
        read -r -p "Restart Finder.app now? [y/n] " RESTART_FINDER
        case $RESTART_FINDER in
            [Yy])
                osascript -e 'quit app "Finder"'
                break
                ;;
            [Nn])
                echo "    To restart Finder.app later, run:"
                echo "        osascript -e 'quit app \"Finder\"'"
                break
                ;;
            * )
                echo "    Please choose a valid option."
        esac
    done
    printf "\n***\n\n"
fi

# Samba server.
# TODO: Make this indelibility test actually be useful.
# queue verify_file_is_indelible "$BREW_ROOT"/etc/smb.conf

queue make_windows_file_history

# TODO: This check for whether the GPG key is out of date is far too sensitive
#       and it frequently triggers when nothing meaningful has changed. This
#       test should be improved.
queue test_gpg_key
# queue test_gpg_secret_key_backups
queue test_pinentry_symlink
queue test_acrobat_extension
# TODO: Hardening these runtimes is currently not a particularly large security improvement.
#       I need to come up with a bettter solution for this.
# queue ensure_hardened_runtime "$BREW_ROOT/bin/pinentry-touchid"
# queue ensure_hardened_runtime "$BREW_ROOT/bin/pinentry-tty"
# queue ensure_hardened_runtime "$BREW_ROOT/bin/pinentry-mac"

queue diff_puppet_chezmoi