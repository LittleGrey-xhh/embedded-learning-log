# 嵌入式学习日记

# 系统 IO 学习笔记（2026-08-13）

## 一、LCD屏幕

### 帧缓冲(Framebuffer)

1.定义：

在Linux系统下是利用`Framebuffer`子系统来驱动显示设备的，所以`Framebuffer`子系统会读取LCD屏的硬件信息并存储在内核空间中，关于LCD的硬件参数都是定义在`/usr/include/linux/fb.h`头文件中。

通过`fb.h`可以看到头文件中存在三个比较重要的结构体，分别是`struct fb_fix_screeninfo`以及`struct fb_var_screeninfo`以及`struct fb_bitfield`，除了这三个结构体之外，可以发现头文件中存在大量的宏定义，用户可以通过这些宏定义来指定读取LCD的部分信息。

2.struct fb_fix_screeninfo结构体：

`struct fb_fix_screeninfo`结构体主要用于获取`FrameBuffer`的固定参数，用户无法在应用层修改这些参数，只能通过系统调用`ioctl`函数使用宏定义`FBIOGET_FSCREENINFO`去获取这些参数。

3.struct fb_var_screeninfo结构体：

`struct fb_var_screeninfo`结构体主要用于获取和设置`FrameBuffer`的可变屏幕参数，包括分辨率、像素位深、像素格式等。这些信息可以通过`ioctl`函数使用宏定义`FBIOGET_VSCREENINFO`获取，也可以通过宏定义`FBIOPUT_VSCREENINFO`修改。

---

### 文件控制

Linux系统提供了一个`ioctl`（input/outputcontrol）函数，该函数是一个专用于设备输入输出操作的系统调用，该调用传入一个跟设备有关的请求码，系统调用的功能完全取决于请求码（FBIOGET_VSCREENINFO）。

追加：
参数不是"本来就有"的。`struct fb_var_screeninfo lcd_into;` 这一句只是给变量分配了一块内存，里面全是垃圾值/零，什么都还没有。

`ioctl(fd_lcd, FBIOGET_VSCREENINFO, &lcd_into)` 的机制是：你把空表的地址（`&lcd_into`）递给内核，内核去读取 LCD 驱动的硬件配置，把结果写进这张表再返回。内核才是填表的人，你只是递了张空表过去。

个人理解：
所以说`ioctl`就是一个加工厂，拿着`fd_lcd`这个门牌号（原材料从哪里来），`FBIOGET_VSCREENINFO`（要对原材料干什么，怎么加工），`&lcd_into`（干完谁来收货），我这么理解对吗？

ds回答：
比喻贴切，方向也抓对了——**fd 是"哪台设备"、命令是"干什么"、第三个参数是"数据放哪/从哪拿"**。但我要给你补一个关键概念：**方向**。ioctl 的命令分两类，方向正好相反：

- **GET 类**（问信息）：内核 → 你。工厂加工完把货给你。`FBIOGET_VSCREENINFO` 就是这类，你的比喻完全成立。
- **SET 类**（下命令）：你 → 内核。你送配置进去，内核去配置硬件。工厂按你的图纸开工。

### framebuffer 常用 ioctl（你最该记住的这组）

| 命令 | 干什么 | 方向 |
|---|---|---|
| `FBIOGET_VSCREENINFO` | 获取可变参数：**分辨率、色深** | 内核→你（你已会用） |
| `FBIOGET_FSCREENINFO` | 获取固定参数：**line_length（行字节数）、smem_len（显存大小）** | 内核→你（我们代码用过，拿 line_length） |
| `FBIOPUT_VSCREENINFO` | **设置**分辨率、色深（驱动层改屏幕配置） | 你→内核 |
| `FBIOPAN_DISPLAY` | 设置显示起始偏移（实现画面滚动、双缓冲切换） | 你→内核 |
| `FBIO_WAITFORVSYNC` | 等待屏幕刷完一帧（写图前等它，**防画面撕裂**） | 你→内核 |

对应的模式都长一个样：

```c
struct fb_var_screeninfo vinfo;              // 空表
ioctl(fd, FBIOGET_VSCREENINFO, &vinfo);      // GET：内核填表
// 改配置后再写回
vinfo.xres = 1024;
ioctl(fd, FBIOPUT_VSCREENINFO, &vinfo);      // SET：你递表，内核执行
```

### 其他设备也各有一堆 ioctl

| 设备 | 常用命令 | 用途 |
|---|---|---|
| 终端 tty | `TCGETS` / `TCSETS` | 获取/设置串口终端参数（波特率、回显开关） |
| RTC 时钟 | `RTC_RD_TIME` / `RTC_SET_TIME` | 读/写硬件实时时钟 |
| 网卡 | `SIOCGIFADDR` | 获取网卡 IP 地址 |
| 磁盘 | `BLKGETSIZE64` | 获取磁盘大小（字节数） |
| 摄像头 V4L2 | `VIDIOC_QUERYCAP` / `VIDIOC_S_FMT` | 查询能力、设置采集格式 |

规律看出来了没？**所有 ioctl 都是三件套：`ioctl(fd, 命令, 数据地址)`**。不同的只是：

- `fd` 换成不同的设备文件
- 命令宏换成那个设备定义的那组
- 数据地址换成对应的结构体

---

### 大体步骤

1. 打开LCD设备文件`open`
2. 获取LCD设备信息`ioctl`
3. 申请内存映射`mmap`
4. 操作映射后的内存空间
5. 解除映射，关闭文件

---

### 具体实现

1.按字节拼小端整数

```c
static unsigned int le32(const unsigned char *p){
    return (unsigned)p[0] | ((unsigned)p[1] << 8)
         | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24);
}
```

2.open读.bmp图片参数

```c
// 1.打开bmp，读54字节头
    int fd_bmp = open("/root/feibi.bmp", O_RDONLY);
    if(fd_bmp == -1){ perror("open bmp fail"); return -1; }

    unsigned char header[54];
    if(read(fd_bmp, header, 54) != 54){ perror("read header"); close(fd_bmp); return -1; }
    if(header[0] != 'B' || header[1] != 'M'){ printf("not bmp\n"); close(fd_bmp); return -1; }

    unsigned int img_w = le32(header + 18);   // 图片宽
    unsigned int img_h = le32(header + 22);   // 图片高
    unsigned int offset = le32(header + 10);  // 像素数据偏移
    printf("bmp: %ux%u\n", img_w, img_h);
```

3.open拿到LCD的门牌号,
定义结构体空表lcd_into，
用ioctl向内核拿到LCD参数后填表

```c
// 2.打开LCD + mmap（屏幕大小，用 lcd_into）
    int fd_lcd = open(LCD_PATH, O_RDWR);
    if(fd_lcd == -1){ perror("open lcd fail"); return -1; }

    struct fb_var_screeninfo lcd_into;
    if(ioctl(fd_lcd, FBIOGET_VSCREENINFO, &lcd_into) == -1){
        perror("ioctl fail"); return -1;
    }
```

4.内存映射

```c
int *lcd_p = mmap(NULL, lcd_into.xres * lcd_into.yres * 4,
                      PROT_READ | PROT_WRITE, MAP_SHARED, fd_lcd, 0);
    if(lcd_p == MAP_FAILED){ perror("mmap fail"); return -1; }
```

5.申请内存、读像素、转换、倒序拷贝（接续上段，同一 main 函数的剩余部分）

```c
    // 按图片大小申请内存（不是屏幕大小！）
    unsigned char *bmp_buf = (unsigned char *)malloc(img_w * img_h * 3);
    int *lcd_buf = (int *)malloc(img_w * img_h * 4);
    if(!bmp_buf || !lcd_buf){ printf("malloc fail\n"); return -1; }

    // 跳到像素数据（用文件头的 offset，不写死 54）
    lseek(fd_bmp, offset, SEEK_SET);
    read(fd_bmp, bmp_buf, img_w * img_h * 3);

    // 4.转换：循环用图片像素数
    for(unsigned int i = 0; i < img_w * img_h; i++){
        lcd_buf[i] = 0xFF000000u | bmp_buf[i*3] | bmp_buf[i*3+1] << 8 | bmp_buf[i*3+2] << 16;
    }

    // 5.倒序拷贝：源行按图片宽，目标行按屏幕宽
    for(unsigned int y = 0; y < img_h && y < lcd_into.yres; y++){
        memcpy(&lcd_p[y * lcd_into.xres],       // 屏幕第 y 行
               &lcd_buf[(img_h - 1 - y) * img_w],  // 图片第 (img_h-1-y) 行
               img_w * 4);                      // 一次拷图片的一整行
    }

    // 6.收尾
    free(bmp_buf);
    free(lcd_buf);
    munmap(lcd_p, lcd_into.xres * lcd_into.yres * 4);
    close(fd_lcd);
    close(fd_bmp);
    return 0;
}
```

---

## 二、关键概念（为什么这么写）

### 1. 大小端（字节序）—— 为什么要有 le32

- BMP 文件存**多字节整数**时用**小端**：低位字节在前。
- 例：宽度 800 = 0x00000320，文件里 4 个字节是 `20 03 00 00`（低字节 0x20 在最前面）。
- `le32` 把 4 个字节按小端顺序拼回整数：`p[0] | p[1]<<8 | p[2]<<16 | p[3]<<24`。
- 拼错（按书写习惯大端拼）会把 800 读成 0x20030000（5 亿多），直接崩。
- **字节序只影响多字节整数**；像素数据是按字节排的 BGR 流，与字节序无关，不用转换。
- `le32` 正好读 4 字节 = int 宽度，不多不少，不用裁剪；读 2 字节字段用 `le16`。

### 2. BMP 文件头结构（54 字节）

| 偏移 | 内容 | 代码读取 |
|---|---|---|
| 0~1 | 'B' 'M' 文件类型标识 | 校验，不是就报错退出 |
| 10~13 | 像素数据偏移 offset | `le32(header + 10)` |
| 18~21 | 图片宽度 | `le32(header + 18)` |
| 22~25 | 图片高度 | `le32(header + 22)` |
| 28~29 | 色深 bpp | `le16(header + 28)` |

- 为什么要用 `offset` 而不是写死 54：文件头不总是 54 字节（可能带调色板、扩展头），offset 是文件自己声明的像素数据真实位置，永远准确。
- 注意：`header[18]~[21]` 只是"宽度"这个数的 4 个零件，不是宽度本身；`le32` 是把零件按小端顺序组装成完整数值。

### 3. 像素格式转换：BGR → ARGB8888

- BMP 24bpp 每个像素 3 字节，顺序是 **B G R**；LCD 32bpp 每个像素 4 字节，顺序是 **A R G B**。
- 转换核心：`0xFF000000u | b<<0 | g<<8 | r<<16`（R 与 B 交换位置，前面补 A）。
- `0xFF` 是 A 通道（不透明）。不补时 A=0，部分驱动会黑屏；自己的屏恰好忽略 A 所以能显示，但标准写法要补。

