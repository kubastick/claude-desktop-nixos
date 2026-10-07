# Claude Desktop (Linux beta), repackaged from Anthropic's official .deb.
#
# The .deb bundles its own Electron (newer than nixpkgs ships), so instead of
# re-running app.asar on nixpkgs' electron we keep the vendored binaries and
# patch their ELF interpreter/RPATH with autoPatchelfHook.
#
# Cowork (the QEMU/KVM VM tab) additionally needs firmware and virtiofsd at
# FHS paths the app hardcodes; that part lives in ./module.nix.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  addDriverRunpath,

  # linked
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libcap_ng,
  libdrm,
  libgbm,
  libseccomp,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,

  # dlopen'd at runtime
  libGL,
  libayatana-appindicator,
  libnotify,
  libpulseaudio,
  libsecret,
  libuuid,
  vulkan-loader,
  wayland,
  libxtst,

  # tools spawned by the app
  gjs,
  xdg-utils,
  qemu_kvm,
  virtiofsd,

  # Put qemu + virtiofsd on the app's PATH so the Cowork tab can start its VM.
  withCowork ? true,
}:

let
  sources = lib.importJSON ./sources.json;
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "claude-desktop: unsupported system ${stdenv.hostPlatform.system}");

  runtimeLibs = [
    libGL
    libayatana-appindicator
    libnotify
    libpulseaudio
    libsecret
    libuuid
    vulkan-loader
    wayland
    libxtst
  ];

  runtimeBins = [ xdg-utils ] ++ lib.optionals withCowork [ qemu_kvm virtiofsd ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-desktop";
  inherit (sources) version;

  src = fetchurl { inherit (source) url sha256; };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libcap_ng
    libdrm
    libgbm
    libseccomp
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    stdenv.cc.cc.lib
    systemd
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
  ];

  runtimeDependencies = runtimeLibs;

  # We build our own wrapper in postFixup and splice gappsWrapperArgs into it.
  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    app=$out/lib/claude-desktop
    mkdir -p $out/lib $out/bin
    cp -a usr/lib/claude-desktop $app
    cp -a usr/share $out/share
    rm -rf $out/share/lintian

    # SUID helper; NixOS uses unprivileged user namespaces instead.
    rm -f $app/chrome-sandbox

    # MIME types for .mcpb / .dxt / .skill (postinst copies these too).
    install -Dm644 $app/resources/linux-mime/com.anthropic.Claude.xml \
      $out/share/mime/packages/com.anthropic.Claude.xml

    # GNOME Shell search provider.
    sp=$app/resources/gnome-search-provider
    install -Dm644 $sp/com.anthropic.Claude.search-provider.ini \
      $out/share/gnome-shell/search-providers/com.anthropic.Claude.search-provider.ini
    install -Dm644 $sp/com.anthropic.Claude.SearchProvider.service \
      $out/share/dbus-1/services/com.anthropic.Claude.SearchProvider.service
    substituteInPlace $out/share/dbus-1/services/com.anthropic.Claude.SearchProvider.service \
      --replace-fail /usr/bin/gjs ${lib.getExe' gjs "gjs"} \
      --replace-fail /usr/lib/claude-desktop $app

    # `ccd` terminal launcher, shipped by some builds only.
    if [ -x $app/resources/bin/ccd ]; then
      ln -s $app/resources/bin/ccd $out/bin/ccd
    fi

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath runtimeBins} \
      --prefix LD_LIBRARY_PATH : ${addDriverRunpath.driverLink}/lib:${lib.makeLibraryPath runtimeLibs} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Claude desktop app: Chat, Cowork and Claude Code (Linux beta)";
    homepage = "https://code.claude.com/docs/en/desktop-linux";
    downloadPage = "https://downloads.claude.ai/claude-desktop/apt/stable";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "claude-desktop";
  };
})
