# NixOS VM test for the module: host setup, and the app opens a window.
{ pkgs, module }:

let
  inherit (pkgs.stdenv.hostPlatform) isAarch64;

  firmware =
    if isAarch64 then "/usr/share/AAVMF/AAVMF_CODE.fd" else "/usr/share/OVMF/OVMF_CODE.fd";

  # Like the Claude Code CLI the Code tab downloads: runs only through nix-ld.
  fhsHello = pkgs.runCommand "fhs-hello" { nativeBuildInputs = [ pkgs.patchelf ]; } ''
    install -Dm755 ${pkgs.hello}/bin/hello $out/bin/fhs-hello
    patchelf --remove-rpath \
      --set-interpreter ${if isAarch64 then "/lib/ld-linux-aarch64.so.1" else "/lib64/ld-linux-x86-64.so.2"} \
      $out/bin/fhs-hello
  '';
in
pkgs.testers.runNixOSTest {
  name = "claude-desktop";

  nodes.machine = {
    imports = [
      module
      "${pkgs.path}/nixos/tests/common/user-account.nix"
      "${pkgs.path}/nixos/tests/common/x11.nix"
    ];

    virtualisation = {
      memorySize = 4096;
      cores = 2;
    };

    test-support.displayManager.auto.user = "alice";

    programs.claude-desktop = {
      enable = true;
      cowork.users = [ "alice" ];
    };

    environment.systemPackages = [ fhsHello ];
  };

  testScript = ''
    from datetime import timedelta

    start_all()
    machine.wait_for_unit("multi-user.target")

    with subtest("Cowork host setup"):
        machine.succeed("lsmod | grep -qw vhost_vsock")
        machine.succeed("id -nG alice | grep -qw kvm")
        machine.succeed("test -f ${firmware}")
        machine.succeed("/usr/libexec/virtiofsd --version")
        machine.succeed("grep -q qemu $(readlink -f /run/current-system/sw/bin/claude-desktop)")

    with subtest("nix-ld runs generic-Linux binaries"):
        machine.succeed("su - alice -c fhs-hello")

    with subtest("app starts and opens a window"):
        machine.wait_for_x()
        # For wait_for_window, which runs xwininfo as root.
        machine.wait_for_file("/home/alice/.Xauthority")
        machine.succeed("xauth merge ~alice/.Xauthority")
        machine.execute("su - alice -c 'claude-desktop >/tmp/claude-desktop.log 2>&1 &'")
        try:
            machine.wait_for_window("Claude", timeout=timedelta(minutes=5))
            machine.sleep(duration=timedelta(seconds=10))
            machine.succeed("pgrep -u alice -f lib/claude-desktop/claude-desktop")
            machine.screenshot("claude-desktop")
        finally:
            print(machine.execute("cat /tmp/claude-desktop.log")[1])
  '';
}
