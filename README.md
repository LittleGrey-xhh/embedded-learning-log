> 📒 历史月份： [2026-07](归档/2026-07.md) · [2026-08](归档/2026-08.md)

# 学习日记 · 2026-09

> 从 2026-09-01 起按月分文件。历史月份：[归档/2026-07](归档/2026-07.md) · [归档/2026-08](归档/2026-08.md)
> 格式规范见 [learning-log-guide.md](learning-log-guide.md)，新条目写在本标题下方（最新在最上面）。

---

# 9.9 笔记

## 一、干了什么

1. 从零摸索 TCP 多任务并发服务器（server.c / clinet1.c / clinet2.c）：评审修正后实现服务器同时服务多客户端、双向收发（定点发送按 IP+端口匹配）。
2. TCP 文件传输服务器（5.tcp传输文件/server.c）：自己从零写服务端接收 jpg 文件落盘，评审修正 8 处问题，打通"文件收发"场景。

## 二、知识点

### 1. 字节序函数按字段大小选：16 位 s，32 位 l

端口 `sin_port` 是 16 位用 `htons/ntohs`，IP `sin_addr.s_addr` 是 32 位用 `htonl/ntohl`。s=short 2 字节，l=long 4 字节，看字段大小选，不背端口还是 IP。`htons(8888)` 传的是**数字**，不是字符串。

### 2. 标准输入两件套：fgets 用 sizeof，scanf 后清换行

1. `fgets` 第三参数是"最多装多少字节"，必须 `sizeof(buf)`；buf 刚定义时 `strlen(buf)` 为 0，什么都读不到。
2. `scanf("%hu", &port)` 会在缓冲区残留 `'\n'`，后面紧跟的 fgets 直接读到空行 → scanf 之后补一句 `while(getchar() != '\n');`。
3. 剪掉 fgets 读到的换行：`buf[strcspn(buf, "\n")] = '\0';`——第二参数是**字符串** `"\n"`，写 `'\n'` 是把字符 10 当指针用，段错误。

### 3. 线程传参：传槽位地址，不传循环变量

`pthread_create(..., Recv_Task, &client_info_arr[idx])`——传**数组槽位的地址**（不是下标）。循环局部变量 `new_socket` 下一轮 accept 就被覆盖，线程拿着它的地址读到的是别人的 fd（竞态）。线程里 `void *arg` 是"拆箱"：`struct client_info *c = (struct client_info *)arg;` 还原类型。没用到参数时写 `(void)arg;` 消 unused 警告。

同进程线程共享内存：客户端只有一个连接，收线程直接用全局 fd，第四参数传 `NULL`；服务器有多个客户端要区分"你是谁的线程"，才传槽位地址。

### 4. 线程资源回收：detach 防"僵尸线程"

joinable 线程退出后资源不自动回收，必须有人 `pthread_join` 收尸；不收尸也不 detach → 每断开一个连接泄漏一份。`pthread_detach(pthread_self())` = "我不要收尸，退出瞬间系统直接回收"。Ctrl+C 杀进程时全部资源由操作系统回收，与此无关——泄漏发生在服务器**长期运行**过程中。严格说"僵尸进程"是 fork 子进程的概念，线程这边是类比。

### 5. _exit 的用法看语境：服务器不能杀全进程，客户端可以

服务器端一个客户端 recv 出错就 `_exit(-1)` → 全部客户端陪葬。正确姿势：close 该 fd + 槽位置回 -1 + 线程退出。客户端只有一个连接，服务器断了程序就没有存在意义 → 直接 `exit(0)` 退出整个进程反而正确。同一个函数，语境不同结论不同。

### 6. recv 不补 '\0'，槽位用 -1 复用

1. `recv` 收到多少就是多少，不会自动补 `'\0'`，按字符串打印前必须 `buf[ret] = '\0'`。
2. fd 0 是 stdin，槽位"无连接"用 `new_socket = -1` 表示；客户端断开时置回 -1，新连接用 `find_free_slot()` 复用，数组不越界不浪费。

### 7. 客户端四步与 connect

TCP 客户端：socket → bind（可选，这里固定端口是为了让服务器按 IP+端口定位你）→ **connect** → send/recv。connect 成功 = 三次握手完成、双向通道已建立，客户端不需要 listen/accept（那是服务器"被动等人"的前台机制）。客户端收发全双工靠两条执行流：主循环 fgets+send，子线程专职 recv。

### 8. INADDR_ANY 只能 bind，connect 要具体 IP

`INADDR_ANY`(0.0.0.0) 含义是"绑我自己的所有网卡"，只用在 bind 里。connect 的目标是别人的机器，必须写服务器具体 IP（`inet_aton`/`inet_addr`）。inet 系列命名：a=ascii（点分字符串），n=network（网络序二进制）——`inet_aton` 字符串填结构体（写），`inet_ntoa` 网络序转字符串（读），方向和 htons 一套逻辑。注意 `inet_ntoa` 用静态缓冲区，多线程同时调用会串数据，取出后立刻 strncpy 存起来。

### 9. 并发模型：accept 管新客，断开检测全在 recv

服务器三路并行：主循环 accept 接新连接（永不退出，接一个登记一个继续等）、Send_Task 等键盘、每客户端一个 Recv_Task。全双工 = TCP socket 天生双向（内核两个独立方向的缓冲区），程序用两条执行流分别堵在 recv 和 send 上才能同时收发。accept 的成败只看返回值：新 fd（>0）成功，-1 失败查 errno——它和新连接之后断没断没有任何关系，"客人走了"全靠 recv 的返回值发现。

### 10. accept 和 connect 的方向相反

