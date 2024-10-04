function sshfs
    command sshfs -o defer_permissions,noapplexattr,noappledouble,reconnect $argv
end