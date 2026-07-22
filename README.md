# Lua Obfuscator & VM Protector

Lua 代码混淆工具，支持多种混淆技术和 VM 字节码虚拟化保护。

> **VM 保护注意**：启用 VM 字节码虚拟化时，指令替换、控制流平坦化、BCF 虚假控制流三个 Pass 会自动禁用（它们通过正则重写会破坏 VM 生成的字节码解释器）。字符串加密、变量名混淆、常量数字加密、虚假控制流增强、垃圾注释注入与 VM 兼容，仍会正常执行。

## 功能概览

| 功能 | 说明 | 默认 |
|------|------|------|
| 字符串加密 | 字符串常量替换为运行时解密调用 | ✅ 开启 |
| 变量名混淆 | 局部变量名替换为随机标识符 | ✅ 开启 ⚠️ |
| 常量数字加密 | 数字常量替换为数学运算表达式 | ✅ 开启 ⚠️ |
| 虚假控制流增强 | 注入不可达的复杂分支 | ✅ 开启 |
| 垃圾注释注入 | 插入无意义注释增加噪音 | ✅ 开启 |
| 指令替换 | 简单运算等价替换 | ❌ 关闭 |
| 控制流平坦化 | switch-case 调度器重组执行流 | ❌ 关闭 |
| BCF 虚假控制流 | 不透明谓词虚假分支 | ❌ 关闭 |
| VM 字节码虚拟化 | 源码编译为自定义字节码 | ❌ 关闭 |
| 基本块拆分 | 函数体拆分为基本块并用 goto/label 连接 | ❌ 关闭 |
 
标注 ❌ 的 Pass 存在已知稳定性问题，默认关闭，可手动开启（VM 模式下会被自动禁用）。
标注 ⚠️ 的 Pass 默认开启且在多数场景下稳定，但存在边缘案例（见下方已知问题）。

### 已知问题

| Pass | 问题 | 触发条件 | 修复状态 |
|------|------|----------|----------|
| 变量名混淆 | 错误重命名表字段键 | `local t = {name="x", value=42}` 中的字段键被重命名，但 `t["value"]` 仍引用原名 | 待修复 |
| 常量数字加密 | 错误加密标识符中的数字 | `ok2` → `ok(0xEC27~0xEC25)`，破坏变量声明语法 | 待修复 |
| 指令替换 | 等价替换改变语义 | 复杂表达式中的算术运算 | 不稳定 |
| 控制流平坦化 | elseif 链嵌套错误 | 长 elseif 链 + 深嵌套 | 不稳定 |
| BCF 虚假控制流 | 破坏控制流结构 | if/for/while 行后注入 | 不稳定 |
| 基本块拆分 | goto/label 跳转可能破坏局部变量作用域 | 含 local 声明的函数体 | 不稳定 |

## 项目结构

```
lua-obfuscator/
├── index.html              # Web 界面（含 Fengari Lua VM）
├── obfuscator.lua          # 主程序（CLI + JS Bridge）
├── obfuscator_bundle.lua   # 构建产物（所有模块内联）
├── pass_manager.lua        # Pass 管理框架
├── build_bundle.lua        # 构建脚本
├── passes/                 # Pass 模块目录
│   ├── init.lua            # Pass 加载器
│   ├── utils.lua           # 通用工具函数
│   ├── string_pool.lua     # 字符串池（提取/恢复）
│   ├── vm.lua              # VM 编译器/解释器
│   ├── vm_protect.lua      # VM 保护 Pass
│   ├── string_encrypt.lua  # 字符串加密 Pass
│   ├── var_mangle.lua      # 变量名混淆 Pass
│   ├── num_encrypt.lua     # 常量数字加密 Pass
│   ├── instr_sub.lua       # 指令替换 Pass（不稳定）
│   ├── adv_fake_cf.lua     # 虚假控制流增强 Pass
│   ├── cf_flatten.lua      # 控制流平坦化 Pass（不稳定）
│   ├── bcf.lua             # BCF 虚假控制流 Pass（不稳定）
│   ├── bb_split.lua       # 基本块拆分 Pass（不稳定）
│   ├── junk_comment.lua    # 垃圾注释注入 Pass
│   └── header.lua          # 代码头部 Pass
├── tests/                  # 测试文件
│   ├── test_85.lua         # 85 项核心测试
│   ├── test_full.lua       # 119 项完整测试
│   ├── test_closure.lua    # 闭包专项测试
│   ├── test_bbsplit.lua    # 基本块拆分测试
│   └── test_comprehensive.lua  # 全面特性测试
├── examples/               # 示例输出
├── PASS_API.md             # Pass 接口文档
├── JS_API.md               # JavaScript API 文档
└── PROJECT.md              # 项目详细文档
```

## 快速开始

### Web 界面

直接打开 `index.html`，输入代码后点击「混淆」。

### CLI

```bash
lua obfuscator.lua -i input.lua -o output.lua
lua obfuscator.lua -i input.lua --vm          # 启用 VM 保护
lua obfuscator.lua -i input.lua --no-var      # 禁用变量名混淆
```

### 构建 Bundle

```bash
lua build_bundle.lua    # 生成 obfuscator_bundle.lua
```

## 测试

```bash
lua tests/test_85.lua       # 85 项核心测试
lua tests/test_full.lua     # 119 项完整测试
```

## 添加自定义 Pass

在 `passes/` 下新建文件，实现标准接口：

```lua
-- passes/my_pass.lua
local M = {}
M.name = "my_pass"
M.title = "自定义 Pass"
M.version = "1.0.0"
M.order = 55
M.enabled = true

function M.apply(code, ctx)
  -- 混淆逻辑
  return code
end

return M
```

在 `passes/init.lua` 的 `BUILTIN` 表中注册即可。

详细接口文档见 [PASS_API.md](PASS_API.md)。

## 技术栈

- **Lua 5.4** - 混淆引擎
- **Fengari** - 浏览器端 Lua VM（JS 实现）
- **Web Worker** - 后台异步混淆（可选）

## 许可证

MIT License · Author: Rainy_qwq

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 2.7.0 | 2025-07-22 | 性能优化（var_mangle/string_pool/pass_manager）；手机端响应式适配；bb_split 默认开启（CLI + Web）；BCF then/else 分支交换修复；bb_split JS 模板字面量转义修复 |
| 2.5.1 | 2025-07-22 | 修复 CLI 默认配置（三个不稳定 Pass 改为关闭）；VM 模式自动禁用不兼容 Pass；adv_fake_cf 修复 return 语句后注入 bug |
| 2.5.2 | 2025-07-22 | 新增基本块拆分 Pass（bb_split）；修复 return 语句编译错误；Web 端同步更新 |
| 2.5.0 | 2025-07-22 | Pass 架构重构，字符串池保护，Web Worker |
| 2.4.0 | - | 原始版本 |
