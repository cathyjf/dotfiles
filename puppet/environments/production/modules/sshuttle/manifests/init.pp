# An SSH key that needs to be decrypted using `gpg(1)`.
define sshuttle::encrypted_ssh_key {
    $file_directory = "${sshuttle::home}/.ssh"
    $file_title = "${file_directory}/${title}"
    file {
        default:
            * => $sshuttle::default_file_params;
        "${file_title}.asc":
            links  => follow,
            source => "puppet:///modules/sshuttle/ssh/keys/${title}.asc";
        $file_title:
    }
    exec { "decrypt ${file_title}.asc":
        require => File[$file_directory, "${file_title}.asc", $file_title],
        # This condition can be run as Cathy without root access because checking the size of
        # the file apparently only requires read access to the enclosing directory, not read
        # access to the file itself.
        onlyif  => [[
            '/bin/bash', '-c', '[[ $(/usr/bin/stat -f %z "$1") -le 0 ]]', 'argv0', $file_title
        ]],
        umask   => '0077',
        command => [
            '/bin/bash', '-c', (
                # The point of this formulation is to avoid running the untrusted `gpg` binary
                # as root, while still writing to a location to which only the `_sshuttle`
                # user can write.
                @(EOT)
                /usr/bin/sudo -u "$1" /bin/launchctl asuser "$2" \
                    /usr/bin/env -i GNUPGHOME="$3" "$4" --decrypt < "$5" > "$6"
                |-EOT
            ), 'argv0',
            $facts['cathy_username'], String($facts['cathy_uid']),
            $facts['gnupghome'], $facts['gpg_bin'], "${file_title}.asc", $file_title
        ]
    }
}

# A full configuration of the `sshuttle` program.
class sshuttle {
    $home = '/var/sshuttle'
    $username = '_sshuttle'
    $groupname = '_sshuttle'

    # Set up user and group.
    cathyjf::role_account_and_group {
        $username:
            groupname => $groupname,
            home      => $home
    }

    $default_file_params = {
        ensure => file,
        owner  => 'root',
        group  => $groupname,
        mode   => 'ugo=,g+rX'
    }
    file {
        default:
            * => $default_file_params;
        [$home, "${home}/.config", "${home}/.ssh", "${home}/sshuttle"]:
            ensure => directory;
        "${home}/logs":
            ensure => directory,
            mode   => 'ug=xrw,o=';
        ["${home}/logs/cathy-alienware.log", "${home}/logs/cathy-alienware.log.bak"]:
            mode   => 'ug=rw,o=';
        "${home}/sshuttle.tar.bz2":
            source         => 'puppet:///modules/sshuttle/sshuttle-1.3.1.tar.bz2',
            checksum_value => 'c16aaa686789a6e7d22392220f712a0b11d1f947f5aee5c32d63bd23fd2100c9';
        "${home}/.config/sshuttle.conf":
            source => 'puppet:///modules/sshuttle/sshuttle.conf';
        "${home}/.ssh/config":
            source => 'puppet:///modules/sshuttle/ssh/config';
        "${home}/connect.sh":
            source => 'puppet:///modules/sshuttle/connect.sh',
            mode   => 'uo=,g=rx';
    }
    sshuttle::encrypted_ssh_key { ['known_hosts', 'id_ed25519', 'id_ed25519.pub']: }

    exec { 'uncompress sshuttle.tar.bz2':
        # We need to use `sudo` here to run the command as the `root:_sshuttle` identity, instead
        # of specifying the `user` property of the `exec` resource, because specifying the `user`
        # property causes `puppet apply` to refuse to run without root access, whereas by using
        # `sudo` instead, we can still cause `puppet apply` to prepare a diff without root access.
        command     => [
            '/bin/bash', '-e', '-c', (
                @(EOT)
                    /usr/bin/sudo -u root -g "$1" \
                        /usr/bin/tar --no-same-owner -f "$2" -x --strip-components 1 -C "$3"
                    /bin/chmod -R "$4" "$3"
                    |-EOT
                ), 'argv0',
                $groupname, "${home}/sshuttle.tar.bz2", "${home}/sshuttle",
                $default_file_params['mode']
        ],
        require     => [
            User[$username], Group[$groupname],
            # This requirement is necessary so that puppet can become `root:_sshuttle`.
            File['/etc/sudoers.d/sshuttle-service']
        ],
        subscribe   => File["${home}/sshuttle.tar.bz2"],
        refreshonly => true,
        umask       => '0706' # ~(uo=,g=rwx)
    }

    file { '/etc/sudoers.d/sshuttle-service':
        ensure       => file,
        mode         => '0440',
        validate_cmd => $cathyjf::validate_sudoers,
        content      => epp('sshuttle/sudoers.epp', {
            username  => $username,
            groupname => $groupname,
            cathy_uid => $facts['cathy_uid'],
            firewall  => [
                '/Applications/Xcode.app/Contents/Developer/usr/bin/python3',
                '/Library/Frameworks/Python.framework/Versions/3.13/bin/python3'
            ].reduce('') |$memo, $python| {
                @("EOT")
                    ${memo}
                    ${username} ALL = (root) NOPASSWD: /usr/bin/env \
                        ^PYTHONPATH=/private/var/sshuttle/sshuttle \
                            ${regexpescape(stdlib::shell_escape($python))} \
                                /private/var/sshuttle/sshuttle/sshuttle/__main__\.py \
                                    (-v ?){0,2} --method auto --firewall$
                    |-EOT
            }.lstrip
        }),
    }

    # Ensure that Cathy can read the non-sensitive files in the `_sshuttle` home directory.
    # This may allow `puppet apply` to create a diff without root access.
    cathyjf::file_readable_by_user {
        [
            '/etc/sudoers.d/sshuttle-service', "${home}/.config/sshuttle.conf",
            "${home}/sshuttle.tar.bz2", "${home}/connect.sh", "${home}/.ssh/config",
            "${home}/logs/cathy-alienware.log", "${home}/logs/cathy-alienware.log.bak",
            # Note: Only the encrypted SSH keys appear in this list, not the unencrypted ones.
            "${home}/.ssh/known_hosts.asc", "${home}/.ssh/id_ed25519.asc", "${home}/.ssh/id_ed25519.pub.asc"
        ]:
    }
}