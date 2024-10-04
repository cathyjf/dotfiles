#!/bin/bash -e

default_cat() {
    exec /bin/cat
}

fish_bin="$(command -v fish)" || default_cat
rclone_bin="$(command -v rclone)" || default_cat
input_data=$(</dev/stdin)
{
    "${fish_bin}" -N -c '$argv[1] --config (psub) config show' "${rclone_bin}" <<< "${input_data}"
} || {
    echo "${input_data}"
}