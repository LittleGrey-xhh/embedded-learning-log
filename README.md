# 嵌入式学习日记

---

## 空白模板

```markdown
## YYYY-MM-DD  标题（一句话概括）

### 知识点
- 

### 踩过的坑
- 

### 正确做法
- 

### 关键词

---
```

---

## 2026-07-14  scanf 输入模式与缓冲区

### 知识点
- `scanf("%c")` 只读一个字符，无法区分"用户输入的是数字串还是单个字符"
- `scanf` 返回值 == 成功匹配的项数，可据此判断用户输入类型
- `scanf` 匹配失败时，已读取的字符**留在输入缓冲区**，后续 `%c` 可直接消费
- `%d` / `%f` / `%s` 自动跳过前导空白（`\n`、空格、tab），`%c` 不跳过

### 踩过的坑
- 想用一个 `scanf("%c", &c)` 同时处理"输入字符"和"输入 ASCII 码数字"两种场景 → **行不通**，因为 `%c` 永远只读一个字节
- 以为 `else` 分支里的第二个 `scanf("%c")` 会阻塞等待新输入 → 实际直接从缓冲区拿，不会阻塞
- 以为直接按回车能走到 `else` 分支 → 实际 `%d` 跳过 `\n` 后还在等有效输入，永远进不了 `else`

### 正确做法
```c
int code;
if (scanf("%d", &code) == 1) {
    // 走通了 → 用户输入的是数字
    printf("字母：%c\n", code);
} else {
    // 没走通 → 用户输入的是非数字字符，留在缓冲区
    char c;
    scanf("%c", &c);        // 直接从缓冲区拿，不阻塞
    printf("ASCII：%d\n", c);
}
```
核心思路：**用 `%d` 先探路，靠返回值判断走哪条分支**。

### 关键词
scanf 缓冲区 %c %d 返回值 输入模式 ASCII转换

---

## 2026-07-14  VMware Ubuntu 虚拟机网络排错：NetworkManager 全局开关

### 知识点
- VMware NAT 模式下，宿主机 VMnet8 网卡和虚拟机同处一个子网（如 192.168.41.0/24），宿主机可直接 ping 通虚拟机 IP，**不需要额外端口转发**
- `nmcli device status` 显示网卡"未托管"时，除了配置文件（`managed`、`unmanaged-devices`），还可能是 NM **全局网络开关被关掉**
- `journalctl -u NetworkManager --no-pager -n 50` 是排查 NM 问题的第一入口，日志里关键信息比改配置文件更直接
- `systemd-networkd` 没有"未托管"概念，`/etc/systemd/network/*.network` 文件匹配到网卡名即自动管理，适合 NM 顽固故障时的兜底方案
- `sshd` 服务安装后默认开机自启；`systemctl enable --now ssh` 一步完成启用+启动

### 踩过的坑
- 网卡 `ens33` 状态 DOWN 且无 IP → 手动 `dhclient ens33` 能拿到 IP → 以为只是 DHCP 客户端没配 → 改 netplan/NetworkManager 配置文件来回折腾
- NM 配置全改对了（`managed=true`、删掉 `10-globally-managed-devices.conf`、`plugins=keyfile`）但 `ens33` 依旧"未托管" → 以为是配置文件语法问题，反复查文档
- 最后看 `journalctl` 才发现一行 `manager: Networking is disabled by state file` → **NM 全局开关被关了**，配置怎么改都没用
- VMware `.vmx` 加 `ethernet0.forwarding = "tcp:2222 -> 22"` 做端口转发 → NAT 里不生效，因为宿主机本来就能直连虚拟机 IP

### 正确做法
```bash
# 排查 NM 问题时，第一步先看日志，不要急着改配置文件
journalctl -u NetworkManager --no-pager -n 50 | grep -i "disabled\|unmanaged\|error"

# 全局开关被关 → 一行解决
sudo nmcli networking on

# 创建 NM 有线连接（如需）
sudo nmcli connection add type ethernet ifname ens33 con-name wired autoconnect yes
```

```bash
# SSH 免密登录（宿主机→虚拟机）
ssh-keygen -t ed25519 -f ~/.ssh/vm_key -N ""
ssh-copy-id -i ~/.ssh/vm_key.pub user@虚拟机IP
ssh -i ~/.ssh/vm_key user@192.168.41.129
```
核心思路：**遇到 NM 问题，先看日志再改配置，`journalctl` 比任何文档都诚实。**

### 关键词
VMware NAT NetworkManager 未托管 nmcli networking journalctl systemd-networkd SSH免密 ens33

---

## 2026-07-14  VMware HGFS 共享文件夹开机自动挂载

### 知识点
- VMware 共享文件夹走的是 VMware Tools 的 HGFS 通道，**与虚拟机网络无关**，网络断了也能用
- `vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other` 手动挂载，`/mnt/hgfs/` 下会显示所有已配置的共享文件夹
- `/etc/fstab` 对 `vmhgfs-fuse` 不可靠（FUSE 文件系统在启动早期可能加载失败）→ 改用 **systemd service** 更稳定
- systemd service 的 `After=open-vm-tools.service` 确保在 VMware Tools 初始化完成后再挂载

### 踩过的坑
- 前一天共享文件夹能用，第二天重启后 `/mnt/hgfs/share/` 消失 → 以为是网络问题 → 实际是 HGFS 没自动挂载
- 按网上教程写 `/etc/fstab` 条目 → 重启后依旧不挂载 → FUSE 文件系统在 `/etc/fstab` 的 `mount -a` 阶段可能因依赖未就绪而跳过