### 4. BMP 自底向上 → 倒序拷贝

- BMP 文件第一行 = 图片**最底行**（bottom-up 存储）。
- 屏幕第 0 行要显示图片最顶行 = 文件的最后一行。
- 所以 `lcd_p[y * 屏幕宽] ← lcd_buf[(高-1-y) * 图片宽]`，y 正序走、行号倒着取。
- 坐标系理解：屏幕坐标 y 与文件行号 (高-1-y) 一一镜像，**翻转只发生在 y 轴，x 轴原样搬运**。

### 5. mmap 原理与六参数

为什么用 mmap：`read/write` 要经过内核缓冲区两次拷贝；mmap 把 LCD 显存（物理内存）直接映射进进程虚拟地址空间，`lcd_p` 指向显存本身——写数组 = 写显存 = 改屏幕，零拷贝。

| 参数 | 代码 | 含义 |
|---|---|---|
| addr | NULL | 让内核自己选地址 |
| length | xres * yres * 4 | 映射大小 = 像素数 × 每像素 4 字节 |
| prot | PROT_READ \| PROT_WRITE | 权限：可读可写 |
| flags | MAP_SHARED | 共享映射，改动直接回写设备 |
| fd | fd_lcd | 映射哪个设备 |
| offset | 0 | 从设备开头映射 |

- 套路固定、数值不固定：length 按资源大小，fd 按对象，权限按需求。

### 6. ioctl 填表机制（补充）

- 定义结构体只是准备**空表**，`ioctl` 让内核读硬件参数填进表里返回。
- GET 类（内核 → 你，问信息）vs SET 类（你 → 内核，下命令）。
- 万能三件套：`ioctl(fd, 命令宏, 数据地址)`，换设备就换 fd 和命令宏。

---

## 三、常见坑总结（必背）

1. 没跳过 BMP 文件头 → 整张图错位（用 `lseek(fd_bmp, offset, SEEK_SET)`）
2. `char` 有符号 → 像素 >127 颜色错乱，必须 `unsigned char`
3. 没补 A 通道 → 可能黑屏（标准写法 `0xFF000000u |`）
4. BMP 自底向上没倒序 → 图上下颠倒
5. 栈上大数组（2.6MB）→ 嵌入式栈小，改用 `malloc` + `free`
6. 分辨率写死 → 图片宽高从 BMP 头读（img_w/img_h），屏幕大小从 lcd_into 读（xres/yres），各归其位

---

## 四、完整代码（通用版：图片多大都能显示，不超屏即可）

```c
#include <fcntl.h>
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/fb.h>

#define LCD_PATH "/dev/fb0"

// 按字节拼小端整数，免疫字节序
static unsigned int le32(const unsigned char *p){
    return (unsigned)p[0] | ((unsigned)p[1] << 8)
         | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24);
}

int main(){
    // 1.打开bmp，读54字节头
    int fd_bmp = open("/root/feibi.bmp", O_RDONLY);
    if(fd_bmp == -1){ perror("open bmp fail"); return -1; }

    unsigned char header[54];
    if(read(fd_bmp, header, 54) != 54){ perror("read header"); close(fd_bmp); return -1; }
    if(header[0] != 'B' || header[1] != 'M'){ printf("not bmp\n"); close(fd_bmp); return -1; }

    unsigned int img_w = le32(header + 18);   // 图片宽
    unsigned int img_h = le32(header + 22);   // 图片高
    unsigned int offset = le32(header + 10);  // 像素数据偏移
    printf("bmp: %ux%u\n", img_w, img_h);

    // 2.打开LCD + mmap（屏幕大小，用 lcd_into）
    int fd_lcd = open(LCD_PATH, O_RDWR);
    if(fd_lcd == -1){ perror("open lcd fail"); return -1; }

    struct fb_var_screeninfo lcd_into;
    if(ioctl(fd_lcd, FBIOGET_VSCREENINFO, &lcd_into) == -1){
        perror("ioctl fail"); return -1;
    }

    int *lcd_p = mmap(NULL, lcd_into.xres * lcd_into.yres * 4,
                      PROT_READ | PROT_WRITE, MAP_SHARED, fd_lcd, 0);
    if(lcd_p == MAP_FAILED){ perror("mmap fail"); return -1; }

    // 3.按图片大小申请内存（不是屏幕大小！）
    unsigned char *bmp_buf = (unsigned char *)malloc(img_w * img_h * 3);
    int *lcd_buf = (int *)malloc(img_w * img_h * 4);
    if(!bmp_buf || !lcd_buf){ printf("malloc fail\n"); return -1; }

    // 跳到像素数据（用文件头的 offset，不写死 54）
    lseek(fd_bmp, offset, SEEK_SET);
    read(fd_bmp, bmp_buf, img_w * img_h * 3);

    // 4.转换：循环用图片像素数
    for(unsigned int i = 0; i < img_w * img_h; i++){
        lcd_buf[i] = 0xFF000000u | bmp_buf[i*3] | bmp_buf[i*3+1] << 8 | bmp_buf[i*3+2] << 16;
    }

    // 5.倒序拷贝：源行按图片宽，目标行按屏幕宽
    for(unsigned int y = 0; y < img_h && y < lcd_into.yres; y++){
        memcpy(&lcd_p[y * lcd_into.xres],       // 屏幕第 y 行
               &lcd_buf[(img_h - 1 - y) * img_w],  // 图片第 (img_h-1-y) 行
               img_w * 4);                      // 一次拷图片的一整行
    }

    // 6.收尾
    free(bmp_buf);
    free(lcd_buf);
    munmap(lcd_p, lcd_into.xres * lcd_into.yres * 4);
    close(fd_lcd);
    close(fd_bmp);
    return 0;
}
```

---

# 系统 IO 学习笔记（2026-08-10）

## 一、两套 IO API（分清层级）

| 层级 | 函数 | 返回类型 | 惯用命名 | 特点 |
|---|---|---|---|---|
| 系统调用 | open / read / write / close / lseek | `int fd` 文件描述符 | `fd` | 无缓冲，直接跟内核打交道 |
| 标准库 | fopen / fread / fprintf / fgets / fclose | `FILE *fp` 流指针 | `fp` | 带缓冲，是系统调用的封装 |

- `fopen` 内部就是 `open` + 一层缓冲 + 格式化工具；`fileno(fp)` 可取出底层 fd
- 命名约定：**open 配 fd，fopen 配 fp**，一眼分清用的是哪套
- 应用场景：普通文件读写用 stdio；网络、管道、文件锁、非阻塞、fcntl/ioctl 必须用系统调用

## 二、核心概念

### 1. 文件偏移（重点中的重点）
- 偏移存在**内核的"打开文件描述"里，不在 C 变量里**
- `read`/`write` 每次自动推进偏移；read 是"消费品"，读走就没了
- **想有独立偏移只有一条路：重新 `open`**（函数/局部变量隔离不了，形参只是复制"门牌号"）
- `dup` 复制的 fd 共享偏移

### 2. 覆盖写 vs 清空重写
- `lseek` 管"写到哪"（position）；`O_TRUNC`/`ftruncate` 管"文件多长"（length）——两个维度
- `lseek(0) + write` = 从开头覆盖 N 字节，**尾部旧数据残留**
- `O_TRUNC + write` = 先清空再写，无残留
- 经验：改文件中间某段用 lseek；整个重写用 O_TRUNC

### 3. EOF 与 '\0'（字符串思维 vs 文件思维）
- `read` 返回 **0 = EOF**（靠文件系统记录的长度判断，不靠 '\0'）；**-1 = 出错**
- 文件是字节序列不是字符串，不需要 '\0' 结尾
- '\0' 只是内存字符串函数（`%s`/`strlen`）的约定
- **`read` 不自动补 '\0'**，要用字符串处理必须手动 `buf[len] = '\0'`

## 三、分块拷贝模板（背下来）

```c
char buf[1024];
int len;
while ((len = read(fd, buf, sizeof(buf))) > 0) {   // 括号必须包住赋值！
    if (write(fd2, buf, len) != len) {             // 检查 write 是否写全
        perror("write");
        break;
    }
}
if (len == -1) perror("read");
```

- 每次最多搬 1024 字节，最后一块可能不足
- 写 `len` 而不是 `sizeof(buf)`，否则尾部塞垃圾
- 读文件的循环中间**绝对不能插任何别的 read**（会消费偏移）

## 四、今天踩过的坑（复习清单）

1. **open 失败不 return** → 拿 -1 fd 继续操作 → read 返回 -1 → 甚至 `buf[-1]` 越界写
2. **read 后不补 '\0' 就 %s 打印** → 越界读到垃圾/乱码
3. **调试 read 插在拷贝循环中间** → 偏移被偷吃，拷贝为空或丢内容
4. **优先级 bug：`len = read(...) > 0`** → 实际是 `len = (read(...) > 0)`，len 变 0/1，每次只写 1 字节
5. **函数返回局部数组指针** → 悬空指针，栈已回收
6. **`open("name")` 字面量 vs 参数 `name`** → 打开的文件叫 "name"
7. **目标文件缺 `O_CREAT`**（不存在打不开）/ **缺 `O_TRUNC`**（旧数据残留）
8. **权限**：文件用 `0644`（`0755` 是给目录的）；源文件用 `O_RDONLY`
9. **资源管理**：谁打开谁负责 close；fd 可 return 跨函数传递，但没人 close 就是泄漏（`ulimit -n` 限制）
10. **失败处理**：打印错误后必须 `return`，不能"打印完假装没事"

## 五、遗留提醒

- 拷贝循环里 `printf("%s", buf)` 打印内容仍有隐患（源文件 ≥1024 字节时 buf 无 '\0'），调试建议只打印字节数
- `perror()` 比 `printf("失败\n")` 有用，能打出具体错误原因

## 六、完整无误的示例代码（文件拷贝）

