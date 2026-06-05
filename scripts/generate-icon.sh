#!/bin/zsh

# generate-icon.sh — 从项目根目录 Logo.png 生成 AppIcon.icns
#
# 用法: zsh scripts/generate-icon.sh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
logo_png="$repo_root/Logo.png"
iconset_dir="$repo_root/.build/AppIcon.iconset"
icns_path="$repo_root/.build/AppIcon.icns"

if [[ ! -f "$logo_png" ]]; then
    echo "❌ Logo.png 未找到，请放置于项目根目录"
    exit 1
fi

rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"

# macOS 图标需要的所有尺寸（使用 sips 缩放）
# 格式: size@scale → 文件名
declare -A sizes
sizes=(
    "16"    "icon_16x16.png"
    "32"    "icon_16x16@2x.png"
    "32"    "icon_32x32.png"
    "64"    "icon_32x32@2x.png"
    "128"   "icon_128x128.png"
    "256"   "icon_128x128@2x.png"
    "256"   "icon_256x256.png"
    "512"   "icon_256x256@2x.png"
    "512"   "icon_512x512.png"
    "1024"  "icon_512x512@2x.png"
)

for size filename in ${(kv)sizes}; do
    sips -z "$size" "$size" "$logo_png" --out "$iconset_dir/$filename" > /dev/null 2>&1
done

iconutil -c icns "$iconset_dir" -o "$icns_path"
rm -rf "$iconset_dir"

echo "✓ AppIcon.icns 已生成: $icns_path"
