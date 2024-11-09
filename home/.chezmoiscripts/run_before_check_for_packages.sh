#!/bin/bash
set -efuC -o pipefail

chezmoi_source_path="${CHEZMOI_SOURCE_DIR:?}"
chezmoi_misc_path="$(chezmoi execute-template '{{ .chezmoi.miscDir }}')" || exit 1

BREW_ROOT="$(chezmoi execute-template '{{ template "brew-root" . }}')"
BREW_BIN="${BREW_ROOT}"/bin/brew

if [[ ! -x ${BREW_BIN} ]]; then
    echo "Homebrew is not installed but is required to run \`chezmoi apply\`." 1>&2
    echo "To install Homebrew, see: https://brew.sh" 1>&2
    echo 1>&2
    exit 1
fi

brew_bundle_args=( --no-upgrade --quiet --file "${chezmoi_misc_path}/Brewfile" )
if ! HOMEBREW_NO_AUTO_UPDATE=1 "${BREW_BIN}" bundle check "${brew_bundle_args[@]}"; then
    echo 'Executing `brew bundle install --no-upgrade`...'
    __status=0
    "${BREW_BIN}" bundle install "${brew_bundle_args[@]}" || __status="${?}"
    echo "Finished \`brew bundle install\`."
    if [[ ${__status} -ne 0 ]]; then
        echo "    Status code: ${__status}."
    fi
fi

export PERL_MM_OPT="INSTALL_BASE=${HOME}/perl5"
if ! perldoc -l local::lib 1>/dev/null 2>&1; then
    echo 'Installing local:lib for perl...'
    __status=0
    cpan local::lib || __status="${?}"
    echo 'Finished installing local::lib.'
    if [[ ${__status} -ne 0 ]]; then
        echo "    Status code: ${__status}."
    fi
fi

echo 'Beginning application of changes to user dotfiles...'

source "${chezmoi_misc_path}/tools/set-common-variables.sh"
if [[ ${chezmoi_encrypted_files_excluded:?} -ne 0 ]]; then
    echo '    Because you supplied `--exclude encrypted`, this operation should not use your GPG key.'
fi