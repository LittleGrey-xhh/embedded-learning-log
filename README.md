> 📒 历史月份： [2026-07](归档/2026-07.md) · [2026-08](归档/2026-08.md) · [2026-09](归档/2026-09.md) · [2026-10](归档/2026-10.md)

# 学习日记 · 2026-11

> 历史月份：[归档/2026-07](归档/2026-07.md) · [归档/2026-08](归档/2026-08.md) · [归档/2026-09](归档/2026-09.md) · [归档/2026-10](归档/2026-10.md)
> 格式规范见 [learning-log-guide.md](learning-log-guide.md)，新条目写在本标题下方（最新在最上面）。

---
# 11.2 笔记

## 一、干了什么

1. 把中控板从裸机重构成 FreeRTOS：拆出 LoRa 接收、MQTT、OLED 三个任务，全链路（小程序 → 巴法云 → MQTT → LoRa → 终端板 → 闭环确认）跑通，行为和裸机版一致。
2. 用二值信号量替掉 `while(!rx_done) HAL_Delay(1)` 的轮询，接收零丢帧。
3. 终端板加光照采集（ADC + DMA）和蜂鸣器（TIM4_CH4 PWM），并把两者联动。
4. 巴法云新建蜂鸣器主题 `krzIenwb5006`，接通 MQTT 手动控制蜂鸣器。
5. 蜂鸣器始终不响，用 ACK 帧 + GPIO 自检把问题从"整条链路"缩到"PWM 或硬件"，最终定位到蜂鸣器本体，明天继续。

---

## 二、知识点

### 1. ★★★ `osKernelStart()` 之前不许有任何阻塞或死循环

CubeMX 保留 `USER CODE BEGIN 2` 区，老工程那句 `app_main();` 留在原地。而 `app_main()` 内部是 `while(1)`，永远不返回：

```c
MX_FREERTOS_Init();
osKernelStart();     // ← 永远执行不到
```

**后果不是报错，是"板子照常跑裸机逻辑，你完全看不出 RTOS 没启动"。**

这是移植最容易踩的一脚，因为所有外设初始化都正常，串口也正常打印，只有调度器没起来。

**铁律：`main()` 里 `osKernelStart()` 之前只允许配外设，不许有任何业务逻辑。**

### 2. ★★★ `delay_ms` 改 `vTaskDelay`，一行解决 12 秒调度器停摆

```c
void delay_ms(int nms) { HAL_Delay(nms); }              // 改前
void delay_ms(int nms) { vTaskDelay(pdMS_TO_TICKS(nms)); }  // 改后
```

`HAL_Delay()` 是"读 uwTick 死等到够数"，**全程占着 CPU 不让出**。而 `esp_mqtt_init()` 里有 6 个 `delay_ms(2000)`，合计 12 秒。

改之前的串口是**完全静默 12 秒**（LoRa 那 6 帧全丢）；改之后两个任务交错输出：

```
[21:29:10.836] [init] 7/10 connect_server     ← MQTT 在连服务器
[21:29:11.304] [lora] #9  type=1 v1=252 v2=590   ← LoRa 同时收数据
[21:29:13.003] [init] 8/10 entry_transparent
[21:29:13.309] [lora] #10 type=1 v1=251 v2=589
```

**只改底层一个函数，上层几十处调用全部自动生效。**这比逐个替换调用点可靠得多。

### 3. ★★★ 中断 → 信号量 → 任务，替掉轮询

```c
// 裸机：等的时候 CPU 原地空转
while (!rx_done && !rx_timeout) {
    if (HAL_GetTick() - start > 60) break;
    HAL_Delay(1);
}

// RTOS：等的时候任务挂起，CPU 让给别人
xSemaphoreTake(g_lora_rx_sem, pdMS_TO_TICKS(60));
```

**驱动写成双模式最划算**：信号量为 NULL 时自动退回轮询，这样同一份 `llcc68_p2p.c` 在裸机工程和 RTOS 工程都能用，不用维护两份。

两个细节：
- 中断里 `xSemaphoreGiveFromISR(sem, &woken)` 之后必须 `portYIELD_FROM_ISR(woken)`，否则要等下一个 tick 才切任务
- `Take` 之前先清一遍残留（`while (xSemaphoreTake(sem, 0) == pdTRUE) {}`），否则上一轮的 give 会让这次立刻返回，表现为"收得特别快但全是垃圾数据"

