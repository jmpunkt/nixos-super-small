{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.time;

  zoneinfoMinimal =
    pkgs.runCommand "zoneinfo-minimal"
      {
        nativeBuildInputs = [ pkgs.buildPackages.coreutils ];
      }
      ''
        mkdir -p $out/Etc
        cp -L ${pkgs.tzdata}/share/zoneinfo/UTC $out/UTC
        cp -L ${pkgs.tzdata}/share/zoneinfo/UTC $out/Etc/UTC
        cp -L ${pkgs.tzdata}/share/zoneinfo/UTC $out/Etc/GMT
      '';
in
{
  options = {
    my.time = {
      enable = lib.mkEnableOption "enable minimal timezone";
    };
  };

  config = lib.mkIf cfg.enable {
    time.timeZone = "UTC";
    environment.etc."zoneinfo" = lib.mkForce {
      source = zoneinfoMinimal;
      mode = "symlink";
    };
    systemd.globalEnvironment.TZDIR = lib.mkForce "/etc/zoneinfo";
    services.timesyncd.enable = false;
  };
}
