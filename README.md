> 📒 历史月份： [2026-07](归档/2026-07.md) · [2026-08](归档/2026-08.md)

# 学习日记 · 2026-09

> 从 2026-09-01 起按月分文件。历史月份：[归档/2026-07](归档/2026-07.md) · [归档/2026-08](归档/2026-08.md)
> 格式规范见 [learning-log-guide.md](learning-log-guide.md)，新条目写在本标题下方（最新在最上面）。

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