| | 地址结构体谁填 | 方向 |
|---|---|---|
| connect（客户端） | 你填服务器的 IP+端口传进去 | 主动发起 |
| accept（服务器） | 给空壳，内核把对方的 IP+端口填给你 | 被动接 |

### 11. 传输二进制文件：strlen 是头号杀手

jpg 里 `0x00` 是合法字节，`strlen` 在第一个 `\0` 截断 → 写出的文件全是废的。读写长度一律用 `recv`/`read` 的**返回值**。同时 TCP 是字节流、无消息边界，一次 recv 返回小于缓冲区大小是常态，`ret < sizeof(buf)` 不能当"传输完成"——正确的完成信号是 **recv 返回 0**（对端发完 close，FIN 包到达）。

### 12. open 写文件的三个细节

1. `O_CREAT` 必须带第三个参数权限（如 `0666`），否则新建文件权限是栈上的垃圾值。
2. 标志用按位或 `|`，不是逻辑或 `||`（`O_CREAT || O_WRONLY` 结果恒为 1）。
3. 收文件加 `O_TRUNC` 清掉旧内容，防上次传输残骸混进去。

### 13. 监听 socket 和通信 socket 是两个 fd

`socket_tcp` 只负责 accept；收发数据必须用 accept 返回的 `new_socket`。对监听 socket 调 recv 收不到任何客户端数据。

### 14. sockaddr 是通用容器，sockaddr_in 是 IPv4 专用填值结构

bind/connect/accept 参数是通用 `struct sockaddr`（一套接口通吃 IPv4/IPv6/Unix 本地），但通用容器没法填字段，实际用 `sockaddr_in` 填值，传参时强转回通用类型 `(struct sockaddr *)&server_addr`，内核按 `sin_family` 认出来。同族：`sockaddr_in6`（IPv6）、`sockaddr_un`（Unix 本地）。

### 15. man 手册检索链

1. 章节号：1 命令、2 系统调用、3 库函数、7 协议与杂项。
2. 链条：`man 2 bind` → 翻末尾 SEE ALSO → `man 7 ip`（TCP/UDP 编程宝藏页，含 sockaddr_in 全字段和字节序要求）→ 还要源码级细节就 `grep -n "struct sockaddr_in" -A 8 /usr/include/netinet/in.h`。

## 三、踩的坑

1. `htons("8888")` 传了字符串 → 端口变成字符串地址的低 16 位，绑到随机端口。根因——坑在知识点第 1 点。
2. `for(i < MAX_CONNECTION, i++)` 分号写成逗号 → 逗号表达式值恒真，死循环 + 数组越界。
3. `main` 里 `int socket_tcp = socket(...)` 遮蔽全局变量 → 收线程里 `recv(0)` 实际在读键盘。根因：线程共享的是全局 fd，被局部变量遮蔽后全局还是 0——坑在第 3 点。
4. `strcspn(buf, '\n')` 传字符 → int 被当指针解引用段错误。根因——坑在第 2 点。
5. 把 accept 写成 connect 用法：自己往 clinet_addr 填 IP/端口 → 白填，内核会覆盖。根因——坑在第 10 点。
6. 二进制写入长度用 `strlen(buf)` → jpg 收到一半全是废数据。根因——坑在第 11 点。
7. `if(ret < sizeof(buf))` 判断传输完成 → 中途频繁误判。根因：TCP 字节流无消息边界——坑在第 11 点，完成信号是 recv==0。
8. `O_CREAT || O_WRONLY` 逻辑或 + O_CREAT 不带权限参数 → 文件权限是垃圾值。根因——坑在第 12 点。
9. `recv(socket_tcp, ...)` 用监听 socket 收数据 → 永远收不到。根因——坑在第 13 点。
10. 同一函数里 `addrlen` 定义两次 → redeclaration 编译错误。

---

# 9.8 笔记

## 一、干了什么

1. 调试 UDP 广播 demo（broadcast.c / 接收.c）：修好发送端 bind 广播地址的错误，实现全网段广播收发，搞清了"端口到底谁能任意"的问题。
2. 调试 UDP 组播 demo（server.c / clinet1.c）：区分发送端/接收端各自的组播配置，修掉 setsockopt 用错选项、imr_address 写死 IP、手抄结构体重复定义等问题，最后在 VMware 克隆机上实现了两台虚拟机的组播互通。

## 二、知识点

### 1. bind 绑的是"我是谁"，sendto 填的是"发给谁"

广播地址 `192.168.172.255` 是发往别人的目标地址，本机网卡上根本没有这个地址，拿去 bind 必失败（`EADDRNOTAVAIL` / `EINVAL`）。发送端根本不需要 bind，内核在第一次 sendto 时自动选出口网卡和临时端口；bind 是接收端登记监听端口用的。

**另外 bind 也不能写进循环里**：第一次绑成功后，第二次再绑同一端口会报 `EADDRINUSE`（端口已被自己占了）。

### 2. 广播的端口约定：目标端口两端统一，源端口随意

| 端口 | 谁在用 | 能否任意 |
|------|--------|----------|
| 目标端口（发送端 `sin_port`） | 写在包里的"收件人端口" | 不能乱填，必须和接收端 bind 的一致，两端约定统一 |
| 源端口（发送端自己） | 不 bind 时内核自动分配（32768~60999） | 任意，每次重启程序还会变 |
| 接收端 bind 的端口 | 本机监听用 | 任意，只要 >1024（0~1023 是特权端口要 root） |

不存在"向所有端口广播"——端口是收件箱号，一个包只能填一个。想全员收到：约定一个公共端口，大家 bind 它。

### 3. 接收端 bind INADDR_ANY = 收全网段

