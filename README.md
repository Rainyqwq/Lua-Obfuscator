# Lua Obfuscator & VM Protector

Lua 代码混淆工具，支持多种混淆技术和 VM 字节码虚拟化保护。


**当前版本：v3.4.0**

## v3.4.0 更新亮点

-  **主题切换添加扩散动画**：基于 `document.startViewTransition`（Chrome 111+/Edge 111+），0.28s linear wipe，从按钮位置圆形扩散/收缩；旧浏览器走 JS fallback 兜底
-  **修复编辑器光标错位**：强制 `textarea.style.height = scrollHeight` 让 textarea 跟内容长高，caret 与 gutter 行号偏差 ≤ 0.19px
-  **解决VM 高级模式的bug**：JS 桥按 `typeof` 分发 boolean/string/number/array/null，不再把 `vm_mode='advanced'` 推成 boolean 丢弃
-  **可访问性**：`prefers-reduced-motion` / `prefers-reduced-transparency` / `prefers-contrast` 三条 media query 完整覆盖
-  **代码健壮性提升**： 修复9 处 bug（worker race / memory leak / null deref / 重复 resize listener 等）
-  **设计 token 化**：补 `--danger` / `--warn`（含 dark 变体），5 处硬编码替换

完整变更列表：[RELEASE_NOTES_v3.4.0.md](RELEASE_NOTES_v3.4.0.md)

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
| VM 高级模式 | 样本模式：U 表状态机 + 4 模式动态索引 + S 表 hex 编码 | 关闭 |

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
│   ├── vm.lua / vm_protect.lua / vm_advanced.lua
│   ├── string_encrypt.lua / num_encrypt.lua / var_mangle.lua
│   ├── instr_sub.lua / adv_fake_cf.lua / cf_flatten.lua
│   ├── bcf.lua / bb_split.lua / junk_comment.lua
│   ├── anti_debug.lua / call_indirect.lua / header.lua
│   ├── api_indirect.lua / string_restore.lua
│   └── vm_function.lua
├── tests/
├── DESIGN/                 # UI 设计规范
├── README.md / PROJECT.md / PASS_API.md / JS_API.md
└── RELEASE_NOTES_v*.md
```

## 使用

### Web

1. 打开 `index.html`（或 GitHub Pages）
2. 选择预设 / Pass / 填写白名单
3. 点击「混淆」/「运行混淆后」
4. 可导出/导入配置 JSON
5. 点击右上角 🌙 / ☀️ 按钮切换主题——**圆形 wipe 动画** 从按钮位置扩散到全屏（dark→light 收缩回按钮）

### CLI

```bash
lua obfuscator.lua -i input.lua -o output.lua
lua obfuscator.lua --preset fast -i input.lua -o out.lua
lua obfuscator.lua --preserve-name keep_me --preserve-string KEEP_PLAIN --in in.lua -o out.lua
lua obfuscator.lua --export-config mycfg.lua
lua obfuscator.lua --import-config mycfg.lua -i in.lua -o out.lua
lua obfuscator.lua --vm-mode advanced -i in.lua -o out.lua   # 高级 VM 模式
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
lua tests/test_vm_mangle_string.lua
```

## 版本历史（摘要）

| 版本 | 日期 | 变更 |
|------|------|------|
| **3.4.0** | 2026-08-20 | 编辑器光标对齐修复、VM 高级模式生效、主题切换扩散动画、UI 设计规范合规、a11y 全面覆盖 |
| 3.3.0 | 2026-08-14 | 高级 VM 模式（样本模式）、api_indirect Pass、数字加密强化、单行输出 |
| 3.1.0 | 2026-08 | VM marker 修复、`__vm_N` scope in `vm_function` |
| 3.0.0 | 2026-08 | Web var_mangle escape 修复；vm_function 默认启用 |
| **2.10.0** | 2026-07 | vm_function 自动标签（max 预设）；string_pool 修复 |
| **2.9.0** | 2026-07-23 | 预设 fast/balanced/max；名称/字符串白名单；配置导出导入（CLI+Web） |
| 2.8.2 | 2026-07-23 | P0 回归 CI、流水线超时、Web 混淆超时 |
| 2.8.1 | 2026-07-23 | 修复 var_mangle 表扫描死循环；默认除 VM/反调试外全开 |
| 2.8.0 | 2026-07-23 | 稳定性大修、字符串池/反调试/调用间接化 |

## License

MIT · Author: Rainy_qwq · [GitHub](https://github.com/Rainyqwq/Lua-Obfuscator)
