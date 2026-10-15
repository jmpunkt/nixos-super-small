{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.wifi;

  wpaStart = pkgs.writeText "wpa_supplicant-start" ''
    iface=""
    while [ -z "$iface" ]; do
      for n in /sys/class/net/*; do
        d=''${n##*/}
        if [ -e "$n/wireless" ] || [ -e "$n/phy80211" ]; then
          iface="$d"
          break
        fi
      done
      [ -n "$iface" ] || sleep 1
    done
    exec ${cfg.package}/bin/wpa_supplicant -s -i "$iface" \
      -c /etc/wpa_supplicant.conf -C /run/wpa_supplicant
  '';
in
{
  options = {
    my.wifi.enable = lib.mkEnableOption "enable wifi support";

    my.wifi.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.wpa_supplicant.override {
        dbusSupport = false;
        withReadline = false;
        withPcsclite = false;
      };
      description = "The wpa_supplicant package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.wirelessRegulatoryDatabase = true;

    environment.systemPackages = [
      pkgs.iw
      cfg.package
    ];

    boot.kernelParams = [ "firmware_class.path=/run/current-system/firmware" ];

    environment.etc."wpa_supplicant.conf".text = ''
      ctrl_interface=DIR=/run/wpa_supplicant GROUP=wheel
      update_config=1
    '';

    systemd.services.wpa_supplicant = {
      description = "WPA supplicant";
      wants = [ "network-pre.target" ];
      after = [ "network-pre.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${config.my.shell.path} ${wpaStart}";
        Restart = "on-failure";
        RestartSec = "5s";
        RuntimeDirectory = "wpa_supplicant";
      };
    };
  };
}