`bind INADDR_ANY:8888` 后，本机所有网卡上到达的、目标端口 8888 的 UDP 包全部交给我，不挑来源 IP，广播和单播都收。`recvfrom` 拿到的 `client_addr` 就是发送方真实 IP:端口（源 IP 是协议栈自动填的发送者身份，源端口是发送端内核分配的临时端口）。

### 4. 广播 vs 组播：投递规则完全不同

| | 广播 | 组播 |
|---|---|---|
| 投递规则 | 发到 .255，全网段每个主机都收到一份，再看端口给谁 | 内核在 IP 层先查：这个包的**组地址**我加入过吗？没加入直接丢弃，轮不到看端口 |
| 能收到的前提 | 对方监听了那个端口 | 对方程序调了 `IP_ADD_MEMBERSHIP` 入组 **且** bind 了同一端口 |

广播是"喇叭喊话人人听得见"，组播是"进群才能收群消息"。组播比广播还省事的一点：发送端连 `SO_BROADCAST` 开关都不用开。

### 5. 组播两端分工：IP_MULTICAST_IF 发，IP_ADD_MEMBERSHIP 收

- 发送端：`IP_MULTICAST_IF` 指定组播包从哪块网卡出去（单网卡环境可以省，内核按路由表自动选；多网卡/走错接口时才需要显式指定）；
- 接收端：必须 `IP_ADD_MEMBERSHIP` 加入组播组，否则内核直接丢弃组播包，recvfrom 永远阻塞。

```c
struct ip_mreqn optval;
optval.imr_multiaddr.s_addr = inet_addr("224.0.0.1");  // 组地址
optval.imr_address.s_addr   = htonl(INADDR_ANY);       // 本机网卡让内核挑
optval.imr_ifindex          = 0;

// 发送端（可选）：
setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &optval, sizeof(optval));
// 接收端（必须）：
setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &optval, sizeof(optval));
```

**imr_address 一律 INADDR_ANY**：写死具体 IP 的代码换台机器跑就报 `No such device`（ENODEV），因为那不是本机的地址。

### 6. setsockopt 失败必须退出，不能只 perror

setsockopt 失败后程序若继续跑，会带着"没入组/没配置好"的状态默默阻塞在 recvfrom——永远收不到数据还以为代码没问题。错误处理三件套：perror + return，让失败立刻暴露。

### 7. struct ip_mreqn 在哪个头文件

`<netinet/in.h>`（glibc，新版本自带完整定义）和 `<linux/in.h>`（内核 UAPI 头）里都有，含 imr_multiaddr / imr_address / imr_ifindex 三个字段。两个头文件都包含时**手抄一遍会报 redefinition**。只有老虚拟机的老 glibc 没有 ip_mreqn，才需要手动定义（注释里说明来源）。

### 8. 组播/广播只在本二层网段内扩散

组播包 TTL 默认为 1，一出本网段就被路由器丢弃。就算把 TTL 调大也没用——普通路由器不转发组播，转发组播需要专门跑 IGMP/PIM 的组播路由器。广播同样跨不了网段。**能 ping 通 ≠ 同网段**：ping 通靠的是路由器转发单播，而广播和组播是二层的活。跨网段想互通只有单播（UDP/TCP 点对点）一条路。

### 9. 收发一体程序：fork 分家，父发子收

单进程里 recvfrom 阻塞会卡死发送循环，标准解法 fork：子进程专职收，父进程专职发。

```c
// socket 创建后：bind 8888（收组播的目标端口）+ IP_ADD_MEMBERSHIP 入组
pid_t pid = fork();
if (pid == 0) {          // 子进程：专职收
    char buf_rec[128];
    struct sockaddr_in from;
    socklen_t len = sizeof(from);
    while (1) {
        int n = recvfrom(socket_udp, buf_rec, sizeof(buf_rec) - 1, 0,
                         (struct sockaddr *)&from, &len);
        if (n > 0) {
            buf_rec[n] = '\0';
            printf("\n[%s:%d] %s\n", inet_ntoa(from.sin_addr), ntohs(from.sin_port), buf_rec);
            fflush(stdout);
        }
    }
}
// 父进程：继续原来的发送循环
```

同机多进程收同一组播：UDP socket 加 `SO_REUSEADDR` 后可以多个 socket bind 同一端口，组播包每家都能收到一份。

### 10. UDP 截断：报文比缓冲大，多的部分直接扔

接收缓冲小于报文长度时，超出部分静默丢弃、不报错。带中文的消息按 UTF-8 每字 3 字节算，接收缓冲开大点（128+）避免消息被拦腰截断。

### 11. VMware 和 WSL 是两套隔离的虚拟网络

VMware NAT（VMnet8）和 WSL2 NAT 即使网段数字撞名（都是 192.168.172.x）也完全隔离，互相 ARP 找不到对方（`Destination Host Unreachable`）。WSL 切 mirrored 模式 + 放开 Hyper-V 防火墙也无法与 VMnet8 打通，这是已知不兼容。

**跨虚拟网络测试的可靠方案**：VMware 里链接克隆一台虚拟机当"第二台机器"（链接克隆引用原机磁盘只存差异，省空间创建快，适合临时实验机），两端挂同一个 VMnet，互 ping 通后组播即通。

## 三、踩的坑

1. 广播发送端 bind 广播地址 → `bind error`。根因：把"发给谁"当成了"我是谁"——坑在第 1 点。
2. 发送端把 bind 写进 while 循环 → 第二次循环报 `EADDRINUSE`。根因：自己占了自己的端口——坑在第 1 点。
3. 接收端组播用 `IP_MULTICAST_IF` → 永远收不到，recvfrom 静默阻塞。根因：那是发送端选项，收组播要 `IP_ADD_MEMBERSHIP`——坑在第 5、6 点。
4. `imr_address` 写死老师代码里的 192.168.63.2 → `setsockopt: No such device`。根因：本机没有这个 IP，内核按地址找网卡找不到——坑在第 5 点。
5. 手抄 struct ip_mreqn 定义 → `redefinition` 编译错误。根因：netinet/in.h 里已经有了——坑在第 7 点。
6. 组播"收不到别人发的"：以为 ping 通就能收组播，实际跨网段时组播包根本过不了路由器；本机测试时 VMware 虚拟机和 WSL 又是两套隔离网络，双向 ARP 不通。根因——坑在第 8、11 点，解法是让收发两端进同一个二层网段（VMware 克隆机互测）。

