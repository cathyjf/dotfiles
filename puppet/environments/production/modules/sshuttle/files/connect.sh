#!/usr/bin/env -i /bin/bash -e
# shellcheck disable=SC2096
# shellcheck shell=bash

export PATH=/usr/bin:/bin
cd ~/sshuttle

option_stream_seconds=1.5
option_verbose=()
option_exit_early=
while [[ ${#} -gt 0 ]]; do
    if [[ ${1} = '-s' ]]; then
        if [[ -n ${2} && ${2} =~ ^[0-9]{0,5}\.?[0-9]{0,5}$ ]]; then
            option_stream_seconds=${2}
            shift 2
        else
            echo 'Error: Invalid syntax for parameters: '"${1} ${2}" >&2
            exit 1
        fi
    elif [[ ${1} = '-v' ]]; then
        option_verbose+=( '-v' )
        shift
    elif [[ ${1} = '-x' ]]; then
        option_exit_early=1
        shift
    else
        echo 'Error: Unknown parameter: '"${1}" >&2
        exit 1
    fi
done

pids=()
username="$(/usr/bin/id -P | /usr/bin/cut -f 1 -d ':')"
while IFS='' read -r pid; do
    pids+=( "${pid}" );
done < <(/usr/bin/pgrep -u "${UID}")
if [[ ${#pids[@]} -gt 0 ]]; then
    pgids=()
    for pid in "${pids[@]}"; do
        pgids+=( "-$(/bin/ps -o pgid= "${pid}")" )
    done
    unique=()
    while IFS='' read -r item; do
        unique+=( "${item}" );
    done < <(printf '%s\n' "${pids[@]}" "${pgids[@]}" | sort | uniq)
    echo 'Killing existing '"${username}"' procesess: '"${unique[*]}"'.'
    jobs=()
    for pid in "${unique[@]}"; do
        ( while /bin/kill -- "${pid}" 2>/dev/null; do /bin/sleep 0.2; done ) &
        jobs+=( "${!}" )
    done
    wait "${jobs[@]}"
fi

readonly hostname=cathy-alienware
/bin/mkdir -p ../logs
log_filename="$(/bin/realpath ../logs)/${hostname}.log"
readonly log_filename
[[ -f ${log_filename} ]] && {
    /bin/cp -p -f "${log_filename}" "${log_filename}.bak"
    /usr/bin/truncate -s 0 "${log_filename}"
}

sshuttle_run="$(/bin/realpath ./run)"
sshuttle_conf="$(/bin/realpath ../.config/sshuttle.conf)"
echo "Launching sshuttle with config (${sshuttle_conf})..."
(
    set +e
    while IFS='' read -r line; do
        printf '[%s] %s\n' "$(/bin/date -Iseconds)" "${line}"
    done < <(
        while true; do
            PATH=/Library/Frameworks/Python.framework/Versions/3.13/bin:"${PATH}" \
                /usr/bin/caffeinate -im -- \
                    /usr/bin/sudo -n -- /usr/bin/nice -n '-20' -- /usr/bin/sudo -nu "${username}" -- \
                        "${sshuttle_run}" @"${sshuttle_conf}" "${option_verbose[@]}" 2>&1 <&-
            echo 'The sshuttle process ended. Relaunching it soon...'
            sleep 10
        done
    ) >> "${log_filename}"
) >&- 2>&- <&- &
disown -h "${!}"

echo 'Started sshuttle. Log location:'
echo "    ${log_filename}"

if [[ ${option_exit_early} -eq 1 ]]; then
    exit 0
fi

print_descendents() {
    local IFS=$'\n'
    local -a pids
    # shellcheck disable=SC2207
    pids=( $(pgrep -P "$1") )
    readonly pids
    echo "${pids[*]}"

    if [[ ${#pids[@]} -ne 0 ]]; then
        IFS=','
        print_descendents "${pids[*]}"
    fi
}

# shellcheck disable=SC2317
kill_tail_job() {
    IFS=$'\n'
    # shellcheck disable=SC2046
    kill "${1}" $(print_descendents "${1}") 2>/dev/null || true
    echo "Finished streaming log."
}
printf '\nNow streaming log for up to %g seconds:\n' "${option_stream_seconds}"
while IFS='' read -r line; do
    printf '    %s'$'\n' "${line}"
done < <(/usr/bin/tail -f "${log_filename}") &
readonly tail_job=${!}
# shellcheck disable=SC2064
trap "kill_tail_job '${tail_job}'" EXIT
/bin/sleep "${option_stream_seconds}"