{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.my;

  systemdOverlay = final: prev: {
    # TODO: Re-check if we need this.
    systemdMinimal = if final.stdenv.hostPlatform.isAarch then final.systemd else prev.systemdMinimal;
    systemdLibs = if final.stdenv.hostPlatform.isAarch then final.systemd else prev.systemdLibs;

    systemd =
      if final.stdenv.hostPlatform.isAarch then
        (prev.systemd.override {
          util-linux = final.util-linux;
          withAcl = false;
          withAnalyze = false;
          withApparmor = false;
          withAudit = false;
          withCompression = false;
          withCoredump = false;
          withCryptsetup = false;
          withDocumentation = false;
          withEfi = false;
          withFido2 = false;
          withFirstboot = false;
          withGcrypt = false;
          withHomed = false;
          withHostnamed = false;
          withHwdb = false;
          withImportd = false;
          withKernelInstall = false;
          withKexectools = false;
          withKmod = false;
          withLibBPF = false;
          withLibarchive = false;
          withLibidn2 = false;
          withLibseccomp = false;
          withLocaled = false;
          withLogind = false;
          withMachined = false;
          withNetworkd = true;
          withNspawn = false;
          withNss = false;
          withOomd = false;
          withOpenSSL = false;
          withPCRE2 = false;
          withPam = false;
          withPasswordQuality = false;
          withPolkit = false;
          withPortabled = false;
          withQrencode = false;
          withRemote = false;
          withRepart = false;
          withResolved = true;
          withShellCompletions = false;
          withSysupdate = false;
          withSysusers = false;
          withTimedated = false;
          withTimesyncd = false;
          withTpm2Tss = false;
          withUkify = false;
          withUserDb = false;
          withUtmp = false;
          withVConsole = false;
          withVmspawn = false;
        }).overrideAttrs
          (
            o:
            let
              lib = prev.pkgs.lib;
            in
            {
              # nixpkgs' systemd replaces /bin/false in its D-Bus service files
              # with ${coreutils}/bin/false. This overlay maps coreutils to
              # busybox, so let busybox through the default `bash` runtime guard
              # (bash and coreutils are the same package here). Any other
              # disallowed requisite is still rejected.
              disallowedRequisites = builtins.filter (p: p != final.busybox) (o.disallowedRequisites or [ ]);

              mesonFlags = (o.mesonFlags or [ ]) ++ [
                (lib.mesonBool "mountfsd" false)
                (lib.mesonEnable "fdisk" false)

                # Keep systemd's libmount/libblkid support: the minimal
                # util-linux below builds those libraries (and the small set of
                # programs whose paths systemd embeds), matching Buildroot.
                (lib.mesonEnable "libmount" true)
                (lib.mesonEnable "blkid" true)

                # Turn off helpers whose features this board does not use:
                # backlight, hibernation, pstore, rfkill, the Storage Target
                # Mode daemon, and the namespace resource daemon. Some helpers
                # with related names are still built by systemd, so their
                # binaries and units are removed below.
                (lib.mesonBool "backlight" false)
                (lib.mesonBool "hibernate" false)
                (lib.mesonBool "nsresourced" false)
                (lib.mesonBool "pstore" false)
                (lib.mesonBool "rfkill" false)
                (lib.mesonBool "storagetm" false)

                # nixpkgs forces SMACK support on. This board has no SMACK
                # policy, and updates go through SWUpdate, so it is not wanted.
                (lib.mesonBool "smack" false)
                (lib.mesonBool "ima" false)
                (lib.mesonBool "translations" false)
                (lib.mesonOption "dbus-interfaces-dir" "no")
                (lib.mesonOption "default-locale" "C")
                (lib.mesonOption "default-user-shell" "/bin/sh")
              ];

              env = (o.env or { }) // {
                NIX_CFLAGS_COMPILE = (o.env.NIX_CFLAGS_COMPILE or "") + " -ffunction-sections -fdata-sections";
              };

              postInstall = (o.postInstall or "") + ''
                rm -rf "$out/share/locale"
                rm -rf "$out/share/polkit-1"
                rm -rf "$out/share/factory"
                rm -rf "$out/share/dbus-1/interfaces"
                rm -rf "$out/share/dbus-1/services"

                # Keep systemd's shutdown/reboot entry points. They are
                # symlinks to systemctl, unlike busybox's applets, which only
                # signal init and do not drive systemd's shutdown transaction.
                keep_bin=" systemctl udevadm journalctl systemd-tmpfiles systemd-sysusers systemd-machine-id-setup reboot poweroff halt shutdown "
                if [ -d "$out/bin" ]; then
                  for p in "$out/bin"/*; do
                    [ -e "$p" ] || [ -L "$p" ] || continue
                    case "$keep_bin" in
                      *" $(basename "$p") "*) ;;
                      *) rm -f "$p" ;;
                    esac
                  done
                fi
                if [ -d "$out/sbin" ]; then
                  find "$out/sbin" -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null || true
                fi

                rm -rf "$out/lib/systemd/catalog"
                rm -f \
                  "$out/lib/systemd/systemd-networkd-wait-online" \
                  "$out/lib/systemd/systemd-factory-reset" \
                  "$out/lib/systemd/systemd-boot-check-no-failures" \
                  "$out/lib/systemd/systemd-ssh-proxy" \
                  "$out/lib/systemd/systemd-volatile-root" \
                  "$out/lib/systemd/systemd-socket-proxyd" \
                  "$out/lib/systemd/systemd-reply-password" \
                  "$out/lib/systemd/systemd-network-generator" \
                  "$out/lib/systemd/systemd-ssh-issue" \
                  "$out/lib/systemd/systemd-update-done" \
                  "$out/lib/systemd/systemd-binfmt" \
                  "$out/lib/systemd/systemd-xdg-autostart-condition" \
                  "$out/lib/systemd/systemd-growfs" \
                  "$out/lib/systemd/systemd-makefs" \
                  "$out/lib/systemd/systemd-fsck" \
                  "$out/lib/systemd/systemd-remount-fs" \
                  "$out/lib/systemd/systemd-sleep" \
                  "$out/lib/systemd/systemd-storage-block" \
                  "$out/lib/systemd/systemd-storage-fs" \
                  "$out/lib/systemd/systemd-battery-check" \
                  "$out/lib/systemd/systemd-validatefs" \
                  "$out/lib/systemd/systemd-report" \
                  "$out/lib/systemd/systemd-report-basic" \
                  "$out/lib/systemd/systemd-report-cgroup" \
                  "$out/lib/systemd/systemd-sulogin-shell"
                rm -rf "$out/lib/systemd/user-generators" "$out/lib/systemd/user-environment-generators"

                rm -f \
                  "$out/lib/udev/cdrom_id" \
                  "$out/lib/udev/fido_id" \
                  "$out/lib/udev/v4l_id" \
                  "$out/lib/udev/mtd_probe" \
                  "$out/lib/udev/ata_id" \
                  "$out/lib/udev/iocost" \
                  "$out/lib/udev/dmi_memory_id"

                rm -f \
                  "$out/lib/systemd/system-generators/systemd-debug-generator" \
                  "$out/lib/systemd/system-generators/systemd-system-update-generator" \
                  "$out/lib/systemd/system-generators/systemd-run-generator" \
                  "$out/lib/systemd/system-generators/systemd-ssh-generator" \
                  "$out/lib/systemd/system-generators/systemd-factory-reset-generator" \
                  "$out/lib/systemd/system-generators/systemd-gpt-auto-generator"
              '';
            }
          )
      else
        prev.systemd;
  };

in
{
  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      systemdOverlay
    ];

    systemd.services.save-hwclock.enable = false;
    systemd.coredump.enable = false;
    systemd.oomd.enable = false;
    systemd.shutdownRamfs.enable = lib.mkForce false;

    systemd.services.systemd-user-sessions.enable = lib.mkForce false;
    systemd.services.network-local-commands.path = lib.mkForce [ ];

    systemd.generatorPath = lib.mkForce [ cfg.shell.utils ];
    systemd.managerEnvironment.PATH = lib.mkForce (
      lib.makeBinPath [
        pkgs.util-linux
        cfg.shell.utils
      ]
    );

    systemd.suppressedSystemUnits = [
      "systemd-modules-load.service"
      "kmod-static-nodes.service"
      "modprobe@.service"

      "systemd-backlight@.service"
      "systemd-rfkill.service"
      "systemd-rfkill.socket"
      "systemd-pstore.service"
      "hibernate.target"
      "suspend.target"
      "suspend-then-hibernate.target"
      "sleep.target"
      "hybrid-sleep.target"
      "systemd-hibernate.service"
      "systemd-hybrid-sleep.service"
      "systemd-suspend.service"
      "systemd-suspend-then-hibernate.service"

      "systemd-ask-password-console.path"
      "systemd-ask-password-console.service"
      "systemd-ask-password-wall.path"
      "systemd-ask-password-wall.service"
      "systemd-ask-password.socket"
      "systemd-ask-password@.service"

      "systemd-journal-catalog-update.service"

      "systemd-networkd-wait-online.service"
      "systemd-networkd-wait-online@.service"

      "systemd-networkd-persistent-storage.service"
    ];
  };
}