---

# 9.7 笔记

## 必背

1. **UDP 最大传输数据长度：65507 字节** = 65535（IP 包总长上限，16 位字段）- 8（UDP 首部）- 20（IP 首部）。记忆链：UDP 总长字段是 16 位 → 上限 65535 → 减 IP 头 20 + UDP 头 8 → 应用层一次最多 65507。
2. **OSI 七层模型（自下而上：物链网传会表应）**：

| 层号 | 层名 | 干什么 | 代表协议/设备 |
|------|------|--------|--------------|
| 7 | 应用层 | 人能看懂的数据 | HTTP / FTP / DNS |
| 6 | 表示层 | 格式转换、加解密、压缩 | TLS、编码 |
| 5 | 会话层 | 建立/管理/终止会话 | RPC |
| 4 | 传输层 | 端到端传输，端口号 | TCP / UDP |
| 3 | 网络层 | 路由选路，IP 地址 | IP / ICMP，路由器 |
| 2 | 数据链路层 | 相邻节点帧传输，MAC 地址 | 以太网，交换机 |
| 1 | 物理层 | 比特流走物理介质 | 网线、光纤、集线器 |

面试常问：交换机在二层（看 MAC），路由器在三层（看 IP），TCP/UDP 在传输层；今天写的 socket/UDP 程序在传输层之上。

## 一、干了什么

1. 写 UDP 一发一收 demo（1.server.c / 1.clinet.c），服务器 bind 8888 收客户端消息并打印对方地址端口。
2. 改成双向通信（2.server.c / 2.clinet.c），服务器收到消息后回包，实现一来一回。
3. 修了两个 bug：bind 报 `Cannot assign requested address`；服务器收到数据但打印的端口号"不对"（48501）。

## 二、知识点

### 1. bind 报错 `Cannot assign requested address` —— inet_network 字节序坑

`s_addr` 里必须存**网络字节序**的 IP，但 `inet_network` 返回的是**主机字节序**，直接赋值在小端机器上 IP 字节全反：`192.168.172.83` 变成 `83.172.168.192`，本机网卡上根本没这个地址，bind 一查就报错。

**bind 的硬规则：绑定的 IP 必须属于本机某块网卡，否则报 `Cannot assign requested address`。**

前后对比：

```c
// 改前（错）：字节序反了，等效于绑 83.172.168.192
server_addr.sin_addr.s_addr = inet_network("192.168.172.83");

// 改后（对）：服务器绑所有网卡
server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
```

### 2. 三个 IP 转换函数对比

| 函数 | 返回字节序 | 能否直接赋给 s_addr |
|------|-----------|-------------------|
| `inet_addr("x.x.x.x")` | 网络字节序 | 能 |
| `inet_network("x.x.x.x")` | 主机字节序 | 不能（小端机上字节全反） |
| `htonl(INADDR_ANY)` | 网络字节序 | 能（0.0.0.0 本身无所谓序） |

记住：**`s_addr` 只认 `inet_addr` / `htonl` 的结果，`inet_network` 的返回值永远不能直接给它。**

### 3. 服务器该绑 INADDR_ANY，不该写死 IP

`INADDR_ANY`（0.0.0.0）= 本机所有网卡的该端口都归我监听。写死 IP 的坏处：WSL 的 IP 重启就变，一变就炸。客户端连服务器才需要指定目标 IP，服务器自己不用。

### 4. 客户端不 bind —— 内核自动分配临时端口

现象：服务器打印的对方端口是 48501，不是客户端想用的 6666。

原因：客户端把 `clinet_addr` 结构体填好了但**没调 bind()**，结构体只是个普通变量，内核不知道它存在。不 bind 就 sendto 时，内核在发送瞬间自动做两件事：

1. 查路由表选出走哪块网卡，用那块网卡的 IP 当源 IP；
2. 从临时端口池抓一个空闲端口绑上去（Linux 范围 32768~60999，48501 正好在里面，所以每次运行端口号还会变）。

| 对比 | 显式 bind | 内核自动 bind |
|------|----------|--------------|
| 端口 | 指定，固定不变 | 随机，每次运行都可能变 |
| 源 IP | 指定 | 按路由自动选网卡 |
| 适用 | 服务器（必须）、要固定身份的客户端 | 普通客户端 |

实践习惯：**服务器必须 bind（要有固定端口让人找），客户端通常不 bind（避免和其他程序撞端口）**。

### 5. bind 的本质：给 socket 登记本地身份

`socket()` 只创建一个通信端点，此时没有本地地址。`bind` 就是把这个 socket 和一个"名字"（本地 IP + 端口二元组）绑到一起，之后它收发的数据包源地址都是这个身份。不 bind 不是"没有地址"，而是"内核发送时临时发一个随机身份"。

### 6. sockaddr_in 结构体与强制转换

```c
struct sockaddr_in {
    sa_family_t    sin_family;   // 协议族 AF_INET
    in_port_t      sin_port;     // 端口（网络字节序，htons）
    struct in_addr sin_addr;     // IP（网络字节序，inet_addr/htonl）
    char           sin_zero[8];  // 填充凑 16 字节，必须 memset 清零
};
```

