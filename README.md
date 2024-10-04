# cathyjf's dotfiles

This repository contains the dotfiles that I use on my macOS machines.

I am able to share most of my dotfiles, but certain private dotfiles contain
personal information and I am unable to share those ones at this time. The
private dotfiles are contained within the `private` subdirectory of the
repository, which is a submodule that points to a private GitHub repository.
In addition to the private dotfiles being stored in a non-public repository,
they are also encrypted within that repository.

## Installation

1. Install [`brew`](https://brew.sh).

2. Install [`chezmoi`](https://chezmoi.io/):
    ```shell
    brew install chezmoi
    ```

3. Initialize `chezmoi` using my dotfiles:
    ```shell
    chezmoi init --ssh github.com/cathyjf
    ```
    This `chezmoi init` command will automatically clone this repository and its `private` submodule.
    To skip cloning the private dotfiles, add the `--recurse-submodules=false` argument.

4. Apply the dotfiles (including the private dotfiles) to the home directory:
    ```shell
    chezmoi apply
    ```
    To apply only the public dotfiles, use:
    ```shell
    chezmoi apply --exclude encrypted
    ```
    One advantage of applying only the public dotfiles is that it will not be necessary to authenticate to decrypt my GPG key.

## Working with the private dotfiles

After the public dotfiles have been applied at least once, a fish function named [`chezmoi-private`](https://github.com/cathyjf/dotfiles/blob/main/home/private_dot_config/private_fish/private_functions/private_chezmoi-private.fish) will be available. This function takes all of the same arguments as the `chezmoi` program, but it operates on the private dotfiles instead of on the public dotfiles.

Examples:
* Run `chezmoi-private managed` to see a list of all of the private dotfiles managed by `chezmoi`.
* Run `chezmoi-private diff` to see pending changes to the private dotfiles.
  This will require authentication to decrypt my GPG key.

## Other relevant repositories

* The [Brewfile](https://github.com/cathyjf/dotfiles/blob/main/misc/Brewfile) in this repository specifies some packages from my [cathyjf/homebrew-misc](https://github.com/cathyjf/homebrew-misc) repository.

* My dotfiles specify [cathyjf/keychain-interpose](https://github.com/cathyjf/keychain-interpose) as the default agent for `gpg(1)`.