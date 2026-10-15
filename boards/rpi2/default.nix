{
  config,
  lib,
  pkgs,
  ...
}:
let
  ath9kHtcFirmware = pkgs.stdenvNoCC.mkDerivation {
    pname = "ath9k-htc-firmware";
    version = "linux-firmware";
    nativeBuildInputs = [ pkgs.buildPackages.coreutils ];
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/firmware"
      cp "${
        pkgs.fetchurl {
          url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/htc_9271.fw";
          sha256 = "17p5ycnzxc48phjcykyvrj4yhkqb2068cc6nvn73ic7jm3wj7hdm";
        }
      }" "$out/lib/firmware/htc_9271.fw"
      cp "${
        pkgs.fetchurl {
          url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/htc_7010.fw";
          sha256 = "053injqqxi92sci6p0bdv1nmv240n21c70gzpfab9w2hjig9xk25";
        }
      }" "$out/lib/firmware/htc_7010.fw"
      runHook postInstall
    '';
  };
in
{
  imports = [
    ./rpi2-minimal-kernel.nix
  ];

  config = lib.mkMerge [
    {
      my.enable = true;
      my.time.enable = true;
      my.readOnlyRoot = true;
      my.sdImage.enable = true;
      my.shell.busybox.enable = true;

      my.ssh.enable = true;
      my.ssh.allowEmptyPassword = true;
      my.wifi.enable = true;
      my.swu.enable = true;
      my.swupdate.enable = true;

      nixpkgs.hostPlatform = lib.mkDefault "armv7l-linux";

      my.sdImage.compress = lib.mkDefault false;
      my.sdImage.data.enable = lib.mkDefault true;
      my.sdImage.extraModules = [ ./sd-image.nix ];

      my.swu.hardware = lib.mkDefault "rpi2";
      my.swu.version = lib.mkDefault "0.3.6";
      my.swupdate.logLevel = "trace";

      my.abSlots.enable = lib.mkDefault true;

      networking.useNetworkd = lib.mkForce true;
      networking.useDHCP = lib.mkForce false;
      networking.resolvconf.enable = lib.mkForce false;
      networking.firewall.enable = false;

      systemd.network.wait-online.enable = lib.mkForce false;
      services.resolved.enable = true;
      systemd.network.networks."10-wired-static" = {
        matchConfig.Type = "ether";
        address = [ "192.168.10.1/24" ];
        networkConfig.DHCPServer = true;
        dhcpServerConfig = {
          PoolOffset = 50;
          PoolSize = 151;
          PersistLeases = "no";
          EmitRouter = false;
        };
      };
    }

    (lib.mkIf config.my.wifi.enable {
      hardware.firmware = [ ath9kHtcFirmware ];
      hardware.firmwareCompression = "none";
    })
  ];
}
