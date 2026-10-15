{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.ssh;

  keysText = pkgs.writeText "dropbear-keys" (
    lib.concatStringsSep "\n" (cfg.authorizedKeys ++ [ "" ])
  );
  authorizedKeysFile = pkgs.runCommand "authorized-keys" { } ''
    cat ${keysText} ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.authorizedKeysFiles} > $out
  '';

  dropbearArgs =
    (lib.filter (arg: !(cfg.allowEmptyPassword && builtins.elem arg [ "-s" "-g" ])) cfg.args)
    ++ lib.optional (cfg.allowEmptyPassword && !(builtins.elem "-B" cfg.args)) "-B";
in
{
  options = {
    my.ssh.enable = lib.mkEnableOption "Dropbear SSH";

    my.ssh.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dropbear.override { enableSCP = true; };
      defaultText = lib.literalExpression "pkgs.dropbear.override { enableSCP = true; }";
      description = "The Dropbear package to use.";
    };

    my.ssh.authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Public keys accepted for root. Written to the squashfs as
        /root/.ssh/authorized_keys (a symlink into the store); there is no
        activation script to install them at boot, and a read-only root has
        no ~/.ssh to create anyway.
      '';
    };

    my.ssh.authorizedKeysFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Files of public keys, appended to my.ssh.authorizedKeys.";
    };

    my.ssh.args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "-F" # stay in the foreground (it is the service)
        "-E" # log to stderr, i.e. the journal
        "-s" # disable password logins
      ];
      description = "Arguments for dropbear(8).";
    };

    my.ssh.allowEmptyPassword = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow root to log in with an empty password. This sets root's password
        hash to the empty string and removes dropbear's "-s"/"-g" arguments
        while adding "-B". Only use this on a trusted network or bench setup;
        it permits unauthenticated root access.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optionals (
      !cfg.allowEmptyPassword && cfg.authorizedKeys == [ ] && cfg.authorizedKeysFiles == [ ]
    ) [
      ''
        my.ssh is enabled and my.ssh.args contains "-s" (refuse empty
        passwords), but my.ssh.authorizedKeys is empty: ssh logins will be
        refused.  Set my.ssh.authorizedKeys (or my.ssh.authorizedKeysFiles),
        set my.ssh.allowEmptyPassword for a bench setup, or set a root password
        and drop "-s".
      ''
    ];

    users.users.root.hashedPassword = lib.mkIf cfg.allowEmptyPassword "";

    systemd.services.dropbear = {
      description = "Dropbear SSH daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        StateDirectory = "dropbear";
        ExecStartPre = pkgs.writeTextFile {
          name = "dropbear-keygen";
          executable = true;
          text = ''
            #!${config.my.shell.path}
            set -eu
            key=/var/lib/dropbear/dropbear_ed25519_host_key
            if [ ! -s "$key" ]; then
              ${cfg.package}/bin/dropbearkey -t ed25519 -f "$key"
            fi
          '';
        };
        ExecStart = "${cfg.package}/bin/dropbear ${lib.escapeShellArgs dropbearArgs} -r /var/lib/dropbear/dropbear_ed25519_host_key";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    # The read-only root has no /root, so the keys are baked into the squashfs
    # instead of being installed by an activation script, which would never
    # actually run on a read-only image.
    my.rootfs.extraFiles = lib.mkIf (cfg.authorizedKeys != [ ] || cfg.authorizedKeysFiles != [ ]) {
      "root/.ssh/authorized_keys" = authorizedKeysFile;
    };
  };
}