```c
#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>

// 打印文件前 1023 字节的内容（独立 open，不影响其他 fd 的偏移）
void printFile(const char *name) {
    int fd = open(name, O_RDONLY);          // 只读打开
    if (fd == -1) {
        perror("open");
        return;                              // 失败立刻退出
    }
    char buf[1024];
    int len = read(fd, buf, sizeof(buf) - 1);   // 留一位放 '\0'
    if (len == -1) {
        perror("read");
        close(fd);
        return;                              // 失败立刻退出
    }
    buf[len] = '\0';                         // read 不补 '\0'，手动加
    printf("%s 的内容是 %s\n", name, buf);
    close(fd);
}

int main() {
    // 源文件：只读打开
    int fd = open("源文件.txt", O_RDONLY);
    if (fd == -1) {
        perror("open 源文件");
        return 1;
    }

    // 目标文件：只写 + 不存在则创建 + 先清空，权限 0644
    int fd2 = open("目标文件.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd2 == -1) {
        perror("open 目标文件");
        close(fd);
        return 1;
    }

    printFile("源文件.txt");      // 拷贝前看一眼（目标文件已被 O_TRUNC 清空）
    printFile("目标文件.txt");

    // 分块拷贝：read 最多搬 1024 字节，读到 EOF（返回 0）结束
    char buf[1024];
    int len, i = 0;
    while ((len = read(fd, buf, sizeof(buf))) > 0) {   // 括号必须包住赋值
        if (write(fd2, buf, len) != len) {   // 检查 write 是否写全
            perror("write");
            break;
        }
        printf("第 %d 次拷贝 %d 字节\n", ++i, len);   // 只打印长度，不打印内容
    }
    if (len == -1) perror("read");           // read 出错

    close(fd);
    close(fd2);

    printFile("源文件.txt");      // 拷贝后验证
    printFile("目标文件.txt");
    return 0;
}
```

---

# 8.6-8.8 项目笔记

## 进阶知识

### snprintf

`snprintf` 和 `printf` 的核心区别在于**输出目标**和**安全性**。它们共享同一套格式化语法（`%d`, `%s` 等），但用途完全不同。

### 核心对比

| 特性 | `printf` | `snprintf` |
| :--- | :--- | :--- |
| **输出目标** | 标准输出（终端/控制台） | 内存中的字符缓冲区 (`char *buffer`) |
| **边界检查** | ❌ 无 | ✅ 有，通过 `size` 参数限制 |
| **缓冲区溢出风险** | 不涉及（直接输出到流） | ✅ 安全，最多写 `size-1` 个字符并补 `\0` |
| **返回值含义** | 成功打印的字符数，失败返回负值 | **空间足够时**：实际写入字符数；**空间不足时**：*本应写入*的完整长度（用于检测截断） |
| **典型用途** | 向用户显示信息、调试输出 | 字符串拼接、格式化存入变量、构建协议报文 |
| **函数原型** | `int printf(const char *fmt, ...)` | `int snprintf(char *buf, size_t size, const char *fmt, ...)` |

### 直观示例

```c
// printf → 直接打印到终端
printf("Score: %d\n", 95);
// 终端显示: Score: 95

// snprintf → 格式化结果存入 buffer
char msg[32];
snprintf(msg, sizeof(msg), "Score: %d", 95);
// msg 的内容是 "Score: 95"，后续可以存数据库、发网络、再拼接等
```

### 为什么不能互相替代？

-   **不能用 `printf` 代替 `snprintf`**：`printf` 无法将格式化结果保存到变量中。如果你需要把格式化后的字符串存起来再用，`printf` 做不到。
-   **不能用 `snprintf` 代替 `printf`**：虽然你可以 `snprintf(buf, sizeof(buf), ...)` 然后再 `puts(buf)`，但这多了一次不必要的内存拷贝。直接输出到终端的场景，`printf` 更高效。

### ⚠️ 容易混淆的相关函数

| 函数 | 输出目标 | 安全 | 备注 |
| :--- | :--- | :--- | :--- |
| `printf` | stdout | — | 终端输出 |
| `fprintf(fp, ...)` | 指定文件流 | — | `printf` 的文件版 |
| `sprintf(buf, ...)` | 缓冲区 | ❌ **不安全** | 🚫 永远别用，无边界检查 |
| `snprintf(buf, size, ...)` | 缓冲区 | ✅ 安全 | `sprintf` 的安全替代 |

> 💡 **一句话总结**：
> -   要**显示给用户看** → 用 `printf`
> -   要**存到字符串变量里** → 用 `snprintf`
> -   **永远不要用 `sprintf`**

---


# 8.4笔记

### 知识点

- 链式栈通过单链表的**头插**和**头删**实现后进先出（LIFO）。
- 利用**指针参数作为输出参数**，可以在函数返回 `bool` 状态的同时向外传递数据。
- `*out_val = tmp->data` 是解引用输出参数，将栈顶数据写入调用者的变量；这必须在 `free(tmp)` 前完成。
- 输出参数允许为 `NULL`，调用者传 `NULL` 表示只删除元素、不需要数据；函数内必须进行 `if(out_val != NULL)` 检查，避免空指针解引用导致段错误。

### 踩过的坑

- **直觉误区**：想当然地认为 `Pop` 只需要返回成功/失败，导致栈顶数据永久丢失，无法使用弹出的值。  
- **语法困惑**：看到 `*out_val = tmp->data` 时，不明白为什么要对 `out_val` 解引用，误以为直接写 `out_val = tmp->data` 就能把数据传出去。  
- **空指针忽略**：起初没想过调用者可能不需要数据而传 `NULL`，若不加判断就解引用会导致程序崩溃；是在讨论防御性编程时才意识到这个隐患。

### 正确做法

```c
// 函数声明
bool LinkedStack_Pop(Manager_t *manager, DataType_t *out_val);

// 实现核心部分
Node_t *tmp = manager->first;          // 1. 保存栈顶节点
if (out_val != NULL) {                 // 2. 调用者需要数据时才写入
    *out_val = tmp->data;
}
manager->first = manager->first->next; // 3. 更新栈顶
free(tmp);                             // 4. 释放原节点（必须先取数据再释放）
```

核心思路：**用指针参数做输出，先取值后释放，调用者可控是否需要该值。**

---

# 8.3笔记

## 栈 vs 单链表 vs 顺序表：三个层面的本质区别

| 比较维度 | 栈 (Stack) | 顺序表 (SeqList) | 单链表 (LinkedList) |
| :--- | :--- | :--- | :--- |
| **本质** | **抽象数据类型 (ADT)**，一种操作受限的线性表逻辑 | **具体存储结构**，用连续内存实现 | **具体存储结构**，用离散结点+指针实现 |
| **核心操作** | 仅 `push` (入栈) / `pop` (出栈) / `peek` (取栈顶)，只能操作一端 | 任意位置插入/删除，随机访问 `list[i]` | 任意位置插入/删除，但只能顺序遍历访问 |
| **实现方式** | 可以**用顺序表或单链表来实现** | 本身是一种实现 | 本身是一种实现 |
| **用户视角** | 看到的是“受限的容器”，遵循 LIFO | 看到的是“可直接操作任意位置”的线性表 | 看到的是“可通过指针高效插入删除”的线性表 |

简单说：**栈是一套规则（ADT），而顺序表和单链表是两种实现这套规则的积木（存储结构）。**

---

## fgets和scanf

### 1. `fgets` 基本使用

| 知识点 | 正确做法 |
|--------|----------|
| 函数原型：`char *fgets(char *buf, int n, FILE *stream)` | 1. 提供足够大的缓冲区，`n` 使用 `sizeof(buf)`。<br>2. 检查返回值是否为 `NULL`。<br>3. 手动去除末尾可能存在的 `\n`：`if (len>0 && buf[len-1]=='\n') buf[len-1]='\0';`<br>4. 第三个参数必须写 `stdin`（或文件指针），不可省略。 |
| 行为：从 `stream` 读取最多 `n-1` 个字符，遇 `\n` 停止并将 `\n` 存入数组，最后自动补 `'\0'`。成功返回 `buf`，失败/EOF 返回 `NULL`。 | 使用示例：<br>```c<br>char buf[100];<br>if (fgets(buf, sizeof(buf), stdin)) {<br>    buf[strcspn(buf, "\n")] = '\0';<br>}<br>``` |
| 换行符处理：`fgets` 会保留读到的 `\n`（除非缓冲区不够长）。 | 使用 `strcspn` 或手动判断 `buf[len-1]=='\n'` 来剔除换行符。 |

---

### 2. `scanf` 与 `fgets` 读取字符串的区别

| 知识点 | 正确做法 |
|--------|----------|
| `scanf("%s", buf)` 特性：跳过前导空白，读到下一个空白（空格、Tab、换行）停止，**不存储空白字符**，末尾自动补 `'\0'`；换行符会留在缓冲区。 | 1. 只适合读无空格单词，且必须限制宽度：`scanf("%9s", buf)`。<br>2. 读带空格的字符串请用 `fgets`。<br>3. 混用 `scanf` 和 `fgets` 时，注意清空缓冲区残留。 |
| `fgets(buf, size, stdin)` 特性：读入整行（包括空格），遇 `\n` 停止，将 `\n` 存入数组，再补 `'\0'`；长度受 `size` 限制，安全。 | 推荐作为常规字符串输入方法，配合去换行处理。 |

**误区：**

- **用 `scanf("%s")` 读取含空格的字符串**：输入 `"hello world"` 只得到 `"hello"`，后半段被截断甚至留作下次输入。
- **未限制 `scanf` 的宽度**：如 `scanf("%s", buf)`，当输入长度超过缓冲区大小时导致缓冲区溢出，属于严重安全漏洞。
- **`scanf` 遗留换行符**：`scanf("%s", ...)` 后残留 `'\n'` 在缓冲区，紧接的 `fgets` 可能直接读到空行（只有换行符），导致逻辑错误。
- **将 `fgets` 的换行符当有效字符**：未去掉 `\n` 时进行字符串比较或入栈，会多出一个换行符。
- **混用后不清除缓冲区**：未使用 `while (getchar() != '\n');` 清掉剩余字符，导致后续输入异常。

**清除'\0'的做法：**

```c
char buf[100];
if (fgets(buf, sizeof(buf), stdin) != NULL) {
    // 去除换行符
    size_t len = strlen(buf);
    if (len > 0 && buf[len-1] == '\n') {
        buf[len-1] = '\0';
    }
    // 现在 buf 是干净的输入
}
```

---

## 今天踩的坑

### 删除逻辑完全错误

双向链表删除函数的DoubleLinkedList_DeleteByValue删除逻辑完全错误
当要删除的不是头节点时，我写了：

```c
cur->prev = cur->next;   // 这改的是 cur 自己的指针，不是前后节点的连接
```

### 为什么 `cur->prev = cur->next` 是错的？

它只修改了 `cur` 自己的 `prev` 指针，相当于：

- 前驱节点的 `next` **仍然指向 `cur`**（链表没断开，但 cur 马上要被释放，前驱的 next 成了野指针）
- 后继节点的 `prev` **仍然指向 `cur`**（同样是野指针）
- 而 `cur` 的 `prev` 被改成了 `cur->next`，但反正 cur 马上要 free 了，这个改动毫无意义，反而让你没法通过 `cur->prev` 找到前驱来做后续操作

---

### 正确的做法

对应到代码（假设删除的是 `cur`，且它不是头也不是尾）：