内核 API 只认通用的 `struct sockaddr`（无字段可填），所以实际写法都是：填 `sockaddr_in`，用 `(struct sockaddr *)` 强转传进去。不清零 `sin_zero` 是隐患。

### 7. server_addr 和 client_addr 的角色：一个是输入，一个是输出

| 变量 | 角色 | 数据方向 | 谁来填 |
|------|------|---------|--------|
| `server_addr` | 我方身份 / 发送目标 | 你 → 内核 | 自己填（bind 用） |
| `client_addr` | 对方身份（来电显示） | 内核 → 你 | `recvfrom` 帮你填 |

```c
recvfrom(socket_udp, buf, sizeof(buf), 0,
         (struct sockaddr *)&client_addr, &addrlen);  // 内核往盒子里填数据
printf("%s %d", inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
```

规律：**参数前带 `&` 的（client_addr、addrlen）基本都是内核要往回写的出参**。addrlen 传值进去告诉内核盒子多大，返回时被改写成实际长度。

### 8. 服务器回包：收到谁的消息，就回给谁

回包目标不要写死 IP:端口，直接用 `recvfrom` 拿到的 `client_addr`（它就是发送方的真实 IP:端口）。写死的问题：IP 会变；客户端用临时端口时找不到人；多客户端时没法区分。

前后对比：

```c
// 改前（错，从客户端代码复制来忘了改）
struct sockaddr_in clinet_addr;
clinet_addr.sin_addr.s_addr = inet_addr("192.168.172.83");  // 目标：服务器的 IP（注释都还是旧的）
clinet_addr.sin_port        = htons(6666);
sendto(sockfd, buf, sizeof(buf), 0, (struct sockaddr *)&clinet_addr, sizeof(clinet_addr));

// 改后（对）
sendto(sockfd, buf, strlen(buf) + 1, 0, (struct sockaddr *)&client_addr, addrlen);
```

### 9. sendto 的长度参数：sizeof 还是 strlen

`sendto(..., sizeof(buf), ...)` 会把整个 buf 发出去，包括 fgets 没填到的栈上垃圾。应该发实际长度，`+1` 把 `'\0'` 带上让对方能 `%s` 打印：

```c
sendto(sockfd, buf_send, strlen(buf_send) + 1, 0, ...);
```

### 10. 出错要退出，perror 不用加 \n

socket/bind 失败只 perror 不 return 的话，后面全是在废 socket 上空转。另外 perror 自带换行，里面写 `\n` 会空两行：

```c
if(ret == -1){
    perror("bind error");
    return -1;
}
```

## 三、踩的坑

1. `inet_network` 返回值直接赋 `s_addr`，IP 字节序全反，bind 报 `Cannot assign requested address` —— 坑在第 1、2 点。
2. 客户端填了地址结构体但没调 bind，以为端口是 6666，实际是内核随机分配的 48501 —— 坑在第 4 点。
3. 从客户端复制 sendto 代码到服务器忘了改目标地址，注释还写着"目标：服务器的 IP" —— 坑在第 8 点。
4. `sendto` 用 `sizeof(buf)` 发送，把栈上未初始化的垃圾一起发出去了 —— 坑在第 9 点。

---

# 9.5 笔记

## 干了什么

写了 6.条件变量.c：4 个售票窗口线程 + main 放票的生产者消费者模型。在 5.互斥锁.c 基础上踩完了条件变量的全套坑。

## 知识点

1. 互斥锁的饥饿问题（5.互斥锁.c 的"生产一边倒"现象）
   - `pthread_mutex_unlock` 只把等待者从睡眠队列挪到就绪队列（标记"可运行"），**并不让出 CPU**。
   - 解锁线程还在 CPU 上，立刻回到循环顶部重新 `lock`，锁空闲直接 CAS 成功——插队。
   - 刚被唤醒的线程要等调度才能真正执行到 lock，永远慢半步 → 一条线程饿死（一边倒生产/销售，num 减成负数）。
   - 结论：**默认 mutex 是非公平锁，锁管"别同时碰"，不管"按什么顺序碰"**。顺序/轮流问题要用信号量或条件变量。解锁后加 sleep 只是让出 CPU 掩盖竞争，治标不治本。

2. `pthread_cond_wait(&cond, &mutex)` 的调用契约（三步原子流程）
   - 必须在**已持有 mutex** 的状态下调用，否则未定义行为。
   - 内部：带着锁进入 → 原子地"解锁 + 睡眠入队" → 被唤醒后**自动重新持锁**再返回。
   - 它就是为"检查-等待"之间的窗口期设计的。

3. 醒来后必须重新检查：用 `while` 包住 wait，不能用 `if/else`
   ```c
   pthread_mutex_lock(&mutex);
   while(ticket_num <= 0){          // while 不是 if
       pthread_cond_wait(&cond, &mutex);
   }
   // 走到这里：已持锁 且 票数 > 0
   ticket_num--;
   pthread_mutex_unlock(&mutex);
   ```
   - 原因一：wait 可能虚假唤醒，且唤醒到拿锁之间条件可能又被改掉，必须复查。
   - 原因二：`cond_wait` 返回时**已自动持有锁**，`if/else` 结构会让程序走出 if 块回到循环顶部再次 `lock`——对自己已持有的普通锁重复加锁 = 自己锁死自己（死锁）。
   - `while` 版本回到 while 条件判断时不再加锁（锁在手里），无缝衔接。

4. 放票后必须手动唤醒：`pthread_cond_broadcast`（叫醒所有等待者）或 `pthread_cond_signal`（叫醒一个）
   - 条件变量等的是"通知"，不是"变量变化"。改变量不会自动唤醒任何人，忘发通知 = 全员永久阻塞。

