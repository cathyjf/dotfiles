function brew --wraps brew
    function __brew_inner
        command brew $argv
        set -l status_code $status
        test $status_code -eq 0 || return $status_code
        test (count $argv) -eq 1 || return 0

        if test $argv[1] = "update"
            echo Running `brew livecheck --newer-only`...
            command brew livecheck --newer-only
        else if test $argv[1] = "upgrade"
            echo Running `mas upgrade`...
            mas upgrade
        end
    end

    set -l old_umask (umask)
    umask 0022 # u=rwx,go=rx

    __brew_inner $argv
    set -l return_value $status

    umask $old_umask
    return $reutrn_value
end