function rclone-edit --description 'Edit an encrypted rclone config file'
    set -l script (dirname (functions --details (status current-function)))/../rclone_edit.ps1
    eval $script $argv
end