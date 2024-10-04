#!/bin/bash

chezmoi_encrypted_files_excluded=0
# shellcheck disable=SC2206
chezmoi_arg_array=( ${CHEZMOI_ARGS:?} )
chezmoi_num_args=${#chezmoi_arg_array[@]}
for (( i = 0; i < chezmoi_num_args; ++i )); do
    current_arg=${chezmoi_arg_array[$i]}
    next_arg=${chezmoi_arg_array[$(( i + 1 ))]:-}
    if [[ ${current_arg} = '--exclude' || ${current_arg} = '-x' ]]; then
        if [[ ${next_arg} = 'encrypted' ]]; then
            chezmoi_encrypted_files_excluded=1
            break
        fi
    fi
done