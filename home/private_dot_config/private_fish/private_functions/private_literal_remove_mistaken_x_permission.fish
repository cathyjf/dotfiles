function remove_mistaken_x_permission -a file
    function __remove_mistaken_x_permission_inner -a file
        if test -L $file # Symbolic link.
            chmod -h a-x $file
            return 0
        else if test -d $file # Directory.
            return 0
        end

        # Skip native executables.
        # We need to use `gcut` because the version of `cut` that ships with macOS
        # does not support the use of null as a delimiter.
        set -l description (file -0 -- $file | head -n 1 | gcut -d '' -f 2)
        string match -q -v '*binary*' -- $description || return 0
        string match -q -v '*executable*' -- $description || return 0

        # Skip shell scripts.
        # This simplistic test should work for our purposes.
        test "$(head -c 3 -- $file)" != '#!/' || return 0

        chmod -h a-x $file
        echo 'Removed executable bit from' "$file."
    end

    # Iterate over all files that currently have the executable bit set.
    find -f $file -- -perm +111 -print0 | while read --local --null i
        __remove_mistaken_x_permission_inner $i
    end
end