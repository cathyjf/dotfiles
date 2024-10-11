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
    exec { "decrypt ${file_title}.asc" :
        require => File[$file_directory, "${file_title}.asc", $file_title],
        # This condition can be run as Cathy without root access because checking the size of
        # the file apparently only requires read access to the enclosing directory, not read
        # access to the file itself.
        onlyif  => [[
            '/bin/bash', '-c', '[[ $(/usr/bin/stat -f %z "$1") -le 0 ]]', 'argv0', $file_title
        ]],
        umask   => $sshuttle::default_umask,
        command => [
            '/bin/bash', '-c', (
                # The point of this formulation is to avoid running the untrusted `gpg` binary
                # as root, while still writing to a location to which only the `_sshuttle`
                # user can write. The curly braces are used to make the logic clearer.
                @(EOT)
                {
                    /usr/bin/sudo -u "$1" /bin/launchctl asuser "$2" \
                        /usr/bin/env -i GNUPGHOME="$3" "$4" --decrypt "$5"
                } | {
                    /usr/bin/sudo -u "$6" /bin/cat > "$7"
                }
                |-EOT
            ), 'argv0',
            $facts['cathy_username'], String($facts['cathy_uid']),
            $facts['gnupghome'], $facts['gpg_bin'], "${file_title}.asc",
            $sshuttle::default_file_params['owner'], $file_title
        ]
    }
}

# A full configuration of the `sshuttle` program.
class sshuttle {
    $home = '/var/sshuttle'
    $username = '_sshuttle'
    $groupname = '_sshuttle'
    $default_umask = '0077'

    # Set up user and group.
    cathyjf::role_account_and_group {
        $username:
            groupname => $groupname,
            home      => $home
    }

    $default_file_params = {
        ensure => file,
        owner  => $username,
        group  => $groupname,
        mode   => 'u+rwX,g=,o='
    }
    file {
        default:
            * => $default_file_params;
        [$home, "${home}/.ssh", "${home}/sshuttle"]:
            ensure  => directory;
        ["${home}/logs/cathy-alienware.log", "${home}/logs/cathy-alienware.log.bak"]: ;
        "${home}/sshuttle.tar.bz2":
            source         => 'puppet:///modules/sshuttle/sshuttle-2f3171670c6188eb842912bf0ab7f93dc0da179b.tar.bz2',
            checksum_value => '85810f8caace52d4a00dd0ad77a4b5cd74ad0a32a7e36fa3d6eb87bd858f9c49';
        "${home}/.ssh/config":
            source => 'puppet:///modules/sshuttle/ssh/config';
        "${home}/connect.sh":
            source => 'puppet:///modules/sshuttle/connect.sh',
            mode   => 'u+rwx,g=,o=';
    }
    sshuttle::encrypted_ssh_key { ['known_hosts', 'id_ed25519', 'id_ed25519.pub']: }

    exec { 'uncompress sshuttle.tar.bz2':
        # We need to use `sudo` here to run the command as the `_sshuttle` service user, instead
        # of specifying the `user` property of the `exec` resource, because specifying the `user`
        # property causes `puppet apply` to refuse to run without root access, whereas by using
        # `sudo` instead, we can still cause `puppet apply` to prepare a diff without root access.
        command     => [
            '/usr/bin/sudo', '-u', $username,
                '/usr/bin/tar',
                    '-f', "${home}/sshuttle.tar.bz2", '-x', '-p', '--strip-components', '1',
                    '-C', "${home}/sshuttle"
        ],
        require     => User[$username],
        subscribe   => File["${home}/sshuttle.tar.bz2"],
        refreshonly => true,
        umask       => $default_umask
    }

    # These two variables are referenced in the `sshuttle/sudoers.erb` template.
    $sudoers_username = sanitized_username($username)
    $sudoers_prefix_sshuttle = @("EOT")
        ${sudoers_username} ALL = (root) NOPASSWD: /usr/bin/env PYTHONPATH=/private/var/sshuttle/sshuttle \
            /Applications/Xcode.app/Contents/Developer/usr/bin/python3 \
            /private/var/sshuttle/sshuttle/sshuttle/__main__.py
        |-EOT
    file { '/etc/sudoers.d/sshuttle-service':
        ensure       => file,
        content      => template('sshuttle/sudoers.erb'),
        mode         => '0440',
        validate_cmd => $cathyjf::validate_sudoers
    }

    # Ensure that Cathy can read the non-sensitive files in the `_sshuttle` home directory.
    # This may allow `puppet apply` to create a diff without root access.
    cathyjf::file_readable_by_user {
        [
            '/etc/sudoers.d/sshuttle-service',
            "${home}/sshuttle.tar.bz2", "${home}/connect.sh", "${home}/.ssh/config",
            "${home}/logs/cathy-alienware.log", "${home}/logs/cathy-alienware.log.bak",
            # Note: Only the encrypted SSH keys appear in this list, not the unencrypted ones.
            "${home}/.ssh/known_hosts.asc", "${home}/.ssh/id_ed25519.asc", "${home}/.ssh/id_ed25519.pub.asc"
        ]:
    }
}