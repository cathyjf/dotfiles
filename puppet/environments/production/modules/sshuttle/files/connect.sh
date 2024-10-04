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
while IFS='' read -r pid; do
    pids+=( "${pid}" );
done < <(/usr/bin/pgrep -u "${UID}")
if [[ ${#pids[@]} -gt 0 ]]; then
    username="$(/usr/bin/id -P | /usr/bin/cut -f 1 -d ':')"
    echo 'Killing existing '"${username}"' procesess: '"${pids[*]}"'.'
    jobs=()
    for pid in "${pids[@]}"; do
        ( while kill "${pid}" 2>/dev/null; do /bin/sleep 0.2; done ) &
        jobs+=( "${!}" )
    done
    wait "${jobs[@]}"
fi

readonly hostname=cathy-alienware
/bin/mkdir -p ../logs
log_filename="$(/bin/realpath ../logs)/${hostname}.log"
readonly log_filename
[[ -f ${log_filename} ]] && /bin/mv -f "${log_filename}" "${log_filename}.bak"

echo "Connecting to ${hostname} via sshuttle..."
(
    set +e
    while IFS='' read -r line; do
        printf '[%s] %s\n' "$(/bin/date -Iseconds)" "${line}"
    done < <(
        while true; do
            ./run -r "${hostname}" "${hostname}:7573" "${option_verbose[@]}" --remote-shell powershell --python py 2>&1 <&-
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

    if [ "${#pids[@]}" -ne "0" ]; then
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