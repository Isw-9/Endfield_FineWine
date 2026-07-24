#!/usr/bin/env bash
# build-wine-macOS27.sh — build 64-bit x86_64 CrossOver Wine on Apple Silicon/macOS 27.
#
# The Apple Command Line Tools bundled with macOS 27 are arm64-hosted. Do not run
# clang itself under Rosetta: the x86_64 launcher cannot load the arm64-only
# libxcrun. Instead, run configure and make natively and ask clang to emit
# x86_64 Mach-O binaries. The resulting Wine runs under Rosetta 2 and defines
# __x86_64__, as required by the Endfield patches and winemac.drv.
#
# Usage:
#   scripts/build-wine-macOS27.sh deps
#   scripts/build-wine-macOS27.sh fetch
#   scripts/build-wine-macOS27.sh apply
#   scripts/build-wine-macOS27.sh configure
#   scripts/build-wine-macOS27.sh build
#   scripts/build-wine-macOS27.sh all
#
# Environment:
#   CX_VER     CrossOver source version (default: 26.2.0)
#   BUILD_DIR  Build workspace (default: <project>/build)
#   JOBS       Parallel build jobs (default: detected CPU count)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CX_VER="${CX_VER:-26.2.0}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"

SRC_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VER}.tar.gz"
WINE_SRC="$BUILD_DIR/wine-src"
WINE_BUILD="$BUILD_DIR/wine-build64"

if [ -x /opt/homebrew/bin/brew ]; then
  BREW="/opt/homebrew/bin/brew"
elif command -v brew >/dev/null 2>&1; then
  BREW="$(command -v brew)"
else
  BREW="/opt/homebrew/bin/brew"
fi

APPLE_CLANG="/usr/bin/clang"
APPLE_CLANGXX="/usr/bin/clang++"

log() {
  printf '\n\033[1m==> %s\033[0m\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

brew_prefix() {
  "$BREW" --prefix "$1"
}

check_host() {
  local kernel_major host_arch
  kernel_major="$(uname -r | cut -d. -f1)"
  host_arch="$(uname -m)"

  [ "$host_arch" = "arm64" ] ||
    die "this script expects Apple Silicon (arm64), found $host_arch"

  if [ "$kernel_major" != "27" ]; then
    printf 'warning: this script targets Darwin 27/macOS 27; found Darwin %s\n' "$kernel_major" >&2
  fi

  [ -x "$BREW" ] || die "Homebrew not found at $BREW; install Homebrew first"
  [ -x "$APPLE_CLANG" ] || die "clang not found; install Xcode Command Line Tools"
  arch -x86_64 /usr/bin/true >/dev/null 2>&1 ||
    die "Rosetta 2 is unavailable; install Rosetta before building x86_64 Wine"

  case "$("$APPLE_CLANG" -arch x86_64 --print-target-triple 2>/dev/null)" in
    x86_64-apple-darwin*) ;;
    *) die "the active clang cannot target x86_64 macOS" ;;
  esac
}

setup_build_env() {
  local bison_bin
  bison_bin="$(brew_prefix bison)/bin"
  [ -x "$bison_bin/bison" ] || die "Homebrew bison not found; run '$0 deps' first"

  export PATH="$bison_bin:$PATH"
  export MACOSX_DEPLOYMENT_TARGET=10.15
}

cmd_deps() {
  log "Installing build dependencies"
  [ -x "$BREW" ] || die "Homebrew not found at $BREW"
  "$BREW" install bison mingw-w64 pkg-config gnutls freetype sdl2 molten-vk meson
}

