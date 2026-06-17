# tommasodotnet's dotfiles - forked from jldeen's repo

### Install
Run the generic setup to configure Ubuntu from scratch:
```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tommasodotnet/dotfiles/main/setup.sh)"
```

GNOME and Microsoft setup are intentionally separate. After the generic setup,
run either of these only when you want that machine-specific configuration:

```sh
gnome-setup.sh
microsoft-setup.sh
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
[Fork holman's](https://github.com/holman/dotfiles/fork) or [Fork jldeen's](https://github.com/jldeen/dotfiles/fork), remove what you don't use, and build on what you do use.

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
  `script/install`. Optional setup scripts should use a different filename so
  they are not discovered automatically.
- **topic/\*.symlink**: Any file ending in `*.symlink` gets symlinked into
  your `$HOME`. This is so you can keep all of those versioned in your dotfiles
  but still keep those autoloaded files in your home directory. These get
  symlinked in when you run `script/bootstrap`.
- **gnome/**: Optional. Run `gnome-setup.sh` deliberately to symlink GNOME Shell
  extensions from `gnome/extensions/`, restore shell/extension settings from
  the tracked dconf dumps, and run `gnome/setup.sh`. The optional MacTahoe
  GTK/icon theme is installed only when `DOTFILES_INSTALL_MACOS_THEME=1` is set.
- **microsoft/**: Optional. Run `microsoft-setup.sh` deliberately to set up
  Microsoft Edge, VS Code, Intune, Microsoft Identity Broker,
  linux-entra-sso's native connector when available, Himmelblau stable without
  the broker package, Azure VPN, and YubiKey support. Himmelblau defaults to
  mapping the current local user to `tstocchi@microsoft.com`; override that with
  `DOTFILES_HIMMELBLAU_UPN`.