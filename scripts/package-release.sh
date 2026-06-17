#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CodexPlus.xcodeproj"
SCHEME_NAME="CodexPlus"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/ReleaseDerivedData}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Manual}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
OTHER_CODE_SIGN_FLAGS="${OTHER_CODE_SIGN_FLAGS:-}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

export DEVELOPER_DIR

if [[ "$CODE_SIGN_IDENTITY" != "-" && -z "$OTHER_CODE_SIGN_FLAGS" ]]; then
  OTHER_CODE_SIGN_FLAGS="--timestamp"
fi

version="$(
  xcodebuild -project "$PROJECT_PATH" \
    -target "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings |
    awk '/MARKETING_VERSION/ { print $3; exit }'
)"

build_number="$(
  xcodebuild -project "$PROJECT_PATH" \
    -target "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings |
    awk '/CURRENT_PROJECT_VERSION/ { print $3; exit }'
)"

if [[ -z "$version" || -z "$build_number" ]]; then
  echo "无法读取版本号，请检查 Xcode 构建设置。" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

build_args=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME_NAME"
  -configuration "$CONFIGURATION"
  -destination "platform=macOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGN_STYLE="$CODE_SIGN_STYLE"
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  ENABLE_HARDENED_RUNTIME=YES
)

if [[ -n "$OTHER_CODE_SIGN_FLAGS" ]]; then
  build_args+=(OTHER_CODE_SIGN_FLAGS="$OTHER_CODE_SIGN_FLAGS")
fi

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  build_args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

echo "Building $SCHEME_NAME $version ($build_number)..."
xcodebuild clean build "${build_args[@]}"

app_path="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/CodexPlus.app"
zip_path="$DIST_DIR/CodexPlus-$version+$build_number.zip"

if [[ ! -d "$app_path" ]]; then
  echo "未找到构建产物：$app_path" >&2
  exit 1
fi

if [[ ! -f "$app_path/Contents/Resources/AppIcon.icns" ]]; then
  echo "构建产物缺少 AppIcon.icns。" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

rm -f "$zip_path"
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$app_path" "$zip_path"

echo "Release build ready:"
echo "  App: $app_path"
echo "  Zip: $zip_path"
echo "  Version: $version ($build_number)"
echo "  Signing identity: $CODE_SIGN_IDENTITY"
echo "  Code sign flags: ${OTHER_CODE_SIGN_FLAGS:-<none>}"
