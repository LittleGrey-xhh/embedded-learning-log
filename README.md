# 嵌入式学习日记

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
