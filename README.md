# tommasodotnet's dotfiles - forked from jldeen's repo

### Install
Run the generic setup to configure Fedora from scratch:
```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tommasodotnet/dotfiles/fedora/setup.sh)"
```

GNOME and Microsoft setup are intentionally separate. After the generic setup,
run either of these only when you want that machine-specific configuration:

```sh
gnome-setup.sh
fedora.sh
setup_himmelblau.sh
```

### Azure VPN (optional, manual connection)

The tested community-client setup is reproducible from the
[Azure VPN topic](azure-vpn/README.md). It pins OpenP2S/OpenVPN, preserves the
local routing fixes, verifies release checksums and GitHub attestations, and
installs a manual desktop launcher. It is **not** part of generic setup:

```sh
bash ~/.dotfiles/azure-vpn/setup.sh --profile /path/outside/dotfiles/azurevpnconfig.xml
```

Read the topic prerequisites first. Supply your organisation's private XML
separately; never commit profiles, tokens or generated VPN configuration.
Setup does not sign in, connect, enable auto-start, or replace an existing VPN.
This is not the retired Microsoft Linux client or native GNOME VPN integration.

### Desktop development tools

Each tool declares its shared environment in `<topic>/environment.conf`.
`script/bootstrap` and `script/install` automatically link these files into
`~/.config/environment.d/60-dotfiles-<topic>.conf` on Linux (respecting
`XDG_CONFIG_HOME`). Zsh reads the same declarations in topic-name order and
deduplicates `PATH`. Desktop applications, including VS Code launched from
Copilot, therefore get the tool paths without having to start Zsh.

The `.conf` format is required by systemd's desktop environment loader. Use only
shell-compatible `NAME=value` assignments, comments, and `${HOME}` or previously
defined variable expansions. Do not use `export`, commands, conditionals, or
shell-specific syntax here; keep shell hooks such as `fnm env` in `.zsh` files.

Commands installed in `~/.local/bin`, `~/bin`, `~/go/bin`, `~/.dotnet/tools`,
the default fnm Node installation, or the pnpm directory need no extra PATH
entry. For a tool with a different installation directory, declare it alongside
its installer rather than editing a central list, for example:

```sh
# example/environment.conf
EXAMPLE_HOME=${HOME}/.local/share/example
PATH=${EXAMPLE_HOME}/bin:${PATH}
```

Run `bash ~/.dotfiles/script/link-environment` after adding a topic, or let
bootstrap/install do it. Edits to existing files apply through their symlinks.
The helper migrates the old managed `60-fnm.conf` link and refuses to overwrite
unmanaged destination files. On a fresh Linux setup, bootstrap creates all the
links automatically; the tool installers still need to run.

Sign out and back in for desktop applications to inherit changes; existing
processes keep their old environment. A new Zsh shell reads changes immediately.
No separate `~/.local/bin/go` link is needed after the desktop session refreshes.

`script/install` includes these tool installers, which can also run separately:

```sh
bash ~/.dotfiles/node/install.sh
bash ~/.dotfiles/dotnet/install.sh
bash ~/.dotfiles/uv/install.sh
```

The Node installer installs Node 24, makes it the fnm default, and installs
Azure Functions Core Tools 4.15.2 globally under that Node version. If you change
the fnm default to another installation, install Core Tools there as well.
The .NET installer adds SDK 10.0.401 to `~/dotnet` without removing older SDKs.
The uv installer installs the current uv release into `~/.local/bin`.
Installation failures are reported rather than ignored.

VS Code user settings and extension preferences remain managed by VS Code
Settings Sync, not by this repository. Keep Settings Sync enabled for the
desired profile; no workspace SDK pin is required.

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
- **topic/environment.conf**: Shared tool paths and environment variables,
  automatically discovered by bootstrap/install for Linux desktop apps and by
  Zsh at shell startup. Keep one declaration alongside each tool's installer.
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
  the broker package, and YubiKey support. Azure VPN is a separate optional topic
  (see above). Himmelblau defaults to
  mapping the current local user to `tstocchi@microsoft.com`; override that with
  `DOTFILES_HIMMELBLAU_UPN`.
