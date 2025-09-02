function apply_liberal_umask
    set -l old_umask (umask)
    umask 0022 # u=rwx,go=rx

    $argv[1] $argv[2..]
    set -l return_value $status

    umask $old_umask
    return $return_value
end