{ pkgs }:
let
  inherit (pkgs) lib;

  boardConfig = with lib.kernel; {
    DEVTMPFS = yes;
    DEVTMPFS_MOUNT = yes;
    TMPFS = yes;
    SQUASHFS = yes;
    SQUASHFS_LZ4 = yes;
    SQUASHFS_LZO = yes;
    SQUASHFS_XZ = yes;
    SQUASHFS_ZLIB = yes;
    SQUASHFS_ZSTD = yes;
    SQUASHFS_4K_DEVBLK_SIZE = yes;
    SQUASHFS_EMBEDDED = no;
    OVERLAY_FS = yes;
    EXT4_FS = yes;
    FAT_FS = yes;
    MSDOS_FS = yes;
    VFAT_FS = yes;
    NLS = yes;
    NLS_CODEPAGE_437 = yes;
    NLS_ISO8859_1 = yes;

    MMC = yes;
    MMC_BLOCK = yes;
    MMC_SDHCI = yes;
    MMC_SDHCI_PLTFM = yes;
    MMC_SDHCI_IPROC = yes;
    MMC_BCM2835 = yes;

    SERIAL_AMBA_PL011 = yes;
    SERIAL_AMBA_PL011_CONSOLE = yes;
    SERIAL_8250 = yes;
    SERIAL_8250_CONSOLE = yes;
    SERIAL_8250_BCM2835_AUX = yes;

    NET = yes;
    INET = yes;
    NET_CORE = yes;
    NETDEVICES = yes;
    ETHERNET = yes;
    USB = yes;
    USB_SUPPORT = yes;
    USB_DWC2 = yes;
    USB_NET_SMSC95XX = yes;
    USB_NET_CDC_SUBSET_ENABLE = yes;
    USB_NET_CDC_SUBSET = yes;
    USB_ALI_M5632 = yes;
    USB_AN2720 = yes;
    USB_BELKIN = yes;
    USB_CATC = yes;
    USB_KAWETH = yes;
    USB_PEGASUS = yes;
    USB_RTL8150 = yes;
    USB_RTL8152 = yes;
    USB_USBNET = yes;
    USB_NET_AX88179_178A = yes;
    USB_NET_AX8817X = yes;
    USB_NET_CDCETHER = yes;
    USB_NET_CDC_EEM = yes;
    USB_NET_CDC_NCM = yes;
    USB_NET_DM9601 = yes;
    USB_NET_GL620A = yes;
    USB_NET_NET1080 = yes;
    USB_NET_PLUSB = yes;
    USB_NET_MCS7830 = yes;
    USB_NET_RNDIS_HOST = yes;
    USB_NET_ZAURUS = yes;
  };

  bootConfig = boardConfig;

  k612 = pkgs.linux_6_12;

  kernel =
    (pkgs.buildLinux {
      pname = "rpi2-linux";
      inherit (k612) version modDirVersion src;
      defconfig = "multi_v7_defconfig";
      autoModules = false;
      ignoreConfigErrors = true;
      # mkForce: common-config.nix sets several of these too and structured
      # kconfig is merged through the module system, where a tie is an error
      # rather than "last one wins".
      structuredExtraConfig = lib.mapAttrs (_: lib.mkForce) bootConfig;
    }).overrideAttrs
      (o: {
        postInstall = (o.postInstall or "") + ''
          cp "$buildRoot/arch/arm/boot/Image" "$out/Image"
          cp "$buildRoot/arch/arm/boot/zImage" "$out/zImage"
          rm -f "$out/System.map"
          find "$out/dtbs" -type f ! -name 'bcm2836-rpi-2-b.dtb' -delete
        '';
      });

  uboot = pkgs.buildUBoot {
    defconfig = "rpi_2_defconfig";
    filesToInstall = [ "u-boot.bin" ];
    extraMeta.platforms = [ "armv7l-linux" ];
  };
in
{
  inherit kernel uboot;
}
