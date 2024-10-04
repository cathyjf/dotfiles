function pdfdecrypt --description 'Remove password from PDF' --argument FILENAME
    set -l GS_BIN (brew --prefix --installed ghostscript 2>/dev/null)/bin/gs
    if test $status -ne 0
        echo "Error: ghostscript is not installed. Try:" 1>&2
        echo "    brew install ghostscript" 1>&2
        return 1
    end
    set -l OUTPUT_FILE (dirname $FILENAME)/(basename -s ".pdf" $FILENAME)" (Unencrypted).pdf"
    $GS_BIN -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile=$OUTPUT_FILE $FILENAME
    if test $status -eq 0
        echo "Wrote $OUTPUT_FILE"
    end
end