{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.swupdate;
  ab = config.my.abSlots;

  logLevels = {
    off = 0;
    error = 1;
    warn = 2;
    info = 3;
    trace = 4;
    debug = 5;
  };

  swupdateCmd = "${cfg.package}/bin/swupdate -f /etc/swupdate.cfg -l ${
    toString logLevels.${cfg.logLevel}
  } -w \"-r /etc/swupdate-web\"";

  swupdateStart = pkgs.writeScript "swupdate-start.sh" ''
    #!${config.my.shell.path}
    ${lib.optionalString (cfg.logFile != null) "mkdir -p \"${dirOf cfg.logFile}\""}
    exec ${swupdateCmd}${lib.optionalString (cfg.logFile != null) " >> \"${cfg.logFile}\" 2>&1"}
  '';

  # NOTE: The script needs to be portable. This is executed on the host which
  # might not has the correct Nix store.
  slotFlip = pkgs.writeScript "slot-flip.sh" ''
    #!/run/current-system/sw/bin/sh
    set -e
      PATH=/run/current-system/sw/bin

      boot="''${BOOT_MNT:-/run/boot}"
      dev="''${BOOT_DEV:-${ab.bootDevice}}"
      inactive="''${INACTIVE:-$(readlink -f ${ab.inactiveDevice})}"

      if [ "$inactive" = "${ab.slotBDevice}" ]; then
        next=b
      else
        next=a
      fi

      mkdir -p "$boot"
      mounted=0
      if [ -n "$dev" ] && ! grep -q " $boot " /proc/mounts; then
        mount -t vfat "$dev" "$boot" && mounted=1
      fi

      echo "slot=$next" > "$boot/slot"
      sync

      if [ "$mounted" = 1 ]; then
        umount "$boot"
      fi
      exit 0
  '';

  rootInactive = pkgs.writeScript "root-inactive.sh" ''
    #!${config.my.shell.path}
    # Slot b is the second root partition; whatever the kernel command line
    # does not name is slot a.
    case "$(cat /proc/cmdline)" in
      *root=${ab.slotBDevice}*) inactive="${ab.slotADevice}" ;;
      *)                        inactive="${ab.slotBDevice}" ;;
    esac
    ln -sf "$inactive" ${ab.inactiveDevice}
  '';
in
{
  options = {
    my.swupdate.enable = lib.mkEnableOption "the SWUpdate web server";

    my.swupdate.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.swupdate;
      description = "The SWUpdate package to run.";
    };

    my.swupdate.port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "HTTP port of the upload server.";
    };

    my.swupdate.logLevel = lib.mkOption {
      type = lib.types.enum (builtins.attrNames logLevels);
      default = "debug";
      description = ''
        SWUpdate loglevel.
      '';
    };

    my.swupdate.logFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/run/swupdate/swupdate.log";
      description = ''
        Where the swupdate log are stored.
      '';
    };

    my.abSlots.enable = lib.mkEnableOption "A/B root partitions updated through SWUpdate";

    my.abSlots.devicePrefix = lib.mkOption {
      type = lib.types.str;
      default = "/dev/mmcblk0";
      description = "Block device of the boot disk; the slot devices default to <prefix>p2 (a) and <prefix>p3 (b).";
    };

    my.abSlots.bootDevice = lib.mkOption {
      type = lib.types.str;
      default = "${config.my.abSlots.devicePrefix}p1";
      defaultText = lib.literalExpression ''"''${config.my.abSlots.devicePrefix}p1"'';
      description = "FAT boot partition holding the A/B slot selector.";
    };

    my.abSlots.slotADevice = lib.mkOption {
      type = lib.types.str;
      default = "${config.my.abSlots.devicePrefix}p2";
      defaultText = lib.literalExpression ''"''${config.my.abSlots.devicePrefix}p2"'';
      description = "Block device of root slot A.";
    };

    my.abSlots.slotBDevice = lib.mkOption {
      type = lib.types.str;
      default = "${config.my.abSlots.devicePrefix}p3";
      defaultText = lib.literalExpression ''"''${config.my.abSlots.devicePrefix}p3"'';
      description = "Block device of root slot B.";
    };

    my.abSlots.inactiveDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/root-inactive";
      description = "Symlink that resolves to the root partition SWUpdate should write.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.my.swu.hardware != "";
          message = "my.swupdate is enabled but my.swu.hardware is empty; the daemon checks /etc/hwrevision against the .swu hardware-compatibility list.";
        }
      ];

      environment.systemPackages = [ cfg.package ];

      environment.etc."hwrevision".text = "${config.my.swu.hardware} ${config.my.swu.hardware}\n";

      environment.etc."swupdate.cfg".text = ''
        globals: { };

        webserver: {
            listening_ports = "${toString cfg.port}";
            document_root = "/etc/swupdate-web";
        };
      '';

      environment.etc."swupdate-web/index.html".text = ''
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>SWUpdate - ${config.my.swu.hardware}</title>
          <style>
            body { font-family: system-ui, sans-serif; max-width: 34em; margin: 3em auto; padding: 0 1em; }
            button { padding: .4em 1.2em; }
            .muted { color: #666; font-size: .9em; }
          </style>
        </head>
        <body>
          <h1>Software update</h1>
          <p>Current version: <code>${config.my.swu.version}</code></p>
          <form method="post" action="/upload" enctype="multipart/form-data">
            <p><input type="file" name="file" accept=".swu" required></p>
            <p><button type="submit">Install</button> <span class="muted">the page stops responding while the rootfs is written</span></p>
          </form>
          <hr>
          <form method="post" action="/restart">
            <button type="submit">Reboot</button> <span class="muted">after a successful install</span>
          </form>
        </body>
        </html>
      '';

      systemd.services.swupdate = {
        description = "SWUpdate web server (.swu upload on port ${toString cfg.port})";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart = "${swupdateStart}";
          Restart = "always";
          RestartSec = "2s";
        };
      };
    })

    (lib.mkIf ab.enable {
      my.swu.device = lib.mkIf config.my.swu.enable ab.inactiveDevice;
      my.swu.postInstallScript = lib.mkIf config.my.swu.enable slotFlip;

      systemd.services.root-inactive = {
        description = "Resolve ${ab.inactiveDevice} (inactive A/B root partition)";
        wantedBy = [ "multi-user.target" ];
        before = [ "swupdate.service" ];
        after = [ "systemd-udevd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = rootInactive;
        };
      };
    })
  ];
}