```c
cur->prev->next = cur->next;   // 前驱的 next 跳过 cur，直接指向后继
cur->next->prev = cur->prev;   // 后继的 prev 跳过 cur，直接指向前驱
```

---

### 中文括号处理问题

| 知识点 | 正确做法 |
|--------|----------|
| 中文括号在 UTF-8 编码下占 3 个字节（`（` 为 `0xEF 0xBC 0x88`），**不能用单引号括起来作为字符**。 | 方法一（推荐）：栈中不存字符本身，**只存类型标记**（如用 `int` 区分 `1` 为英文 `(`，`2` 为中文 `（`）。<br>方法二：使用 `strncmp`/`memcmp` 比较字节序列：<br>```c<br>if (i+2 < len && strncmp(&s[i], "（", 3) == 0)<br>``` |
| 单引号括中文会触发 `multi-character character constant` 警告，比较行为为实现定义，通常无效。 | 彻底避免使用 `'（'`，改用字符串比较或标记法。 |
| 中文括号不能用双引号与 `char` 直接 `==` 比较：`if (s[i] == "（")` 类型错误。 | 理解 `"（"` 是字符串地址，不可与字符比较。 |

**踩坑/误区：**

- **1、将中文括号用单引号括起来比较**：例如 `if (input[i] == '（')`，编译器产生多字符常量警告，且运行时**永远无法匹配**真正的多字节序列。
- **被表面“测试通过”欺骗**：在 GBK 编码或特定编译器下，多字符常量值可能偶然与字符串某个字节相同，但不可移植，换环境即失败。
- **2、误以为中文括号有 ASCII 码**：试图“转换成 ASCII 码”再比较，实际上中文没有 ASCII，应处理其 UTF-8 字节序列。
- **3、手动拼凑整数比较时踩坑**：使用 `int code = (input[i]<<16) | (input[i+1]<<8) | input[i+2]` 可能因 `char` 为有符号类型导致符号扩展，拼出错误的负数值；或未考虑字节序导致比较失败。
- **4、忽略跳过剩余字节**：当使用 `strncmp` 匹配 3 字节的中文括号后，忘记将循环索引 `i += 2`，导致重复匹配或错位。
- **5、尝试 `input[i] == "（"`**：将字符串字面量与字符比较，编译错误（类型不匹配）。

#### 错误做法

```c
if(input[i] == '（'){
            SequenceStack_Push(stack1, input[i]);
        }
```

---

#### 正确的处理方式

```c
//  新代码：用 strncmp 比较 3 字节的 UTF-8 序列
        if(i + 2 < size && strncmp(&input[i], "（", 3) == 0){
            SequenceStack_Push(stack1, input[i]);
            i += 2;  // 跳过中文字符的剩余 2 个字节
        }
```

---


# 8.1笔记

## 一、头删法代码犯的错误

### 错误做法

```c
bool CircularLinkedList_HeadDelete(Manager_t *manager){
    if(manager == NULL){
        printf("参数错误，该链表结构不存在\n");
        return false;
    }
    if(manager->first == NULL){
        printf("链表为空，无法删除\n");
        return false;
    }    
    
    // 1.定义一个临时变量来存放首节点的地址
    Node_t *tmp = manager->first;    
    
    // 2.将首节点的下一个节点作为新的首节点
    manager->first = manager->first->next;

    
    // 3.释放掉原来的首节点
    if(manager->first == NULL){
        // 删除后如果链表为空，必须把尾指针也置空
        manager->tail = NULL;
    }
    else{
        // 删除后如果链表不为空，必须将尾节点的next指向新的首节点
        manager->tail->next = manager->first;
    }    
    free(tmp);
    tmp = NULL;    
    
    // 4.链表节点数减1
    manager->num -= 1;  

    
    return true;
}
```

代码有一个**致命的逻辑错误**，和单链表的习惯用法不同：**在单向循环链表中，如果只有一个节点，`first->next` 指向自己，执行 `manager->first = manager->first->next` 后 `first` 仍然是原来的地址，并不会变成 `NULL`。**

这会导致：

1. **`manager->first == NULL` 这个分支永远不会执行**。  
2. 程序会错误地走入 `else` 分支，执行 `manager->tail->next = manager->first`，而此时那个唯一的节点已经被 `free` 了，**访问已释放内存**，未定义行为（崩溃或逻辑错乱）。  
3. 删完后 `first` 和 `tail` 都还指向已释放的节点，成为悬挂指针。

---

### 正确做法

必须**单独处理链表只剩一个节点的情况**，判断条件通常是 `manager->first == manager->tail`（且非空）。

#### 修正版代码

```c
bool CircularLinkedList_HeadDelete(Manager_t *manager)
{
    if (manager == NULL) {
        printf("参数错误，该链表结构不存在\n");
        return false;
    }
    if (manager->first == NULL) {
        printf("链表为空，无法删除\n");
        return false;
    }

    Node_t *tmp = manager->first;

    // 情况1：链表中只有一个节点
    if (manager->first == manager->tail) {
        manager->first = NULL;
        manager->tail = NULL;
    }
    // 情况2：多个节点
    else {
        manager->first = manager->first->next;   // 首节点后移
        manager->tail->next = manager->first;    // 尾节点指向新的首节点，保持循环
    }

    free(tmp);
    tmp = NULL;

    manager->num -= 1;
    return true;
}
```

---

### 为什么需要这样改？

- **单节点链表**：直接置空 `first` 和 `tail`，表示链表已空，循环结构自然消失。
- **多节点链表**：先移动 `first`，再让 `tail->next` 指向新的 `first`，保证环不断裂，且不访问已释放内存。

原来的思路（通过 `first == NULL` 判断链表变空）只适用于非循环链表，循环链表里不可能通过移动 `first` 得到 `NULL`（除非错误地断开环，但那就不是循环链表了）。

---

### 延伸

- **尾删**也会遇到类似问题：当只剩一个节点时，不能用通用逻辑，需要单独处理。
- 删除中间节点也要注意更新 `tail`（如果删除的是尾节点）和维持环的连接。

---

## 二、销毁代码犯的错误

### 1.错误做法

```c
free(p);              // 1. 假设这里释放的是首节点
p = next;             // 2. p 指向了下一个节点（有效）
if(p == manager->first){  // 3. 比较：p 有效，但 manager->first 已经是被释放的地址！
    break;
}
```

- 当 `p` 第一次进入循环，指向首节点并释放后，`manager->first` 这个成员变量**仍然保存着刚刚被释放的首节点地址**，变成了悬垂指针。
- 接下来的 `if(p == manager->first)` 是在用**有效地址**（下一个节点）和**无效地址**（已释放的首节点）做比较。
- C 标准规定，使用已释放指针的值进行比较属于**未定义行为**（哪怕只是读它的值）。实际中，编译器可能假设这块内存已无效，优化后产生意想不到的结果，比如永不相等导致死循环，或碰巧相等导致提前退出。

---

### 2.正确的终止方式

有一个简单且完全正确的方式是：
**先断开环**，再遍历销毁，与普通单链表销毁完全一致。

```c
// 断开环：尾节点 next 置 NULL
manager->tail->next = NULL;

// 普通遍历销毁
Node_t *p = manager->first;
while (p != NULL) {
    Node_t *next = p->next;
    free(p);
    p = next;
}
```

这样完全避免了和已释放地址比较的问题，也是最推荐的循环链表销毁方法。

---

**总结**： `manager->first` 的“值”已经变成无效地址，拿它和有效地址比较就是错误的根源

下次再遇到销毁单向循环链表时，直接**先断开环**，再遍历销毁。

# 7.31笔记

## 一、在写链表时踩得坑

### 1.尾插法代码的错误顺序

```c

manager->tail       = new_node;   // tail 直接跳到新节点
manager->tail->next = new_node;   // 此时 tail->next 就是 new_node->next，指向自己！

```

**执行效果：**

1. `tail` 立即变成 `new_node`，原来尾节点的地址丢失了。

2. 接着执行 `manager->tail->next = new_node;` 等价于 `new_node->next = new_node;` —— 新节点指向自己，形成自环。

3. 原链表尾部节点（之前真正的尾节点）的 `next` 依然是 `NULL`，链表被截断，丢失了与新节点的连接。

---

**为什么：**

1. 原来`manager->tail = new_node`的意思就是直接改变尾巴的地址，如果第一步就改变地址之后尾巴就直接变成了新的节点，那么旧的节点就没了，就无法让原先是尾巴节点指针指向现在新的尾巴节点了

2. 第二步执行`manager->tail->next = new_node`此时`manager->tail`存的已经是改变过的新尾巴节点了，再让他`->next = new_node`就相当于指向他自己

---

### 2.尾插的正确做法

```c
manager->tail->next = new_node;   // 原尾节点的 next 指向新节点
manager->tail       = new_node;   // 更新尾指针，指向新的尾节点
```

---

**完整代码:**

```c
bool LinkedList_TailInsert(Manager_t *manager, DataType_t val){
    if(manager == NULL){
        return false;
    }

    // 1.创建一个新节点
    Node_t *new_node = LinkedList_NewNode(val);
    if(new_node == NULL){
        printf("创建新节点失败\n");
        return false;
    }

    // 2.插入前判断链表是否为空
    // 如果链表为空，则新节点既是头结点也是尾结点
    if(manager->first == NULL){
        manager->first  = new_node;
        manager->tail   = new_node;
    }
    // 如果链表不为空，则新节点
    else{
        manager->tail->next = new_node;
        manager->tail       = new_node;
    }
}

    // 3.链表节点数加1
    manager->num += 1;

    return true;

```

---

# 7.30笔记

## 一、数据结构

### 1.逻辑关系

1.线性结构：一对一（数组，链表，栈，队列）
2.非线性结果：不是一对一（树，堆，散列表，图）

---

### 2.物理关系

1.顺序存储：数组（顺序结构）
2.链式存储：链表（离散结构）

---

## 二、在写顺序表时遇到的问题

我的理解：如果`SequenceList_Destory`传入的参数是一级指针，就要在主函数调用销毁后手动置空指针，如果传入的参数是二级指针，就不用手动置空。

原因在于 **C 语言函数参数是值传递**。

---

### 1. 一级指针的情况

```c
void SequenceList_Destory(SList_t *manager)
{
    free(manager->addr);
    free(manager);
    // manager 是局部变量，指向已释放的内存
}
```

调用时：

```c
SList_t *list = SequenceList_Create(10);
SequenceList_Destory(list);
// 此时 list 仍然保存着原来的地址值（野指针）
```

**原理：**  
函数参数 `manager` 是 `list` 的一个**副本**。  
你把 `list` 的值（某内存地址 0x1000）传进去，`manager` 也变成了 0x1000。  
函数内部 `free(manager)` 只释放了 0x1000 处的内存，但 `manager` 这个局部变量本身和外面的 `list` 是**独立的两个变量**。  
函数结束时 `manager` 被销毁，但 `list` 的值依然是 0x1000，就成了野指针。  
所以**必须手动** `list = NULL`。