### 4. ★★★ 能在中断里调 FreeRTOS API 的优先级，必须 ≥ `configMAX_SYSCALL_INTERRUPT_PRIORITY`

CubeMX 给 EXTI15_10 配的是 **3**，而 `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY` 是 **5**。

STM32 的 NVIC 是**数值越小优先级越高**，所以 3 比 5 更"高"，属于 FreeRTOS 管不着的层级。在里面调 `xSemaphoreGiveFromISR` 会命中 `vPortValidateInterruptPriority()` 的断言。

**现象是"一收到 LoRa 就死机"**，而且不会告诉你是优先级的问题。

改法：`HAL_NVIC_SetPriority(EXTI15_10_IRQn, 6, 0);` 写在 `MX_FREERTOS_Init()` 里，别改 `Core/Src/gpio.c`（Generate 会冲掉）。

### 5. ★★ 队列的两个参数决定语义，别乱配

| 用途 | 深度 | API | 理由 |
|---|---|---|---|
| 环境数据（LoRa → MQTT） | **1** | `xQueueOverwrite` | 上报只要最新值，旧的覆盖掉，慢的一方不会积压 |
| 控制指令（MQTT → LoRa） | **4** | `xQueueSend` | 连点几下不能丢 |

深度 1 + `Overwrite` 是"永远保留最新"的标准写法；深度 1 + `Send` 会变成"满了就丢新数据"，语义正好相反。

### 6. ★★ 两个触发源控制同一个执行器，必须先用标志合成再执行

蜂鸣器有两个触发源：光照太暗、巴法云下发 `on`。

**错误写法**（两边各自调 `BEEP_Alarm`）：

```c
if (太暗)     BEEP_Alarm(1);
if (变亮了)   BEEP_Alarm(0);
if (远端 on)  BEEP_Alarm(1);
```

MQTT 刚让它响，200ms 后光照判断"不够暗"立刻把它关掉，**互相打架**。

**正确写法**：各自只改自己的标志，在固定节拍里统一合成。

```c
static uint8_t beep_by_light, beep_by_remote;

每 20ms：BEEP_Alarm(beep_by_light || beep_by_remote);
```

这条对任何"多来源控制一个设备"的场景都成立（比如以后的电机、继电器）。

### 7. ★★ 没有串口时的调试手段：让对端回一帧 ACK

终端板的 CH340 接触不良，看不到它的打印，"指令发到了没"完全抓瞎。

解法：**让终端板收到控制帧后立刻回一帧 ACK**，借中控板的串口打出来。

```c
// 终端板
frame_build(frame, TYPE_ACK, CMD_BEEP, beep_by_remote, s_led_state);
llcc68_lora_send(&llcc68_ctx, frame, FRAME_LEN, 1000);
```

```
[lora] *** ACK from terminal: cmd=0x03 val=1
```

`val=1` 这一条就把"指令到了、进对了分支、变量置对了"全部证明掉，**问题范围立刻从"整条链路"缩到"PWM 或硬件"**。

**这是"链路分段验证"思路的具体实现**：哪一段看不到，就让它的对端帮你把结果带出来。

### 8. ★★ J-Link ARM-OB 的速度，两块板不一样

| 板 | 可用速度 | 现象 |
|---|---|---|
| 中控板 | 400kHz | 正常 |
| 终端板 | **100kHz** | 400kHz 报 `Verification of RAMCode failed` |

`RAMCode` 是 J-Link 下载算法（跑在目标 RAM 里），写进去读回来不一致就是速度太快。**看到这个错误先降速，别怀疑接线。**

这块 J-Link 是 2012 年固件的克隆 OB，对速度很挑。

### 9. ★ 阻塞式接收会把"20ms 节拍"拖成 1 秒

终端板主循环：

```c
while (1) {
    20ms 节拍块           // 想每 20ms 跑一次
    ...
    receive_data(1000);   // 但这里阻塞 1000ms
}
```

节拍块实际每 1 秒才执行一次。**凡是在主循环里塞"高频节拍"的，先检查循环里有没有阻塞调用。**

修法：把接收超时降到 20ms，让循环真正转起来（代价是每圈多几次 `receive_mode` 的 SPI 配置开销）。

### 10. ★ 有源蜂鸣器的 PWM 占空比不能太低

8kHz × 4.8% = 每个周期只通电 **6 微秒**。

有源蜂鸣器的机械响应时间是几十微秒量级，**6us 根本来不及让它动**。表现是"完全不响"，而不是"声音小"。

