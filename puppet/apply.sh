#!/bin/bash -e
gpg_bin="$(command -v gpg)"
chezmoi_target="$(chezmoi target-path)"
brew_root="$(chezmoi execute-template '{{ template "brew-root" . }}')"
PATH=/opt/puppetlabs/puppet/bin:/usr/bin:/bin
script_dir="$(/bin/realpath "$(/usr/bin/dirname "$0")")"
conf_dir="${script_dir}/config"
manifest_dir="$(puppet config print --confdir="${conf_dir}" manifest)"
readonly gpg_bin chezmoi_target brew_root PATH script_dir conf_dir manifest_dir

# shellcheck disable=SC2016
print_usage() {
    basename="$(basename "${0}")"
    echo "Usage: ${basename} [options]"
    echo 'Options:'
    echo '       --help'
    echo '           Print this usage infromation.'
    echo '       --suppress-explanations'
    echo '           Don'"'"'t print the `puppet` commands before executing them.'
    echo '       --without-root'
    echo '           Don'"'"'t become root when invoking `puppet apply`.'
    echo '       --only-chezmoi'
    echo '           Execute only the chezmoi-related manifests.'
    echo '       --ensure-stdlib'
    echo '           Ensure that the Puppet standard library is installed.'
    echo '       --debug'
    echo '       --detailed-exitcodes'
    echo '       --noop'
    echo '       --show_diff'
    echo '       --verbose'
    echo '          These options are directly passed through to `puppet apply`.'
}

sudo_user='root'
suppress_explanations=0
puppet_execution=( "${manifest_dir}" )
puppet_extra_args=()
ensure_stdlib=0
while [[ ${#} -gt 0 ]]; do
    case "${1}" in
        --help)
            print_usage
            exit 0
            ;;
        --suppress-explanations)
            suppress_explanations=1 ;;
        --without-root)
            sudo_user="${USER}" ;;
        --only-chezmoi)
            puppet_execution=( '-e' 'include chezmoi' ) ;;
        --ensure-stdlib)
            ensure_stdlib=1 ;;
        --debug | --detailed-exitcodes | --noop | --show_diff | --verbose)
            puppet_extra_args+=( "${1}" ) ;;
        *)
            printf 'Unrecognized argument: %s\n' "${1}" >&2
            print_usage
            exit 1
            ;;
    esac
    shift
done

execute_as_user() {
    username=${1}
    purpose=${2}
    shift 2
    if [[ ${suppress_explanations} -eq 0 ]]; then
        echo "This command will be executed as ${username} to ${purpose}:"
        for arg in "${@}"; do
            printf '    %s\n' "${arg}"
        done
    fi
    /usr/bin/sudo -u "${username}" -k "${@}"
}

extra_env_vars=( "PATH=${PATH}" "FACTERLIB=${script_dir}/facts" )
# Ensure that Ruby is configured to use UTF-8.
extra_env_vars+=( 'RUBYOPT=-Ku' )

if [[ ${ensure_stdlib} -eq 1 ]]; then
    root_module_path=/opt/puppetlabs/puppet/modules
    readonly root_module_path
    if [[ ! -d "${root_module_path}/stdlib" ]]; then
        echo 'The Puppet standard library needs to be installed.'
        execute_as_user 'root' 'install the Puppet standard library' \
            env -i "${extra_env_vars[@]}" \
            puppet module install puppetlabs-stdlib --version 9.6.0 --modulepath "${root_module_path}"
    fi
fi

execute_as_user "${sudo_user}" 'apply the Puppet manifests' \
    env -i "${extra_env_vars[@]}" \
    SUDO_UID="${UID}" FACTER_GPG_BIN="${gpg_bin}" FACTER_GNUPGHOME="${GNUPGHOME:?}" \
    FACTER_BREW_ROOT="${brew_root}" \
    FACTER_CHEZMOI_TARGET="${chezmoi_target}" \
    puppet apply --confdir="${conf_dir}" "${puppet_execution[@]}" \
    "${puppet_extra_args[@]}"