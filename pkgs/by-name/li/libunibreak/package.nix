{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
}:

stdenv.mkDerivation rec {
  pname = "libunibreak";
  version = "6.1";

  src =
    let
      rev_version = lib.replaceStrings [ "." ] [ "_" ] version;
    in
    fetchFromGitHub {
      owner = "adah1972";
      repo = "libunibreak";
      rev = "libunibreak_${rev_version}";
      sha256 = "sha256-8yheb+XSvc1AqITjSutF+/4OWb4+7hweedKzhKJcE1Y=";
    };

  nativeBuildInputs = [ autoreconfHook ];

  meta = with lib; {
    homepage = "https://github.com/adah1972/libunibreak";
    description = "Implementation of line breaking and word breaking algorithms as in the Unicode standard";
    license = licenses.zlib;
    platforms = platforms.unix;
    maintainers = [ maintainers.coroa ];
  };
}
