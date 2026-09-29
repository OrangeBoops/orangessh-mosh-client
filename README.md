# mosh-client for Android

This is the complete corresponding source for the `mosh-client` program that
ships inside OrangeSSH (as `lib/<abi>/libmoshclient.so`). It builds the stock
Mosh client from **unmodified upstream source**:

| Component | Version | Licence |
|---|---|---|
| [Mosh](https://mosh.org) | 1.4.0 | GPL-3.0, with an OpenSSL linking exception |
| [Protocol Buffers](https://github.com/protocolbuffers/protobuf) | 21.12 | BSD-3-Clause |
| [OpenSSL](https://www.openssl.org) | 3.5.8 | Apache-2.0 |
| This folder's own files (`build.sh`, `android/`, `termshim/`) | | MIT, see `LICENSE` |

`mosh-client` is a separate program. OrangeSSH starts it on a pseudo-terminal
and shows its output; none of Mosh's code is linked into the app.

## What is here

- `build.sh`: downloads the three upstream tarballs, checks their SHA-256
  hashes, and cross-compiles `mosh-client` for arm64-v8a and x86_64.
- `android/config.h`: Mosh's `config.h` for Android, used in place of running
  `configure` (bionic, API 26 and up, OpenSSL's AES-OCB).
- `termshim/`: Android has no ncurses and no terminfo database. Mosh uses
  terminfo only to ask whether the terminal supports erase-characters and
  background colour erase, and for the alternate-screen strings. `termshim`
  answers those for `xterm-256color`, the terminal `mosh-client` always runs
  in here.

No Mosh source file is changed. The build compiles the same files Mosh's own
Makefiles put into `mosh-client`, generates `version.h` the way Mosh's
`src/include/Makefile` does, and links the result.

## Building

Needs an Android NDK (built with r29), CMake, curl and a C++ toolchain for
the build host (to build `protoc`).

```sh
ANDROID_NDK_HOME=/path/to/android-ndk ./build.sh out
```

The binaries land in `out/arm64-v8a/libmoshclient.so` and
`out/x86_64/libmoshclient.so`; downloads and intermediate builds go to `work/`.

The exact upstream tarballs are also attached to this repository's releases,
in case an upstream download ever disappears. `build.sh` checks their SHA-256
hashes either way.

## How OrangeSSH runs it

`mosh-client <ip> <port>` on a pty, with `MOSH_KEY` from the `MOSH CONNECT`
line that `mosh-server new` printed over SSH, `TERM=xterm-256color`,
`LANG=C.UTF-8`, `MOSH_NO_TERM_INIT=1` (draw on the main screen, so scrolled-off
lines reach the terminal's scrollback) and `MOSH_PREDICTION_DISPLAY` from the
app's settings.
