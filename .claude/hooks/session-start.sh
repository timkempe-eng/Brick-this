#!/bin/bash
# Give the agent container a Swift toolchain, so `swift test` runs where the
# contract says it does. The web sessions' image has none (measured 2026-09-03:
# `which swift` empty), which meant every push went out untested and waited
# six minutes for CI to say what a local run says in seconds.
#
# Same major as CI's `swift:6.0` container, so what passes here passes there.
# Idempotent: a container that already has swift is left alone, and the
# container state is cached after this completes, so the 748 MB download
# happens once per image rather than once per session.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SWIFT_VERSION="6.0.3"
SWIFT_HOME="/opt/swift"

if [ -x "$SWIFT_HOME/usr/bin/swift" ]; then
  echo "swift already installed at $SWIFT_HOME"
else
  . /etc/os-release
  case "$VERSION_ID" in
    24.04) platform=ubuntu2404; suffix=ubuntu24.04 ;;
    22.04) platform=ubuntu2204; suffix=ubuntu22.04 ;;
    *) echo "no Swift build for $PRETTY_NAME; swift test will not be available"; exit 0 ;;
  esac

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    binutils gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
    libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev \
    libz3-dev pkg-config tzdata unzip zlib1g-dev >/dev/null

  url="https://download.swift.org/swift-${SWIFT_VERSION}-release/${platform}/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-${suffix}.tar.gz"
  tmp="$(mktemp -d)"
  echo "downloading $url"
  curl -fsSL --retry 3 -o "$tmp/swift.tar.gz" "$url"
  mkdir -p "$SWIFT_HOME"
  tar -xzf "$tmp/swift.tar.gz" -C "$SWIFT_HOME" --strip-components=1
  rm -rf "$tmp"
fi

ln -sf "$SWIFT_HOME/usr/bin/swift" /usr/local/bin/swift
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$SWIFT_HOME/usr/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
export PATH="$SWIFT_HOME/usr/bin:$PATH"
swift --version

# Build the tests once now, so the first `swift test` of the session is the
# fast incremental one. This is cached with the container.
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
swift build --build-tests