---

### 2. 二级指针的情况

```c
void SequenceList_Destory(SList_t **pp_manager)
{
    free((*pp_manager)->addr);
    free(*pp_manager);
    *pp_manager = NULL;   // 将外部指针置空
}
```

调用时：

```c
SList_t *list = SequenceList_Create(10);
SequenceList_Destory(&list);
// 此时 list 自动变成 NULL
```

**原理：**  
这次传的不是 `list` 的值，而是 **`list` 自己的地址**（`&list`）。  
函数内部 `*pp_manager` 就是 **外面的 `list` 本身**。  
所以 `*pp_manager = NULL` 这句话，直接修改了外部 `list` 的值。  
函数结束后，`list` 就已经是 `NULL` 了，不需要再手动置空。

---

### 3. 直观对比

| 方式 | 传进去的是什么 | 函数能修改外部的什么 |
|------|----------------|---------------------|
| 一级指针 `SList_t *` | 指针的**值**（地址副本） | 能修改**指针指向的内容**（如 `manager->last`），但**不能修改指针本身** |
| 二级指针 `SList_t **` | 指针的**地址** | 既能修改指针指向的内容，**也能修改指针本身**（让它指向别处或置 NULL） |

---

### 4. 简单总结

- 想改外部的 `int`，需要传 `int *`。  
- 想改外部的 `SList_t *`（即修改指针本身），需要传 `SList_t **`。

所以使用二级指针的销毁函数更“省心”，一次调用彻底安全；  
用一级指针的版本则是“用完自己记得打扫”，需要手动 `list = NULL`，但代码看着更简洁。

---

## 三、踩的坑

尝试在一级指针`void SequenceList_Destory(SList_t *manager)`里面写`*manager = NULL`，同时调用的时候也传list的地址`SequenceList_Destory(&list);`

结论：**不行**，这样做会导致编译错误，而且逻辑上也不对。分两点说清楚：

---

### 1. 类型不匹配

```c
void SequenceList_Destory(SList_t *manager)
{
    free(manager->addr);
    free(manager);
    *manager = NULL;   // ❌ 编译错误
}
```

这里的 `manager` 是 `SList_t *` 类型，`*manager` 就是 **一个 `SList_t` 结构体**。  
`NULL` 是指针类型的空值（通常定义为 `(void*)0`），**不能赋值给结构体变量**。  
编译器会直接报错：

```text
error: incompatible types when assigning to type ‘SList_t’ from type ‘void *’
```

---

### 2. 即使强行转换，意义也不对

如果非要写 `*manager = (SList_t){0};` 之类的东西，那只是把 `manager` 指向的结构体内容清空。但——

此时 `manager` 刚被 `free` 掉，它指向的内存已经不可访问，`*manager` 本身就是**未定义行为**。而且做完这个操作，外部的 `list` 指针**依然是原来的地址值**，并没有变成 `NULL`。

---

### 3. 如果用 `SequenceList_Destory(&list)` 调用

假设写的是：

```c
SList_t *list = SequenceList_Create(10);
SequenceList_Destory(&list);   // 但函数定义是 SList_t *manager
```

`&list` 的类型是 `SList_t **`，而函数参数类型是 `SList_t *`，**类型不匹配**，编译器会报警告或错误（取决于设置）。就算勉强通过，传给 `manager` 的也是 `list` 的地址（一个二级指针值），把它当作一级指针去访问 `manager->addr` 会直接崩溃。

---

### 4. 总结

- **用一级指针**：函数里 `free(manager)` 释放的是 `list` 指向的内存，但 `list` 本身不变，需要**调用后手动 `list = NULL`**。
- **用二级指针**：函数里 `*pp_manager = NULL` 直接修改外部 `list` 指针，因为 `*pp_manager` 就是外面的 `list`，类型是 `SList_t *`，赋值 `NULL` 合法。

如果不用二级指针，那就需要走“手动置空”这个步骤。没有其他让一级指针函数自动置空外部指针的办法。

---

## 四、对以往的知识点回顾（sizeof和strlen的区别）

### 1. 对数组与指针的行为

这是最易混淆的地方：

| 情况 | `sizeof` | `strlen` |
|------|----------|----------|
| 字符数组 `char arr[] = "hello";` | 6（包含 `'\0'`） | 5 |
| 字符串字面量 `"hello"` | 6（包含 `'\0'`） | 5 |
| 指针 `char *p = "hello";` | 指针本身大小（4 或 8 字节） | 5（按指向内容计算） |
| 数组作为函数参数退化为指针时 | 指针大小，而非原数组大小 | 仍求字符串长度（需有 `'\0'`） |

**关键**：数组名在 `sizeof` 中不会退化为指针，在函数参数中会。

---

### 2. 常见陷阱总结

- 将数组传入函数后，用 `sizeof` 求大小只会得到指针大小。
- 用 `strlen` 处理可能没有 `'\0'` 的字符数组（如网络数据包）会导致越界。
- 混淆 `sizeof("abc")`（4）和 `strlen("abc")`（3）。
- 以为 `sizeof` 是函数而写成 `sizeof` 后有空格，其实它是运算符，`sizeof expr` 可省略括号，但 `sizeof(type)` 必须加括号。

---

### 3. 速查对比表

| 对比项 | `sizeof` | `strlen` |
|--------|----------|----------|
| 类型 | 运算符 | 库函数 |
| 求值时机 | 编译时（VLA 除外） | 运行时 |
| 功能 | 内存占用字节数 | 字符串字符数 |
| 头文件 | 无需 | `<string.h>` |
| 参数 | 类型或表达式 | `const char*` |
| 是否包含 `'\0'` | 若存在则计入 | 不计入 |
| 数组与指针 | 区分数组名和指针 | 只关心指向的内容 |
| 未初始化/无 `'\0'` | 仍安全返回大小 | 未定义行为 |

---

### 4. 代码实例

注意：sizeof 在编译期求值时，只关心操作数的类型，不实际计算操作数的值。

```c
#include <stdio.h>

int main() {
    int i = 10;

    printf("sizeof(i++) = %zu\n", sizeof(i++));  // 输出 sizeof(int)，通常是 4
    printf("sizeof(++i) = %zu\n", sizeof(++i));  // 输出 sizeof(int)，通常是 4
    printf("i = %d\n", i);                       // i 仍然是 10

    // 对比：正常的 ++i
    ++i;
    printf("After normal ++i, i = %d\n", i);     // i 变成 11
    return 0;
}
```

## 2026-07-28 跨平台类型字节长度与运算符右结合性

### 跨平台(32位->64位)字节长度速查：不变类型 vs 变化类型

---

#### 大小不变的类型（与系统位数无关）

| 类型 | 32位 | 64位 | 备注 |
|------|------|------|------|
| `char` | 1 字节 | 1 字节 | 永远为 1 |
| `short` | 2 字节 | 2 字节 | 至少 2 字节 |
| `int` | 4 字节 | 4 字节 | 几乎所有平台 |
| `float` | 4 字节 | 4 字节 | IEEE 754 单精度 |
| `double` | 8 字节 | 8 字节 | IEEE 754 双精度 |
| `long long` | 8 字节 | 8 字节 | 始终 8 字节 |

---

#### 大小改变的类型（32位 → 64位）

| 类型 | 32位 | 64位 Unix/macOS (LP64) | 64位 Windows (LLP64) |
|------|------|------------------------|----------------------|
| `void*` (指针) | 4 字节 | 8 字节 | 8 字节 |
| `long` | 4 字节 | **8 字节** | **4 字节（不变）** |
| `size_t` | 4 字节 | 8 字节 | 8 字节 |
| `ptrdiff_t` | 4 字节 | 8 字节 | 8 字节 |
| `intptr_t` 等 | 4 字节 | 8 字节 | 8 字节 |

---

#### 关于中文字节的混淆

- **错误理解：** 以为 `char` 在 Linux 下是 3 字节，因为一个中文占 3 字节。
- **事实：** `char` 本身永远是 1 字节。中文字符在 UTF-8 编码下需要用 **3 个连续的 `char`** 来存储，所以会误以为单个 `char` 有 3 字节，但 `sizeof(char)` 始终是 1。

---

### 运算符结合性：右结合运算符详解
---

#### 1. 赋值运算符（`=`, `+=`, `-=`, `*=` 等）
所有赋值运算符都是**右结合**的，多个赋值连写时从右向左逐级赋值。
```c
int a, b, c;
a = b = c = 5;   // 等价于 a = (b = (c = 5))
```
执行过程：`c = 5` 首先计算并返回 `c`，再赋给 `b`，最后赋给 `a`。

---

#### 2. 条件运算符 `?:`
嵌套使用时从右向左分组。
```c
int x = 1, y = 2, z = 3;
int result = x > 0 ? y : z > 0 ? z : 0;
// 等价于 x > 0 ? y : (z > 0 ? z : 0)
```
右结合避免了歧义：每个 `:` 都与其左边最近的 `?` 匹配。

---

#### 3. 一元运算符（`!`, `~`, `++`, `--`, `+`, `-`, `*`, `&`, `(type)` 等）
所有一元运算符都是**右结合**的，即操作数先与其右侧的运算符结合（如果有多个一元运算符连用）。
```c
int a = 5;
int *p = &a;
int b = *p;          // 一元 * 右结合：*p 作为一个整体
int c = - -a;        // 等价于 -(-a)，从右向左结合
```
后置 `++`/`--` 虽然优先级更高，但从语法角度看也是右结合。

---

#### 总结
- **左结合**（自左向右）：`&&`、`||`、算术运算符 `+ - * / %`、关系运算符 `< <= > >=`、`& | ^` 等。
- **右结合**（自右向左）：赋值类 `=` `+=` 等、条件 `?:`、一元运算符。

“什么情况下会自右向左”的答案就是：**在使用赋值运算符、条件运算符或一元运算符时**，它们会按右结合性从右向左分组和计算。

---
## 2026-07-27  宏定义文本替换陷阱与大小端判断

### 知识点
- 宏是**纯文本替换**，在预处理阶段完成，不会对参数求值或自动加括号
- 宏参数是表达式时，替换后直接与相邻运算符结合，可能受运算符优先级影响改变原意
- 宏定义中要给**每个参数外加括号**，整体结果也要加括号，才能保证参数整体求值
- 后缀自增 `a++` 在表达式求值后生效；宏只粘贴参数一次时不会多次自增，但仍要警惕优先级和求值顺序
- 嵌套宏先展开内层，展开过程依然是文本替换，不会产生隐式括号
- 大小端存储：小端模式低地址存低位字节，大端模式低地址存高位字节
- `char*` 一次只读一个字节，能直接探查数据在内存起始地址的内容
- `int*` 解引用会按本机字节序把多个字节重新组合成原值，无论大小端结果相同，无法判断字节序

