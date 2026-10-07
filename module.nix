# NixOS module: Claude Desktop (Linux beta) - Chat, Cowork and Claude Code.
#
# Packages Anthropic's official .deb (see ./package.nix) and, optionally,
# provides what the Cowork tab needs to run its QEMU/KVM virtual machine:
#
#   - qemu + virtiofsd on the app's PATH (package `withCowork`)
#   - UEFI firmware and virtiofsd at the FHS paths the app hardcodes
#     (/usr/share/OVMF, /usr/share/AAVMF, /usr/libexec/virtiofsd)
#   - the vhost_vsock kernel module
#   - membership of the `kvm` group (/dev/kvm and /dev/vhost-vsock)
#
# It also enables nix-ld: the Code tab downloads a pinned, checksum-verified
# Claude Code CLI into ~/.config/Claude/claude-code/ at runtime. That binary
# is built for generic Linux and can't start on NixOS without a loader at
# /lib64/ld-linux-*.so; patching it would break the app's checksum check.
#
# Usage - flake:
#   imports = [ inputs.claude-desktop-nixos.nixosModules.default ];
#   programs.claude-desktop = { enable = true; cowork.users = [ "alice" ]; };
#
# Usage - plain import (channels):
#   imports = [ ./claude-desktop-nixos/module.nix ];
#   programs.claude-desktop = { enable = true; cowork.users = [ "alice" ]; };
#
# The app is unfree: set `nixpkgs.config.allowUnfree = true` (or allow
# "claude-desktop" via `allowUnfreePredicate`).

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-desktop;

  firmwareDir =
    if pkgs.stdenv.hostPlatform.isAarch64 then "/usr/share/AAVMF" else "/usr/share/OVMF";
in
{
  options.programs.claude-desktop = {
    enable = lib.mkEnableOption "Claude Desktop, Anthropic's desktop app for Claude";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { withCowork = cfg.cowork.enable; };
      defaultText = lib.literalExpression ''
        pkgs.callPackage ./package.nix { withCowork = config.programs.claude-desktop.cowork.enable; }
      '';
      description = "The claude-desktop package to install.";
    };

    nixLd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable {option}`programs.nix-ld` so the Claude Code CLI that the app
        downloads at runtime (a generic-Linux, glibc-only binary) can run.
        Without it the Code tab fails with "Could not start dynamically
        linked executable". Disable if you provide nix-ld (or envfs/an FHS
        loader) some other way.
      '';
    };

    cowork = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Set up the host for Cowork, which runs tasks in a QEMU/KVM virtual
          machine: firmware and virtiofsd at the paths the app expects, the
          vhost_vsock kernel module, and kvm group membership for
          {option}`programs.claude-desktop.cowork.users`.
          Hardware virtualization must also be enabled in firmware.
        '';
      };

      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "alice" ];
        description = ''
          Users added to the `kvm` group so Cowork can open /dev/kvm and
          /dev/vhost-vsock. Log out and back in after the first switch.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ cfg.package ];

      # D-Bus activation for the GNOME Shell search provider.
      services.dbus.packages = [ cfg.package ];
    }

    # The downloaded CLI only links glibc (libc, libm, libdl, libpthread,
    # librt), which nix-ld provides by default.
    (lib.mkIf cfg.nixLd.enable {
      programs.nix-ld.enable = true;
    })

    (lib.mkIf cfg.cowork.enable {
      boot.kernelModules = [ "vhost_vsock" ];

      users.users = lib.genAttrs cfg.cowork.users (_: {
        extraGroups = [ "kvm" ];
      });

      # The app probes fixed paths: <firmwareDir>/{OVMF,AAVMF}_CODE.fd (and the
      # matching *_VARS.fd next to it) and /usr/libexec/virtiofsd.
      systemd.tmpfiles.rules = [
        "d /usr/share 0755 root root -"
        "d /usr/libexec 0755 root root -"
        "L+ ${firmwareDir} - - - - ${pkgs.OVMF.fd}/FV"
        "L+ /usr/libexec/virtiofsd - - - - ${lib.getExe pkgs.virtiofsd}"
      ];

      warnings = lib.optional (cfg.cowork.users == [ ]) ''
        programs.claude-desktop.cowork.enable is set but cowork.users is empty.
        Cowork needs the user to be in the `kvm` group to open /dev/vhost-vsock.
      '';
    })
  ]);
}
