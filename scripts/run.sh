#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_dir="$HOME/Applications/Shell Island Dev.app"
logs_dir="$repo_root/logs"

cd "$repo_root"

# 先构建
zsh scripts/build.sh

# 确保日志目录存在
mkdir -p "$logs_dir"

# 停止旧实例
osascript -e 'tell application "Shell Island Dev" to quit' 2>/dev/null || true
pkill -9 -f "Shell Island Dev" 2>/dev/null || true
sleep 1

# 启动应用
open -na "$bundle_dir"

echo "✓ Shell Island Dev launched"
