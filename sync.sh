#!/bin/bash
# 同步脚本 v2（2026-11-21）
#
# 和 v1 的区别：v1 把整月笔记直接覆盖成 README.md，导致 README 变成 2800 行、
# 陌生人点进来第一屏看到的是"11.20 笔记"而不是"这是什么仓库"。
# v2 改成：README 是门面（手工维护），当月正文放 学习日记/，脚本只更新
# README 里 <!-- RECENT --> 标记之间的「最近在学」区块，其余一个字都不动。
#
# 用法：
#   bash sync.sh          更新本地 + 提交
#   bash sync.sh --push   更新本地 + 提交 + 推送

set -e

REPO="E:/a2_QianRuShi/embedded-learning-log"
NOTES="E:/a2_QianRuShi/笔记"
ARCHIVE="$NOTES/归档"
PY="D:/python/python.exe"
DO_PUSH=0
[ "$1" = "--push" ] && DO_PUSH=1

# ---------- 1. 找当月笔记文件（跨月当晚兜底取最新） ----------
SRC="$NOTES/$(date '+%Y-%m').md"
if [ ! -f "$SRC" ]; then
    SRC=$(ls "$NOTES"/20*.md 2>/dev/null | sort | tail -1)
fi
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    echo "!!! 找不到月度笔记文件，同步中止"
    exit 1
fi
MONTH=$(basename "$SRC" .md)
echo "同步：$SRC  →  学习日记/$MONTH.md"

mkdir -p "$REPO/学习日记"

# ---------- 2. 复制当月正文，修正内部相对路径 ----------
# 学习日记/ 比仓库根目录深一层，原来指向 归档/ 和 learning-log-guide.md 的链接会 404
sed -e 's|](归档/|](../归档/|g' \
    -e 's|](learning-log-guide.md)|](../learning-log-guide.md)|g' \
    "$SRC" > "$REPO/学习日记/$MONTH.md"

# 在第一行标题后补一条返回首页的链接
awk 'NR==1 { print; print ""; print "> [← 返回仓库首页](../README.md)"; next } { print }' \
    "$REPO/学习日记/$MONTH.md" > "$REPO/学习日记/.tmp.md"
mv "$REPO/学习日记/.tmp.md" "$REPO/学习日记/$MONTH.md"

# ---------- 3. 归档 + 格式规范 ----------
mkdir -p "$REPO/归档"
cp "$ARCHIVE"/20*.md "$REPO/归档/" 2>/dev/null || true
if [ -f "$NOTES/learning-log-guide.md" ]; then
    cp "$NOTES/learning-log-guide.md" "$REPO/"
fi

# ---------- 4. 只更新 README 的「最近在学」区块 ----------
"$PY" - "$REPO/README.md" "$REPO/学习日记/$MONTH.md" "$MONTH" <<'PYEOF'
import re
import sys

readme, src, month = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src, encoding='utf-8').read().splitlines()


def make_brief(start):
    """从一条笔记里提摘要。1. 优先取 > 开头的简述行；2. 没有就退化用「干了什么」的第一条"""
    for j in range(start, min(start + 6, len(lines))):
        if lines[j].startswith('> '):
            return lines[j][2:].strip()
        if re.match(r'^# ', lines[j]):
            break
    for j in range(start, min(start + 60, len(lines))):
        if j > start and re.match(r'^# \d+\.\d+ 笔记', lines[j]):
            break
        # 编号列表项，加粗不加粗都要（早期笔记是纯文本的 "1. xxx"）
        m = re.match(r'^\d+\.\s+(\S.*)$', lines[j])
        if m:
            txt = m.group(1).replace('**', '').strip()
            return txt
    return ''


# 从正文里抓最近 5 条笔记的日期 + 摘要
items = []
i = 0
while i < len(lines) and len(items) < 5:
    m = re.match(r'^# (\d+\.\d+) 笔记', lines[i])
    if m:
        date = m.group(1)
        brief = make_brief(i + 1)
        if len(brief) > 70:                     # 太长就截断，优先在句号处断
            cut = brief.find('。', 15)
            brief = brief[:cut + 1] if 0 < cut < 75 else brief[:70] + '……'
        items.append(f'- **{date}** — {brief}' if brief else f'- **{date}**')
    i += 1

if not items:
    items = ['（本月还没有笔记）']

block = (
    '<!-- RECENT:BEGIN -->\n'
    f'> 自动生成于 {month}，由 `sync.sh` 从当月笔记提取，不要手改。\n\n'
    + '\n'.join(items) +
    '\n<!-- RECENT:END -->'
)

text = open(readme, encoding='utf-8').read()
new, n = re.subn(r'<!-- RECENT:BEGIN -->.*?<!-- RECENT:END -->', block, text, flags=re.S)
if n == 0:
    print('!!! README 里找不到 RECENT 标记，跳过（请检查 README.md）')
else:
    open(readme, 'w', encoding='utf-8').write(new)
    print(f'README 最近在学：{len(items)} 条')
PYEOF

# ---------- 5. 提交 ----------
cd "$REPO"
git add -A
if git diff --cached --quiet; then
    echo "没有变更，跳过提交"
    exit 0
fi
git commit -q -m "$(date '+%Y-%m-%d') 更新学习日记"
echo "已提交"
if [ "$DO_PUSH" -eq 1 ]; then
    git push
    echo "已推送"
else
    echo "（未推送，要推加 --push）"
fi
