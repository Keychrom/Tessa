# Tessa on NixOS

The repository is a flake with a package and a NixOS module. The module installs
the compositor, its session desktop file, the XDG portal entry, and the optional
XWayland satellite, and registers Tessa as a Wayland session for SDDM, GDM, or
greetd.

## Package

```sh
nix build github:Keychrom/Tessa
./result/bin/tessa --help
```

Or from a checkout:

```sh
nix build .#tessa
```

Two variants are provided:

- `packages.tessa` (default) uses scenefx 0.5 for rounded corners, blur, and
  shadows. It needs a working EGL/GLES2 driver.
- `packages.tessa-plain` builds with `-Dscenefx=false` for pixman/software
  rendering. Use it on VMs without 3D acceleration, together with
  `environment.sessionVariables.WLR_RENDERER = "pixman"`.

The package builds Zig 0.17, wlroots 0.20, and scenefx 0.5 from nixpkgs. The
pinned `translate-c`/`arocc` sources are copied into Zig's local `zig-pkg`
directory so the sandboxed build does not need network access. If
`build.zig.zon` changes those dependencies, update the URLs, revisions, hashes,
and directory names in `package.nix`.

## NixOS module

Add the flake as an input and import the module:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.tessa.url = "github:Keychrom/Tessa";

  outputs = { self, nixpkgs, tessa, ... }: {
    nixosConfigurations.tessa-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        tessa.nixosModules.default
        {
          programs.tessa.enable = true;

          # A display manager is required for a graphical login.
          services.displayManager.sddm.enable = true;

          # Recommended for a usable desktop.
          programs.tessa.extraPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            foot
            fuzzel
            grim
            slurp
            fcitx5
            fcitx5-mozc
          ];

          # Optional: configure the compositor. Panel-only settings normally
          # live in /etc/tessa/panel.conf; see /etc/tessa/panel.example.
          # programs.tessa.config = ''
          #   gaps = 10
          #   animations = true
          # '';
        }
      ];
    };
  };
}
```

Build and switch:

```sh
sudo nixos-rebuild switch --flake .#tessa-vm
```

Then pick **Tessa** at the login screen. The module sets
`services.displayManager.defaultSession = "tessa"` unless
`programs.tessa.defaultSession = false`.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `programs.tessa.enable` | `false` | Install Tessa and register its Wayland session |
| `programs.tessa.package` | `callPackage ./package.nix` | Package to install |
| `programs.tessa.configFile` | `null` | Config file installed as `/etc/tessa/config` |
| `programs.tessa.config` | `null` | Inline config; mutually exclusive with `configFile` |
| `programs.tessa.extraPackages` | `[ ]` | Terminal, launcher, IME, and tools for the session |
| `programs.tessa.xwayland` | `true` | Add `xwayland-satellite` for X11 applications |
| `programs.tessa.portals` | `true` | Enable `xdg-desktop-portal-wlr` for screenshots/screencasts |
| `programs.tessa.defaultSession` | `true` | Set the display manager's default session to Tessa |
| `programs.tessa.networkmanager` | `false` | Enable NetworkManager for control-center Wi-Fi |
| `programs.tessa.bluetooth` | `false` | Enable BlueZ for control-center Bluetooth |
| `programs.tessa.powerProfiles` | `false` | Enable power-profiles-daemon for power profiles |

The module also enables polkit, D-Bus, and `hardware.graphics`, which the
compositor needs for seat management and GPU rendering. NetworkManager,
Bluetooth, and power-profiles-daemon are opt-in because not every Tessa machine
uses them; enabling an option turns on the corresponding NixOS service. The
control center shows an unavailable section when a service is absent, so they
can also be enabled later without changing the Tessa package.

## Minimal test VM

A complete configuration for a VM with software rendering fallback. The flake
input is used for the module and the `tessa-plain` package:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.tessa.url = "github:Keychrom/Tessa";

  outputs = { self, nixpkgs, tessa, ... }: {
    nixosConfigurations.tessa-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        tessa.nixosModules.default
        {
          programs.tessa.enable = true;
          programs.tessa.package =
            tessa.packages.x86_64-linux.tessa-plain;
          programs.tessa.extraPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            foot
            grim
          ];

          services.displayManager.sddm.enable = true;

          # Without 3D acceleration the SDDM Wayland greeter may fail; use the
          # X11 greeter on a VM.
          services.displayManager.sddm.wayland.enable = false;
          services.xserver.enable = true;

          # Test VM only: boot straight into the Tessa session.
          services.displayManager.autoLogin.enable = true;
          services.displayManager.autoLogin.user = "suiren";

          # vmwgfx/VirtualBox without 3D acceleration.
          environment.sessionVariables.WLR_RENDERER = "pixman";
        }
      ];
    };
  };
}
```

The package, module, SDDM session, keyboard input, panel, and launcher were
validated on NixOS 26.05 with a vmwgfx VM. On that GPU, use `tessa-plain` and
`WLR_RENDERER=pixman`; the scenefx build cannot create a GLES2 context without
3D acceleration. On real hardware, the default `tessa` package is the right
choice.

## Notes

- Tessa reads `$TESSA_CONFIG`, then `$XDG_CONFIG_HOME/tessa/config`, then
  `~/.config/tessa/config`. Panel-only settings load from
  `$TESSA_PANEL_CONFIG` or `panel.conf` next to that file. The module's
  `configFile`/`config` options use `/etc/tessa/config` and set `TESSA_CONFIG`
  for the whole system.
- `xwayland-satellite` is added when nixpkgs provides it. If your nixpkgs does
  not have it, add another XWayland package to `extraPackages`.
- The package installs `/share/wayland-sessions/tessa.desktop`,
  `/share/tessa/config.example`, `/share/tessa/panel.example`, and
  `/share/xdg-desktop-portal/portals/tessa.portal`.
- Window shaders are enabled by default in the package. Use
  `TESSA_SHADER_DISABLE=1` or build with `-Dshaders=false` to disable them.
