{
  config,
  pkgs,
  lib,
  ...
}:
let
  artifacts = import ./rpi2-artifacts.nix { inherit pkgs; };

  agetty =
    tty:
    lib.concatStringsSep " " [
      "${lib.getExe' pkgs.util-linux "agetty"}"
      "--login-program"
      config.services.getty.loginProgram
      "--issue-file"
      "/etc/issue:/etc/issue.d:/run/issue:/run/issue.d"
      "--autologin"
      config.services.getty.autologinUser
      "--noclear"
      "--keep-baud"
      tty
      "115200,38400,9600"
      "$TERM"
    ];

  gettyService = {
    enable = lib.mkOverride 49 true;
    serviceConfig.ExecStart = [
      ""
      (agetty "%I")
    ];
  };
in
{
  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor artifacts.kernel);

  # The sd-image module defaults to 7, which floods the local console with
  # kernel info messages. Keep only errors on the console.
  boot.consoleLogLevel = lib.mkForce 4;

  boot.kernelParams = [
    "console=tty1"
    "console=ttyAMA0,115200"
    "rootwait"
    "rw"
    "elevator=deadline"
  ];

  services.fstrim.enable = lib.mkForce false;
  services.journald.extraConfig = lib.mkForce "Storage=volatile";

  systemd.additionalUpstreamSystemUnits = [
    "getty-pre.target"
    "getty.target"
    "getty@.service"
    "serial-getty@.service"
  ];

  systemd.services."getty@" = gettyService;

  systemd.services."serial-getty@" = gettyService // {
    restartIfChanged = false;
  };

  systemd.services."getty@tty1" = gettyService // {
    wantedBy = [ "getty.target" ];
    overrideStrategy = "asDropin";
  };
  systemd.targets.getty.wantedBy = [ "multi-user.target" ];

  hardware.deviceTree = {
    enable = lib.mkForce true;
    filter = lib.mkForce "bcm2836-rpi-2-b.dtb";
    name = lib.mkForce "bcm2836-rpi-2-b.dtb";
  };
}
