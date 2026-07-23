# Lua Obfuscator & VM Protector

Lua 代码混淆工具，支持多种混淆技术和 VM 字节码虚拟化保护。


**当前版本：v2.10.0**

## 功能概览

| 功能 | 说明 | 默认 |
|------|------|------|
| 字符串加密 | 分层字符串池：独立密钥、切片乱序、哈希索引、多态解码 | 开启 |
| 变量名混淆 | 局部变量名替换为随机标识符 | 开启 |
| 常量数字加密 | 数字常量替换为安全算术/位运算表达式 | 开启 |
| 虚假控制流增强 | 注入不可达的复杂分支 | 开启 |
| 垃圾注释注入 | 插入无意义注释增加噪音 | 开启 |
| 基本块拆分 | 函数体拆分为基本块并用 goto/label 连接 | 开启 |
| 指令替换 | 原子表达式等价替换 | 开启 |
| 控制流平坦化 | switch-case 调度器重组执行流 | 开启 |
| BCF 虚假控制流 | 不透明谓词虚假分支（仅包装完整语句） | 开启 |
| 调用间接化 | 全局函数调用经分发表间接化 | 开启 |
| 反调试检测 | hook/计时/JIT 检测 | 关闭 |
| VM 字节码虚拟化 | 源码编译为自定义字节码 + 解释器 | 关闭 |
| 函数级VM保护 | 通过--@vm注解选择性保护关键函数，独立VM字节码 | 关闭 |

### P1：预设 / 白名单 / 配置

| 能力 | 说明 |
|------|------|
| 预设 `fast` / `balanced` / `max` | 一键切换保护强度 |
| 名称白名单 | 指定标识符不被变量混淆 |
| 字符串白名单 | 指定字符串保持明文 |
| 配置导出/导入 | CLI Lua 表 / Web JSON |

> Pass 设计目标为**相互独立、可任意组合**。开启 VM 时不会静默禁用其他 Pass。

## 项目结构

```
lua-obfuscator/
├── index.html              # Web 界面（含 Fengari Lua VM）
├── obfuscator.lua          # 主程序（CLI + JS Bridge）
├── obfuscator_bundle.lua   # 构建产物
├── pass_manager.lua        # Pass 管理框架
├── build_bundle.lua        # 构建脚本
├── build_html.js           # 注入 index.html
├── passes/                 # Pass 模块
│   ├── init.lua / utils.lua / string_pool.lua
│   ├── vm.lua / vm_protect.lua
│   ├── string_encrypt.lua / num_encrypt.lua / var_mangle.lua
│   ├── instr_sub.lua / adv_fake_cf.lua / cf_flatten.lua
│   ├── bcf.lua / bb_split.lua / junk_comment.lua
│   └── anti_debug.lua / call_indirect.lua / header.lua
├── tests/
└── README.md / PROJECT.md / PASS_API.md / JS_API.md
```

## 使用

### Web

1. 打开 `index.html`（或 GitHub Pages）
2. 选择预设 / Pass / 填写白名单
3. 点击「混淆」/「运行混淆后」
4. 可导出/导入配置 JSON

### CLI

```bash
lua obfuscator.lua -i input.lua -o output.lua
lua obfuscator.lua --preset fast -i input.lua -o out.lua
lua obfuscator.lua --preserve-name keep_me --preserve-string KEEP_PLAIN -i in.lua -o out.lua
lua obfuscator.lua --export-config mycfg.lua
lua obfuscator.lua --import-config mycfg.lua -i in.lua -o out.lua
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
lua tests/test_p0_regression.lua
lua tests/test_p1_presets_whitelist.lua
lua tests/test_full.lua
lua tests/test_string_pool_regression.lua
```

## 版本历史（摘要）

| 版本 | 日期 | 变更 |
|------|------|------|
| **2.9.0** | 2026-07-23 | 预设 fast/balanced/max；名称/字符串白名单；配置导出导入（CLI+Web） |
| **2.8.2** | 2026-07-23 | P0 回归 CI、流水线超时、Web 混淆超时 |
| **2.8.1** | 2026-07-23 | 修复 var_mangle 表扫描死循环；默认除 VM/反调试外全开 |
| **2.8.0** | 2026-07-23 | 稳定性大修、字符串池/反调试/调用间接化 |
| 2.7.x | 2026-07 | 反调试、调用间接化、字符串池 Fengari 修复 |
| 2.6.0 | 2026-07 | 发布整理、基本块拆分 Web 同步 |

## License

MIT · Author: Rainy_qwq · [GitHub](https://github.com/Rainyqwq/Lua-Obfuscator)
