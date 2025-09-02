function pass --wraps pass
    # This function (pass) is a wrapper for pass(1) that provides special
    # handling for displaying PDF secrets. The `--raw` argument can be
    # supplied as an argument to bypass this wrapper and invoke the original
    # pass(1) instead.

    # Ensure that git hooks are correctly set up for pass(1).
    if not grep -q "^[[:space:]]*hooksPath = .githooks\$" $PASSWORD_STORE_DIR/.git/config 2>/dev/null
        GIT_DIR="$PASSWORD_STORE_DIR/.git" git config --local core.hooksPath .githooks
    end

    switch (count $argv)
        case 1
            # If there's only one argument, that argument is a potential filename.
            set -f pass_filename $argv[1]
        case 2
            # If there are exactly two arguments and the first argument is "show",
            # the second argument is a potential filename.
            test $argv[1] = "show" && set -f pass_filename $argv[2]
    end

    # If we didn't identify a potential filename, fall through to pass(1).
    # Also fall through if the user specified the --raw option.
    argparse --ignore-unknown "raw" -- $argv
    if ! set -qf pass_filename || set -ql  _flag_raw
        command pass $argv
        return
    end

    if test -f "$PASSWORD_STORE_DIR/$pass_filename.gpg" -a (path extension -- $pass_filename) = ".pdf"
        # If the potential filename corresponds to an item in the password store and
        # the filename ends in ".pdf", open the item with my pass(1) pdf extension.
        command pass pdf $pass_filename
    else
        # Otherwise, fall through to pass(1).
        command pass $argv
    end
end