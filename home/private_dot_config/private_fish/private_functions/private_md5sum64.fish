function md5sum64 --description 'Print base64-encoded MD5 message digest' --argument FILENAME
    # See https://stackoverflow.com/a/4584064.
    openssl dgst -md5 -binary $FILENAME | openssl enc -base64
end