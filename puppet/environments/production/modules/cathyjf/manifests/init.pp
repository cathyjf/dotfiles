# Use macOS ACLs to ensure that a particular file is readable by a given user.
define cathyjf::file_readable_by_user (
    String $username = $facts['cathy_username'],
    Boolean $is_directory = false
) {
    $acl = "read${$is_directory ? { true => ',search', false => '' }}"
    $acl_string = "user:${sanitized_username($username)} allow ${acl}"
    $condition_array = [
        ['/usr/bin/sudo', '-u', $username, '/bin/test', '(', '-r', $title, ')'] +
            ($is_directory ? {
                true  => ['-a', '(', '-r', "${title}/.", ')'],
                false => []
            })
    ]
    $parent = dirname($title)
    if !defined(Cathyjf::File_Readable_By_User[$parent]) {
        create_resources('cathyjf::file_readable_by_user', {
            $parent => {
                username     => $username,
                is_directory => true
            }
        })
    }
    $file_requirements = defined(File[$title]) ? { true => [File[$title]], false => [] }
    $requirements = $file_requirements + ($parent ? {
        '/'     => [],
        default => [Cathyjf::File_Readable_By_User[$parent]]
    })
    exec { "ensure ${username} can ${acl} ${title}":
        require => $requirements,
        command => ['/bin/chmod', '+a', $acl_string, $title],
        unless  => $condition_array
    }
}

# Define a role account and corresponding group.
define cathyjf::role_account_and_group (
    String $groupname,
    String $home,
    String $shell = '/usr/bin/false'
) {
    $username = $title
    group { $groupname:
        members => ((get_uid($username) != Undef) ? {
            true  => [$username],
            false => []
        })
    }
    user { $username:
        ensure => present,
        home   => $home,
        shell  => $shell,
        gid    => $groupname
    } -> cathyjf::ensure_group_contains_user($groupname, $username)
    $safe_username = sanitized_username($username)
    exec { "mark user as hidden: ${username}":
        require => User[$username],
        command => ['/usr/bin/dscl', '.',
            'create', "/Users/${safe_username}", 'IsHidden', '1'],
        unless  => @("EOT")
            /bin/test "`/usr/bin/dscl . read /Users/${safe_username} IsHidden`" \
                = 'dsAttrTypeNative:IsHidden: 1'
            |-EOT
    }
}

# Declare that a particular group has a particular member
function cathyjf::ensure_group_contains_user(String $groupname, String $username) {
    exec { "ensure ${username} is a member of ${groupname}":
        require => Group[$groupname],
        command => ['/usr/sbin/dseditgroup', '-o', 'edit', '-a', $username, '-t', 'user', $groupname],
        unless  => [['/usr/sbin/dseditgroup', '-o', 'checkmember', '-m', $username,  $groupname]]
    }
}

# Configure the fish shell.
class cathyjf::fish_shell {
    $fish_shell = "${facts['brew_root']}/bin/fish"
    $sanitized_username = sanitized_username($facts['cathy_username'])
    exec { "add ${fish_shell} to /etc/shells":
        command => ['/bin/bash', '-c', 'echo "$1" >> /etc/shells', 'argv0', $fish_shell],
        unless  => [['/usr/bin/grep', '-F', '-x', '-q', $fish_shell, '/etc/shells']]
    } -> exec { "set shell to ${fish_shell} for ${facts['cathy_username']}":
        command => ['/usr/bin/chsh', '-s', $fish_shell, $facts['cathy_username']],
        unless  => @("EOT")
            /bin/test "`/usr/bin/dscl . read /Users/${sanitized_username} UserShell | /usr/bin/sed 's/UserShell: //'`" \
                = ${shell_escape($fish_shell)}
            |-EOT
    }
}

# Configure certain macOS nvram variables.
class cathyjf::macos_nvram {
    # If macOS is configured to use external bluetooth adapters when they are plugged in
    # (which is the default), this causes problems when attempting to use VirtualHere USB
    # to share USB bluetooth adapters on the network. Setting this nvram variable prevents
    # macOS from using external blutooth adapters. A computer restart is necessary after
    # making this change, although this Puppet configuration does not currently enforce
    # the restart in any way.
    exec { 'prevent macOS from using an external bluetooth adapter':
        command => ['/usr/sbin/nvram', 'bluetoothHostControllerSwitchBehavior=never'],
        unless  => '/bin/test "`/usr/sbin/nvram bluetoothHostControllerSwitchBehavior | /usr/bin/cut -wf 2`" = \'never\''
    }
}

# Class used for deploying root config files to machines managed by Cathy.
class cathyjf {
    $validate_plist = '/usr/bin/plutil %'
    $validate_sudoers = '/usr/sbin/visudo -c -q -f %'
    $default_file_params = {
        ensure => file,
        owner  => 'root',
        group  => 'wheel',
        links  => follow,
        mode   => 'ugo=r'
    }
    file {
        default:
            * => $default_file_params;
        '/etc/puppetlabs/facter':
            ensure => directory,
            mode   => 'ugo=rx';
    }
    Hash({
        '/etc/hosts' => {},
        '/etc/pam.d/sudo_local' => {},
        '/etc/ppp/ip-up' => { mode => 'u=rx,go=r' },
        '/etc/puppetlabs/facter/facter.conf' => {
            source => 'puppet:///modules/cathyjf/facter.conf'
        },
        '/etc/ssh/ssh_config.d/100-cathy-alienware.conf' => {
            source => 'puppet:///modules/cathyjf/ssh_config.d/100-cathy-alienware.conf'
        },
        '/etc/ssh/sshd_config.d/200-cathyjf.conf' => {},
        '/Library/vhusbd.ini' => { mode => 'u=rw,go=r' },
        '/Library/LaunchDaemons/com.virtualhere.vhusbd.plist' => {
            validate_cmd => $validate_plist
        },
        '/var/db/com.apple.xpc.launchd/config/user.plist' => {
            source       => 'puppet:///modules/cathyjf/launchd-user.plist',
            mode         => 'u=rw,go=',
            validate_cmd => $validate_plist
        },
        '/var/root/run-startup-commands' => { mode => 'u=rwx,go=' },
        '/etc/sudoers.d/run-startup-commands' => {
            mode         => 'u=r,g=r,o=',
            validate_cmd => $validate_sudoers
        },
        "${facts['brew_root']}/etc/smb.conf" => { mode => 'u=r,go=' },
        '/Library/LaunchDaemons/cathy.samba-dot-org-smbd.plist' => {
            validate_cmd => $validate_plist
        }
    }).each |$filename, $overrides| {
        file {
            default:
                source => "${facts['chezmoi_target']}/.config${filename}",
                *      => $default_file_params;
            $filename:
                *      => $overrides;
        }
        cathyjf::file_readable_by_user { $filename: }
    }
    include cathyjf::fish_shell
    include cathyjf::macos_nvram
    include sshuttle
}