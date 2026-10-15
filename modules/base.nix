{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.my;

  baseOverlay = final: prev: {

    swupdate = prev.callPackage ../pkgs/swupdate { };
    libubootenv = prev.callPackage ../pkgs/libubootenv { };

    stdenv =
      if prev.stdenv.hostPlatform.isAarch then
        prev.stdenvAdapters.withCFlags [
          "-Os"
          "-mthumb"
          "-D_TIME_BITS=64"
          "-D_FILE_OFFSET_BITS=64"
          "-D_LARGEFILE_SOURCE"
          "-D_LARGEFILE64_SOURCE"
        ] prev.stdenv
      else
        prev.stdenv;

    dbus =
      if final.stdenv.hostPlatform.isAarch then
        (prev.dbus.override {
          x11Support = false;
        }).overrideAttrs
          (o: {
            buildInputs = builtins.filter (
              dep:
              !final.lib.elem (final.lib.getName dep) [
                "audit"
                "libapparmor"
                "libcap-ng"
              ]
            ) (o.buildInputs or [ ]);
            mesonFlags = (o.mesonFlags or [ ]) ++ [
              "-Dapparmor=disabled"
              "-Dlibaudit=disabled"
            ];
          })
      else
        prev.dbus;

    glibc =
      if final.stdenv.hostPlatform.isAarch then
        prev.glibc.overrideAttrs (o: {
          env = (o.env or { }) // {
            NIX_CFLAGS_COMPILE = (o.env.NIX_CFLAGS_COMPILE or "") + " -Os";
          };
          # TODO: Maybe this can be disabled more easily.
          postInstall = (o.postInstall or "") + ''
            rm -rf "$out/lib/gconv" "$out/share/i18n" "$out/share/locale"
          '';
        })
      else
        prev.glibc;

    # swupdate only uses libconfig's C API. The C++ bindings are unused here,
    # but their SONAME reference pulls the full libstdc++ runtime into the image.
    libconfig =
      if final.stdenv.hostPlatform.isAarch then
        prev.libconfig.overrideAttrs (o: {
          postInstall = (o.postInstall or "") + ''
            rm -f "$out"/lib/libconfig++*
            rm -f "$out"/lib/pkgconfig/libconfig++.pc
            rm -rf "$out"/lib/cmake/libconfig++
            rm -f "$out"/include/libconfig.h++
            rm -rf "$out"/share/info
          '';
        })
      else
        prev.libconfig;

    # Runtime images do not need static archives. json-c otherwise installs
    # libjson-c.a into the same output as the shared library.
    json_c =
      if final.stdenv.hostPlatform.isAarch then
        prev.json_c.overrideAttrs (o: {
          cmakeFlags = (o.cmakeFlags or [ ]) ++ [
            "-DBUILD_STATIC_LIBS:BOOL=OFF"
          ];
        })
      else
        prev.json_c;
  };
in
{
  options = {
    my.enable = lib.mkEnableOption "the minimal embedded base system";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ baseOverlay ];

    nixpkgs.config.replaceCrossStdenv =
      { baseStdenv, ... }:
      if baseStdenv.hostPlatform.isAarch && (baseStdenv.hasCC or false) then
        baseStdenv.override {
          cc = baseStdenv.cc.override {
            cc = baseStdenv.cc.cc.overrideAttrs (o: {
              configureFlags = (o.configureFlags or [ ]) ++ [
                "--disable-libsanitizer"
                "--disable-libgomp"
                "--disable-libquadmath"
                "--disable-libitm"
              ];
            });
          };
        }
      else
        baseStdenv;

    environment.etc.services.enable = lib.mkForce false;
    environment.etc.protocols.enable = lib.mkForce false;
    environment.etc.terminfo.enable = lib.mkForce false;

    fonts.fontconfig.enable = lib.mkForce false;
    security.pki.installCACerts = lib.mkForce false;
    hardware.enableAllHardware = lib.mkForce false;
    programs.nano.enable = false;
    programs.less.enable = lib.mkForce false;
    services.nscd.enable = lib.mkForce false;
    nix.enable = false;
    system.nssModules = lib.mkForce [ ];
    powerManagement.enable = lib.mkDefault false;

    boot.bcache.enable = lib.mkForce false;
    boot.swraid.enable = lib.mkForce false;
    boot.kexec.enable = false;

    services.dbus.enable = true;
    services.dbus.implementation = "dbus";
    systemd.services.dbus.wantedBy = [ "multi-user.target" ];
    systemd.user.services.dbus.enable = false;
    systemd.user.sockets.dbus.enable = false;
    systemd.user.sockets.dbus.wantedBy = lib.mkForce [ ];
    security.wrappers.dbus-daemon-launch-helper.enable = false;

    services.getty.autologinUser = "root";
    services.getty.loginProgram = lib.getExe' cfg.shell.utils "login";
    systemd.targets.getty.wants = lib.mkForce [ ];
    systemd.services."getty@".enable = lib.mkForce false;

    environment.etc."udev/hwdb.bin".source = lib.mkForce "${pkgs.runCommand "empty-hwdb" { }
      "touch $out"
    }";
  };
}
