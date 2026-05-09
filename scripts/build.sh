#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_dir="$HOME/Applications/Shell Island Dev.app"
plist_path="$bundle_dir/Contents/Info.plist"
bundle_binary="$bundle_dir/Contents/MacOS/ShellIslandApp"

cd "$repo_root"

echo "• Building ShellIslandApp…"
swift build -c debug --product ShellIslandApp
echo "• Building ShellIslandHooks…"
swift build -c debug --product ShellIslandHooks

build_root="$(swift build -c debug --show-bin-path)"
app_binary="$build_root/ShellIslandApp"
hooks_binary="$build_root/ShellIslandHooks"

# 停止旧实例
osascript -e 'tell application "Shell Island Dev" to quit' 2>/dev/null || true
pkill -9 -f "Shell Island Dev" 2>/dev/null || true
sleep 1

# 创建 .app bundle 结构
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"

# 复制可执行文件
command cp "$app_binary" "$bundle_binary"
chmod +x "$bundle_binary"

# 复制 ShellIslandHooks CLI 到 Application Support
hooks_dest_dir="$HOME/Library/Application Support/ShellIsland"
mkdir -p "$hooks_dest_dir"
command cp "$hooks_binary" "$hooks_dest_dir/ShellIslandHooks"
chmod +x "$hooks_dest_dir/ShellIslandHooks"
echo "✓ ShellIslandHooks installed to $hooks_dest_dir"

# 生成 Info.plist
cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ShellIslandApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.shellisland.dev</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Shell Island Dev</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Shell Island needs automation access to focus kitty terminal sessions.</string>
</dict>
</plist>
EOF

# 签名
sign_identity="-"
if security find-identity -p codesigning -v "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
       | grep -q '"ShellIsland Dev Local"'; then
    sign_identity="ShellIsland Dev Local"
else
    echo
    echo "⚠ Using ad-hoc signing. TCC grants will be invalidated on every rebuild."
    echo "  Run once to fix: zsh scripts/setup-dev-signing.sh"
    echo
fi

codesign --force --deep --sign "$sign_identity" "$bundle_dir" 2>/dev/null || true
codesign --force --sign "$sign_identity" "$hooks_dest_dir/ShellIslandHooks" 2>/dev/null || true

echo "✓ Build complete: $bundle_dir"
