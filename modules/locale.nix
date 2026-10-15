{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.my.locale;
in
{
  options = {
    my.locale = lib.mkOption {
      type = lib.types.enum [
        "none"
        "en-utf8"
      ];
      default = "en-utf8";
      description = ''
        Installed locales for the system.

        `"none"` keeps the C/POSIX locale and ships no locale archive, which is
        the smallest option. `"en-utf8"` additionally installs the glibc
        `en_US.UTF-8` locale.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg == "none") {
      i18n.glibcLocales = lib.mkForce null;
      i18n.defaultLocale = lib.mkForce "C";
      i18n.supportedLocales = lib.mkForce [ ];
    })
    (lib.mkIf (cfg == "en-utf8") {
      i18n.defaultLocale = lib.mkForce "en_US.UTF-8";
      i18n.supportedLocales = lib.mkForce [ "en_US.UTF-8/UTF-8" ];
    })
  ];
}
