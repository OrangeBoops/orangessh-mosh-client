#!/usr/bin/env bash
#
# Builds mosh-client for Android as a standalone executable, from unmodified
# upstream sources: mosh 1.4.0, protobuf 21.12 and OpenSSL 3.2.1. This folder
# (this script, android/config.h and termshim/) plus those three upstream
# tarballs is the complete corresponding source of the mosh-client binary
# that OrangeSSH ships.
#
# Usage:
#   ANDROID_NDK_HOME=/path/to/ndk ./build.sh [out-dir]
#
# Writes <out-dir>/<abi>/libmoshclient.so for each ABI (default out-dir: ./out).
# The name is only so Android packages it with an app's native libraries,
# where it may be executed; it is a program, not a library.
#
set -euo pipefail

MOSH_VERSION="1.4.0"
MOSH_SHA256="872e4b134e5df29c8933dff12350785054d2fd2839b5ae6b5587b14db1465ddd"
PROTOBUF_VERSION="21.12"
PROTOBUF_SHA256="2c6a36c7b5a55accae063667ef3c55f2642e67476d96d355ff0acb13dbb47f09"
OPENSSL_VERSION="3.2.1"
OPENSSL_SHA256="83c7329fe52c850677d75e5d0b0ca245309b97e8ecbcfdc1dfdc4ab9fac35b39"
ANDROID_API=26
ABIS=("arm64-v8a" "x86_64")

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(realpath -m "${1:-$HERE/out}")"
# Downloads and intermediate builds; set MOSH_CLIENT_WORK to keep them elsewhere.
WORK="${MOSH_CLIENT_WORK:-$HERE/work}"
mkdir -p "$WORK/src"
WORK="$(realpath "$WORK")"

if [ -z "${ANDROID_NDK_HOME:-}" ] || [ ! -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" ]; then
    echo "ERROR: set ANDROID_NDK_HOME to an Android NDK." >&2
    exit 1
fi
case "$(uname -s)" in
    Linux*)  HOST_TAG="linux-x86_64" ;;
    Darwin*) HOST_TAG="darwin-x86_64" ;;
    *)       echo "ERROR: unsupported build host" >&2; exit 1 ;;
esac
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

# ---------------------------------------------------------------------------
# Sources, checked against known hashes
# ---------------------------------------------------------------------------
fetch() {
    local url="$1" file="$2" sha="$3"
    if [ ! -f "$WORK/src/$file" ]; then
        echo "==> Downloading $file"
        curl -fSL "$url" -o "$WORK/src/$file.part"
        mv "$WORK/src/$file.part" "$WORK/src/$file"
    fi
    echo "$sha  $WORK/src/$file" | sha256sum -c --quiet -
}
fetch "https://github.com/mobile-shell/mosh/releases/download/mosh-$MOSH_VERSION/mosh-$MOSH_VERSION.tar.gz" \
    "mosh-$MOSH_VERSION.tar.gz" "$MOSH_SHA256"
fetch "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOBUF_VERSION/protobuf-all-$PROTOBUF_VERSION.tar.gz" \
    "protobuf-$PROTOBUF_VERSION.tar.gz" "$PROTOBUF_SHA256"
fetch "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" \
    "openssl-$OPENSSL_VERSION.tar.gz" "$OPENSSL_SHA256"

# ---------------------------------------------------------------------------
# Host protoc, to generate mosh's protocol code
# ---------------------------------------------------------------------------
HOST_PREFIX="$WORK/host"
if [ ! -x "$HOST_PREFIX/bin/protoc" ]; then
    echo "==> Building host protoc"
    rm -rf "$WORK/build/protobuf-host"
    mkdir -p "$WORK/build/protobuf-host"
    tar xzf "$WORK/src/protobuf-$PROTOBUF_VERSION.tar.gz" -C "$WORK/build/protobuf-host" --strip-components=1
    cmake -S "$WORK/build/protobuf-host/cmake" -B "$WORK/build/protobuf-host/build" \
        -DCMAKE_INSTALL_PREFIX="$HOST_PREFIX" -DCMAKE_BUILD_TYPE=Release \
        -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_SHARED_LIBS=OFF -Dprotobuf_WITH_ZLIB=OFF > /dev/null
    cmake --build "$WORK/build/protobuf-host/build" -j"$JOBS" > /dev/null
    cmake --install "$WORK/build/protobuf-host/build" > /dev/null
fi
PROTOC="$HOST_PREFIX/bin/protoc"

