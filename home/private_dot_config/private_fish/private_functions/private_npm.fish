function npm --wraps npm
    function __npm_inner
        command npm $argv
    end

    argparse --ignore-unknown 'g/global' -- $argv
    if set -ql _flag_global
        # Globally installed packages should be readable by all users.
        apply_liberal_umask __npm_inner $_flag_global $argv
    else
        __npm_inner $argv
    end
end