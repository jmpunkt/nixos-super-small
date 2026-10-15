{
  pkgs,
  lib,
  storePaths,
  populateImageCommands,
  volumeLabel,
  compressImage ? false,
  pruneCruft ? true,
  compression ? "lzo",
  blockSize ? 131072, # 128KB
  ...
}:
let
  sdClosureInfo = pkgs.buildPackages.closureInfo { rootPaths = storePaths; };
  targetStrip = "${pkgs.stdenv.cc.bintools}/bin/${pkgs.stdenv.cc.targetPrefix}strip";

  stripElf = pkgs.buildPackages.writeTextFile {
    name = "strip-elf";
    text = builtins.readFile ./strip-elf.sh;
    executable = true;
  };
in
pkgs.stdenv.mkDerivation {
  name = "squashfs-fs.img${lib.optionalString compressImage ".zst"}";

  nativeBuildInputs = [
    pkgs.buildPackages.squashfsTools
    pkgs.buildPackages.zstd
  ];

  buildCommand = ''
    (
      mkdir -p ./files
      ${populateImageCommands}
    )

    echo "Preparing store paths for squashfs..."
    mkdir -p ./rootImage/nix/store
    xargs -I % cp -a --reflink=auto % -t ./rootImage/nix/store/ < ${sdClosureInfo}/store-paths
    (
      GLOBIGNORE=".:.."
      shopt -u dotglob
      for f in ./files/*; do
        cp -a --reflink=auto -t ./rootImage/ "$f"
      done
    )
    cp ${sdClosureInfo}/registration ./rootImage/nix-path-registration
  ''
  + ''
    echo "Trimming unused toolchain runtime files..."
    chmod -R u+w ./rootImage/nix/store 2>/dev/null || true

    find ./rootImage/nix/store -type d -path '*/lib/gcc' -prune -exec rm -rf {} + 2>/dev/null || true
    rm -rf ./rootImage/nix/store/*/share/gcc-* 2>/dev/null || true

  ''
  + ''
    echo "Trimming glibc's bin output..."
    for d in ./rootImage/nix/store/*-glibc-*-bin/bin; do
      [ -d "$d" ] || continue
      find "$d" -mindepth 1 -maxdepth 1 -type f \
        ! -name locale ! -name iconv ! -name getconf -delete
    done
  ''
  + ''
    echo "Trimming glibc's built-in locale-archive..."
    for d in ./rootImage/nix/store/*-glibc-*/lib/locale; do
      case "$d" in
        *-glibc-locales-*) ;;
        *) [ -d "$d" ] && rm -rf "$d" ;;
      esac
    done
  ''
  + (lib.optionalString pruneCruft ''
    echo "Pruning build-only files from every store path..."
    # Remove Headers, pkg-config data, man pages, docs and info pages (same as Buildroot)
    for dir in include pkgconfig aclocal man doc info gtk-doc bash-completion zsh; do
      find ./rootImage/nix/store -mindepth 3 -type d -name "$dir" -prune -exec rm -rf {} + 2>/dev/null || true
    done

    # Remove static objects and build metadata
    for suffix in a la o pc cmake prl pyc pyo; do
      find ./rootImage/nix/store -type f -name "*.$suffix" -delete 2>/dev/null || true
    done
  '')
  + ''
    echo "Stripping target ELF files..."
    find ./rootImage -type f -exec "${stripElf}" "${targetStrip}" {} +
  ''
  + ''
    mksquashfs ./rootImage ./squashfs.img \
      -comp ${compression} -b ${toString blockSize} \
      -noappend -all-root -no-xattrs -no-duplicates \
      -no-progress

    ${
      if compressImage then
        ''
          zstd -q -T0 -o "$out" ./squashfs.img
        ''
      else
        ''
          mv ./squashfs.img "$out"
        ''
    }

    echo "Final squashfs size: $(stat -c %s "$out") bytes"
  '';
}
