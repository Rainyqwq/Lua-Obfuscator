# 项目详细文档

**版本：v2.8.1**

## 架构

### 混淆流程

```
源代码
  ↓
字符串提取 (string_pool.extract)   — 非 VM 路径
  ↓ 字符串 → __STRn__ 占位符
  ↓
Pass Pipeline（按 order 排序，用户启用的全部执行，不静默禁用）
  ├─ vm_protect (10)           VM 字节码虚拟化
  ├─ anti_debug (15)           反调试
  ├─ string_encryption (20)    字符串加密标记
  ├─ variable_mangling (30)    变量名混淆
  ├─ instruction_substitution (40)
  ├─ constant_encryption (50)  常量数字加密
  ├─ advanced_fake_cf (65)
  ├─ control_flow_flattening (70)
  ├─ bogus_control_flow (80)
  ├─ call_indirection (85)
  ├─ basic_block_splitting (90)
  ├─ junk_comments (100)
  └─ header (200)
  ↓
字符串恢复 (string_pool.restore / restore_raw)  — 非 VM 路径
  ↓
输出
```

> VM 路径下字符串由 VM 自己的 char-pool / 常量编码处理，跳过 string_pool 提取/恢复。

### 设计原则

1. **Pass 独立**：每个 Pass 应在任意合法 Lua 输入上保持语义；组合失败优先修 Pass，而非在流水线里静默关闭。
2. **Fengari 安全**：位运算与 `string.format("%X")` 前必须 `to_u32` / 手写 hex，避免 “number has no integer representation”。
3. **Web / CLI 同源**：`build_bundle.lua` + `build_html.js` 把模块内联进 `index.html`。

### 关键模块

| 文件 | 职责 |
|------|------|
| `obfuscator.lua` | CLI、Config、JS Bridge、`obfuscate_code` |
| `pass_manager.lua` | 注册 / 排序 / 执行 Pipeline |
| `passes/string_pool.lua` | 字符串提取与分层加密恢复 |
| `passes/vm.lua` | 解析 → 编译 → op-pool/char-pool 编码 → 解释器源码 |
| `passes/num_encrypt.lua` | 安全数字字面量加密 |
| `index.html` | Fengari 前端、Worker 混淆、运行超时 hook |

### 构建

```bash
lua build_bundle.lua   # → obfuscator_bundle.lua
node build_html.js     # 注入 index.html 的 OBFUSCATOR_LUA
```

### 测试建议

- `tests/test_full.lua`：语言特性基线  
- 组合：全 Pass ± VM 对 fib 等样例做 10+ 轮随机种子回归  
- Web：Ctrl+F5 后测「混淆 / 运行混淆后」

## 已知边界

- 文本 Pass 基于行/正则，极端多行表达式仍可能有边角问题  
- 反调试的 hook 检测会在外层 `debug.sethook` 时主动报错（预期行为）  
- VM 解释器设有步数上限，防止损坏字节码导致浏览器卡死  

## License

MIT · Rainy_qwq