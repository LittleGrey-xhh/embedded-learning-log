#!/bin/bash
# 同步脚本（2026-09-01 起按月分文件版）：
# 1. 自动找到 笔记/ 下最新一个月度日记文件，复制为仓库 README.md（并在顶部生成历史月份导航）
# 2. 把 归档/ 一起同步进仓库，保证 README 里的链接在 GitHub 上可跳转
# 用法：每次更新日记后，在 Git Bash 里执行 bash sync.sh

REPO="E:/a2_QianRuShi/embedded-learning-log"
NOTES="E:/a2_QianRuShi/笔记"
ARCHIVE="$NOTES/归档"

# 当前月文件，不存在则取笔记根目录下最新的月度文件（跨月当晚兜底）
MONTH_FILE="$NOTES/$(date '+%Y-%m').md"
if [ ! -f "$MONTH_FILE" ]; then
    MONTH_FILE=$(ls "$NOTES"/20*.md 2>/dev/null | sort | tail -1)
fi
if [ -z "$MONTH_FILE" ]; then
    echo "!!! 找不到月度日记文件，同步中止"
    exit 1
fi
echo "同步文件：$MONTH_FILE"

# 顶部导航：链接到 归档/ 里的历史月份
NAV=""
for f in "$ARCHIVE"/20*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .md)
    NAV="$NAV [$name](归档/$name.md) ·"
done
NAV="> 📒 历史月份：${NAV% ·}"

{
    echo "$NAV"
    echo ""
    cat "$MONTH_FILE"
} > "$REPO/README.md"

# 归档目录整体进仓库（结构本地/远程一致）
rm -rf "$REPO/归档"
cp -r "$ARCHIVE" "$REPO/归档" 2>/dev/null

cd "$REPO" || exit 1
git add -A
git commit -m "$(date '+%Y-%m-%d') 更新日记"
git push
echo "=== 同步完成 ==="
