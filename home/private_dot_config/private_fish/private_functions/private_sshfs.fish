function sshfs
    command sshfs -o defer_permissions,follow_symlinks,noapplexattr,noappledouble,reconnect -o Compression=no $argv
end