function sshfs
    command sshfs -o defer_permissions,noapplexattr,noappledouble,reconnect -o Compression=no $argv
end