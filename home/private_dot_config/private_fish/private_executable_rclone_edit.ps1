#!/usr/bin/env pwsh
# This script allows for relatively secure editing of an encrypted
# rclone configuration file by using a ram disk for intermediate
# storage of the unencrypted text.

$ErrorActionPreference = 'Stop'

# We'll use a 10 MiB ram disk as temporary storage for this script.
# According to `man 1 hdiutil`, a ram disk sector is 512 bytes.
# Therefore, a 10 MiB ram disk is approximately 20480 sectors.
Set-Variable RAMDISK_SECTORS -Option Constant -Value 20480

function throw_if_error {
    param ([Parameter(Mandatory)]$throwable)
    if ($LastExitCode -ne 0) {
        throw $throwable
    }
}

function find_apfs_container_from_device {
    param ([Parameter(Mandatory)][string]$device)
    $plist = (diskutil apfs list -plist)
    throw_if_error 'failed to list all APFS containers'

    $container_count = $plist | plutil -extract Containers raw -
    throw_if_error 'failed to count number of APFS containers'

    for ($i = 0; $i -lt $container_count; ++$i) {
        $candidate = $plist | plutil -extract Containers.${i}.PhysicalStores.0.DeviceIdentifier raw -
        if ($LastExitCode -ne 0) {
            continue;
        } elseif ("/dev/$($candidate.Trim())".Equals($device)) {
            $container = $plist | plutil -extract Containers.${i}.ContainerReference raw -
            throw_if_error 'failed to extract container reference for APFS volume'
            return "/dev/$($container.Trim())"
        }
    }
    throw 'failed to find APFS container'
}

$rclone_conf = rclone config file | tail -n 1 || ''
if (!(Test-Path -Path $rclone_conf -PathType Leaf)) {
    throw 'failed to identify location of `rclone.conf`'
}

function secure_edit_rclone {
    param (
        [Parameter(Mandatory)][string]$rclone_conf,
        [Parameter(Mandatory)][string]$device
    )
    diskutil apfs createContainer $device | Out-Null
    throw_if_error 'failed to create APFS container'

    $container = find_apfs_container_from_device($device)
    head -c 30 /dev/urandom | diskutil apfs addVolume $container APFS 'Temporary Volume' -stdinpassphrase | Out-Null
    throw_if_error 'failed to create and mount APFS volume'

    $mnt = diskutil info -plist "${container}s1" | plutil -extract MountPoint raw - | ForEach-Object { $_.Trim() }
    throw_if_error 'failed to determine mount point of APFS volume'

    umask 077
    chmod -R u=rwX,g=,o= $mnt
    throw_if_error 'failed to set permissions on mount point'

    $tmp_conf = "${mnt}/rclone.conf"
    Copy-Item -Path $rclone_conf -Destination $tmp_conf
    rclone config encryption remove --config $tmp_conf
    throw_if_error 'failed to decrypt rclone config file'

    $hash = (Get-FileHash $tmp_conf).Hash
    Write-Host 'Opening editor...'
    & $Env:EDITOR $tmp_conf
    if (!(Test-Path -Path $tmp_conf -PathType Leaf)) {
        throw 'temporary config file disappeared'
    } elseif ($hash -eq (Get-FileHash $tmp_conf).Hash) {
        Write-Host 'Config file was unmodified.'
        exit 0
    }
    rclone config encryption set --config $tmp_conf
    throw_if_error 'failed to re-encrypt rclone config file'

    & mv $tmp_conf (readlink -f $rclone_conf)
    throw_if_error 'failed to install new rclone config file'
    Write-Host 'Config file edited successfully.'
}

try {
    Write-Host 'Setting up ram disk...'
    $device = hdiutil attach -nobrowse -nomount ram://${RAMDISK_SECTORS} | ForEach-Object { $_.Trim() }
    throw_if_error 'hdiutil attach failed'

    secure_edit_rclone $rclone_conf $device
} finally {
    diskutil eject $device | Out-Null
    Write-Host 'Deleted ram disk.'
}