{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.swu;

  swuOverlay =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.my.swu;

      members = [
        "sw-description"
        "rootfs.squashfs"
      ]
      ++ lib.optional (cfg.postInstallScript != null) "slot-flip.sh";

      bundle =
        pkgs.runCommand "${cfg.hardware}-swu"
          {
            nativeBuildInputs = [
              pkgs.buildPackages.cpio
              pkgs.buildPackages.coreutils
            ];
            meta.platforms = lib.platforms.all;
          }
          ''
            mkdir -p $out work
            cp ${config.sdImage.rootFilesystemImage} work/rootfs.squashfs
            sha256=$(sha256sum work/rootfs.squashfs | cut -d' ' -f1)
            ${lib.optionalString (cfg.postInstallScript != null) ''
              cp ${cfg.postInstallScript} work/slot-flip.sh
              chmod +x work/slot-flip.sh
            ''}

            cat > work/sw-description <<EOF
            software =
            {
                version = "${cfg.version}";
                description = "${cfg.hardware} squashfs root filesystem";
                hardware-compatibility = [ "${cfg.hardware}" ];
                files = (
                    {
                        filename = "rootfs.squashfs";
                        device = "${cfg.device}";
                        type = "raw";
                        properties = { sha256 = "$sha256"; };
                    }
                );
                ${lib.optionalString (cfg.postInstallScript != null) ''
                  scripts = (
                      {
                          filename = "slot-flip.sh";
                          type = "postinstall";
                          properties = { sha256 = "$(sha256sum work/slot-flip.sh | cut -d' ' -f1)"; };
                      }
                  );
                ''}
            }
            EOF

            (
              cd work
              printf '%s\n' ${lib.concatMapStringsSep " " (m: "'${m}'") members} |
                ${pkgs.buildPackages.cpio}/bin/cpio -o -H newc --quiet
            ) > $out/${cfg.hardware}-rootfs-${cfg.version}.swu
          '';
    in
    {
      system.build.image = lib.mkForce bundle;
      image.filePath = lib.mkForce "${cfg.hardware}-rootfs-${cfg.version}.swu";
      my.swu.bundle = lib.mkOptionDefault bundle;
    };
in
{
  options = {
    my.swu.enable = lib.mkEnableOption "SWupdate file builder";

    my.swu.version = lib.mkOption {
      type = lib.types.str;
      default = "0.1.0";
      description = "sw-description version";
    };

    my.swu.device = lib.mkOption {
      type = lib.types.str;
      default = config.my.abSlots.slotADevice;
      defaultText = lib.literalExpression "config.my.abSlots.slotADevice";
      description = "Target device the rootfs image is written to.";
    };

    my.swu.hardware = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "hardware-compatibility entry of the sw-description";
    };

    my.swu.postInstallScript = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Shell script run by SWUpdate on the target after the rootfs image has
        been written. Used to flip the A/B boot slot.

        The script is packed into the .swu and runs on a device that may be
        running a different build, so it must not reference any /nix/store path.
        Use `#!/run/current-system/sw/bin/sh` for the shell script.
      '';
    };

    my.swu.bundle = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hardware != "";
        message = "my.swu is enabled but my.swu.hardware is empty";
      }
      {
        assertion = config.my.sdImage.enable;
        message = "my.swu is enabled but my.sdImage is not: the .swu packs the sd-card image's root partition.";
      }
      {
        assertion =
          cfg.postInstallScript == null
          || !lib.strings.hasInfix "/nix/store" (builtins.readFile cfg.postInstallScript);
        message = "my.swu.postInstallScript references /nix/store, but it is packed into the .swu and runs on a device whose store must not contain this build's paths.";
      }
      {
        assertion = !config.my.sdImage.enable || !config.my.sdImage.compress;
        message = "my.swu requires my.sdImage.compress = false: the .swu embeds the raw root partition image.";
      }
    ];

    environment.etc."sw-version".text = "${cfg.version}\n";

    image.modules.swu = {
      imports = [ config.image.modules.sd-card ] ++ [ swuOverlay ];
    };
  };
}
