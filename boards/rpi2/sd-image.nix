{
  config,
  lib,
  pkgs,
  ...
}:
let
  artifacts = import ./rpi2-artifacts.nix { inherit pkgs; };

  rpiFirmware = pkgs.buildPackages.raspberrypifw;
  firmwareBoot = "${rpiFirmware}/share/raspberrypi/boot";

  abBootScript =
    pkgs.runCommand "rpi2-ab-boot.scr"
      {
        nativeBuildInputs = [ pkgs.buildPackages.ubootTools ];
      }
      ''
        printf 'setenv extra_args "%s"\n' "$(cat ${config.system.build.toplevel}/kernel-params)" > boot.cmd
        cat >> boot.cmd <<'EOF'
        echo "NixOS RPi2 A/B: selecting slot"
        if test -z "''${kernel_addr_r}"; then setenv kernel_addr_r 0x08000000; fi
        if test -z "''${fdt_addr_r}"; then setenv fdt_addr_r 0x07000000; fi
        if test -z "''${ramdisk_addr_r}"; then setenv ramdisk_addr_r 0x06000000; fi
        if test -z "''${slot_addr_r}"; then setenv slot_addr_r 0x05f00000; fi
        setenv slot a
        fatload mmc 0:1 ''${slot_addr_r} slot && env import -t ''${slot_addr_r} ''${filesize}
        if itest.s "x''${slot}" == "xb"; then setenv rootdev ${config.my.abSlots.slotBDevice}; else setenv rootdev ${config.my.abSlots.slotADevice}; fi
        echo "NixOS RPi2 A/B: slot ''${slot}, root device ''${rootdev}"
        fatload mmc 0:1 ''${fdt_addr_r} rpi2.dtb
        fatload mmc 0:1 ''${kernel_addr_r} zImage
        fatload mmc 0:1 ''${ramdisk_addr_r} initrd.gz
        setenv bootargs root=''${rootdev} rootwait rootfstype=squashfs init=/init ''${extra_args}
        bootz ''${kernel_addr_r} ''${ramdisk_addr_r}:''${filesize} ''${fdt_addr_r}
        EOF
        mkimage -A arm -T script -C none -n "NixOS Rpi2 Ab Boot" -d boot.cmd "$out"
      '';
in
{
  sdImage = {
    firmwareSize = 32;
    rootVolumeLabel = "NIXOS_RPI2";

    populateFirmwareCommands = lib.mkForce ''
      mkdir -p firmware
      cp ${firmwareBoot}/bootcode.bin firmware/bootcode.bin
      cp ${firmwareBoot}/start.elf firmware/start.elf
      cp ${firmwareBoot}/fixup.dat firmware/fixup.dat
      cp ${firmwareBoot}/bcm2709-rpi-2-b.dtb firmware/bcm2709-rpi-2-b.dtb
      cp ${artifacts.uboot}/u-boot.bin firmware/u-boot.bin

      cat > firmware/config.txt <<EOF
      kernel=u-boot.bin
      dtb=bcm2709-rpi-2-b.dtb
      arm_64bit=0
      enable_uart=1
      disable_fw_kms_setup=1
      disable_overscan=1
      disable_splash=1
      avoid_warnings=1
      boot_delay=0
      gpu_mem=32
      EOF

      cp ${artifacts.kernel}/zImage firmware/zImage
      cp ${artifacts.kernel}/dtbs/bcm2836-rpi-2-b.dtb firmware/rpi2.dtb
      cp ${config.my.sdImage.initramfs} firmware/initrd.gz
      cp ${abBootScript} firmware/boot.scr

      echo "slot=a" > firmware/slot
    '';
  };
}
