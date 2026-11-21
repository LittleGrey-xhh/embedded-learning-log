#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""学习日记同步脚本（Python 版，2026-11-21）

为什么从 bash 改成 Python：
  1. 双击运行不能依赖 bash —— `where bash` 在 Windows 上会先命中 WSL 的
     C:\\Windows\\System32\\bash.exe，那个 bash 看不到 Windows 路径
  2. sed / awk 处理中文相对路径容易出错
  3. Python 路径在这台机器上是确定的

用法：
    python sync.py            只更新本地 + 提交
    python sync.py --push     更新 + 提交 + 推送

被 同步.bat（双击）和 sync.sh（薄壳）调用。
"""

import os
import re
import subprocess
import sys
import shutil
from datetime import date
from pathlib import Path

NOTES = Path(r"E:\a2_QianRuShi\笔记")
REPO = Path(r"E:\a2_QianRuShi\embedded-learning-log")
ARCHIVE = NOTES / "归档"


def run(cmd, cwd=None):
    """跑一条命令，返回 (是否成功, 合并输出)"""
    r = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )
    return r.returncode == 0, (r.stdout or "") + (r.stderr or "")


def find_month_file():
    """当月笔记；跨月当晚兜底取最新的月度文件"""
    cur = NOTES / f"{date.today():%Y-%m}.md"
    if cur.exists():
        return cur
    cands = sorted(NOTES.glob("20*.md"))
    return cands[-1] if cands else None


def sync_body(src: Path):
    """当月正文 → 学习日记/YYYY-MM.md，并把相对链接改深一层"""
    month = src.stem
    dst_dir = REPO / "学习日记"
    dst_dir.mkdir(exist_ok=True)
    dst = dst_dir / f"{month}.md"

    text = src.read_text(encoding="utf-8")
    # 学习日记/ 比仓库根目录深一层，指向 归档/ 和 guide 的链接要加 ../
    text = text.replace("](归档/", "](../归档/")
    text = text.replace("](learning-log-guide.md)", "](../learning-log-guide.md)")

    lines = text.split("\n")
    if lines and lines[0].startswith("#"):
        lines.insert(1, "")
        lines.insert(2, "> [← 返回仓库首页](../README.md)")

    dst.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"✓ 正文  →  学习日记/{month}.md")
    return dst, month


def sync_archive():
    """归档 + 格式规范一起同步"""
    dst = REPO / "归档"
    dst.mkdir(exist_ok=True)
    n = 0
    for f in sorted(ARCHIVE.glob("20*.md")):
        shutil.copy2(f, dst / f.name)
        n += 1
    guide = NOTES / "learning-log-guide.md"
    if guide.exists():
        shutil.copy2(guide, REPO / "learning-log-guide.md")
    print(f"✓ 归档  →  {n} 个文件 + 格式规范")


def brief_of(lines, start):
    """从一条笔记里提摘要：优先 > 引用行，退化用「干了什么」的第一条"""
    for j in range(start, min(start + 6, len(lines))):
        if lines[j].startswith("> "):
            return lines[j][2:].strip()
        if lines[j].startswith("# "):
            break
    for j in range(start, min(start + 60, len(lines))):
        if j > start and re.match(r"^# \d+\.\d+ 笔记", lines[j]):
            break
        m = re.match(r"^\d+\.\s+(\S.*)$", lines[j])
        if m:
            return m.group(1).replace("**", "").strip()
    return ""


def update_readme(month_file: Path, month: str):
    """只替换 README 里 <!-- RECENT --> 之间的内容"""
    readme = REPO / "README.md"
    text = readme.read_text(encoding="utf-8")
    lines = month_file.read_text(encoding="utf-8").split("\n")

    items = []
    i = 0
    while i < len(lines) and len(items) < 5:
        m = re.match(r"^# (\d+\.\d+) 笔记", lines[i])
        if m:
            brief = brief_of(lines, i + 1)
            if len(brief) > 70:
                cut = brief.find("。", 15)
                brief = brief[: cut + 1] if 0 < cut < 75 else brief[:70] + "……"
            items.append(f"- **{m.group(1)}** — {brief}" if brief else f"- **{m.group(1)}**")
        i += 1
    if not items:
        items = ["（本月还没有笔记）"]

    block = (
        "<!-- RECENT:BEGIN -->\n"
        f"> 自动生成于 {month}，由 `sync.py` 从当月笔记提取，不要手改。\n\n"
        + "\n".join(items)
        + "\n<!-- RECENT:END -->"
    )
    new, n = re.subn(
        r"<!-- RECENT:BEGIN -->.*?<!-- RECENT:END -->", block, text, flags=re.S
    )
    if n == 0:
        print("!!! README 里找不到 RECENT 标记，跳过")
        return
    readme.write_text(new, encoding="utf-8", newline="\n")
    print(f"✓ README 「最近在学」{len(items)} 条")


def commit_and_push(do_push: bool):
    ok, out = run(["git", "add", "-A"], cwd=REPO)
    if not ok:
        print("!!! git add 失败\n" + out)
        return 1

    ok, out = run(["git", "diff", "--cached", "--quiet"], cwd=REPO)
    if ok:                              # 返回 0 = 没有差异
        print("· 没有新变更")
    else:
        ok, out = run(
            ["git", "commit", "-q", "-m", f"{date.today():%Y-%m-%d} 更新学习日记"],
            cwd=REPO,
        )
        print("✓ 已提交" if ok else "!!! 提交失败\n" + out)
        if not ok:
            return 1

    if not do_push:
        print("· 未推送（要推加 --push）")
        return 0

    ok, out = run(["git", "rev-list", "--count", "@{u}..HEAD"], cwd=REPO)
    ahead = int(out.strip()) if ok and out.strip().isdigit() else 1
    if ahead == 0:
        print("✓ 远程已是最新，无需推送")
        return 0

    print(f"· 有 {ahead} 个提交待推送")
    ok, out = run(["git", "push"], cwd=REPO)
    if ok:
        print("✓ 已推送")
        return 0

    # 这台机器的网络查不了证书吊销状态（CRYPT_E_NO_REVOCATION_CHECK），退一步重试
    print("· 正常推送失败，尝试跳过证书验证重试……")
    ok, out = run(["git", "-c", "http.sslVerify=false", "push"], cwd=REPO)
    if ok:
        print("✓ 已推送（本次跳过证书验证，因为网络无法检查证书吊销状态）")
        return 0

    print("!!! 推送失败，本地提交已保留")
    print("    检查两件事：1. 能否打开 github.com  2. 网络是否换了")
    print(out[-400:])
    return 1


def main():
    do_push = "--push" in sys.argv

    src = find_month_file()
    if not src:
        print("!!! 找不到月度笔记文件，同步中止")
        return 1
    print(f"源文件：{src}\n")

    month_file, month = sync_body(src)
    sync_archive()
    update_readme(month_file, month)
    print()
    return commit_and_push(do_push)


if __name__ == "__main__":
    sys.exit(main())