**降音量要靠占空比，但下限大约在 20~30%**，再低就起不了振。真要更小声，串电阻比压占空比可靠。

---

## 三、RTOS 概念速查（附本项目实际用法）

下面这张表按"通用概念 / 本项目用了没"对照着记。**只看概念容易飘，标上实际状态才知道自己真正掌握了什么。**

| 概念 | 本质 | 本项目实际状态 |
|---|---|---|
| **Task** | 拥有独立栈的无限循环函数 | ✅ 4 个任务。没有进程隔离，所以全局变量是共享的 |
| **NVIC 优先级** | 中断的抢占等级，数值越小越高 | ⚠️ EXTI15_10 从 CubeMX 的 3 **改成 6**。必须 ≥ `configMAX_SYSCALL_INTERRUPT_PRIORITY`(5) |
| **EXTI** | 外部中断，感知突发事件 | ✅ DIO1(PB10) 用上升沿。⚠️ **PB12 按键中断里还有 `delay_nms(15)` 空转，RTOS 下要删** |
| **DMA** | 硬件搬运数据，不占 CPU | ✅ 终端板 ADC1 用它搬 `adc1_value[]`，**连续模式，没开 DMA 中断**（用不上信号量） |
| **二值信号量** | 0/1 标志，做同步通知 | ✅ `g_lora_rx_sem`。中断 give、任务 take，替代了 `while(!rx_done)` 轮询 |
| **队列** | 任务间传数据，自带同步 | ✅ 两个，方向相反：`env_queue`（深度1+Overwrite）和 `cmd_queue`（深度4+Send） |
| **互斥量 Mutex** | 带所有权的二值信号量，支持优先级继承 | ❌ **一个都没用**。`configUSE_MUTEXES=1` 只是开了编译开关 |
| **SPI** | 4 线高速总线（SCK/MOSI/MISO/CS） | ✅ 驱动 LLCC68。**只有 `loraTask` 用，单任务独占所以不需要锁** |
| **I2C** | 2 线低速总线（SCL/SDA），开漏+上拉 | ✅ 驱动 OLED。**只有 `oledTask` 用，也不需要锁** |
| **UART** | 点对点串口 | ✅ 中控板 USART2 接 ESP12-F。⚠️ 它是 `HAL_UARTEx_ReceiveToIdle_IT` 空闲中断收整包，**不是 DMA 方式** |
| **CS 片选** | 告诉 SPI 从机"在跟你说话" | ⚠️ LLCC68 的 NSS 在 `llcc68_hal.c` 里手动拉。**将来如果多个任务用 SPI，拉 CS 和发数据必须是一个原子段，在锁里面做** |
| **delay_us()** | 忙等待，占着 CPU 不让出 | ⚠️ 终端板 DHT22 还在用，而它**借 SysTick 当定时器**。RTOS 下要么换 DWT，要么用 `vTaskSuspendAll` 包住 |
| **vTaskDelay()** | 挂起任务，让出 CPU | ✅ `osDelay` 全是它。**关键收益：`esp_mqtt_init()` 那 12 秒不再卡死 LoRa 收数** |
| **portYIELD_FROM_ISR** | 中断里触发立即切换 | ✅ `DIO1_EXTI_Callback` 里调了。不调的话要等下一个 tick 才切任务，延迟 1ms |

**一句话总结这张表**：真正在用的只有 **Task、信号量、队列、vTaskDelay、EXTI→信号量** 这五样；Mutex、DMA 中断、事件组、任务通知都还没碰。**"学过"和"用过"是两件事，别混。**

### 本项目实际的完整数据流

