{ config, lib, pkgs, ... }:

let
  cfg = config.programs.tessa;
  hasConfig = cfg.configFile != null || cfg.config != null;
in
{
  options.programs.tessa = {
    enable = lib.mkEnableOption "the Tessa Wayland compositor";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix {
        zig = pkgs.zig_0_17 or pkgs.zig;
      };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The Tessa package to use.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/nixos/tessa.conf";
      description = ''
        A Tessa configuration file installed as /etc/tessa/config and exposed
        through TESSA_CONFIG. See /etc/tessa/config.example from the package.
      '';
    };

    config = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      example = ''
        panel = true
        panel_renderer = gpu
        wallpaper_animation = auto
      '';
      description = ''
        Inline Tessa configuration. Ignored when configFile is set.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "with pkgs; [ foot fuzzel fcitx5 ]";
      description = ''
        Extra packages added to the system profile for the Tessa session
        (terminal, launcher, input method, screenshot tools, and so on).
      '';
    };

    xwayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add xwayland-satellite so Tessa can start X11 applications. Disable
        this if the system provides its own XWayland setup.
      '';
    };

    portals = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable xdg-desktop-portal and route Tessa to the wlr screenshot and
        screencast backend.
      '';
    };

    defaultSession = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Set services.displayManager.defaultSession to "tessa". The display
        manager still needs to be enabled separately.
      '';
    };

    networkmanager = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable NetworkManager so the Tessa control center can manage Wi-Fi.
        This changes the system network configuration; enable it only when
        NetworkManager is the intended network backend.
      '';
    };

    bluetooth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable BlueZ for the Tessa Bluetooth control center.";
    };

    powerProfiles = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable power-profiles-daemon for the Tessa power profile switch.
        Do not enable it together with TLP or auto-cpufreq.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.configFile != null && cfg.config != null);
        message = "programs.tessa: set either configFile or config, not both.";
      }
    ];

    environment.systemPackages = [ cfg.package ] ++ cfg.extraPackages
      ++ lib.optional (cfg.xwayland && pkgs ? xwayland-satellite) pkgs.xwayland-satellite;

    services.displayManager.sessionPackages = [ cfg.package ];

    services.displayManager.defaultSession =
      lib.mkIf cfg.defaultSession (lib.mkDefault "tessa");

    environment.etc."tessa/config.example".source =
      "${cfg.package}/share/tessa/config.example";

    environment.etc."tessa/config" = lib.mkIf hasConfig {
      source = if cfg.configFile != null
        then cfg.configFile
        else pkgs.writeText "tessa-config" cfg.config;
    };

    environment.sessionVariables = lib.mkIf hasConfig {
      TESSA_CONFIG = "/etc/tessa/config";
    };

    security.polkit.enable = lib.mkDefault true;
    services.dbus.enable = lib.mkDefault true;
    hardware.graphics.enable = lib.mkDefault true;
    services.networkmanager.enable = lib.mkIf cfg.networkmanager true;
    hardware.bluetooth.enable = lib.mkIf cfg.bluetooth true;
    services.power-profiles-daemon.enable = lib.mkIf cfg.powerProfiles true;

    xdg.portal = lib.mkIf cfg.portals {
      enable = lib.mkDefault true;
      extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
      config.Tessa.default = [ "wlr" ];
    };

    warnings = lib.optional
      (cfg.xwayland && !(pkgs ? xwayland-satellite))
      "programs.tessa.xwayland is enabled but pkgs.xwayland-satellite is unavailable; add an XWayland package to programs.tessa.extraPackages.";
  };
}