### 踩过的坑
- `#define Y(n) ((N+1)*n)`，`Y(5+1)` 预期 `4*6=24`，实际得 21 → 错误直觉：以为宏像函数一样先算出参数 `5+1=6` 再代入；实际 `Y(5+1)` 展开成 `((3+1)*5+1)`，乘法先抓住 `5`，变成 `4*5+1=21`
- `#define N M+M`，`N*N*5` 预期 `(5+5)*(5+5)*5=500`，实际得 55 → 展开成 `5+5*5+5*5`，乘法优先等于 `5+25+25=55`，原因是宏 `N` 缺少整体括号
- `F(a++, b++)`：本题 `#define F(X,Y) (X)*(Y)` 只用参数一次，结果正确（`3*4=12`）；但若宏多次使用同一参数（如 `(X)*(X)`），会导致多次自增，是未定义行为
- 以为任何指针解引用都能"看到"内存的原始字节排列，用 `int*` 也能判断大小端 → 实际 `int*` 解引用时按当前字节序自动合成整数，值与原始赋值完全一致，掩盖了字节内部顺序；只有转成 `char*` 取单字节才暴露真实存储顺序

### 正确做法
```c
// 宏：每个参数加括号 + 整体加括号
#define Y(n) ((N+1)*(n))
#define N (M+M)
#define MAX(a,b) ((a) > (b) ? (a) : (b))  // 标准写法

// 避免带副作用的宏参数
int x = a; x++; F(x, y);   // 手动控制自增点
```
```c
// 大小端判断：char* 取首字节
#include <stdio.h>
int main() {
    int a = 0x00000001;
    char *p = (char*)&a;
    if (*p == 1) printf("小端存储\n");
    else         printf("大端存储\n");
    return 0;
}
```
核心思路：把宏当成"字符串拷贝粘贴"，参数和整体全部手动加括号；判断字节序必须用 `char*` 逐字节看内存，绕过 CPU 的自动重组。

### 关键词
宏定义 #define 文本替换 括号 运算符优先级 副作用 a++ 未定义行为 大小端 字节序 小端 char指针 内存布局

---

## 2026-07-24  static 关键字、内存对齐与数组指针结构体辨析

### 知识点
- `static` 修饰局部变量：只改变生命周期不改变作用域，函数多次调用时只在第一次初始化，执行结束后值保留
- `static` 修饰全局变量：将作用域限制在当前 .c 文件内，其他文件即使 `extern` 也无法访问，实现文件级私有
- 内存对齐：64 位系统 CPU 一次访问 8 字节，变量地址必须能被自身大小整除，牺牲内存换取访问效率
- 结构体对齐原则：成员放在自身类型整数倍的地址上，结构体总大小为最大成员类型的整数倍（补位是为结构体数组留出对齐空间）
- 结构体类型定义中不能包含可执行语句，C 语言中不能给成员设置默认值
- 结构体字符数组成员不能用 `=` 直接赋值，数组名是地址常量，应使用 `strcpy`
- 二维数组名在表达式中退化为指向首行的指针，类型为 `int (*)[列数]`
- `*(*(a+1)+2)` 等价于 `a[1][2]`：`a+1` 指向第 1 行 → `*(a+1)` 得到该行并退化为 `int*` → `+2` 偏移到第 2 列 → 解引用取值
- `sizeof(数组名)` 返回整个数组占用的字节数，不会退化为指针大小
- `char *str[]` 是指针数组：`str` 先与 `[]` 结合为数组，元素类型为 `char*`
- `int (*p)[3]` 是数组指针：`*` 先与 `p` 结合为指针，指向含 3 个 int 的数组
- `p[2]` 恒等于 `*(p+2)`，无论 p 是静态数组名还是动态分配的指针，编译器均转换为 `*(p + i)`

### 踩过的坑
- 错误直觉：以为能在结构体类型定义里给成员设默认值，或用 `a1.name = "abc"` 给字符数组成员赋值 → 实际 C 语言不支持，数组名不能作赋值左值，必须用 `strcpy`
- 混淆指针数组与数组指针：凭直觉记不清谁是谁 → 看最后一个词："指针数组"本体是数组，"数组指针"本体是指针。声明时 `[]` 优先级高于 `*`，先结合谁就是什么

### 正确做法
```c
// 1. 结构体字符数组成员赋值
struct student { char name[20]; };
struct student a1;
strcpy(a1.name, "abc");   // 数组名不能作赋值左值

// 2. 二维数组指针运算
int a[2][3] = {1,2,3,4,5,6};
int value = *(*(a + 1) + 2);   // 等价于 a[1][2]，值为 6

// 3. 指针数组 vs 数组指针
char *str[] = {"C", "C++", "Java", "Python"};   // 指针数组：数组，元素为指针
int (*p)[3];                                     // 数组指针：指针，指向含 3 个 int 的数组

// 4. malloc 动态数组下标操作
int *p = (int *)malloc(5 * sizeof(int));
p[2] = 10;   // 完全等价于 *(p + 2)
```
核心思路：关注声明优先级——无括号时 `[]` 先结合形成数组，有括号时 `*` 先结合形成指针。`p[i]` 编译器统一转为 `*(p + i)`，静态数组与动态指针行为一致。

### 关键词
static 内存对齐 结构体赋值 指针数组 数组指针 strcpy sizeof malloc 二维数组指针 *(a+1)+2

---
## 2026-07-23  理解 sizeof 与 strlen 的区别、sizeof(char) 恒为 1 的原因

### 知识点
- `sizeof` 是编译期运算符，返回对象或类型占用的内存字节数；`strlen` 是运行时函数，从地址开始扫描直到遇到 `'\0'` 并返回字符个数。
- 指针变量只存储地址，`sizeof(指针)` 返回的是指针变量本身的大小（如 4 或 8 字节），与它指向的字符串长度无关。
- 当用 `char arr[] = "..."` 定义数组时，`sizeof(arr)` 返回整个数组占用的字节数（包含编译器自动添加的 `'\0'`），因此可以间接得到字符数组的长度（但包含 `'\0'`）。
- `sizeof(char)` 在任何平台都恒为 1，因为 C 标准规定 `char` 的大小是衡量所有存储的"基准单位"；"字节"在 C 中的定义就是"存放一个 `char` 所需的存储单元"，其宽度可以不是 8 位。
- 可移植代码中，字符串长度应使用 `strlen`，内存大小应使用 `sizeof`，不要混用。

### 踩过的坑
- **错误直觉**：认为 `char *arr = "abcde abcde"; int len = sizeof(arr)/sizeof(arr[0]);` 能像数组一样得到字符串长度（比如 11）。  
  **实际发生**：`sizeof(arr)` 拿到的是指针变量自身大小（我机器上是 8），除以 `sizeof(arr[0])`（即 `sizeof(char)`，值为 1），结果永远是 8 或 4，根本不是字符串长度。
- **错误直觉**：以为 `sizeof(char) == 1` 是因为一个 char 就是 8 位、1 字节固定为 8 位。  
  **实际发生**：C 语言的"字节"是以 `char` 的大小定义的，如果平台上的 `char` 是 16 位，那么 1 字节就是 16 位；`sizeof(char)` 恒为 1 是因为它本身就是度量其他类型的尺子，与具体多少位无关。

### 正确做法
```c
#include <stdio.h>
#include <string.h>

int main() {
    char arr[] = "abcde abcde";   // 数组，包含整个字符串
    char *ptr = "abcde abcde";    // 指针，仅存地址

    printf("Array: sizeof=%zu, strlen=%zu\n", sizeof(arr), strlen(arr));
    printf("Pointer: sizeof=%zu, strlen=%zu\n", sizeof(ptr), strlen(ptr));
    return 0;
}
```
核心思路：**数组名在定义作用域内用 `sizeof` 可得到总字节数（含 `\0`）；指针无论如何 `sizeof` 只得到指针变量本身大小。获取字符串长度统一用 `strlen`。**

### 关键词
sizeof strlen 指针 数组 编译期 运行时 char 字节 C标准 \0

---

## 2026-07-20  数组退化与指针——函数传参的陷阱

### 知识点
- 数组作为函数参数会退化为指针，丢失长度信息
- `sizeof(arr)` 在函数内部求的是指针大小（4 或 8 字节），而不是数组大小
- C 语言中函数不能直接返回数组，但可以返回指针（原数组地址、静态数组地址、动态分配数组地址）
- 返回指针时，函数签名必须用 `int*` 而不是 `int`，接收端用 `int *p`
- `int *p = pt(arr, 10);` 正确；`int p = pt(...)` 将地址截断为整数（编译器警告）；`*pt(...)` 取到首元素值；`int *p = *pt(...)` 把整数当作地址是错的
- `malloc` 是动态分配数组内存，不是获取数组长度的方法——获取长度必须额外传参
- `sizeof(arr) / sizeof(arr[0])` 是计算数组元素个数的通用写法，优于 `sizeof(arr) / sizeof(int)`，因为类型改变时仍正确
- 以上计算只在定义数组的作用域内有效，进入函数后失效

### 踩过的坑
- **在函数内用 `sizeof(arr)` 求数组长度**：以为 `int arr[]` 形参还是一个完整数组，`sizeof` 能得出总字节数 → 实际形参退化为指针，`sizeof(arr)` 得到的是 4 或 8 字节（指针大小），导致循环次数错误，可能越界
- **函数返回类型写成 `int`，却 `return arr;`**：想返回数组首地址，写 `int pt(...)` → 实际返回的是 `int*`，赋给 `int` 类型变量会截断地址，编译器警告
- **用 `int ans[] = pt(arr);` 接收返回值**：以为可以像初始化一样用函数调用给数组赋值 → 实际 C 不允许用整数或指针初始化一个未知大小的数组，必须用 `{}` 列表
- **`int *p = *pt(arr, 10);`**：想要指针指向整个数组 → 实际先解引用得到第一个元素的值（整数），再把该整数值当作地址赋给指针，造成危险
- **以为 `malloc` 能让函数内自动获取数组长度**：动态分配的数组似乎带有长度信息 → 实际 `malloc` 返回的也是指针，函数内部仍然不知道长度，必须传参

### 正确做法
```c
// 需要知道数组长度时，额外传递长度参数
void printArr(int arr[], int len) {
    for (int i = 0; i < len; i++)
        printf("%d ", arr[i]);
}
```
核心思路：**长度由调用者显式提供，函数内部不依赖 `sizeof`。**

```c
// 在函数内生成新数组并返回（调用后需 free）
int* createArray(int size) {
    int *arr = malloc(size * sizeof(int));
    // 填充数据...
    return arr;
}
```
核心思路：**动态分配，返回指针，调用者负责释放。**

