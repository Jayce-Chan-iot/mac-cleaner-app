#!/bin/bash
set -euo pipefail

# ============================================================
# MacCleanerApp — SPM → .app → .dmg 一键构建脚本
# ============================================================

APP_NAME="Mac 清理助手"
BUNDLE_NAME="MacCleanerApp"
BINARY_NAME="MacCleanerApp"
VERSION="0.1.1"
BUNDLE_ID="com.maccleaner.app"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_BIN="$BUILD_DIR/release/$BINARY_NAME"
DMG_DIR="$BUILD_DIR/dmg"
APP_BUNDLE="$DMG_DIR/$APP_NAME.app"
DMG_FILE="$PROJECT_DIR/$BUNDLE_NAME-v$VERSION.dmg"

echo "=========================================="
echo " MacCleanerApp DMG 构建脚本"
echo "=========================================="
echo ""

# ── Step 1: 编译 Release 二进制 ─────────────────────────────
echo "▶ Step 1/5: 编译 Release 二进制..."
cd "$PROJECT_DIR"

# Patch DynamicNotchKit @Entry / #Preview macros
# (These require SwiftUIMacros/PreviewsMacros plugin modules only available in Xcode toolchain)
DNOTCH_ENV_FILE="$BUILD_DIR/checkouts/DynamicNotchKit/Sources/DynamicNotchKit/Utility/EnvironmentValues+Extensions.swift"
DNOTCH_SHAPE_FILE="$BUILD_DIR/checkouts/DynamicNotchKit/Sources/DynamicNotchKit/Views/NotchShape.swift"
if [ -f "$DNOTCH_ENV_FILE" ]; then
    echo "  → 修复 DynamicNotchKit @Entry / #Preview 宏兼容性..."
    chmod u+w "$DNOTCH_ENV_FILE" 2>/dev/null || true
    # Replace @Entry macro with manual EnvironmentKey pattern
    cat > "$DNOTCH_ENV_FILE" << 'SWIFTEOF'
import SwiftUI

extension EnvironmentValues {
    var notchStyle: DynamicNotchStyle {
        get { self[NotchStyleKey.self] }
        set { self[NotchStyleKey.self] = newValue }
    }
    var notchSection: DynamicNotchSection {
        get { self[NotchSectionKey.self] }
        set { self[NotchSectionKey.self] = newValue }
    }
}

private struct NotchStyleKey: EnvironmentKey {
    static let defaultValue: DynamicNotchStyle = .auto
}

private struct NotchSectionKey: EnvironmentKey {
    static let defaultValue: DynamicNotchSection = .expanded
}

enum DynamicNotchSection {
    case expanded
    case compactLeading
    case compactTrailing
}
SWIFTEOF

    # Remove #Preview macro block from NotchShape.swift
    if [ -f "$DNOTCH_SHAPE_FILE" ]; then
        chmod u+w "$DNOTCH_SHAPE_FILE" 2>/dev/null || true
        sed -i '' '/^#Preview {/,/^}/d' "$DNOTCH_SHAPE_FILE" 2>/dev/null || true
    fi
    echo "  ✅ DynamicNotchKit 宏已修复"
fi

swift build -c release --arch arm64
swift build -c release --arch x86_64 2>/dev/null || echo "  (跳过 x86_64，M-series Mac 只构建 arm64)"

# 创建 Universal Binary（如果两个架构都存在）
ARM64_BIN="$BUILD_DIR/arm64-apple-macosx/release/$BINARY_NAME"
X86_BIN="$BUILD_DIR/x86_64-apple-macosx/release/$BINARY_NAME"
UNIVERSAL_BIN="$BUILD_DIR/release/$BINARY_NAME"

if [ -f "$ARM64_BIN" ] && [ -f "$X86_BIN" ]; then
    echo "  → 创建 Universal Binary (arm64 + x86_64)..."
    mkdir -p "$BUILD_DIR/release"
    lipo -create "$ARM64_BIN" "$X86_BIN" -output "$UNIVERSAL_BIN"
elif [ -f "$ARM64_BIN" ]; then
    mkdir -p "$BUILD_DIR/release"
    cp "$ARM64_BIN" "$UNIVERSAL_BIN"
fi

echo "  ✅ 编译完成"
echo ""

# ── Step 2: 创建 .app Bundle 结构 ──────────────────────────
echo "▶ Step 2/5: 创建 .app Bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制二进制
cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"

# 复制资源文件
cp "$PROJECT_DIR/Sources/MacCleanerApp/Resources/Whitelist.plist" "$APP_BUNDLE/Contents/Resources/"

echo "  ✅ Bundle 结构已创建"
echo ""

# ── Step 3: 生成 Info.plist ─────────────────────────────────
echo "▶ Step 3/5: 生成 Info.plist..."

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleExecutable</key>
	<string>$BINARY_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
PLIST

echo "  ✅ Info.plist 已生成"
echo ""

# ── Step 4: Ad-hoc 签名 ─────────────────────────────────────
echo "▶ Step 4/5: Ad-hoc 签名..."

# 移除旧签名
codesign --remove-signature "$APP_BUNDLE" 2>/dev/null || true

# Ad-hoc 签名（-s -）
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || {
    echo "  ⚠️  签名失败（无签名状态下 App 仍可运行，但需右键打开）"
}

echo "  ✅ 签名完成"
echo ""

# ── Step 5: 打包 DMG ───────────────────────────────────────
echo "▶ Step 5/5: 打包 DMG..."

# 删除旧 DMG
rm -f "$DMG_FILE"

# 创建 DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_FILE" 2>&1 | tail -1

echo "  ✅ DMG 已生成"
echo ""

# ── 摘要 ────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "$DMG_FILE" | cut -f1)
echo "=========================================="
echo " 🎉 构建完成！"
echo "=========================================="
echo ""
echo "  📦 DMG:  $DMG_FILE"
echo "  📏 大小: $DMG_SIZE"
echo "  🏗️  架构: $(lipo -info "$RELEASE_BIN" 2>/dev/null | sed 's/.*: //' || echo 'arm64')"
echo ""
echo "  分发步骤："
echo "  1. 拖到「应用程序」文件夹即可安装"
echo "  2. 首次运行若提示「无法验证开发者」→ 右键 App → 打开"
echo "  3. 正式分发需 Apple Developer 签名（\$99/年）"
echo ""