5. 标准生产者消费者范式
   - 消费者：lock → `while(条件不满足) cond_wait` → 干活 → unlock。
   - 生产者：改共享数据要持锁；改完 unlock 再 broadcast。

## 踩的坑

1. 检查 `if(ticket_num <= 0)` 写在锁外面 → "检查-执行"竞态：检查时还有票，排队等锁期间票被卖光，拿到锁不复查直接减 → 卖出 -1、-2。检查必须进锁内。

2. 未持锁就裸调 `pthread_cond_wait` → 未定义行为（wait 内部要解锁一把自己没持有的锁）。必须先 `lock` 再 wait。

3. main 放完票（scanf 写入 ticket_num）没有 `broadcast` → 窗口全部阻塞在 wait 上，程序僵死。放票 = 持锁改变量 + 解锁 + broadcast。

4. 检查用 `if/else` 结构包 wait → 被 broadcast 唤醒后（自动持锁）走出 if 块回到循环顶重复 `lock`，自己锁死自己，输入放票数字后全场零反应。改成 `while` 包 wait。

5. 复制四个窗口函数时丢了 `while(1)` → 窗口 2/3/4 各卖一张就函数返回、线程退出，之后只剩窗口 1 独营（2 秒一张 = 锁内 sleep(1) + 锁外 sleep(1)）。广播唤醒不了已退出的线程。教训：重复代码抽成一个函数 + 参数传窗口号，别复制粘贴。

## 遗留认知

- `pthread_join(tid, NULL)` 写重复/漏传是常见笔误，第二个参数是线程返回值指针。
- scanf 直接裸写全局变量未持锁，碰巧无害但规范写法应持锁后再写。


# 9.4 笔记：线程的创建与退出（pthread_create / pthread_exit / pthread_join）

线程是系统调度资源的最小单位

进程是系统分配资源的最小单位

---

## 总结

- **wait()**：是**进程**的收尸工具。父进程等子进程退出，回收的是僵尸进程的 PCB 和退出码。
- **pthread_join()**：是**线程**的收尸工具。等同进程内的某条线程结束，回收它的栈资源 + `void*` 返回值。
- 两者道理相同：**退出后的残余必须有人来收**，进程不收就变僵尸，joinable 线程不被 join 栈就不释放——"线程级僵尸"。

---

### 详细对比表（背下这 4 点就够了）

| 对比维度 | **wait() (进程)** | **pthread_join() (线程)** |
| :--- | :--- | :--- |
| **1. 作用对象** | 子进程（默认等**任意**一个，waitpid 才能指定） | 同进程内**指定的那条**线程（必须传 tid） |
| **2. 回收什么** | 僵尸进程的 PCB、退出码 | 线程的栈空间、退出状态（`void*` 返回值） |
| **3. 产出形式** | `status`（要用 `WEXITSTATUS` 宏解析） | `retval`（直接拿到 `pthread_exit` 传的指针） |
| **4. 不收的后果** | 子进程变僵尸，占 PID 和进程表项 | joinable 线程的栈资源不释放 |

---

### 主线程"退出但不杀进程"

1. 执行 `main()` 的线程**本身就是主线程**，不用单独写"主线程函数"。
2. `main` 里 `return 0` = **整个进程结束**，所有线程陪葬。
3. 主线程想先走但让子线程活着，必须调 `pthread_exit(&val)`——只终止主线程，进程等最后一条线程退出才结束。

---

### 线程间传数据的两条通道（互不干扰）

1. **创建时传参通道**：`pthread_create` 第 4 参数传"变量的**地址**"（如 `&main_tid`），子线程用形参 `void *arg` 接住，按约定类型解引用还原：`*(pthread_t *)arg`。
2. **返回值通道**：主线程 `pthread_exit(&exit_val)` 把值挂在退出状态上 → 子线程 `pthread_join(main_tid, &retval)` 的**第 2 个参数**接回来。
3. `pthread_self()` 在 `main` 里调用，拿到的就是主线程自己的 tid，配合通道 1 传给子线程供它 join。

**代码模板**：

```c
void *task_fun(void *arg){
    pthread_t main_tid = *(pthread_t *)arg;   // 解引用还原 tid
    void *retval = NULL;
    pthread_join(main_tid, &retval);          // 接合主线程
    printf("主线程的退出值为%d\n", *(int *)retval);
    pthread_exit(NULL);
}

int main(){
    pthread_t thread_1;
    pthread_t main_tid = pthread_self();
    pthread_create(&thread_1, NULL, task_fun, &main_tid);  // 传地址！

    static int i = 0;   // 必须 static：主线程退出后栈失效
    while(i < 3){ i++; sleep(1); }
    pthread_exit(&i);   // 不是 return！
}
```

---

## 踩坑

1. **线程函数返回类型少写 `*`**：写成 `void task_fun(void *)`，`pthread_create` 第 3 参类型不匹配，报 `argument 3 from incompatible pointer type`。必须是 `void *task_fun(void *)`。
2. **第 4 参数硬传 `(void *)main_tid`**：tid 本质是整数（unsigned long），强转成指针是把整数伪装成地址，子线程一解引用就段错误。规矩：**想传谁的值就传谁的地址**，传值和解引用两头必须配套。
3. **返回值变量必须 static 或全局**：主线程退出后其栈失效，传局部变量地址是悬空指针，子线程 join 拿到的值不可靠。

---

## 易混淆

| 对比维度 | `return`（main 里） | `pthread_exit()`（main 里） |
| :--- | :--- | :--- |
| **终止范围** | 整个进程，所有线程陪葬 | 只有主线程自己 |
| **使用场景** | 真的要结束程序 | 主线程先退，把舞台留给子线程 |

