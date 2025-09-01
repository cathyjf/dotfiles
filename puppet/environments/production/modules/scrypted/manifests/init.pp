# Configuration of `scrypted`.
class scrypted {
    $home = '/var/scrypted'
    $username = '_scrypted'
    $groupname = '_scrypted'

    cathyjf::role_account_and_group {
        $username:
            groupname => $groupname,
            home      => $home
    }

    file {
        default:
            ensure => directory,
            owner  => $username,
            group  => $groupname,
            mode   => 'u=wrx,g=,o=';
        [$home, "${home}/.scrypted", '/var/log/scrypted']: ;
        "${home}/.scrypted/profile.sb":
            ensure => file,
            mode   => 'u=r,g=,o=',
            source => 'puppet:///modules/scrypted/profile.sb';
    }

    cathyjf::file_readable_by_user {
        ["${home}/.scrypted/profile.sb", '/var/log/scrypted']:
    }

    file {
        '/Library/LaunchDaemons/cathy.scrypted.server.plist':
            ensure       => file,
            owner        => 'root',
            group        => 'wheel',
            mode         => 'u=rw,g=r,o=r',
            source       => 'puppet:///modules/scrypted/cathy.scrypted.server.plist',
            validate_cmd => $cathyjf::validate_plist;
    }
}