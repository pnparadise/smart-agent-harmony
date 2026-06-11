#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/native/wg_boringtun"
OUT_DIR="$ROOT_DIR/entry/libs/arm64-v8a"

export PATH="$HOME/.cargo/bin:/root/.cargo/bin:$PATH"

is_valid_ohos_ndk() {
  local sdk_root="$1"
  [[ -f "$sdk_root/native/build/cmake/ohos.toolchain.cmake" ]] &&
    [[ -x "$sdk_root/native/llvm/bin/clang" ]]
}

find_ohos_ndk() {
  for SDK_ROOT in \
    "/sdk/ohos-sdk/6.1-Release/openharmony" \
    "/tmp/ohos-sdk/6.1-Release/openharmony" \
    "/mnt/e/Program Files/Huawei/DevEco Studio/sdk/default/openharmony" \
    "/mnt/c/Program Files/Huawei/DevEco Studio/sdk/default/openharmony"; do
    if is_valid_ohos_ndk "$SDK_ROOT"; then
      echo "$SDK_ROOT"
      return 0
    fi
  done
  return 1
}

if [[ -z "${OHOS_NDK_HOME:-}" ]] || ! is_valid_ohos_ndk "$OHOS_NDK_HOME"; then
  if DETECTED_OHOS_NDK_HOME="$(find_ohos_ndk)"; then
    export OHOS_NDK_HOME="$DETECTED_OHOS_NDK_HOME"
  fi
fi

if [[ -z "${OHOS_NDK_HOME:-}" ]]; then
  echo "OHOS_NDK_HOME is required. Expected a Linux OpenHarmony SDK root with native/llvm/bin/clang." >&2
  exit 1
fi

if [[ "$OHOS_NDK_HOME" == *" "* ]]; then
  SDK_LINK="/tmp/wg-agent-openharmony-sdk"
  rm -f "$SDK_LINK"
  ln -s "$OHOS_NDK_HOME" "$SDK_LINK"
  export OHOS_NDK_HOME="$SDK_LINK"
fi

if ! is_valid_ohos_ndk "$OHOS_NDK_HOME"; then
  echo "Invalid OHOS_NDK_HOME: $OHOS_NDK_HOME" >&2
  echo "Expected native/build/cmake/ohos.toolchain.cmake and executable native/llvm/bin/clang." >&2
  exit 1
fi

if ! command -v ohrs >/dev/null 2>&1; then
  echo "ohrs is required. Install and configure ohos-rs first: https://ohos.rs/en/docs/basic/quick-start.html" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
(
  cd "$NATIVE_DIR"
  ohrs build --release --arch aarch
)

SO_PATH="$(find "$NATIVE_DIR" -path '*/dist/*' -name 'libwg_boringtun.so' -print -quit)"
if [[ -z "$SO_PATH" ]]; then
  SO_PATH="$(find "$NATIVE_DIR" -path '*/target/*' -name 'libwg_boringtun.so' -print -quit)"
fi

if [[ -z "$SO_PATH" ]]; then
  echo "libwg_boringtun.so was not found after ohrs build." >&2
  exit 1
fi

cp "$SO_PATH" "$OUT_DIR/libwg_boringtun.so"
echo "Copied $SO_PATH to $OUT_DIR/libwg_boringtun.so"
