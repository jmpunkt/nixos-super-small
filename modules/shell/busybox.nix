{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.shell.busybox;

  usedShell = "${pkgs.busybox}/bin/ash";

  shellOverlay = final: prev: {
    busybox-nologin =
      if final.stdenv.hostPlatform.isAarch && !final.stdenv.hostPlatform.isStatic then
        final.busybox.overrideAttrs (o: {
          passthru = (o.passthru or { }) // {
            shellPath = "/bin/nologin";
            su = final.busybox-nologin;
          };
        })
      else
        final.busybox;

    shadow = final.busybox-nologin;

    coreutils = if final.stdenv.hostPlatform.isAarch then final.busybox else prev.coreutils;
    bash = if final.stdenv.hostPlatform.isAarch then final.busybox else prev.bash;
    bashNonInteractive =
      if final.stdenv.hostPlatform.isAarch then final.busybox else prev.bashNonInteractive;
    bashInteractive = if final.stdenv.hostPlatform.isAarch then final.busybox else prev.bashInteractive;

    util-linux =
      if final.stdenv.hostPlatform.isAarch then
        (prev.util-linux.override {
          fetchurl = final.stdenv.fetchurlBoot;
          capabilitiesSupport = false;
          cryptsetupSupport = false;
          nlsSupport = false;
          ncursesSupport = false;
          pamSupport = false;
          shadowSupport = false;
          systemdSupport = false;
          translateManpages = false;
          withLastlog = false;
          writeSupport = false;
        }).overrideAttrs
          (o: {
            configureFlags = (o.configureFlags or [ ]) ++ [
              "--disable-all-programs"
              "--disable-asciidoc"
              "--disable-poman"
              "--enable-libblkid"
              "--enable-libmount"
              "--enable-libsmartcols"
              "--enable-libuuid"
              "--enable-agetty"
              "--enable-fsck"
              "--enable-mount"
              "--enable-swapon"
              "--enable-sulogin"
            ];

            passthru = (o.passthru or { }) // {
              hasCol = false;
            };

            postInstall = (o.postInstall or "") + ''
              rm -rf "$bin/share"
              find "$bin/bin" -maxdepth 1 -xtype l -delete
              find "$man/share/man" -xtype l -delete
            '';
          })
        // {
          lastlog = final.runCommand "util-linux-lastlog-stub" { } ''
            mkdir -p $out/lib/security $out/lib/tmpfiles.d
          '';
        }
      else
        prev.util-linux;

    util-linuxMinimal =
      if final.stdenv.hostPlatform.isAarch then final.util-linux else prev.util-linuxMinimal;

    # Applets this image has no use for: they either duplicate a program
    # another package of the base system owns, or repeat what systemd already
    # does for it. They are compiled out rather than just ordered behind in the
    # profile: a busybox symlink that wins the PATH lookup is silently the
    # wrong program, and the busybox variant talks to the wrong init.
    busybox =
      if final.stdenv.hostPlatform.isAarch && !final.stdenv.hostPlatform.isStatic then
        prev.busybox.override {
          extraConfig = ''
            # util-linux builds these, see the override above.
            CONFIG_MOUNT n
            CONFIG_UMOUNT n
            CONFIG_SWAPON n
            CONFIG_SWAPOFF n
            CONFIG_FSCK n
            CONFIG_SULOGIN n
            CONFIG_GETTY n

            # systemd is PID 1. Its reboot/poweroff/halt/shutdown are symlinks
            # to systemctl and run the shutdown transaction (including our
            # post-install hook). The busybox applets instead just signal PID
            # 1, and systemd reads those signals as re-exec (reboot/SIGTERM),
            # D-Bus reconnect (halt/SIGUSR1) and status dump (poweroff/
            # SIGUSR2) - the board stayed on the old slot. init, linuxrc and
            # runlevel are the sysv leftovers of the same family, bootchartd
            # profiles that init.
            CONFIG_INIT n
            CONFIG_LINUXRC n
            CONFIG_RUNLEVEL n
            CONFIG_HALT n
            CONFIG_POWEROFF n
            CONFIG_REBOOT n
            CONFIG_BOOTCHARTD n

            # systemd-udevd creates and manages /dev; a second device manager
            # must not be around to be started by accident.
            CONFIG_MDEV n
            CONFIG_UEVENT n

            # journald owns /dev/log, the kernel log and the service output,
            # so there is nothing for busybox's syslog stack to collect.
            CONFIG_SYSLOGD n
            CONFIG_KLOGD n
            CONFIG_LOGREAD n

            # Services are started by systemd, on timers instead of cron.
            CONFIG_CROND n
            CONFIG_CRONTAB n

            # systemd-networkd configures the interfaces and runs the DHCP
            # server; busybox's client, server and ifupdown would race it for
            # the address, the routes and resolv.conf.
            CONFIG_UDHCPC n
            CONFIG_UDHCPC6 n
            CONFIG_UDHCPD n
            CONFIG_IFUP n
            CONFIG_IFDOWN n

            # systemd supervises the services and journald collects their
            # output: runsvdir and the daemontools wrappers are a second
            # supervisor, svlogd a second log pipeline, start-stop-daemon a
            # second service command.
            CONFIG_RUNSV n
            CONFIG_RUNSVDIR n
            CONFIG_SV n
            CONFIG_SVC n
            CONFIG_SVOK n
            CONFIG_SVLOGD n
            CONFIG_CHPST n
            CONFIG_ENVDIR n
            CONFIG_ENVUIDGID n
            CONFIG_SETUIDGID n
            CONFIG_SOFTLIMIT n
            CONFIG_START_STOP_DAEMON n

            # Listeners that have no job here: the update is served by
            # SWUpdate's own webserver, logins go over Dropbear, name
            # resolution over systemd-resolved, and there is no print spool.
            CONFIG_INETD n
            CONFIG_HTTPD n
            CONFIG_TELNETD n
            CONFIG_FTPD n
            CONFIG_TFTPD n
            CONFIG_LPD n
            CONFIG_DNSD n
          '';
        }
      else
        prev.busybox;

    findutils =
      if final.stdenv.hostPlatform.isAarch then
        (final.runCommand "findutils-busybox" { } ''
          mkdir -p $out/bin
          for t in find xargs; do ln -s ${final.busybox}/bin/$t $out/bin/$t; done
        '').overrideAttrs
          (_: {
            meta = {
              mainProgram = "find";
            };
          })
      else
        prev.findutils;

    gnused =
      if final.stdenv.hostPlatform.isAarch then
        (final.runCommand "gnused-busybox" { } ''
          mkdir -p $out/bin
          ln -s ${final.busybox}/bin/sed $out/bin/sed
        '').overrideAttrs
          (_: {
            meta = {
              mainProgram = "sed";
            };
          })
      else
        prev.gnused;

    gnugrep =
      if final.stdenv.hostPlatform.isAarch then
        (final.runCommand "gnugrep-busybox" { } ''
          mkdir -p $out/bin
          for t in grep egrep fgrep; do ln -s ${final.busybox}/bin/grep $out/bin/$t; done
        '').overrideAttrs
          (_: {
            meta = {
              mainProgram = "grep";
            };
          })
      else
        prev.gnugrep;
  };
