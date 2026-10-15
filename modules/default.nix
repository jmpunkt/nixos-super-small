{ modulesPath, ... }: {
  imports = [
    "${modulesPath}/profiles/minimal.nix"
    "${modulesPath}/profiles/perlless.nix"

    ./services/ssh.nix
    ./services/swupdate.nix
    ./services/wifi.nix

    ./base.nix
    ./systemd.nix
    ./locale.nix
    ./time.nix
    ./shell/default.nix
    ./shell/busybox.nix

    ./output/sd-image.nix
    ./output/swu.nix
  ];
}