```c
// 保留原数组的修改，直接返回原数组地址
int* modify(int arr[], int len) {
    // 修改 arr 的内容...
    return arr;
}
int main() {
    int a[10];
    int *p = modify(a, 10);  // p 和 a 指向同一块内存
}
```
核心思路：**返回传入的指针即可，无需新建。**

```c
// 在定义数组处计算长度（类型变更时自动适应）
int arr[] = {33, 5, 22};
int len = sizeof(arr) / sizeof(arr[0]);
```
核心思路：**用 `arr[0]` 代替具体类型名，类型变更时自动适应。**

### 关键词
数组退化 指针 sizeof 数组长度 函数传参 返回数组 C语言 指针截断 动态数组 malloc 数组初始化 int*

---

## 2026-07-20  unsigned 取反与补码——~x = -(x+1) 的通用公式

### 知识点
- `unsigned` 类型的"负数"本质是模加法逆元，求法仍然是取反加一
- 整型提升规则：`unsigned char` 等小类型参与运算前会被提升为 `int`（值不变，高位补 0），然后才执行 `~` 等操作
- 补码解码：看到最高位为 1 的有符号数，想求它的值，可以对该补码"取反加一"得到绝对值，再冠以负号
- 通用公式 `~x = -(x + 1)` 对正数、负数、零均成立，因为推导自 `-x = ~x + 1`，整个补码系统内有效
- 补码表示下 `-1` 是全 1 位模式，`~(-1)` 得到全 0 即 0，与公式吻合

### 踩过的坑
- **对 `~a` 的结果反复做"取反加一"**：错误直觉——对 `~a` 的结果还需要再做一次"取反加一"才能得到 `-5`，然后再减 1 变回 `-6`，推导绕了两步 → 实际 `unsigned char a = 5;` 提升为 `int 5` 后取反，得到的 `111...1010` 本身就是 `-6` 的补码，不需要再编码。"取反加一"原本是用在解码时求绝对值的工具，我把它当成了对表达式的额外变换 → 如何发现：通过老师纠偏，指出"取反加一"是补码翻译工具，而非针对结果的二次运算；直接用公式 `~5 == -(5+1) == -6` 可秒得答案

### 正确做法
```c
// 直接套用公式，无需绕路
unsigned char a = 5;
// ~a 的求值过程：
//   1. 整型提升：a(5) → int(5)，二进制 000...0101
//   2. 按位取反：~5 → 111...1010，即 -6 的补码
//   3. 验证公式：~x = -(x+1) → ~5 = -(5+1) = -6 ✓
printf("%d\n", ~a);  // 输出 -6
```
核心思路：**`unsigned char` 参与 `~` 运算时先整型提升为 `int`，再取反，结果直接由 `~x = -(x+1)` 得出。不要把"取反加一"这个解码工具当成对表达式的额外运算。**

### 关键词
unsigned 取反 补码 ~x=-(x+1) 整型提升 取反加一 模加法逆元 位模式

---

## 2026-07-17  位计数判断条件错误 & 回文数数组越界与赋值陷阱

### 知识点
- 判断二进制某一位是否为 1，用 `(num >> i) & 1` 而不是 `(num >> i) == 1`
- `num1 >>= 1` 每次右移 1 位，`num1 >>= i` 每次右移 `i` 位（位移量随循环增长，导致累计移位远超预期）
- 用 `while(num1 != 0)` 直接控制循环，比 `while(!flag)` + 额外判断变量更简洁
- `=` 是赋值运算符，`==` 是相等比较运算符，`if(flag = 1)` 永远为真
- 循环结束后 `i` 的值已经是"越界下标"，用 `b[i]` 填写数组会从末尾之后开始，漏掉 `b[0]`

### 踩过的坑
- **位计数**：写 `if((num >> i) == 1)` 以为能检测"第 i 位为 1"→ 实际只有当整个右移结果刚好等于 1 时才成立，比如 `num=5` 二进制 `101`，`5>>0=5`、`5>>1=2` 都不等于 1，一个 1 都检测不到
- **位计数**：写 `num1 >>= i` 以为"每次移 1 位"→ 实际 i 不断增长，第 1 次移 1 位、第 2 次移 2 位、第 3 次移 3 位……累计移了 1+2+3=6 位，完全失控
- **回文数**：在 `if(flag = 1)` 里把 `==` 写成了 `=`，编译无警告但逻辑全崩——无论前面怎么比较，走到这里永远返回 true，导致 123 这种非回文数也判为 true
- **回文数**：第二个 while 循环用 `b[i]` 从 `i=max` 开始填，填到 `i=1` 时退出，`b[0]` 从未赋值，存的是栈上的随机垃圾值

### 正确做法
```c
// 统计二进制中 1 的个数（简化版）
int num1 = num, sum = 0;
while (num1 != 0) {
    if (num1 & 1) {      // 检查最低位
        sum++;
    }
    num1 >>= 1;           // 每次只移 1 位
}
```
核心思路：**用 `& 1` 剥最低位，每次固定右移 1 位，用原值是否为 0 控制循环**。

```c
// 回文数判断（双数组法，修复后）
int a[100], b[100], i = 0;
while (x1 != 0) {
    a[i] = x1 % 10;
    x1 /= 10;
    i++;
}
int max = i;
while (i != 0) {
    b[i - 1] = x2 % 10;   // 下标减 1，从 b[max-1] 填到 b[0]
    x2 /= 10;
    i--;
}
int flag = 1;
for (int j = 0; j < max; j++) {
    if (a[j] != b[j]) {
        flag = 0;
    }
}
if (flag == 1) {          // == 不是 =
    return true;
}
```
核心思路：**数组下标从 0 开始，循环结束后的 i 是"越界值"，必须 `-1` 回退到有效范围；比较用 `==` 不是 `=`。**

```c
// 回文数判断（更优解：反转一半数字）
bool isPalindrome(int x) {
    if (x < 0 || (x % 10 == 0 && x != 0))
        return false;
    int reversed = 0;
    while (x > reversed) {
        reversed = reversed * 10 + x % 10;
        x /= 10;
    }
    return x == reversed || x == reversed / 10;
}
```
核心思路：**只反转数字的后半段，比较前后两半是否相等，避免溢出也省了数组空间。**

### 关键词
位计数 & 右移 移位量 循环条件 while flag = vs == 赋值与比较 数组越界 下标偏移 回文数 反转一半

---

### 知识点
- `num1 % 10` 取个位数：任何整数对 10 取余，结果就是个位上的数字（0–9）
- `num1 /= 10` 消除个位数：整数除以 10 会截断个位，原来的十位变成新的个位
- 循环配合 `while (num1 != 0)`：反复"取个位 → 消个位"，直到数字被拆光（变为 0），适合逐位处理任意整数
- 这个套路不仅用于求和，也用于反转数字（`reversed = reversed * 10 + digit`）、回文数判断、进制转换等场景

### 踩过的坑
- 忘记先取个位再消个位：如果把 `num1 /= 10` 写在 `sum += num1 % 10` 前面，会先丢掉个位再取余，导致个位数字被跳过
- 在回文数练习中，已经无意识用过 `a[i] = x1 % 10; x1 /= 10;` 但没有把它抽象成通用套路 → 下次看到"逐位处理整数"的需求，应该第一时间想到这个组合

### 正确做法
```c
// 计算整数各位数字之和
int num1 = 12345, sum = 0;
while (num1 != 0) {
    sum += num1 % 10;   // 取个位数，加到 sum
    num1 /= 10;          // 消除个位数
}
// 循环过程：12345 → sum=5, 1234 → sum=9, 123 → sum=12, 12 → sum=14, 1 → sum=15, 0 退出
printf("%d\n", sum);    // 输出 15
```
核心思路：**`% 10` 取最后一位，`/ 10` 丢掉最后一位，循环直到数字为 0。先取后丢，顺序不能反。**

### 关键词
取个位数 消个位数 %10 /=10 逐位处理 数字拆分 各位求和 反转数字 while循环

---

### 知识点
- 力扣C语言模板必须用 `malloc` 动态分配返回数组的内存，并用 `*returnSize` 通知系统返回数组长度
- `int* result` 和 `int *result` 在单独声明时完全相同，但一行声明多个变量时 `*` 只粘着最近的一个变量
- `*returnSize = 2` 中的 `*` 是解引用运算符，用于向系统给的地址里写入整数2
- 双重循环暴力解法的下标选择：`i < numsSize - 1` 且 `j = i + 1`，只组合 `(0,1)(0,2)(0,3)(1,2)(1,3)(2,3)`
- 普通数组 `int a[4]` 存整数；指针数组 `int *a[4]` 存指针，每个元素是 `int*` 类型
- `int (*a)[4]` 是指向长度为4的整型数组的指针，不是数组
- 指向数组元素的指针用 `int *p = &a[2];`，类型必须匹配：左边是指针只能接地址，左边是整数只能接内容
- `int *c[4] = {10,20,30,40}` 在C语言中是错误的初始化方式（把整数当指针）

### 踩过的坑
- 以为 `int* a, b;` 能同时声明两个指针 → 实际 b 是 int，必须写 `int *a, *b;`
- 混淆 `*p = a;` 和 `p = &a;`，前者是把整数写入 p 指向的格子，后者是让 p 指向 a
- 想把地址赋给 int 变量（如 `int x = &a;`），编译器警告且无意义
- 尝试 `int *c[4] = {10,20,30,40}` 初始化指针数组，误以为能把整数转成地址
- 写出非法声明 `int (*a)a[4]`，错在重复使用变量名 a (AI推断)
- 对 `*returnSize` 的作用不理解，以为直接修改形参 `returnSize` 就行，未认识到传指针才能影响外部变量

### 正确做法
```c
// 暴力法解决两数之和（力扣模板）
int* twoSum(int* nums, int numsSize, int target, int* returnSize) {
    int* result = (int*)malloc(2 * sizeof(int));
    *returnSize = 2;
    for (int i = 0; i < numsSize - 1; i++) {
        for (int j = i + 1; j < numsSize; j++) {
            if (nums[i] + nums[j] == target) {
                result[0] = i;
                result[1] = j;
                return result;
            }
        }
    }
    return result; // 题目保证不会走到这
}
```
核心思路：双层循环只遍历 i<j 的组合，找到答案后用 malloc 的数组返回下标，通过 *returnSize 告诉系统长度。

```c
// 指向数组元素的正确方式
int a[4] = {10,20,30,40};
int *p = &a[2];   // p 指向 a[2]，*p 得到 30
```
核心思路：左边指针类型必须匹配右边的地址。

### 关键词
力扣 两数之和 malloc returnSize 指针 数组 解引用 int* 声明陷阱 指针数组