| 对比维度 | joinable（默认） | detached（`pthread_detach`） |
| :--- | :--- | :--- |
| **退出后** | 资源保留，等别人 join | 资源自动回收 |
| **能否拿返回值** | 能（join 的 retval） | 不能 |
| **类比进程** | 需要父进程 wait 收尸 | 托给 init 自动收尸 |

---

# 9.2 笔记：signal 和 sigaction

## 总结

- **`signal()`**：是**远古时代的简易版**。它只管“**做什么**”（忽略/捕获/默认），但管不了“**怎么做**”（跨平台乱来，中间被打断不管）。
- **`sigaction()`**：是**现代工业的增强版**。它除了管“做什么”，还能精确控制“**做的时候要不要拦住别的信号**”和“**被中断后要不要自动重启**”。

---

### 详细对比表（背下这 4 点就够了）

| 对比维度 | **`signal()` (老式)** | **`sigaction()` (新式)** |
| :--- | :--- | :--- |
| **1. 参数形式** | **直接传参**。直接把函数名或 `SIG_IGN` 扔进去。<br>`signal(SIGINT, my_func);` | **填表上交**。需要先定义一个结构体变量 `sa`，把“干法”填进 `sa.sa_handler`，再把表（`&sa`）传给内核。 |
| **2. 最大的坑（可靠性）** | **行为不一致（致命伤）**。在旧的 System V 系统上，信号处理函数执行完后，系统会自动把处理方式重置为默认。导致**第一次按 Ctrl+C 能捕获，第二次按进程就直接崩溃**。 | **绝对可靠**。注册一次永久生效，永远不会自动重置，所有 Linux/Unix 系统行为完全统一。 |
| **3. 控制能力** | **几乎没有**。无法控制在执行 `my_func` 期间，如果来了其他信号该怎么办。 | **极其精细**。通过 `sa_mask`（屏蔽集）可以指定：“在执行我的函数期间，把 `SIGQUIT` 给我拦住，处理完再放行”。 |
| **4. 获取旧的处理方式** | **靠返回值**。`signal()` 执行后会返回旧的函数指针，你需要用一个变量去接。 | **靠参数指针**。通过第 3 个参数 `oldact` 把旧的设置吐出来。不需要就填 `NULL`（这就是我让你写 NULL 的原因）。 |

---

### 用生活中的“点外卖”来理解

- **`signal()`**：你给外卖员打电话说：“**把餐放门口**”。（说完就挂了，没留备注。外卖员可能放门口就走了，也可能下次不按你说的做）。
- **`sigaction()`**：你在外卖 APP 上**填了一张详细的备注单**。单子上不仅写着“把餐放门口”（`sa_handler`），还勾选了“**外卖员按门铃时，请勿打扰**”（`sa_mask` 屏蔽其他信号），并勾选了“**如果我没接电话，自动重拨**”（`sa_flags` 里的 `SA_RESTART`）。这张单子交上去，系统会严格执行，绝不会变。

---

### 结论

1. **现在学 `signal()` 绝对没有错**，因为它语法最简单，能帮你把“捕获、忽略、默认”这三个概念跑通。**这相当于先学会开自动挡汽车**。
2. **等彻底搞懂了逻辑，直接套用“三要素模板”换成 `sigaction()`**。会发现，除了多写 3 行固定的“套话”（定义结构体、清空屏蔽、flags 置 0），本质上**填的 `sa.sa_handler` 和你之前写的 `signal()` 第二个参数是完全一样的**。**这相当于从自动挡升级到手动挡，但方向盘和油门刹车位置没变**。

---

## 补充：两个重点信号 SIGCHLD 与 SIGKILL

### 先搞懂信号到达后的两种走法

1. **普通信号**（如 SIGINT、SIGUSR1）：内核先查进程有没有注册处理函数——有就跳去执行用户代码，没有才执行默认动作。
2. **特例信号**（SIGKILL、SIGSTOP，仅此两个）：内核根本不走用户注册的那套流程，直接由内核执行默认动作。

### SIGCHLD（17 号）：服务器的"收尸通知单"

**是什么**：子进程终止时，内核向其父进程发送的通知信号。

**为什么服务器必须处理它**（fork 型 TCP 服务器场景）：

1. 子进程退出后不会凭空消失，会变成**僵尸进程（zombie）**——内核保留它的退出状态，等父进程调 `wait`/`waitpid` 来"收尸"。
2. 服务器长期运行，子进程源源不断退出。父进程不能一直阻塞在 `waitpid` 上（它还要 `accept` 新连接）。
3. 内核用 SIGCHLD 通知父进程"有子进程死了"，父进程在处理函数里循环 `waitpid(-1, NULL, WNOHANG)` 一次收干净。
4. 不处理的后果：僵尸越积越多，占满 PID 和内核进程表项。
5. 僵尸进程用 `ps -ef` 看得到：进程名后面带 `<defunct>` 标记，状态是 `Z`。它不占内存、不占 CPU，只占一个 PID 和进程表项，用 `kill -9` 也杀不掉（它已经死了，就差父进程收尸）。真正能清掉它的办法：让父进程收尸，或者父进程自己退出后僵尸被 init 接管收走。

**代码模板**（结合 sigaction）：

```c
#include <sys/wait.h>

void child_reap(int sig){
    // 循环 + WNOHANG：把本次所有已退出的子进程全部回收，没有就立刻返回
    while(waitpid(-1, NULL, WNOHANG) > 0);
}

// main 中注册：
struct sigaction sa;
sa.sa_handler = child_reap;
sigemptyset(&sa.sa_mask);
sa.sa_flags = 0;
sigaction(SIGCHLD, &sa, NULL);
```

### SIGKILL（9 号）：内核的"强制处决通道"

**是什么**：管理员强制终止进程的最终手段（`kill -9`）。