```
                     ┌──────────── 中断层（只做"短平快"）────────────┐
  终端板发帧 ──空中──> DIO1(PB10) 上升沿 → EXTI15_10_IRQn
                     → HAL_GPIO_EXTI_Callback()
                     → DIO1_EXTI_Callback()   读 IRQ 状态+清除
                     → rx_done = true
                     → xSemaphoreGiveFromISR(g_lora_rx_sem)
                     → portYIELD_FROM_ISR()
                     └───────────────────┬───────────────────────────┘
                                         │ 唤醒
                     ┌───────────────────▼───────────────────────────┐
                     │ loraTask（AboveNormal / 1KB）                  │
                     │ 1. receive_mode(0)     进连续接收              │
                     │ 2. receive_data(50)    → xSemaphoreTake(50ms)  │
                     │ 3. 四查：长度/帧头/设备ID/校验和               │
                     │ 4. 更新 g_disp 快照（给 OLED 用）              │
                     │ 5. env_queue ← xQueueOverwrite(温度湿度)       │
                     │ 6. cmd_queue → 取指令，搭车发控制帧             │
                     └───────┬───────────────────────┬───────────────┘
                             │ env_queue(深度1)      ▲ cmd_queue(深度4)
                             ▼                       │
                     ┌───────────────────────────────┴───────────────┐
                     │ mqttTask（Normal / 1.5KB）                     │
                     │ 1. xQueueReceive(env) → esp_mqtt_set_env()     │
                     │ 2. esp_mqtt_poll()：收指令/心跳/10秒上报        │
                     │ 3. esp_mqtt_take_cmd/beep → cmd_queue          │
                     │ 4. osDelay(20)    ← 主动交出 CPU               │
                     └───────────────────────────────────────────────┘

                     ┌───────────────────────────────────────────────┐
                     │ oledTask（BelowNormal / 1KB）                  │
                     │ 拷 g_disp 快照 → 刷 4 行 → osDelay(1000)      │
                     └───────────────────────────────────────────────┘

   SysTick（FreeRTOS 独占）每 1ms 一跳 → 决定谁上 CPU、谁去睡觉
   TIM2（HAL 时基）每 1ms 一次     → HAL_GetTick() 靠它递增
```

**和通用架构图的区别，正是本项目最该记住的地方**：

1. **没有 Mutex** —— 每个外设只有一个任务碰，用不着锁。将来加第二个 SPI 设备才需要。
2. **没有 DMA 中断** —— ADC 连续转换，任务随时读最新值，比"搬完发信号量"更简单。
3. **有两条独立队列，方向相反** —— 这是双板架构决定的：环境数据往上传（只要最新），控制指令往下传（不能丢）。
4. **两个 1ms 时基分开** —— SysTick 归 FreeRTOS，TIM2 归 HAL。混用一个就是死锁。

---

## 四、踩的坑

1. **`app_main()` 挡在 `osKernelStart()` 前面**，RTOS 压根没启动，而所有外设看起来都正常。这个坑不报错、不报警，只能靠"任务里加心跳打印"发现。
2. **任务启动那两行打印只出现一次**，串口抓晚了就错过，差点误判成"任务没创建"。判据：看 `heap_free` 掉了多少 —— 掉了约 1200 字节就说明任务和信号量都建成功了。
3. **通过 bash 传给 `python -c` 的字符串会被两层转义**，`printf("...\r\n")` 里的 `\r\n` 变成真实换行，字符串字面量跨行，编译报 `missing closing quote`。以后这种改动用脚本文件，别用 `-c`。
4. **CubeMX 生成的是 `Template.uvprojx`，不是覆盖 `Terminal.uvprojx`**。两个 `.ioc` 的 ProjectName 都是 `Template`，所以每次 Generate 都新生成一个工程文件，原来的分组一个都不继承。

---

## 五、遗留

1. **蜂鸣器不响**（明天第一件事）。已排除：MQTT 链路、LoRa 下行（有 ACK）、TIM4 时钟和 PB9 复用配置、占空比过低。待验证：GPIO 直推能不能响、蜂鸣器是有源还是无源/三脚（**三脚是低电平触发，和现在的代码极性相反**）。
2. **终端板节拍被 1 秒阻塞拖慢**，蜂鸣器节奏会是"响 1 秒停 1 秒"，不是要求的 200/300ms。
3. **OLED 字库曾被链接器裁掉**（`RO-data` 只有 352 字节），现在 OLED 任务已经用上了，下次编译要留意 RO-data 应该回升到 15KB 左右。
4. **调试打印要收拾**：`esp_mqtt.c` 里那句 `[MQTT] rx topic=[..] payload=[..]` 是诊断用的，稳定后删掉。
5. **终端板还没移植 RTOS**，按计划压后，先解决蜂鸣器硬件。
6. **中控板按键中断里的 `delay_nms(15)` 还留着**：`ISR_callback.c` 的 `HAL_GPIO_EXTI_Callback()` 里，`GPIO_Pin == GPIO_PIN_12` 分支空转 15ms 做"软件去抖"。PB12 和 LoRa 的 DIO1(PB10) 同属 `EXTI15_10_IRQn`，按一下键就把 LoRa 中断堵住 15ms —— 正好可能错过终端板那一帧。RTOS 下的正确做法：中断里只置标志发信号量，去抖交给任务用 `vTaskDelay` 做。
