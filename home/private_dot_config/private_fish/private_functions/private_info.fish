function info --description 'Convert info(1) manual into man(1) page and then display it'
    command info $argv --subnodes -o - | while read read_line
        echo "  $read_line"
    end | $MANPAGER
end