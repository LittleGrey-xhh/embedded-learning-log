#!/bin/bash
# 薄壳：真正的逻辑在 sync.py
#
# 为什么不再用 bash 实现：双击 `.bat` 运行不能依赖 bash —— Windows 上 `where bash`
# 会先命中 WSL 的 C:\Windows\System32\bash.exe，那个 bash 看不到 Windows 路径，
# 而且 sed / awk 处理中文相对路径容易出错。
#
# 保留这个文件只是让老习惯 `bash sync.sh --push` 继续可用。

PY="D:/python/python.exe"
[ -f "$PY" ] || PY=$(command -v python3 || command -v python)

exec "$PY" "$(dirname "$0")/sync.py" "$@"
