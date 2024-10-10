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

# Configure the fish shell.
class cathyjf::fish_shell {
    $fish_shell = "${facts['brew_root']}/bin/fish"
    $sanitized_username = sanitized_username($facts['cathy_username'])
    exec { "add ${fish_shell} to /etc/shells":
        command => "/bin/echo ${shell_escape($fish_shell)} >> /etc/shells",
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
    $validate_sudoers = '/usr/sbin/visudo -c -q -f %'
    Hash({
        '/etc/hosts' => {},
        '/etc/pam.d/sudo' => {},
        '/etc/ppp/ip-up' => { mode => 'u=rx,g=r,o=r' },
        '/etc/ssh/sshd_config.d/200-cathyjf.conf' => {},
        '/Library/vhusbd.ini' => { mode => 'u=rw,g=r,o=r' },
        '/Library/LaunchDaemons/com.virtualhere.vhusbd.plist' => {},
        '/var/root/run-startup-commands' => { mode => 'u=rwx,g=,o=' },
        '/etc/sudoers.d/run-startup-commands' => {
            mode         => 'u=r,g=r,o=',
            validate_cmd => $validate_sudoers
        },
        "${facts['brew_root']}/etc/smb.conf" => { mode => 'u=r,g=,o=' },
        '/Library/LaunchDaemons/cathy.samba-dot-org-smbd.plist' => {}
    }).each |$filename, $overrides| {
        file {
            default:
                ensure => file,
                owner  => 'root',
                group  => 'wheel',
                links  => follow,
                mode   => 'u=r,g=r,o=r';
            $filename:
                source => "${facts['chezmoi_target']}/.config${filename}",
                *      => $overrides;
        }
    }
    cathyjf::file_readable_by_user {
        ['/var/root/run-startup-commands', '/etc/sudoers.d/run-startup-commands', "${facts['brew_root']}/etc/smb.conf"]:
    }
    include cathyjf::fish_shell
    include cathyjf::macos_nvram
    include sshuttle
}