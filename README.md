# Lua Obfuscator & VM Protector v2.4

基于纯 Lua 实现的代码混淆器 + 自定义虚拟机保护工具。

## 功能概览

### 10 种混淆技术

| # | 技术 | 标识 | 说明 |
|---|------|------|------|
| 1 | 变量名混淆 | VarMangle | 将变量名替换为随机标识符 |
| 2 | 常量数字加密 | NumEnc | 数字转等价算术表达式（浮点IEEE 754无损） |
| 3 | 字符串加密 | StrEnc | XOR/字符编码多层加密 |
| 4 | 控制流平坦化 | CFE | 顺序代码转状态机调度 |
| 5 | BCF 虚假控制流 | BCF | 注入不透明谓词死代码块 |
| 6 | 指令替换 | InstrSub | 等价但更复杂的表达式替换 |
| 7 | 虚假控制流增强 | AdvFakeCF | 12种谓词生成器注入虚假分支 |
| 8 | 基本块拆分 | BBSplit | goto拆分函数体基本块 |
| 9 | 垃圾注释 | Junk | 注入无害注释干扰阅读 |
| 10 | VM 字节码虚拟化 | VM | 编译为自定义指令集在嵌入式VM中执行 |

### VM 虚拟化

将 Lua 源码编译为自定义字节码，嵌入纯Lua栈式VM解释器执行。

已支持：闭包/upvalue、for..in、数值for、while、repeat..until、do..end块、goto/label、break、多重赋值、CONCAT链、可变参数打包、快速排序。

## 使用方式

### CLI

```bash
./lua obfuscator.lua -i input.lua -o output.lua
./lua obfuscator.lua -i input.lua -o output.lua --vm
./lua obfuscator.lua -i input.lua -o output.lua --no-cfe --no-bcf
```

### 模块 API

```lua
local M = dofile("obfuscator.lua")
local result = M.obfuscate_code(code, {vm_protect = true})

local vm = dofile("vm_protect.lua")
local protected = vm.protect(code)
```

### 参数

| 参数 | 说明 |
|------|------|
| `-i FILE` | 输入文件 |
| `-o FILE` | 输出文件 |
| `--vm` | 启用VM字节码虚拟化 |
| `--no-cfe` | 禁用控制流平坦化 |
| `--no-bcf` | 禁用BCF虚假块 |
| `--no-advbcf` | 禁用虚假控制流增强 |
| `--no-bbsplit` | 禁用基本块拆分 |
| `--no-instr` | 禁用指令替换 |
| `--no-num` | 禁用数字加密 |
| `--no-str` | 禁用字符串加密 |
| `--no-var` | 禁用变量名混淆 |
| `--no-junk` | 禁用垃圾注释 |

### Web 前端

直接打开 `index.html`，无需服务器。通过 Fengari 调用同一份 Lua 代码。

## 测试

```bash
./lua test_85.lua        # 81项功能测试
./lua test_full.lua      # 119项完整测试
./lua test_closure.lua   # VM闭包测试
bash run_mixed.sh        # 混合模式一致性测试
```

结果：257项全部通过。

## 环境要求

- **CLI**: Lua 5.4+（自带解释器）
- **Web**: 现代浏览器，需联网加载 Fengari CDN

## 许可

MIT License
