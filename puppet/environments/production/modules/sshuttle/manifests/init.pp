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
    $shell_uid = shell_escape(String($facts['cathy_uid']))
    $shell_username = shell_escape($facts['cathy_username'])
    $gnupghome = shell_escape($facts['gnupghome'])
    $gpg_bin = shell_escape($facts['gpg_bin'])
    $source = shell_escape("${file_title}.asc")
    $target = shell_escape($file_title)
    exec { "decrypt ${file_title}.asc" :
        require => File[$file_directory, "${file_title}.asc", $file_title],
        # This condition can be run as Cathy without root access because checking the size of
        # the file apparently only requires read access to the enclosing directory, not read
        # access to the file itself.
        onlyif  => "/bin/test `stat -f %z ${target}` -le 0",
        umask   => $sshuttle::default_umask,
        # The point of this complicated formulation is to avoid running the untrusted `gpg`
        # binary as root, while still writing to a location that Cathy cannot write to.
        command => @("EOT")
            /usr/bin/sudo -u ${shell_username} /bin/launchctl asuser ${shell_uid} \
                /usr/bin/env GNUPGHOME=${gnupghome} \
                    ${gpg_bin} --decrypt ${source} > ${target}
            |-EOT
    }
}

# A full configuration of the `sshuttle` program.
class sshuttle {
    $home = '/var/sshuttle'
    $username = '_sshuttle'
    $safe_username = sanitized_username($username)
    $groupname = '_sshuttle'
    $default_umask = '0077'

    # Set up user and group.
    user { $username:
        ensure => present,
        home   => $home,
        shell  => '/usr/bin/false',
        gid    => get_gid($groupname)
    }
    group { $groupname:
        ensure  => present,
        require => User[$username],
        members => [$username]
    }
    exec { "mark user as hidden: ${username}":
        require => User[$username],
        command => ['/usr/bin/dscl', '.',
            'create', "/Users/${safe_username}", 'IsHidden', '1'],
        unless  => @("EOT")
            /bin/test "`/usr/bin/dscl . read /Users/${safe_username} IsHidden`" \
                = 'dsAttrTypeNative:IsHidden: 1'
            |-EOT
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

    # This `$sudoers_prefix_sshuttle` variable is referenced in the `sshuttle/sudoers.erb` template.
    $sudoers_prefix_sshuttle = @("EOT")
        ${safe_username} ALL = (root) NOPASSWD: /usr/bin/env PYTHONPATH=/private/var/sshuttle/sshuttle \
            /Applications/Xcode.app/Contents/Developer/usr/bin/python3 \
            /private/var/sshuttle/sshuttle/sshuttle/__main__.py
        |-EOT
    file { '/etc/sudoers.d/sshuttle-service':
        ensure       => file,
        content      => template('sshuttle/sudoers.erb'),
        mode         => '0440',
        validate_cmd => $chezmoi::validate_sudoers
    }

    # Ensure that Cathy can read the non-sensitive files in the `_sshuttle` home directory.
    # This may allow `puppet apply` to create a diff without root access.
    chezmoi::file_readable_by_user {
        [
            '/etc/sudoers.d/sshuttle-service',
            "${home}/sshuttle.tar.bz2", "${home}/connect.sh", "${home}/.ssh/config",
            # Note: Only the encrypted SSH keys appear in this list, not the unencrypted ones.
            "${home}/.ssh/known_hosts.asc", "${home}/.ssh/id_ed25519.asc", "${home}/.ssh/id_ed25519.pub.asc"
        ]:
    }
}