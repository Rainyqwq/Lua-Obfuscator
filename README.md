# Lua Obfuscator & VM Protector

Lua 代码混淆工具，支持多种混淆技术和 VM 字节码虚拟化保护。

**当前版本：v2.8.2**

## 功能概览

| 功能 | 说明 | 默认 |
|------|------|------|
| 字符串加密 | 分层字符串池：独立密钥、切片乱序、哈希索引、多态解码 | ✅ 开启 |
| 变量名混淆 | 局部变量名替换为随机标识符 | ✅ 开启 |
| 常量数字加密 | 数字常量替换为安全算术/位运算表达式（Fengari 安全） | ✅ 开启 |
| 虚假控制流增强 | 注入不可达的复杂分支 | ✅ 开启 |
| 垃圾注释注入 | 插入无意义注释增加噪音 | ✅ 开启 |
| 基本块拆分 | 函数体拆分为基本块并用 goto/label 连接 | ✅ 开启 |
| 指令替换 | 原子表达式等价替换 | ✅ 开启 |
| 控制流平坦化 | switch-case 调度器重组执行流 | ✅ 开启 |
| BCF 虚假控制流 | 不透明谓词虚假分支（仅包装完整语句） | ✅ 开启 |
| 反调试检测 | hook/计时/JIT 检测 | ❌ 关闭 |
| 调用间接化 | 全局函数调用经分发表间接化 | ✅ 开启 |
| VM 字节码虚拟化 | 源码编译为自定义字节码 + 解释器 | ❌ 关闭 |

> Pass 设计目标为**相互独立、可任意组合**。开启 VM 时不会静默禁用其它 Pass。

## 项目结构

```
lua-obfuscator/
├── index.html              # Web 界面（含 Fengari Lua VM）
├── obfuscator.lua          # 主程序（CLI + JS Bridge）
├── obfuscator_bundle.lua   # 构建产物（所有模块内联）
├── pass_manager.lua        # Pass 管理框架
├── build_bundle.lua        # 构建脚本
├── build_html.js           # 将 bundle 注入 index.html
├── passes/                 # Pass 模块目录
│   ├── init.lua
│   ├── utils.lua
│   ├── string_pool.lua
│   ├── vm.lua / vm_protect.lua
│   ├── string_encrypt.lua / num_encrypt.lua / var_mangle.lua
│   ├── instr_sub.lua / adv_fake_cf.lua / cf_flatten.lua
│   ├── bcf.lua / bb_split.lua / junk_comment.lua
│   ├── anti_debug.lua / call_indirect.lua / header.lua
├── tests/                  # 测试文件
├── README.md / PROJECT.md / PASS_API.md / JS_API.md
├── RELEASE_NOTES_v2.8.0.md
└── RELEASE_NOTES_v2.8.1.md
```

## 使用

### Web

1. 打开 `index.html`（或 GitHub Pages）
2. 勾选需要的 Pass，粘贴/编写 Lua 源码
3. 点击「混淆」/「运行混淆后」

### CLI

```bash
lua obfuscator.lua -i input.lua -o output.lua
lua obfuscator.lua --demo
lua obfuscator.lua --help
```

### 构建

```bash
lua build_bundle.lua
node build_html.js
```

## 测试

```bash
lua tests/test_p0_regression.lua  # P0: 单Pass/组合/语义对拍/防挂死
lua tests/test_full.lua           # 119 项语言特性
lua tests/test_85.lua      # 核心功能
```

## 版本历史（摘要）

| 版本 | 日期 | 变更 |
|------|------|------|
| **2.8.1** | 2026-07-23 | 修复 var_mangle 表构造扫描死循环（浏览器无 VM 也卡死）；默认除 VM/反调试外全开 |
| **2.8.0** | 2026-07-23 | 稳定性大修：VM for 步长/FORLOOP、num_encrypt 32 位安全、BCF 完整语句包装、去静默禁用；字符串池/反调试/调用间接化；Web 超时保护 |
| 2.7.x | 2026-07 | 反调试、调用间接化、字符串池 Fengari 修复 |
| 2.6.0 | 2026-07 | 发布整理、基本块拆分 Web 同步 |
| 2.5.x | 2025-07 | Pass 架构重构、字符串池、VM 保护 |

## License

MIT · Author: Rainy_qwq · [GitHub](https://github.com/Rainyqwq/Lua-Obfuscator)