### 正确做法
```ini
# /etc/systemd/system/hgfs-mount.service
[Unit]
Description=Mount VMware HGFS shared folders
After=open-vm-tools.service vmware-tools.service
Wants=open-vm-tools.service

[Service]
Type=oneshot
ExecStartPre=/bin/mkdir -p /mnt/hgfs
ExecStart=/usr/bin/vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hgfs-mount.service
```
核心思路：**FUSE 挂载用 systemd service 而非 fstab**，并通过 `After=` 保证启动顺序。

### 关键词
VMware HGFS vmhgfs-fuse 共享文件夹 开机挂载 systemd fstab FUSE

---

## 2026-07-14  WSL 环境配置：中文编码、路径映射、Claude Code 配置共享

### 知识点
- WSL 自动挂载 Windows 盘符到 `/mnt/` 下：`C:` → `/mnt/c/`，`E:` → `/mnt/e/`，以此类推
- WSL 终端中文乱码（八进制转义如 `\346\226\260\345\273\272`）→ `LANG` 环境变量未设为中文 locale
- `~/.bashrc` 中写入 `export LANG=zh_CN.UTF-8` 可永久生效，前提是系统已生成该 locale
- Windows 版 Claude Code 配置在 `C:\Users\用户名\.claude\`，WSL 版在 `~/.claude/`，两者独立
- CLAUDE.md 中 `@~/path/file.md` 的 `~` 在不同环境下解析不同：Windows 是 `C:\Users\用户名`，WSL 是 `/home/xhh`
- 跨环境共享 CLAUDE.md 时，路径必须用 `/mnt/c/...` 这种 WSL 能识别的绝对路径写法

### 踩过的坑
- WSL 里 `ls /mnt/e/VMware/share/` 看到中文文件显示为八进制数字 → 以为是文件损坏 → 实际只是 `LANG` 没设中文
- 在 WSL 新装 Claude Code，以为会自动继承 Windows 的配置 → 实际 `~/.claude/` 是空的，settings / CLAUDE.md / 插件全部独立
- 直接复制 Windows CLAUDE.md 到 WSL → `@~/Developer/...` 这条路径在 WSL 里 `~` 是 `/home/xhh`，文件找不到
- `wsl -d Ubuntu` 报 `WSL_E_DISTRO_NOT_FOUND` → distro 名字是 `Ubuntu-26.04` 不是 `Ubuntu`，用 `wsl -l --running` 查真实名字

### 正确做法
```bash
# 永久修复 WSL 中文显示
sudo locale-gen zh_CN.UTF-8
echo "export LANG=zh_CN.UTF-8" >> ~/.bashrc
source ~/.bashrc

# WSL 中复制 Windows Claude Code 配置
cp /mnt/c/Users/是一只灰呀/.claude/settings.json ~/.claude/
cp /mnt/c/Users/是一只灰呀/.claude/config.json ~/.claude/
```
```markdown
# WSL 版 CLAUDE.md —— 路径必须用 /mnt/c/... 写法
@/mnt/c/Users/是一只灰呀/Developer/browser-harness/SKILL.md
```
核心思路：**WSL 和 Windows 的 `~` 不是同一个目录，跨环境引用 Windows 文件时用 `/mnt/c/` 绝对路径。**

### 关键词
WSL locale 中文乱码 LANG zh_CN.UTF-8 Claude Code 配置共享 CLAUDE.md /mnt 路径映射

---

## 2026-07-13  Linux 基础命令入门

### 知识点
- `ls` — list，罗列当前目录下的文件和文件夹
- `cd` — change directory，切换工作路径；`cd -` 返回上一次路径；`cd ..` 返回上一层
- `cat` — 查看普通文件内容
- `touch` — 创建新的空普通文件
- `mkdir` — make directory，创建目录文件夹
- `find -name "文件名"` — 在指定目录中按名称查找文件，打印所在路径
- `chmod` — change mode，修改文件或目录权限，权限值用 8 进制表示
- `cp` — copy，复制文件到指定路径；`cp 文件 ../` 复制到上一层
- `mv` — move，移动/剪切文件（第二个参数为已有目录）或重命名（第二个参数为不存在的文件名）
- `rm` — remove，删除普通文件；`rm -r 目录` 递归删除目录；`rm -rf /*` 强制删除系统根目录所有内容（毁灭性命令，永远不要执行）
- `sudo` — 以超级用户权限执行命令；`sudo -s` 切换为 root 用户
- `df` — 查看磁盘使用空间；`df -h` 易读格式，`df -haT` 列出所有文件系统及类型
- Linux 文件的后缀名只是标记，**不代表文件的实际类型或编码格式**

### 踩过的坑
- 无（纯知识点学习，未实际操作）

### 正确做法
```bash
# 路径切换
cd /path/to/dir        # 进入指定目录
cd -                   # 返回上一次所在路径
cd ..                  # 返回上一层

# 文件操作
touch hello.c          # 创建空文件
cat hello.c            # 查看内容
cp hello.c ../         # 复制到上一层
mv hello.c world.c     # 重命名（第二个参数是不存在的文件名）
mv hello.c mydir/      # 移动文件（第二个参数是已存在的目录）
rm hello.c             # 删除普通文件
rm -r mydir/           # 递归删除目录

# 权限与查找
chmod 755 script.sh    # 修改权限（rwxr-xr-x）
find -name "hello.c"   # 按文件名查找

# 系统信息
df -h                  # 查看磁盘使用（易读格式）
df -haT                # 列出所有文件系统及其类型

# 超级用户
sudo apt update        # 以 root 权限执行命令
sudo -s                # 切换为 root 用户
```
核心思路：Linux 命令通用格式 = `命令名 [-选项] [参数]`，善用 `--help` 和 `man` 查看用法。文件后缀名只是给人类看的标记，系统不靠它判断文件类型。

### 关键词
ls cd cat touch mkdir find chmod cp mv rm sudo df Linux基础命令 权限 8进制
