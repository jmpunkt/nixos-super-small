{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.shell;
in
{
  options = {
    my.shell.path = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.busybox}/bin/ash";
      defaultText = lib.literalExpression ''"''${pkgs.busybox}/bin/ash"'';
      description = ''
        Absolute path to the real shell used for our service scripts.
      '';
    };

    my.shell.utils = lib.mkOption {
      type = lib.types.package;
      default = pkgs.busybox;
      description = ''
        Package providing the busybox-compatible programs.
      '';
    };
  };

  config = { };
}
