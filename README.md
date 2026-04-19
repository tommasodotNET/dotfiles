# tommasodotnet's dotfiles - forked from jldeen's repo

### Install
Run the following to configure Ubuntu from scratch...
```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tommasodotnet/dotfiles/main/setup.sh)"
```

## topical

Everything's built around topic areas. If you're adding a new area to your
forked dotfiles — say, "Java" — you can simply add a `java` directory and put
files in there. Anything with an extension of `.zsh` will get automatically
included into your shell. Anything with an extension of `.symlink` will get
symlinked without extension into `$HOME` when you run `script/bootstrap`.

## what's inside

A lot of stuff. Seriously, a lot of stuff. Check them out in the file browser
above and see what components may mesh up with you.
[Fork holman's](https://github.com/holman/dotfiles/fork) or [Fork jldeen's](htps://github.com/jldeen/dotfiles/fork), remove what you don't use, and build on what you do use.

## components

There are a few special files in the hierarchy.

- **bin/**: Anything in `bin/` will get added to your `$PATH` and be made
  available everywhere.
- **topic/\*.zsh**: Any files ending in `.zsh` get loaded into your
  environment.
- **topic/path.zsh**: Any file named `path.zsh` is loaded first and is
  expected to set up `$PATH` or similar.
- **topic/completion.zsh**: Any file named `completion.zsh` is loaded
  last and is expected to set up autocomplete.
- **topic/install.sh**: Any file named `install.sh` is executed when you run
  `script/install`. To avoid being loaded automatically, its extension is
  `.sh`, not `.zsh`.
- **topic/\*.symlink**: Any file ending in `*.symlink` gets symlinked into
  your `$HOME`. This is so you can keep all of those versioned in your dotfiles
  but still keep those autoloaded files in your home directory. These get
  symlinked in when you run `script/bootstrap`.
- **gnome/**: Running `script/bootstrap` symlinks GNOME Shell extensions from
  `gnome/extensions/` into `~/.local/share/gnome-shell/extensions/` and
  restores shell/extension settings from the tracked dconf dumps.
  Running `script/install` (which discovers `gnome/install.sh`) will install
  the **MacTahoe GTK theme**, **MacTahoe icon theme**, and
  **CaskaydiaCove Nerd Font Mono**.
- **microsoft/**: Running `script/install` (which discovers `microsoft/install.sh`)
  sets up Microsoft Edge, VS Code, Edge PWA launchers, Intune, and YubiKey
  support. Custom `.icns` icon files under `microsoft/icons/` are converted to
  PNG and used to replace the default PWA icons.

## Git clone
There are two "master" branches here: WSL and MacOS.

If you wish to clone these files and run scripts manually, run this:

```sh
git clone https://github.com/tommasodotnet/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
script/bootstrap
```

This will symlink the appropriate files in `.dotfiles` to your home directory.
Everything is configured and tweaked within `~/.dotfiles`.

The main file you'll want to change right off the bat is `zsh/zshrc.symlink`,
which sets up a few paths that'll be different on your particular machine. You also might want to configure `.tmux.conf` since I run a few scripts in the status bar.