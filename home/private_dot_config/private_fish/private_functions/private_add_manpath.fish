function add_manpath --description 'Add paths to MANPATH'
    for path in $argv
        if contains -- $path $MANPATH
            # Don't add a duplicate copy of the same path.
            continue
        end
        set -gx MANPATH "$MANPATH:$path"
    end
end
