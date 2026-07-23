# Lua Obfuscator v2.8.0 Release Notes

**发布日期：2026-07-23**

## 概要

v2.8.0 聚焦**正确性与可组合性**：修掉 VM / 数字加密 / BCF 等会导致错误结果或浏览器卡死的缺陷，并取消“启用 VM 时静默禁用其它 Pass”的做法。Pass 应各自正确、可任意组合。

## 新功能与能力（累计至 2.8.0）

- **增强字符串加密（string_pool）**  
  每字符串独立密钥、密文切片乱序、哈希索引、多态解码器、诱饵解码路径；Fengari 下使用 32 位安全算术，避免 `number has no integer representation`。
- **反调试（anti_debug）**  
  debug hook / 计时异常 / JIT 状态检测；Web 端放宽计时阈值，减少误报。
- **调用间接化（call_indirection）**  
  全局函数调用经分发表间接化。
- **VM op-pool + char-pool**  
  运行时操作码映射打乱 + 字符池编码，贴近真实 VM 保护形态。
- **Web**  
  运行超时 hook；功能开关默认可配置；移动端适配相关改动保留。

## 关键修复

### VM（`passes/vm.lua`）
- 数值 `for` 支持**负步长**（修复 `for i=#t,1,-1` 等，字符串解密器依赖此语义）。
- 修正 `FORLOOP` 继续条件运算符优先级错误（原先正步长几乎不退出 → 卡死）。
- 解释器增加**步数上限**，损坏字节码时快速失败而非挂死浏览器。

### 常量数字加密（`passes/num_encrypt.lua`）
- 禁止不安全的 `(n<<k)>>k` 在高位溢出后回不来的编码。
- 加法路径保证 `sum` 不超出目标位宽，避免 hex 截断。
- 手写 hex / `to_u32`，兼容 Fengari。

### BCF（`passes/bcf.lua`）
- **仅包装完整、括号平衡的单行语句**；禁止打断多行 `function(` / 未闭合调用（修复 `'end' expected near 'else'`）。

### 流水线（`obfuscator.lua`）
- **移除**启用 VM 时自动禁用 instruction_substitution / control_flow_flattening / bogus_control_flow / basic_block_splitting 的逻辑。

### 其它
- string_pool FNV/LCG 全面 32 位安全。
- 头注释版本统一为 v2.8。

## 破坏性/行为变化

- 启用 VM 后，用户勾选的结构类 Pass **会真正执行**（不再被静默关掉）。若旧文档写“VM 会自动禁用三者”，以本版为准。
- 混淆输出头部标识：`Lua Obfuscator v2.8`。

## 验证

- `tests/test_full.lua`：119/119  
- 全 Pass ± VM 对算法样例多轮回归通过  
- Fengari 执行 VM 输出样例通过  

## 升级说明

1. 拉取本版本后执行：`lua build_bundle.lua && node build_html.js`  
2. Web 用户 **Ctrl+F5** 刷新  
3. 建议重新混淆旧产物（旧 VM 循环语义有缺陷）

## License

MIT · Author: Rainy_qwq  
https://github.com/Rainyqwq/Lua-Obfuscator