in
{
  options = {
    my.shell.busybox = {
      enable = lib.mkOption {
        default = false;
        example = true;
        description = "enable busybox shell";
        type = lib.types.bool;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      shellOverlay
    ];

    # The profile keeps the first package that provides a name, so systemd
    # stays in front: it owns the shutdown entry points
    # (reboot/poweroff/halt/shutdown) and the udev and journal tools. Busybox
    # does not build the colliding applets any more, this order is what keeps
    # it that way for any applet added later.
    environment.corePackages = lib.mkForce [
      pkgs.systemd
      config.my.shell.utils
      pkgs.util-linux
    ];
    environment.defaultPackages = lib.mkForce [ ];
    environment.shell.enable = false;
    environment.shells = lib.mkForce [ usedShell ];
    environment.binsh = usedShell;
    environment.etc.profile.text = ''
      export PATH=/run/current-system/sw/bin:/bin
      ${lib.optionalString (config.i18n.glibcLocales != null) ''
        export LANG=${config.i18n.defaultLocale}
        export LOCALE_ARCHIVE=${config.i18n.glibcLocales}/lib/locale/locale-archive
      ''}
    '';

    console.enable = false;
    programs.bash.enable = false;
    security.sudo.enable = false;
    security.enableWrappers = false;
    users.manageLingering = false;

    # NixOS 26.05 always evaluates the PAM and shadow modules. Keep the
    # busybox login stack, but stop those modules from pulling their normal
    # packages into the minimal image.
    security.shadow.enable = lib.mkForce true;
    security.shadow.su.package = lib.mkForce pkgs.busybox;
    security.loginDefs.package = lib.mkForce pkgs.busybox;
    security.pam.package = lib.mkForce pkgs.busybox;
    security.pam.services = lib.mkForce { };
    security.wrappers.unix_chkpwd.enable = false;
    security.wrappers.su.enable = false;
    security.wrappers.sg.enable = false;
    security.wrappers.newgrp.enable = false;
    security.wrappers.newuidmap.enable = false;
    security.wrappers.newgidmap.enable = false;

    systemd.sysusers.enable = false;
    services.userborn.enable = true;
    services.userborn.package = pkgs.buildPackages.userborn;
    services.userborn.static = true;
    environment.etc.shadow.mode = lib.mkForce "0600";

    services.logind.enable = lib.mkForce false;

    users.defaultUserShell = usedShell;
    my.shell.path = lib.mkForce usedShell;
  };
}
