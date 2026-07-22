# 项目详细文档

## 架构

### 混淆流程

```
源代码
  ↓
字符串提取 (string_pool.extract)
  ↓ 全部字符串替换为 __STR0__, __STR1__... 占位符
  ↓
Pass Pipeline (按 order 排序)
  ├─ vm_protect (10)      - 源码→字节码→VM解释器
  ├─ string_encryption (20) - 字符串加密标记
  ├─ variable_mangling (30) - 变量名替换
  ├─ constant_encryption (50) - 数字加密
  ├─ advanced_fake_cf (65)  - 虚假分支注入
  ├─ basic_block_splitting (90) - 基本块拆分
  ├─ junk_comments (100)    - 垃圾注释
  └─ header (200)           - 代码头部
  ↓
字符串恢复 (string_pool.restore / restore_raw)
  ↓ 占位符替换为加密/原始字符串
  ↓
输出
```

### 字符串保护机制

所有 Pass 运行前，字符串被提取为占位符。Pass 只处理占位符，不接触字符串内容。Pass 运行后，占位符恢复为字符串。

这解决了：
- 变量名混淆破坏字符串内容
- 数字加密破坏格式字符串（`%s=%d`）
- 指令替换破坏模式字符串（`%a+`）

### Web 端架构

```
浏览器
├── 主线程
│   ├── Fengari Lua VM (window._luaState)
│   │   ├── package.preload (所有 Pass 模块)
│   │   ├── _obfuscator (混淆器模块)
│   │   └── _obfuscate_lua (包装函数)
│   └── UI 控制
└── runLua - 每次创建独立 Lua 状态机执行混淆结果
```

### 构建流程

```bash
lua build_bundle.lua
# 1. 读取 obfuscator.lua + 所有 passes/*.lua
# 2. 将 Pass 模块通过 package.preload 内联
# 3. 生成 obfuscator_bundle.lua
# 4. 嵌入 index.html（转义 \ ` ${）
```

## Pass 开发指南

### 标准接口

```lua
local M = {}
M.name = "pass_id"           -- 唯一标识
M.title = "显示名称"
M.version = "1.0.0"
M.order = 50                 -- 执行顺序
M.enabled = true             -- 默认启用

function M.apply(code, ctx)
  -- code: string 当前代码（字符串已被占位符替换）
  -- ctx.vm_module: VM 模块（仅 vm_protect 使用）
  -- ctx.config: Pass 配置
  return code                -- 返回变换后的代码
end

return M
```

### 注意事项

1. **不要破坏占位符**：`__STR0__` 等占位符在 Pass 运行后会被恢复
2. **不要破坏控制流结构**：避免在 `if/elseif` 链中间注入 `end`
3. **不要在 `then`/`do` 行后注入代码**：会破坏嵌套
4. **字符串中可能有 `%`**：`gsub` 替换串中 `%` 需转义为 `%%`

### 已知问题

| Pass | 问题 | 状态 |
|------|------|------|
| variable_mangling | 错误重命名表字段键（`local t = {name="x", value=42}` 中 `value` 被重命名） | 待修复 |
| constant_encryption | 错误加密标识符中的数字（`ok2` → `ok(0xEC27~0xEC25)`） | 待修复 |
| instruction_substitution | 等价替换在复杂表达式中改变语义 | 默认关闭 |
| control_flow_flattening | elseif 链偶发嵌套错误 | 默认关闭 |
| bogus_control_flow | 注入破坏多行语句和嵌套结构 | 默认关闭 |
| basic_block_splitting | goto/label 跳转可能破坏局部变量作用域 | 默认关闭 |

### VM 模式自动禁用

启用 VM 字节码虚拟化时，以下三个 Pass 会被自动禁用，避免破坏 VM 生成的字节码解释器：

- `instruction_substitution`（指令替换）- 正则重写破坏 VM 字节码语义
- `control_flow_flattening`（控制流平坦化）- switch-case 重构破坏 VM 解释器结构
- `bogus_control_flow`（BCF 虚假控制流）- 虚假分支注入破坏 VM 控制流

其余 Pass（字符串加密、变量名混淆、常量数字加密、虚假控制流增强、垃圾注释注入）与 VM 兼容，正常执行。

### v2.6.0 修复内容

1. **性能优化**：var_mangle 改为单次扫描 + table.concat（O(n) 替代 O(n*k)）；string_pool restore/restore_raw 改为单次 gsub（O(n) 替代 O(n*k)）；pass_manager 缓存 os.clock 引用
2. **手机端响应式适配**：768px + 480px 双断点 CSS；移动端面板垂直堆叠；resizer 移动端跳过鼠标拖拽
3. **bb_split 默认开启**：CLI 和 Web 端均默认启用基本块拆分 Pass
4. **BCF then/else 分支交换修复**：真实代码放 then（恒真谓词，总执行），假代码放 else
5. **bb_split JS 模板字面量转义修复**：build_html.js 将 bundle 反斜杠翻倍后注入 index.html

### v2.5.1 修复内容

1. **CLI 默认配置修复**：`instruction_substitution`、`control_flow_flattening`、`bogus_control_flow` 三个不稳定 Pass 的 CLI 默认值从 `true` 改为 `false`，与文档一致
2. **VM 兼容性修复**：VM 模式下自动禁用上述三个不兼容 Pass（见上方"VM 模式自动禁用"）
3. **adv_fake_cf return 修复**：虚假控制流增强 Pass 不再在 `return` 语句后注入代码块（Lua 要求 `return` 必须是块的最后一条语句）

## 测试

| 测试文件 | 项目数 | 说明 |
|----------|--------|------|
| test_85.lua | 81 | 核心功能验证 |
| test_full.lua | 119 | 完整功能覆盖 |
| test_closure.lua | - | 闭包专项 |
| test_comprehensive.lua | 42 | 全 Lua 特性覆盖（4/42 通过） |
| test_bbsplit.lua | - | 基本块拆分专项 |

```bash
lua tests/test_85.lua    # 快速验证
lua tests/test_full.lua  # 完整测试
```

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 2.5.1 | 2025-07-22 | 修复 CLI 默认配置；VM 模式自动禁用不兼容 Pass；adv_fake_cf 修复 return 语句注入 |
| 2.5.2 | 2025-07-22 | 新增基本块拆分 Pass（bb_split）；修复 return 语句编译错误；Web 端同步更新 |
| 2.5.0 | 2025-07-22 | Pass 架构重构，字符串池保护，Web Worker |
| 2.4.0 | - | 原始版本 |