for ABI in "${ABIS[@]}"; do
    echo "==> $ABI"
    case "$ABI" in
        arm64-v8a) TRIPLE="aarch64-linux-android"; OPENSSL_TARGET="android-arm64" ;;
        x86_64)    TRIPLE="x86_64-linux-android";  OPENSSL_TARGET="android-x86_64" ;;
    esac
    CC="$TOOLCHAIN/bin/${TRIPLE}${ANDROID_API}-clang"
    CXX="$TOOLCHAIN/bin/${TRIPLE}${ANDROID_API}-clang++"
    PREFIX="$WORK/install/$ABI"
    mkdir -p "$PREFIX"

    # -- OpenSSL (libcrypto: AES-OCB for mosh's encryption) -----------------
    if [ ! -f "$PREFIX/lib/libcrypto.a" ]; then
        echo "  --> OpenSSL"
        rm -rf "$WORK/build/openssl-$ABI"
        mkdir -p "$WORK/build/openssl-$ABI"
        tar xzf "$WORK/src/openssl-$OPENSSL_VERSION.tar.gz" -C "$WORK/build/openssl-$ABI" --strip-components=1
        (
            cd "$WORK/build/openssl-$ABI"
            export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME" PATH="$TOOLCHAIN/bin:$PATH"
            ./Configure "$OPENSSL_TARGET" -D__ANDROID_API__=$ANDROID_API --prefix="$PREFIX" \
                --libdir=lib --openssldir="$PREFIX/ssl" no-shared no-tests no-ui-console \
                no-engine no-comp no-dso no-legacy -fPIC > /dev/null
            make -j"$JOBS" > /dev/null
            make install_sw > /dev/null
        )
    fi

    # -- protobuf (lite runtime) ------------------------------------------
    if [ ! -f "$PREFIX/lib/libprotobuf-lite.a" ]; then
        echo "  --> protobuf"
        rm -rf "$WORK/build/protobuf-$ABI"
        mkdir -p "$WORK/build/protobuf-$ABI"
        tar xzf "$WORK/src/protobuf-$PROTOBUF_VERSION.tar.gz" -C "$WORK/build/protobuf-$ABI" --strip-components=1
        cmake -S "$WORK/build/protobuf-$ABI/cmake" -B "$WORK/build/protobuf-$ABI/build" \
            -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
            -DANDROID_ABI="$ABI" -DANDROID_NATIVE_API_LEVEL=$ANDROID_API \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release \
            -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_SHARED_LIBS=OFF \
            -Dprotobuf_BUILD_PROTOC_BINARIES=OFF -Dprotobuf_WITH_ZLIB=OFF > /dev/null
        cmake --build "$WORK/build/protobuf-$ABI/build" -j"$JOBS" > /dev/null
        cmake --install "$WORK/build/protobuf-$ABI/build" > /dev/null
    fi

    # -- mosh-client -------------------------------------------------------
    echo "  --> mosh-client"
    SRC="$WORK/build/mosh-$ABI"
    rm -rf "$SRC"
    mkdir -p "$SRC"
    tar xzf "$WORK/src/mosh-$MOSH_VERSION.tar.gz" -C "$SRC" --strip-components=1
    cp "$HERE/android/config.h" "$SRC/config.h"
    # What mosh's src/include/Makefile generates. The release tarball has no
    # VERSION file (that comes from git), so name the release instead.
    printf '#define BUILD_VERSION "%s"\n' "mosh-$MOSH_VERSION" > "$SRC/src/include/version.h"
    for proto in "$SRC"/src/protobufs/*.proto; do
        "$PROTOC" --cpp_out="$SRC/src/protobufs" -I "$SRC/src/protobufs" "$proto"
    done

    # What mosh's Makefiles build into mosh-client with OpenSSL's AES-OCB.
    SOURCES=(
        src/frontend/mosh-client.cc src/frontend/stmclient.cc src/frontend/terminaloverlay.cc
        src/statesync/completeterminal.cc src/statesync/user.cc
        src/network/compressor.cc src/network/network.cc src/network/transportfragment.cc
        src/crypto/base64.cc src/crypto/crypto.cc src/crypto/ocb_openssl.cc
        src/util/locale_utils.cc src/util/select.cc src/util/swrite.cc src/util/timestamp.cc
        src/terminal/parseraction.cc src/terminal/parser.cc src/terminal/parserstate.cc
        src/terminal/terminal.cc src/terminal/terminaldispatcher.cc src/terminal/terminaldisplay.cc
        src/terminal/terminaldisplayinit.cc src/terminal/terminalframebuffer.cc
        src/terminal/terminalfunctions.cc src/terminal/terminaluserinput.cc
        src/protobufs/hostinput.pb.cc src/protobufs/transportinstruction.pb.cc src/protobufs/userinput.pb.cc
    )
    OBJS=()
    for src in "${SOURCES[@]}"; do
        obj="$SRC/${src%.cc}.o"
        "$CXX" -std=c++17 -O2 -fPIE -DHAVE_CONFIG_H \
            -I"$SRC" -I"$SRC/src/include" -I"$SRC/src/statesync" -I"$SRC/src/terminal" \
            -I"$SRC/src/network" -I"$SRC/src/crypto" -I"$SRC/src/util" -I"$SRC/src/protobufs" \
            -I"$SRC/src/frontend" -I"$HERE/termshim" -I"$PREFIX/include" \
            -c "$SRC/$src" -o "$obj"
        OBJS+=("$obj")
    done
    "$CC" -O2 -fPIE -I"$HERE/termshim" -c "$HERE/termshim/termshim.c" -o "$SRC/termshim.o"
    OBJS+=("$SRC/termshim.o")

    mkdir -p "$OUT_DIR/$ABI"
    "$CXX" -pie -static-libstdc++ -Wl,--gc-sections -s -o "$OUT_DIR/$ABI/libmoshclient.so" "${OBJS[@]}" \
        -L"$PREFIX/lib" -lprotobuf-lite -lcrypto -lz -llog
    echo "  --> $OUT_DIR/$ABI/libmoshclient.so"
done
