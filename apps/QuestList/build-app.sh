#!/bin/bash
# build-app.sh — 把 SwiftPM 构建产物封装成标准 macOS .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="QuestList"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"

echo "==> 构建 release 二进制..."
swift build -c release --package-path "$SCRIPT_DIR"

BINARY="$SCRIPT_DIR/.build/release/$APP_NAME"

echo "==> 创建 .app bundle 目录结构..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "==> 复制可执行文件..."
cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "==> 写入 Info.plist..."
cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>QuestList</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.questlist</string>
    <key>CFBundleName</key>
    <string>任务清单</string>
    <key>CFBundleDisplayName</key>
    <string>任务清单</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
EOF

echo "==> 赋予执行权限..."
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "==> 完成！启动方式："
echo "    open \"$APP_DIR\""
echo ""
echo "==> 正在打开应用..."
open "$APP_DIR"
