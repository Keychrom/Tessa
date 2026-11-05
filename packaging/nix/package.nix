{
  lib,
  stdenv,
  fetchgit,
  zig,
  pkg-config,
  autoPatchelfHook,
  wlroots_0_20,
  scenefx,
  wayland,
  wayland-protocols,
  libinput,
  libxkbcommon,
  pixman,
  cairo,
  pango,
  glib,
  libglvnd,
  mesa,
  libdrm,
  xcursor-themes,
  withScenefx ? true,
}:

let
  # Zig 0.17 materializes build.zig.zon dependencies into a local `zig-pkg`
  # directory. Populating it from the pinned sources keeps the Nix build
  # offline; the directory names come from the hashes in build.zig.zon.
  translateC = fetchgit {
    url = "https://codeberg.org/ziglang/translate-c";
    rev = "cfac21f3199b2b02ce3fd7db652aa456421fe4ab";
    hash = "sha256-s3kHcl0SEgpTrPsjpzUsQS/6YDCfLCflj/HkIU59Kk0=";
  };
  arocc = fetchgit {
    url = "https://codeberg.org/ziglang/arocc";
    rev = "630d99ed60fe61ccabe721f1af60881f8b2adde3";
    hash = "sha256-lG+T8svTkI3pHJrgTNccZS5sU2pMOMTs2gZ8qbTH5dQ=";
  };
  translateCDir = "translate_c-2.0.2-Q_BUWvBNBwDnyehSiuAJmdFcMYHYGA-Jc3KiYdrV2Dqx";
  aroccDir = "aro-0.0.0-JSD1QvCRNwC2O1Jkop9TO6sXb1U1vhrH8FnYK1VdEMKn";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "tessa";
  version = "0.2.5";

  # Flake evaluation copies only git-tracked files, so local build artifacts
  # (zig-out, zig-pkg, .zig-cache) do not leak into the source.
  src = ../..;

  nativeBuildInputs = [
    zig
    pkg-config
    autoPatchelfHook
  ];

  buildInputs = [
    wlroots_0_20
    wayland
    wayland-protocols
    libinput
    libxkbcommon
    pixman
    cairo
    pango
    glib
    libglvnd
    mesa
    libdrm
    libdrm.dev
    xcursor-themes
    stdenv.cc.cc.lib
  ] ++ lib.optional withScenefx scenefx;

  preBuild = ''
    mkdir -p zig-pkg
    cp -r ${translateC} zig-pkg/${translateCDir}
    cp -r ${arocc} zig-pkg/${aroccDir}
    chmod -R u+w zig-pkg
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
  '';

  buildPhase = ''
    runHook preBuild
    zig build \
      -Doptimize=ReleaseSafe \
      -Dscenefx=${if withScenefx then "true" else "false"} \
      -Dcpu=baseline \
      -j"$NIX_BUILD_CORES" \
      --prefix "$out"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 scripts/tessa-session "$out/bin/tessa-session"
    install -Dm644 session/tessa.desktop \
      "$out/share/wayland-sessions/tessa.desktop"
    install -Dm644 config/config.example "$out/share/tessa/config.example"
    install -Dm644 packaging/portal/tessa.portal \
      "$out/share/xdg-desktop-portal/portals/tessa.portal"

    install -Dm644 debian/man/tessa.1 "$out/share/man/man1/tessa.1"
    install -Dm644 debian/man/tessa-panel.1 "$out/share/man/man1/tessa-panel.1"
    install -Dm644 debian/man/tessa-ctl.1 "$out/share/man/man1/tessa-ctl.1"
    install -Dm644 debian/man/tessa-session.1 "$out/share/man/man1/tessa-session.1"

    install -Dm644 README.md "$out/share/doc/tessa/README.md"
    install -Dm644 README.ja.md "$out/share/doc/tessa/README.ja.md"
    install -Dm644 LICENSE "$out/share/doc/tessa/LICENSE"
    for doc in docs/*.md; do
      install -Dm644 "$doc" "$out/share/doc/tessa/$(basename "$doc")"
    done

    runHook postInstall
  '';

  # The compositor and panel are normal dynamically linked executables.
  # autoPatchelfHook adds the store paths of the libraries above.

  meta = {
    description = "A quiet tiled Wayland compositor and desktop shell";
    homepage = "https://github.com/Keychrom/Tessa";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = lib.platforms.linux;
    mainProgram = "tessa";
  };

  passthru.providedSessions = [ "tessa" ];
})