---

## 2026-07-16  printf/scanf 格式、固定宽度整数、位操作与 unsigned char 输入

### 知识点
- `%u` 输出无符号十进制整数，`%d` 输出有符号十进制整数，`%o`/`%x` 读取八进制/十六进制，`%#o`/`%#x` 可自动加前缀 `0`/`0x`
- 十进制没有标准前缀，`0d` 不是 C 语言规定，可用 `%+d` 或自定义字符串
- 定义精确 32 位整数要使用 `<stdint.h>` 中的 `int32_t`/`uint32_t`，不能用 `unsigned int32_t` 组合
- 提取整数某个字节直接使用移位和按位与：`(val >> 24) & 0xFF`
- 用 `scanf("%hhu", &var)` 读取 `unsigned char` 类型的整数（0–255）
- 无符号整数的二进制打印可通过逐位右移和 `& 1` 手动完成

### 踩过的坑
- 误以为 `scanf("%o,%x")` 会把输入当十进制，导致 7,15 求和结果是 28（八进制7=7，十六进制15=21），而不是 22
- 想给十进制加前缀时，直接写了文字"十进制显示（带前缀说明）"，但 `%u` 并不会自动加前缀
- 试图写 `unsigned int32_t val;` 或 `unsigned int int32_t val;` 定义无符号 32 位整数，编译报错——`int32_t` 本身是 typedef，不能再加 `unsigned`
- 用数组逐位存储高低字节时，循环嵌套和内层条件写错，导致逻辑不工作
- 用 `scanf("%c", &a)` 读取 `unsigned char` 的数值，实际上读入的是字符的 ASCII 码，输入 5 输出二进制是 53 的二进制 `00110101` 而非 `00000101` (AI推断)

### 正确做法
```c
// 定义无符号 32 位整数
#include <stdint.h>
uint32_t val;

// 交换高低字节并组成新 16 位整数（低8位放高位，高8位放低位）
uint8_t low_byte  = val & 0xFF;
uint8_t high_byte = (val >> 24) & 0xFF;
uint16_t new_val  = (low_byte << 8) | high_byte;
printf("%u\n", new_val);

// 读取 unsigned char 并打印 8 位二进制
unsigned char a;
scanf("%hhu", &a);
printf("%d%d%d%d%d%d%d%d\n",
    (a>>7)&1, (a>>6)&1, (a>>5)&1, (a>>4)&1,
    (a>>3)&1, (a>>2)&1, (a>>1)&1, a&1);
```
核心思路：利用 `<stdint.h>` 的类型保证位宽，位操作直接提取/拼接字节，`%hhu` 正确读取 unsigned char 数值。

### 关键词
printf scanf %u %d %o %x %hhu stdint.h uint32_t 位操作 移位 unsigned char 二进制

---

## 2026-07-15  按位运算（| & ^ ~ << >>）与位操作套路

### 知识点
- 十六进制 `0x` 前缀和二进制有天然对应关系：1 位十六进制 = 4 位二进制
- `unsigned char` 占 1 字节 = 8 位，每位有权重（bit n 权重 = 2ⁿ）
- `|`（按位或）：有 1 则 1，常用于**把某些位置 1**
- `&`（按位与）：全 1 才 1，常用于**把某些位清 0**（配合 `~` 取反）
- `^`（按位异或）：不同为 1，相同为 0
- `~`（按位取反）：0 变 1，1 变 0
- `<<`（左移 n 位）：每位向左移 n 格，右边补 0，等价于 × 2ⁿ
- `>>`（右移 n 位）：每位向右移 n 格，无符号数左边补 0，等价于 ÷ 2ⁿ（取整）
- `1 << n` 的含义：把数字 1（只有 bit 0 为 1）向左推 n 格，**造出一个只有第 n 位是 1 的数**（掩码）
- 置 1 套路：`data | (1 << n)`；清 0 套路：`data & ~(1 << n)`
- 同时操作多位：`data | ((1 << 14) | (1 << 15))` 把第 14、15 位置 1
- `printf` 默认是**行缓冲**：没有 `\n` 时输出卡在缓冲区，屏幕上看不到

### 踩过的坑
- 运行程序后终端没有任何输出 → 不是代码写错了，是 `printf` 最后没加 `\n`，输出卡在缓冲区没刷新
- 把 `1 << 14` 里的 `1` 理解为"第 1 位"→ 实际 `1` 是只有 bit 0 为 1 的数字，`14` 是左移的格数
- 不理解 "bit 3" 是什么意思 → bit 编号从 0 开始，bit 3 的权重是 2³ = 8

### 正确做法
```c
// 打印整数的二进制表示（从高位到低位）
void print_binary(unsigned int num) {
    for (int i = 31; i >= 0; i--) {
        printf("%u", (num >> i) & 1);   // 逐位剥出 0 或 1
        if (i % 8 == 0 && i != 0) printf(" ");
    }
    printf("\n");   // 最后一定要有换行！否则输出不显示
}

// 置 1：第 14、15 位设为 1
data = data | ((1 << 14) | (1 << 15));

// 清 0：第 22、23 位设为 0
data = data & ~((1 << 22) | (1 << 23));
```
核心思路：**置 1 用 `|`，清 0 用 `& ~`。`1 << n` 是造一个只有第 n 位为 1 的"掩码"，然后把它作用到 data 上。**

### 关键词
按位或 按位与 按位异或 按位取反 左移 右移 位操作 掩码 置1 清0 printf 缓冲区 换行 \n 二进制

---

## 2026-07-15  printf 格式占位符、二进制输出原理、unsigned 与形参实参

### 知识点
- `%u` 以十进制输出无符号整数；`%x` 输出小写十六进制；`%X` 输出大写十六进制
- `%%` 用来输出一个字面百分号 `%`，因为 `%` 在 printf 中是格式引入字符
- 计算机内部所有整数都以**二进制**存储，打印二进制不是"计算"二进制，而是把内存中已有的二进制位逐位"剥"出来
- `(n >> i) & 1` 可取出无符号整数 n 的第 i 位（bit 0 为最低位），循环从高到低即可输出完整二进制
- `unsigned int` 参数不是为了"把数变成二进制"，而是保证右移为**逻辑右移**（高位补 0），避免有符号数右移补 1 导致错误
- C 语言函数参数传递是**值传递**，形参是实参的副本，修改形参不影响外部的实参；要修改外部变量需传指针
- 代码中的十六进制字面量（如 `0xFF`）本身就是整数，可直接参与运算，无需"转换"

### 踩过的坑
- 误以为 `%%` 是两个格式符，或直接写 `%` 就能输出 `%` → 实际单写 `%` 会被当作占位符起始，输出乱码或出错
- 认为二进制输出函数内部应该用"除 2 取余"→ 整数在内存中已是二进制，函数只需读取各位，用移位和按位与更高效
- 以为在参数前加 `unsigned` 能把一个数变成二进制 → `unsigned` 只改变位模式的解读规则，不改变底层二进制
- 记混"形参不能用"的情形：以为函数内不能修改形参 → 实际可以直接使用和修改，只是修改不影响外部实参

### 正确做法
```c
// 打印二进制：移位取位法（不是除 2 取余法）
void print_binary(unsigned int num) {   // unsigned 保证逻辑右移
    for (int i = 31; i >= 0; i--) {
        printf("%u", (num >> i) & 1);
    }
}

// 输出字面百分号
printf("100%%\n");   // 输出 100%
```
核心思路：**二进制已在内存中，函数只是"读取"而非"计算"；unsigned 保证右移安全。**

### 关键词
printf %u %x %X %% 格式占位符 二进制输出 移位取位 unsigned 逻辑右移 值传递 形参 实参

---

## 2026-07-15  C语言练习题错题复盘：关键字、整数除法、自增、格式化输出

### 知识点
- `main` 是函数名，**不是** C 语言关键字；C 共有 32 个关键字（`int`、`char`、`const`、`if`、`while` 等）
- 整数除法：两个 `int` 相除，结果仍为 `int`（截断取整），若想要浮点数需将其中一个操作数强转为 `float` 或 `double`
- 转义字符 `\n` 的标准含义是**换行**（光标移到下一行开头）；"刷新缓冲区"是行缓冲模式下的副作用，不是 `\n` 本身的定义
- `%d` 输出有符号十进制整数，`%u` 输出无符号十进制整数，`%c` 输出字符
- `%x` 输出小写十六进制（`ff`），`%X` 输出大写十六进制（`FF`）
- `%f` 默认保留 6 位小数
- 后置自增 `a++`：表达式的值是自增**前**的值；前置自增 `++a`：表达式的值是自增**后**的值
- 在一个表达式中对同一变量多次修改且没有序列点隔开（如 `a++ + ++a`），属于**未定义行为（Undefined Behavior）**，不同编译器结果可能不同

### 踩过的坑
- **单选 1**：误以为 `main` 是关键字 → 实际 `main` 只是程序入口函数名，不是保留字
- **单选 6**：以为 `a / 2`（a=5）会得到 `2.5` 且类型为 `double` → 实际两个 int 做除法，结果是 `2`，类型 `int`（整数除法截断）
- **填空 3**：凭运行经验把 `\n` 写成"换行+清空输出缓存"→ 考试/教材只认"换行"，清缓存不是其标准定义
- **填空 5**：把"有符号整数"的格式符误写成 `%u` → `%u` 专用于无符号，有符号十进制必须用 `%d`
- **填空 6**：把 `a++` 表达式的值误写成 6、a 自增后误写成 5，顺序反了
- **阅读 1**：输出写成 `c = 3.0` → `%f` 默认保留 6 位小数，实际是 `c = 3.000000`
- **阅读 2**：把十六进制写成大写 `FF` → `%x` 输出小写 `ff`
- **阅读 3**：`a++ + ++a` 结果因编译器而异，但考试按**未定义行为**理解即可，不必纠结具体数值

### 正确做法
```c
// 整数除法 → 浮点结果
int a = 5;
double result = (double)a / 2;   // 2.5，必须强转一个操作数

// 自增运算
int a = 5;
int b = a++;    // b = 5（旧值），a = 6
int c = ++a;    // a 先变成 7，c = 7

// 正确的格式占位符
printf("%d\n",   -42);   // 有符号十进制
printf("%u\n",    42);   // 无符号十进制
printf("%x\n",   255);   // ff（小写十六进制）
printf("%f\n",   3.0);   // 3.000000（默认 6 位小数）
printf("%%\n");          // 输出字面 %
```
核心思路：**int/int = int（截断），想得浮点就强转；a++ 取值后加，++a 先加后取值；%d 有符号，%u 无符号。**

### 关键词
C关键字 main 整数除法 截断 转义字符 \n 自增 a++ ++a 未定义行为 printf %d %u %x %f %% 错题复盘

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
