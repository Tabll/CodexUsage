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
ZIP_BASENAME="${ZIP_BASENAME:-CodexUsage}"

export DEVELOPER_DIR

if [[ "$CODE_SIGN_IDENTITY" == "-" && "${ALLOW_AD_HOC_APP_GROUP_BUILD:-}" != "1" ]]; then
  cat >&2 <<'EOF'
Codex用量 现在包含 WidgetKit 小组件，并使用 App Group:
  group.com.weitianshu.CodexPlus

可运行的 Release 包需要为主 App 和小组件配置包含 App Group 能力的签名身份和 provisioning/profile。
请传入 CODE_SIGN_IDENTITY 和 DEVELOPMENT_TEAM，或在只想验证编译时直接使用 xcodebuild test ... CODE_SIGNING_ALLOWED=NO。

如确实要尝试旧的 ad-hoc 打包流程，可显式设置 ALLOW_AD_HOC_APP_GROUP_BUILD=1。
EOF
  exit 1
fi

if [[ "$CODE_SIGN_IDENTITY" != "-" && -z "$OTHER_CODE_SIGN_FLAGS" ]]; then
  OTHER_CODE_SIGN_FLAGS="--timestamp"
fi

build_settings="$(
  xcodebuild -project "$PROJECT_PATH" \
    -target "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings
)"

version="$(printf '%s\n' "$build_settings" | awk '/MARKETING_VERSION/ { print $3; exit }')"
build_number="$(printf '%s\n' "$build_settings" | awk '/CURRENT_PROJECT_VERSION/ { print $3; exit }')"
full_product_name="$(printf '%s\n' "$build_settings" | awk '/FULL_PRODUCT_NAME/ { print $3; exit }')"

if [[ -z "$version" || -z "$build_number" || -z "$full_product_name" ]]; then
  echo "无法读取版本号或产物名，请检查 Xcode 构建设置。" >&2
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

app_path="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$full_product_name"
zip_path="$DIST_DIR/$ZIP_BASENAME-$version+$build_number.zip"

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
