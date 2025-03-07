# QEMU-related utilities shared between various Nix expressions.
{ lib, pkgs }:

let
  zeroPad = n:
    lib.optionalString (n < 16) "0" +
    (if n > 255
    then throw "Can't have more than 255 nets or nodes!"
    else lib.toHexString n);
in

rec {
  qemuNicMac = net: machine: "52:54:00:12:${zeroPad net}:${zeroPad machine}";

  qemuNICFlags = nic: net: machine:
    [
      "-device virtio-net-pci,netdev=vlan${toString nic},mac=${qemuNicMac net machine}"
      ''-netdev vde,id=vlan${toString nic},sock="$QEMU_VDE_SOCKET_${toString net}"''
    ];

  qemuSerialDevice =
    if with pkgs.stdenv.hostPlatform; isx86 || isLoongArch64 || isMips64 || isRiscV then "ttyS0"
    else if (with pkgs.stdenv.hostPlatform; isAarch || isPower) then "ttyAMA0"
    else throw "Unknown QEMU serial device for system '${pkgs.stdenv.hostPlatform.system}'";

  qemuBinary = qemuPkg:
    let
      hostStdenv = qemuPkg.stdenv;
      hostSystem = hostStdenv.system;
      guestSystem = pkgs.stdenv.hostPlatform.system;

      linuxHostGuestMatrix = {
        x86_64-linux = "${qemuPkg}/bin/qemu-system-x86_64 -machine accel=kvm:tcg -cpu max";
        armv7l-linux = "${qemuPkg}/bin/qemu-system-arm -machine virt,accel=kvm:tcg -cpu max";
        aarch64-linux = "${qemuPkg}/bin/qemu-system-aarch64 -machine virt,gic-version=max,accel=kvm:tcg -cpu max";
        powerpc64le-linux = "${qemuPkg}/bin/qemu-system-ppc64 -machine powernv";
        powerpc64-linux = "${qemuPkg}/bin/qemu-system-ppc64 -machine powernv";
        riscv32-linux = "${qemuPkg}/bin/qemu-system-riscv32 -machine virt";
        riscv64-linux = "${qemuPkg}/bin/qemu-system-riscv64 -machine virt";
        x86_64-darwin = "${qemuPkg}/bin/qemu-system-x86_64 -machine accel=kvm:tcg -cpu max";
      };
      otherHostGuestMatrix = {
        aarch64-darwin = {
          aarch64-linux = "${qemuPkg}/bin/qemu-system-aarch64 -machine virt,gic-version=2,accel=hvf:tcg -cpu max";
          inherit (otherHostGuestMatrix.x86_64-darwin) x86_64-linux;
        };
        x86_64-darwin = {
          x86_64-linux = "${qemuPkg}/bin/qemu-system-x86_64 -machine type=q35,accel=hvf:tcg -cpu max";
        };
      };

      throwUnsupportedHostSystem =
        let
          supportedSystems = [ "linux" ] ++ (lib.attrNames otherHostGuestMatrix);
        in
        throw "Unsupported host system ${hostSystem}, supported: ${lib.concatStringsSep ", " supportedSystems}";
      throwUnsupportedGuestSystem = guestMap:
        throw "Unsupported guest system ${guestSystem} for host ${hostSystem}, supported: ${lib.concatStringsSep ", " (lib.attrNames guestMap)}";
    in
    if hostStdenv.hostPlatform.isLinux then
      linuxHostGuestMatrix.${guestSystem} or "${qemuPkg}/bin/qemu-kvm"
    else
      let
        guestMap = (otherHostGuestMatrix.${hostSystem} or throwUnsupportedHostSystem);
      in
      (guestMap.${guestSystem} or (throwUnsupportedGuestSystem guestMap));
}
