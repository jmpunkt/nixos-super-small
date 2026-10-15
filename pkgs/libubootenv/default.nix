{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  zlib,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "libubootenv";
  version = "0.3.8";

  src = fetchFromGitHub {
    owner = "sbabic";
    repo = "libubootenv";
    rev = "tags/v${finalAttrs.version}";
    hash = "sha256-vPeLSec3zkz8+392PniMDxGni8CZXVw9h+xGRyzST3c=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ zlib ];

  cmakeFlags = [
    (lib.cmakeBool "NO_YML_SUPPORT" true)
    (lib.cmakeBool "BUILD_DOC" false)
  ];

  postInstall = ''
    find "$out" -name '*.a' -delete
  '';

  meta = {
    description = "U-Boot environment read/write library and tools";
    homepage = "https://github.com/sbabic/libubootenv";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.linux;
  };
})
