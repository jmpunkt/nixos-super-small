{
  lib,
  stdenv,
  buildPackages,
  python3,
  fetchFromGitHub,
  libconfig,
  openssl,
  zlib,
  json_c,
  libubootenv,
  writeShellScript,
}:
let
  hostcc = writeShellScript "swupdate-hostcc" ''
    exec env -u NIX_CFLAGS_COMPILE ${buildPackages.stdenv.cc}/bin/cc "$@"
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "swupdate";
  version = "2026.05.1";

  src = fetchFromGitHub {
    owner = "sbabic";
    repo = "swupdate";
    rev = "tags/${finalAttrs.version}";
    hash = "sha256-AeT6eJCtVwX++ZxNW9I7s8wZvwrYAV1ZL6mO4fDIYm4=";
  };

  nativeBuildInputs = [
    python3
    buildPackages.stdenv.cc
  ];

  makeFlags = [ "HOSTCC=${hostcc}" ];

  buildInputs = [
    libconfig
    openssl
    zlib
    json_c
    libubootenv
  ];

  extraConfig = ''
    CONFIG_HW_COMPATIBILITY=y
    CONFIG_LIBCONFIG=y
    CONFIG_SSL_IMPL_OPENSSL=y
    CONFIG_HASH_VERIFY=y
    CONFIG_WEBSERVER=y
    CONFIG_MONGOOSE=y
    CONFIG_RAW=y
    CONFIG_SHELLSCRIPTHANDLER=y
  '';

  HAVE_LUA = "n";
  HAVE_LIBARCHIVE = "n";
  HAVE_LIBCURL = "n";
  HAVE_LIBFDISK = "n";
  HAVE_LIBBLKID = "n";
  HAVE_LIBGPIOD = "n";
  HAVE_LIBMTD = "n";
  HAVE_LIBUBI = "n";
  HAVE_LIBUBOOTENV = "n";
  HAVE_LIBEBGENV = "n";
  HAVE_LIBTEGRABOOT_TOOLS = "n";
  HAVE_LIBZEROMQ = "n";
  HAVE_ZLIB = "y";
  HAVE_XZ = "n";
  HAVE_ZSTD = "n";
  HAVE_LZ4 = "n";
  HAVE_LIBEXT2FS = "n";
  HAVE_LIBBTRFS = "n";
  HAVE_LIBSSL = "y";
  HAVE_LIBSYSTEMD = "n";
  HAVE_LIBCRYPTO = "y";
  HAVE_WOLFSSL = "n";
  HAVE_MBEDTLS = "n";
  HAVE_GPGME = "n";
  HAVE_P11KIT = "n";
  HAVE_LIBWEBSOCKETS = "n";
  HAVE_LIBRSYNC = "n";
  HAVE_URIPARSER = "n";
  HAVE_ZCK = "n";

  configurePhase = ''
    runHook preConfigure
    patchShebangs scripts
    echo "$extraConfig" > .config
    make $makeFlags olddefconfig
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make $makeFlags swupdate
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 swupdate $out/bin/swupdate
    runHook postInstall
  '';

  meta = {
    description = "Software Update for Embedded Systems";
    homepage = "https://sbabic.github.io/swupdate/";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
})