cmd_fetch() {
  local tgz

  check_host
  log "Fetching CrossOver ${CX_VER} source"
  mkdir -p "$BUILD_DIR"
  tgz="$BUILD_DIR/crossover-sources-${CX_VER}.tar.gz"

  if [ ! -f "$tgz" ]; then
    curl -fL "$SRC_URL" -o "$tgz"
  fi

  rm -rf "$WINE_SRC"
  mkdir -p "$WINE_SRC"
  tar xzf "$tgz" -C "$BUILD_DIR" sources/wine
  mv "$BUILD_DIR/sources/wine"/* "$WINE_SRC/"
  rmdir "$BUILD_DIR/sources/wine" "$BUILD_DIR/sources" 2>/dev/null || true

  log "Initializing the Wine source tree"
  (
    cd "$WINE_SRC"
    git init -q
    git add -A
    git -c user.email=build@local -c user.name=build \
      commit -qm "vanilla CrossOver ${CX_VER} wine"
  )

  printf 'Wine source ready at %s\n' "$WINE_SRC"
}

cmd_apply() {
  local patch_root

  [ -d "$WINE_SRC/.git" ] || die "run '$0 fetch' first"
  patch_root="$PROJECT_ROOT/patches"

  log "Applying Endfield patches"
  (
    cd "$WINE_SRC"
    local count=0 patch_file

    for patch_file in \
      $(ls "$patch_root"/stage2-dwproton/em-backports/*.patch | sort) \
      $(ls "$patch_root"/stage2-dwproton/misc/*.patch | sort) \
      "$patch_root"/stage1-macos/0000-*.patch \
      "$patch_root"/stage1-macos/0001-*.patch; do
      git apply "$patch_file"
      count=$((count + 1))
    done

    printf 'Applied %d patches.\n' "$count"
  )
}

patch_config_define() {
  local config_file macro value
  config_file="$1"
  macro="$2"
  value="$3"

  if grep -q "^#define $macro " "$config_file"; then
    return
  fi

  grep -q "^/\\* #undef $macro \\*/$" "$config_file" ||
    die "$macro was not found in $config_file"

  sed -i '' \
    "s|/\\* #undef $macro \\*/|#define $macro \"$value\"|" \
    "$config_file"
}

cmd_configure() {
  local config_file

  check_host
  setup_build_env
  [ -d "$WINE_SRC" ] || die "run '$0 fetch' first"

  log "Configuring x86_64 Wine with the native macOS 27 toolchain"
  rm -rf "$WINE_BUILD"
  mkdir -p "$WINE_BUILD"

  (
    cd "$WINE_BUILD"
    printf 'configure process: %s; compiler target: %s; bison: %s\n' \
      "$(uname -m)" \
      "$("$APPLE_CLANG" -arch x86_64 --print-target-triple)" \
      "$(bison --version | head -1)"

    CC="$APPLE_CLANG -arch x86_64" \
    CXX="$APPLE_CLANGXX -arch x86_64" \
    OBJC="$APPLE_CLANG -arch x86_64" \
      "$WINE_SRC/configure" \
      --build=x86_64-apple-darwin \
      --host=x86_64-apple-darwin \
      --enable-archs=x86_64 \
      --disable-tests \
      --without-x \
      --without-freetype \
      --without-gnutls \
      --without-sdl \
      --without-vulkan \
      --without-krb5 \
      --without-gstreamer \
      --without-gphoto \
      --without-sane \
      --without-pcap \
      --without-usb \
      --without-cups \
      --without-coreaudio
  ) 2>&1 | tee "$BUILD_DIR/configure-macOS27.log"

  config_file="$WINE_BUILD/include/config.h"
  [ -f "$config_file" ] || die "configure did not create $config_file"

  patch_config_define "$config_file" SONAME_LIBVULKAN "libvulkan.1.dylib"
  patch_config_define "$config_file" SONAME_LIBMOLTENVK "libMoltenVK.dylib"

  grep -q '^HOST_ARCH = x86_64$' "$WINE_BUILD/Makefile" ||
    die "configure did not produce an x86_64 host build"

  log "Configuration completed"
  printf 'Build directory: %s\n' "$WINE_BUILD"
  printf 'Log: %s\n' "$BUILD_DIR/configure-macOS27.log"
}

cmd_build() {
  check_host
  setup_build_env
  [ -f "$WINE_BUILD/Makefile" ] || die "run '$0 configure' first"

  log "Building x86_64 Wine with $JOBS parallel jobs"
  (
    cd "$WINE_BUILD"
    make -j"$JOBS"
  ) 2>&1 | tee "$BUILD_DIR/build-macOS27.log"

  [ -x "$WINE_BUILD/loader/wine" ] ||
    die "build completed without producing loader/wine"
  [ -x "$WINE_BUILD/server/wineserver" ] ||
    die "build completed without producing server/wineserver"

  case "$(file "$WINE_BUILD/loader/wine")" in
    *x86_64*) ;;
    *) die "loader/wine is not an x86_64 executable" ;;
  esac

  log "Build completed"
  file "$WINE_BUILD/loader/wine"
  file "$WINE_BUILD/server/wineserver"
  printf 'Build log: %s\n' "$BUILD_DIR/build-macOS27.log"
}

case "${1:-all}" in
  deps)
    cmd_deps
    ;;
  fetch)
    cmd_fetch
    ;;
  apply)
    cmd_apply
    ;;
  configure)
    cmd_configure
    ;;
  build)
    cmd_build
    ;;
  all)
    cmd_deps
    cmd_fetch
    cmd_apply
    cmd_configure
    cmd_build
    ;;
  *)
    die "usage: $0 {deps|fetch|apply|configure|build|all}"
    ;;
esac
