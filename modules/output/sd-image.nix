{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.sdImage;

  initramfs =
    let
      busybox = pkgs.pkgsStatic.busybox;

      initScript = ''
        #!/bin/sh
        B=/bin/busybox
        $B mkdir -p /proc /sys /dev /lower /ov /merged
        $B mount -t proc proc /proc
        $B mount -t sysfs sys /sys
        $B mount -t devtmpfs dev /dev

        root=
        for a in $($B cat /proc/cmdline); do
          case $a in
            root=/dev/*) root=''${a#root=} ;;
          esac
        done

        if [ -z "$root" ]; then
          echo "initramfs: no usable root=/dev/... on the kernel command line" >&2
          exec $B sh
        fi

        i=0
        while [ ! -e "$root" ] && [ "$i" -lt 200000 ]; do
          i=$((i + 1))
        done
        if [ ! -e "$root" ]; then
          echo "initramfs: root device $root did not appear" >&2
          exec $B sh
        fi

        $B mount -t squashfs -o ro "$root" /lower
        $B mount -t tmpfs tmpfs /ov
        $B mkdir -p /ov/upper /ov/work
        $B mount -t overlay overlay -o lowerdir=/lower,upperdir=/ov/upper,workdir=/ov/work /merged

        $B mkdir -p /merged/dev /merged/proc /merged/sys /merged/run /merged/tmp
        $B mount --move /proc /merged/proc
        $B mount --move /sys /merged/sys
        $B mount --move /dev /merged/dev
        $B mount -t tmpfs tmpfs /merged/run

        export IN_NIXOS_SYSTEMD_STAGE1=true
        exec $B switch_root /merged /init
      '';
    in
    pkgs.runCommand "squashfs-ab-initrd.gz"
      {
        nativeBuildInputs = [
          pkgs.buildPackages.cpio
          pkgs.buildPackages.gzip
        ];
      }
      ''
        mkdir -p initrd/bin
        cp -L ${busybox}/bin/busybox initrd/bin/busybox
        ln -s busybox initrd/bin/sh

        cat > initrd/init <<'EOF'
        ${initScript}
        EOF
        chmod +x initrd/init

        ( cd initrd && find . | cpio -o -H newc 2>/dev/null | gzip -9n ) > "$out"
      '';

  body =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      slotSizeMB = cfg.slotSizeMB;

      diskId = lib.removePrefix "0x" config.sdImage.firmwarePartitionID;

      # systemd-repart (`image.repart`) alternative with MBR support.
      firmwarePartition = {
        name = "firmware";
        startMB = config.sdImage.firmwarePartitionOffset;
        sizeMB = config.sdImage.firmwareSize;
        type = "b";
        bootable = true;
      };

      slotAPartition = {
        name = "slot-a";
        startMB = firmwarePartition.startMB + firmwarePartition.sizeMB;
        sizeMB = slotSizeMB;
        type = "83";
      };

      slotBPartition = {
        name = "slot-b";
        startMB = slotAPartition.startMB + slotAPartition.sizeMB;
        sizeMB = slotSizeMB;
        type = "83";
      };

      dataPartition = {
        name = "data";
        startMB = slotBPartition.startMB + slotBPartition.sizeMB;
        sizeMB = cfg.data.sizeMB;
        type = "83";
      };

      partitions = [
        firmwarePartition
        slotAPartition
        slotBPartition
      ]
      ++ lib.optional cfg.data.enable dataPartition;

      imageSizeMB = lib.foldl' (
        size: partition: lib.max size (partition.startMB + partition.sizeMB)
      ) 0 partitions;

      partitionIndex =
        name:
        let
          index = lib.lists.findFirstIndex (partition: partition.name == name) null partitions;
        in
        if index == null then throw "sd-image: no partition named ${name}" else index + 1;

      partitionPartuuid =
        name: "${diskId}-${lib.fixedWidthString 2 "0" (toString (partitionIndex name))}";

      sfdiskPartitions = lib.concatMapStringsSep "\n" (
        partition:
        "start=${toString partition.startMB}M, size=${
          toString (partition.sizeMB * 1024 * 2)
        }, type=${partition.type}"
        + lib.optionalString (partition.bootable or false) ", bootable"
      ) partitions;

      minimalToplevel =
        pkgs.runCommand "nixos-system-minimal"
          {
            toplevel = config.system.build.toplevel;
            preferLocalBuild = true;
          }
          ''
            cp -a "$toplevel" "$out"
            chmod -R u+w "$out"
            rm -f "$out"/bin/switch-to-configuration "$out"/bin/.switch-to-configuration-wrapped 2>/dev/null || true
            rm -f "$out"/activate "$out"/dry-activate "$out"/prepare-root 2>/dev/null || true
            rm -f "$out"/kernel "$out"/boot.json
            rm -f "$out"/kernel-modules
            sed -i "s|$toplevel|$out|g" "$out"/init
          '';

    in
    {
      imports = lib.optional (cfg.template != null) cfg.template;

      fileSystems = {
        "/" = lib.mkForce {
          device = "/dev/disk/by-label/${config.sdImage.rootVolumeLabel}";
          fsType = "squashfs";
          noCheck = true;
          autoResize = false;
          autoFormat = false;
        };
      }
      // lib.optionalAttrs cfg.data.enable {
        "${cfg.data.mountPoint}" = {
          device = "/dev/disk/by-partuuid/${partitionPartuuid "data"}";
          fsType = "ext4";
          options = [
            "defaults"
            "noatime"
          ];
          noCheck = true;
        };
      };

      boot.loader.grub.enable = lib.mkForce false;
      sdImage.expandOnBoot = false;
      sdImage.compressImage = lib.mkForce cfg.compress;
      sdImage.rootFilesystemImage = lib.mkForce (
        pkgs.callPackage ./make-squashfs-fs.nix {
          inherit (config.sdImage) storePaths;
          compressImage = config.sdImage.compressImage;
          populateImageCommands = config.sdImage.populateRootCommands;
          volumeLabel = config.sdImage.rootVolumeLabel;
          pruneCruft = cfg.pruneCruft;
          compression = cfg.squashfsCompression;
          blockSize = cfg.squashfsBlockSize;
        }
      );
      sdImage.storePaths = lib.mkForce [ minimalToplevel ];

      sdImage.postBuildCommands = ''
        truncate -s $(( ${toString imageSizeMB} * 1024 * 1024 )) $img
        sfdisk --no-reread --no-tell-kernel $img <<EOF
        label: dos
        label-id: ${config.sdImage.firmwarePartitionID}
        ${sfdiskPartitions}
        EOF
        dd conv=notrunc if=$root_fs of=$img seek=$(( ${toString slotBPartition.startMB} * 2048 ))
        ${lib.optionalString cfg.data.enable ''
          data_fs=./data-fs.img
          truncate -s $(( ${toString dataPartition.sizeMB} * 1024 * 1024 )) "$data_fs"
          faketime "2000-01-01 00:00:00" mkfs.ext4 -F -q \
            -L ${lib.escapeShellArg cfg.data.label} \
            -U ${lib.escapeShellArg cfg.data.uuid} \
            -m 0 \
            -E lazy_itable_init=0,lazy_journal_init=0 \
            "$data_fs"
          dd conv=notrunc if="$data_fs" of=$img seek=$(( ${toString dataPartition.startMB} * 2048 ))
        ''}
      '';

      sdImage.populateRootCommands = lib.mkForce (
        # Put /etc into the image. There is not activation scripts that runs
        # during boot.
        ''
          etcStore=$(readlink -f ${config.system.build.etc}/etc)
          files=$PWD/files
          mkdir -p "$files/etc"
          ln -s "$etcStore" "$files/etc/static"
          (
            cd "$etcStore"
            find . -mindepth 1 | while IFS= read -r rel; do
              rel="''${rel#./}"
              src="$etcStore/$rel"
              tgt="$files/etc/$rel"
              if [ -e "$src.mode" ]; then
                mode=$(cat "$src.mode")
                mkdir -p "$(dirname "$tgt")"
                if [ "$mode" = direct-symlink ]; then
                  ln -sfn "$(readlink "$src")" "$tgt"
                else
                  cp -L "$src" "$tgt"
                  chmod "$mode" "$tgt"
                fi
              elif [ -L "$src" ]; then
                mkdir -p "$(dirname "$tgt")"
                ln -sfn "/etc/static/$rel" "$tgt"
              fi
            done
          )
          top=$(readlink -f ${minimalToplevel})
          ln -sfn "$top/init" ./files/init
        ''
        # Create /bin/sh
        + ''
          mkdir -p ./files/bin
          ln -sfn /run/current-system/sw/bin/sh ./files/bin/sh
        ''
        # Read-only squashfs root: the stage-2 init mounts a tmpfs here and
        # layers an overlay over /.
        + ''
          mkdir -p ./files/overlay

          # root's home. config/users-groups.nix creates it at boot with a tmpfiles
          # rule, but the autologin must not depend on that rule having run:
          # the login applet only warns ("can't change directory to '/root'")
          # and lands the shell in /, so bake the directory in.
          mkdir -p ./files/root
          ${lib.optionalString cfg.data.enable ''
            # Mount point for the persistent p4 filesystem.
            mkdir -p "./files${cfg.data.mountPoint}"
          ''}

          # my.rootfs.extraFiles (modules/base.nix): what a service needs outside
          # /etc on a root that cannot create anything at boot -- /root/.ssh for
          # dropbear is the one user today.
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (path: target: ''
              mkdir -p "./files/${dirOf path}"
              ln -sfn ${target} "./files/${path}"
            '') config.my.rootfs.extraFiles
          )}
        ''
      );
    };
in
{
  options = {
    my.readOnlyRoot = lib.mkEnableOption "a read-only SquashFS root with a tmpfs overlay";

    my.rootfs.extraFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''{ "root/.ssh/authorized_keys" = pkgs.writeText "keys" "ssh-ed25519 ..."; }'';
      description = ''
        Extra files at the root of the squashfs: relative path -> store path to
        symlink there. For example, `/init`, `/bin/sh`, `/etc` and the
        `/overlay` mount point are added by whichever module builds the root.

        The image bakes /etc at build time, so this is also how a service
        installs something outside /etc.
      '';
    };

    my.sdImage = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "the A/B SquashFS sd-card image";
          compress = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Compress the final image";
          };
          squashfsCompression = lib.mkOption {
            type = lib.types.str;
            default = "lzo";
            description = ''
              The mksquashfs compressor for the root partition: one of gzip, lzo,
              lz4, xz, zstd, lzma.
            '';
          };
          squashfsBlockSize = lib.mkOption {
            type = lib.types.int;
            default = 131072;
            description = ''
              The mksquashfs data block size, in bytes. Larger blocks compress
              better, but every random read has to unpack the whole block. 128
              KiB is the squashfs default and what the reference image uses; xz
              is usually paired with 1 MiB blocks, which is why switching the
              compressor here comes with switching this too.
            '';
          };
          pruneCruft = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Remove build-only files from every store path.
            '';
          };
          slotSizeMB = lib.mkOption {
            type = lib.types.int;
            default = 64;
            description = "Size of each A/B root partition, in MiB.";
          };
          data = lib.mkOption {
            type = lib.types.submodule {
              options = {
                enable = lib.mkEnableOption "a persistent ext4 data partition mounted at /data";
                sizeMB = lib.mkOption {
                  type = lib.types.int;
                  default = 128;
                  description = ''
                    Size of the data partition (p4), in MiB. This is independent
                    of the two A/B root slots.
                  '';
                };
                mountPoint = lib.mkOption {
                  type = lib.types.str;
                  default = "/data";
                  description = "Mount point of the persistent data partition.";
                };
                label = lib.mkOption {
                  type = lib.types.str;
                  default = "NIXOS_DATA";
                  description = "ext4 label of the data partition.";
                };
                uuid = lib.mkOption {
                  type = lib.types.str;
                  default = "6e69786f-732d-6461-7461-000000000004";
                  description = ''
                    Fixed ext4 filesystem UUID. Keeping it fixed makes the image
                    reproducible; the partition is referenced by MBR PARTUUID.
                  '';
                };
              };
            };
            default = { };
            description = "Persistent mutable data partition (p4), outside both A/B root slots.";
          };
          initramfs = lib.mkOption {
            type = lib.types.package;
            default = initramfs;
            description = ''
              Initramfs that mounts the read-only SquashFS root, builds the
              tmpfs overlay and switch_root's into the NixOS stage-2 init.
            '';
          };
          template = lib.mkOption {
            type = lib.types.nullOr lib.types.unspecified;
            default = "${pkgs.path}/nixos/modules/installer/sd-card/sd-image.nix";
            description = ''
              The nixpkgs sd-image template module to import.
            '';
          };
          extraModules = lib.mkOption {
            type = lib.types.listOf lib.types.deferredModule;
            default = [ ];
            example = lib.literalExpression ''
              [ ({ lib, ... }: { sdImage.firmwareSize = lib.mkForce 64; }) ]
            '';
            description = ''
              Modules appended to `image.modules.sd-card`, after the body.

              This is where a board supplies its boot files and where a
              configuration can tune nixpkgs `sdImage.*` options.
            '';
          };
        };
      };
      default = { };
      description = "A/B SquashFS sd-card image options.";
    };
  };

  config = lib.mkIf cfg.enable {
    image.modules.sd-card =
      let
        composed = {
          imports = [ body ] ++ cfg.extraModules;
        };
      in
      if cfg.template == null then composed else lib.mkForce composed;

    system.switch.enable = lib.mkForce false;
    system.activatable = lib.mkForce false;
    system.disableInstallerTools = true;
    system.build.etcActivationCommands = lib.mkForce "";

    # TODO: This doesnt seem necessary
    system.etc.overlay.enable = false;

    system.build.bootStage2 = lib.mkForce (
      pkgs.writeTextFile {
        name = "init-ash";
        executable = true;
        # TODO: Use environment.systemPackages for PATH here?
        text = ''
          #!${config.my.shell.path}
          export HOME=/root
          export PATH=${
            lib.makeBinPath [
              pkgs.util-linux
              config.my.shell.utils
              pkgs.coreutils
            ]
          }
          systemConfig=@systemConfig@
          if [ "''${IN_NIXOS_SYSTEMD_STAGE1:-}" != true ]; then
            ${lib.optionalString (
              !config.my.readOnlyRoot
            ) "mount -n -o remount,rw none / 2>/dev/null || true"}
            ${lib.optionalString config.my.readOnlyRoot ''
              mount -t tmpfs -o mode=0755 tmpfs /overlay
              mkdir -p /overlay/upper /overlay/work
              mount -t overlay overlay -o lowerdir=/,upperdir=/overlay/upper,workdir=/overlay/work /
            ''}
            if [ ! -e /proc/1 ]; then
              specialMount() {
                install -m 0755 -d "$2"
                mount -n -t "$4" -o "$3" "$1" "$2"
              }
              . ${config.system.build.earlyMountScript}
            fi
          fi
          [ -c /dev/kmsg ] && echo "booting system configuration $systemConfig" > /dev/kmsg
          install -m 0755 -d /etc
          install -m 0755 -d /etc/nixos
          install -m 01777 -d /tmp
          ln -sfn "$systemConfig" /run/current-system
          ln -sfn "$systemConfig" /run/booted-system
          exec "$systemConfig/systemd/lib/systemd/systemd" "$@"
        '';
      }
    );

    environment.etc."systemd/system-environment-generators/env-generator".enable = lib.mkForce false;

    # TODO: can we use `.enable = lib.mkForce false`?
    systemd.services.register-nix-paths = lib.mkForce {
      wantedBy = [ ];
      after = [ ];
      before = [ ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStart = "${config.my.shell.utils}/bin/true";
      };
    };

    system.build.installBootLoader = lib.mkForce "${pkgs.coreutils}/bin/true";
    boot.supportedFilesystems = lib.mkForce [
      "squashfs"
      "vfat"
      "ext4"
    ];

    boot.initrd.enable = lib.mkForce false;
    boot.modprobeConfig.enable = lib.mkForce false;
    boot.kernelModules = lib.mkForce [ ];

    system.fsPackages = lib.mkForce [ ];

    services.lvm.enable = lib.mkForce false;

    systemd.suppressedSystemUnits = [
      # Read-only SquashFS do not need these utils.
      "systemd-growfs-root.service"
      "systemd-growfs@.service"
      "systemd-makefs@.service"
      "systemd-fsck-root.service"
      "systemd-fsck@.service"
      "systemd-remount-fs.service"
      "systemd-quotacheck-root.service"
      "systemd-quotacheck@.service"
      "systemd-repart.service"
      "systemd-repart@.service"

      "factory-reset.target"
      "systemd-factory-reset-request.service"
      "systemd-factory-reset-reboot.service"
      "systemd-factory-reset@.service"
      "systemd-factory-reset.socket"
      "systemd-update-done.service"
    ];
  };
}