**为什么自定义处理对它无效**：

1. SIGKILL 和 SIGSTOP 是仅有的两个**不可捕获、不可忽略、不可屏蔽**的信号——`signal(SIGKILL, handler)` 注册的函数永远不会被调用，`sigprocmask` 也拦不住。
2. 处理逻辑直接写在内核里，进程的用户代码没有任何说话的机会。
3. 这是**故意设计**的：如果允许进程自定义 SIGKILL 响应，失控或恶意进程就能"免疫"一切清除手段，管理员对它毫无办法。内核留这条通道，保证 root 总能杀掉任何进程（init 除外）。

**踩坑**：状态为 D（不可中断睡眠，通常是磁盘 IO 卡死）的进程连 SIGKILL 都"杀不死"——不是信号没用，是进程没机会处理任何信号，只能等 IO 返回或重启机器。

**易混淆**：SIGSTOP（19 号）不可捕获，但 SIGTSTP（20 号）可以——终端按 Ctrl+Z 发的是 SIGTSTP，所以程序能自己捕获"挂起"信号做清理，而 `kill -19` 发的 SIGSTOP 拦不住。两者效果都是暂停进程（状态 T），恢复都用 SIGCONT。

### 对比表

| 对比维度 | SIGCHLD (17) | SIGKILL (9) |
| :--- | :--- | :--- |
| **谁发出** | 内核（子进程终止时，自动发给父进程） | 用户/管理员（kill -9） |
| **可否自定义处理** | 可以，且**应该**处理 | 完全不行，内核强制默认动作 |
| **可否捕获/屏蔽** | 可以 | 三条路全堵死 |
| **不处理的后果** | 子进程变僵尸，进程表耗尽 | 无（它就是拿来杀进程的） |
| **典型用途** | 通知父进程回收子进程，防僵尸 | 强制终止失控进程的最后手段 |

---

# 9.1 笔记：链表哑节点（Dummy Node）

LeetCode 链表题最强工具，速查卡。

## 1. 核心心法（一句话）

**用空间换逻辑统一**：在头节点前面安插一个"傀儡前驱"，让头节点变成普通节点，消灭所有 `if (head == NULL)` 和 `if (插入头部)` 特判。

## 2. 起手式（肌肉记忆，先写这 3 行）

```c
Node dummy;          // 栈上分配（不用 free，函数结束自动回收）
dummy.next = head;   // 挂在原链表前面
Node *prev = &dummy; // 遍历指针永远从哑节点出发
```

**为什么最后 `return dummy.next` 而不是 `return head`**：插入可能发生在头部、头节点也可能被删掉，`head` 已经不可信，`dummy.next` 永远指向真正的新头。

## 3. 四大经典场景代码模板

### 3.1 升序插入（统一操作）

无论空链表、插头、插尾，代码完全一样。

```c
while (prev->next != NULL && prev->next->data < value) {
    prev = prev->next;          // 找位置
}
new_node->next = prev->next;    // 插入
prev->next = new_node;
return dummy.next;              // 返回新头
```

**死穴**：条件必须用 `&&`（与）。用 `||`（或）会在尾节点处访问 `NULL->data` 造成段错误。

### 3.2 删除单个节点

```c
while (prev->next != NULL && prev->next->data != value) {
    prev = prev->next;          // 找目标
}
if (prev->next != NULL) {
    Node *tmp = prev->next;     // 保存
    prev->next = tmp->next;     // 绕过
    free(tmp);                  // 释放
}
return dummy.next;
```

### 3.3 删除全部匹配节点（连续重复陷阱）

**关键区别**：删除后 `prev` **原地不动**（不走 `prev = prev->next`），否则会漏删连续重复节点。

```c
while (prev->next != NULL) {
    if (prev->next->data == value) {
        Node *tmp = prev->next;
        prev->next = tmp->next;
        free(tmp);
        // 核心：这里绝对不移动 prev！让 prev 站在原地审问新来的后继
    } else {
        prev = prev->next;      // 只有当节点安全时，才向前移动
    }
}
return dummy.next;
```

### 3.4 删除正数第 K 个（边界检查）

```c
for (int i = 0; i < k - 1; i++) {
    if (prev->next == NULL) return head; // 防崩溃：K 超出链表长度
    prev = prev->next;
}
if (prev->next == NULL) return head;     // 再次确保要删的节点存在
// 执行删除（保存、绕过、释放）...
return dummy.next;
```

## 4. 常用错误汇总（防坑指南）

| 常见错误 | 后果 | 正确姿势 |
| --- | --- | --- |
| `while` 用了 `\|\|` | 访问空指针，段错误 | 必须用 **`&&`**（短路求值） |
| 删除全部时移动了 `prev` | 跳过下个节点，漏删 | **不移动**，原地审问新后继 |
| 没检查 K / N 是否越界 | 指针变成 `NULL` 后崩溃 | 循环内加 `if (prev->next == NULL)` |
| 对 `void*` 做加法 | 编译警告 / 标准 C 禁止 | 强转 `char*` 再偏移 |

## 5. 记忆口诀

> 链表开头安哑点，头尾中间都等闲。
> 删除节点脚别动，连续重复不漏删。
> while 里用与不用或，短路求值保平安。

## 6. 补充：哑节点 vs 不用哑节点

| 对比项 | 不用哑节点 | 用哑节点 |
| --- | --- | --- |
| 插入头部 | 需要特判 `if (head == NULL \|\| value < head->data)` | 与插中间完全相同 |
| 删除头节点 | 需要特判并更新 head | prev 从 dummy 出发，统一处理 |
| 返回值 | head 可能被改，逻辑分散 | 永远 `return dummy.next` |
| 代码量 | 每个操作多一段特判 | 模板统一，不容易漏边界 |

