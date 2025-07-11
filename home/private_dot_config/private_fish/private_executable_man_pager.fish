#!/usr/bin/env fish

function __get_default_browser
    defaults read ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure | \
        awk -F'"' '/http;/{print window[(NR)-1]}{window[NR]=$2}'
end

argparse --ignore-unknown "chrome" "title=" -- $argv || exit
if set -ql _flag_chrome
    set -l html_title (begin; set -ql _flag_title && echo $_flag_title; end || echo "stdin")

    set -l temp_dir (mktemp -d)
    chmod -R go-rwx $temp_dir
    set -l temp_body $temp_dir/body
    set -l temp_html $temp_dir/terminal.xhtml
    aha --no-header $argv > $temp_body
    m4 -D HTML_TITLE="$html_title" -D HTML_TEXT="undivert(`$temp_body')" \
        (status dirname)/terminal_html.m4 > $temp_html
    rm $temp_body
    open -b (__get_default_browser) $temp_html &

    set -l fish_bin (status fish-path)
    $fish_bin -c 'sleep 3; rm -Rf -- $argv[1]' $temp_dir &
    disown
    exit
end

# Fall back to `less -s` if we're using ssh or if recode(1) and aha(1) are both unavailable.
begin
    test -n "$SSH_CLIENT" || begin
        ! which -s recode && ! which -s aha
    end
end && exec less -s

set -l man_title (
    if which -s recode
        ps -o command= -p (ps -o ppid= -p $fish_pid) |
            grep -o "man .*" |
            tr -d \n |
            recode utf-8..html
    else
        echo "man"
    end)

set -l this_script (status filename)
if which -s aha
    ul
else
    col -b | recode utf-8..html
end | $this_script --chrome --title $man_title --stylesheet