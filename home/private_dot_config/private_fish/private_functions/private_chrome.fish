function chrome --description 'Open stdin as a webpage'
    set -l pager (dirname (functions --details (status current-function)))/../man_pager.fish
    source $pager --chrome $argv
end