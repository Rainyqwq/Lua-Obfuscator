# Lua Obfuscator & VM Protector - 项目文档

## 项目概述

基于纯 Lua 实现的代码混淆器 + 自定义虚拟机保护工具。

**运行环境**: Lua 5.4+
**项目版本**: v2.4.0
**最后更新**: 2026-07-19

---

## 文件结构

```
lua-obfuscator/
├── obfuscator.lua       # 主混淆器 - 10种混淆技术 + 模块API
├── vm_protect.lua       # VM字节码虚拟化 - 解析器+编译器+VM解释器
├── index.html           # Web前端（通过Fengari调用Lua代码）
├── lua                  # Lua 5.4 解释器（Linux x64）
├── test_85.lua          # 81项功能正确性测试
├── test_full.lua        # 119项功能测试
├── test_closure.lua     # VM闭包upvalue测试
├── run_mixed.sh         # 混合模式一致性测试脚本
├── README.md            # 使用文档
├── PROJECT.md           # 本文件
└── TEST_REPORT.md       # 测试报告
```

---

## 架构设计

### 统一代码架构

Web端和CLI端共享同一份Lua混淆逻辑：

```
CLI:  obfuscator.lua ─┐
                       ├──→ 同一份 Lua 代码
Web:  Fengari 调用  ──┘
```

### 模块 API

```lua
local M = dofile("obfuscator.lua")
local result = M.obfuscate_code(source_code, options, vm_module)

local vm = dofile("vm_protect.lua")
local protected = vm.protect(source_code)
```

---

## 当前状态（2026-07-19 v2.4.0）

### ✅ 源码级混淆（10种技术）

| # | 功能 | 标识 | 测试 |
|---|------|------|------|
| 1 | 变量名混淆 | VarMangle | ✅ 81/81 |
| 2 | 常量数字加密 | NumEnc | ✅ 81/81 |
| 3 | 字符串加密 | StrEnc | ✅ 81/81 |
| 4 | 控制流平坦化 | CFE | ✅ 81/81 |
| 5 | BCF虚假控制流块 | BCF | ✅ 81/81 |
| 6 | 指令替换 | InstrSub | ✅ 81/81 |
| 7 | 虚假控制流增强 | AdvFakeCF | ✅ 81/81 |
| 8 | 基本块拆分 | BBSplit | ✅ 81/81 |
| 9 | 垃圾注释 | Junk | ✅ |
| 10 | 全功能组合 | ALL | ✅ 81/81 |

36种混合模式组合全部通过。

### ✅ VM字节码虚拟化

| 特性 | 状态 |
|------|------|
| 基础语句/函数调用/递归 | ✅ |
| 数值for/while/repeat..until循环 | ✅ |
| do..end块（词法作用域） | ✅ |
| goto/label正向反向跳转 | ✅ |
| break语句（所有循环类型） | ✅ |
| 闭包+upvalue | ✅ |
| for..in泛型循环 | ✅ |
| 多重赋值 a,b=b,a | ✅ |
| CONCAT链 a..f()..b | ✅ |
| 可变参数 {...} 打包 | ✅ |
| 快速排序/冒泡排序 | ✅ |
| VM+全功能源码混淆 | ✅ |

### ✅ Web前端

通过Fengari调用Lua代码，与CLI完全一致。

---

## Bug修复记录

### v2.4.0 (2026-07-19)

| 问题 | 根因 | 修复 |
|------|------|------|
| VM不支持goto/label | Parser/Compiler缺少处理 | 添加词法分析+解析器+JMP解析 |
| CONCAT指令性能 | 每个操作数都调用tostring | 字符串类型跳过tostring |
| Web端OBFUSCATOR_LUA丢失 | 嵌入脚本覆盖错误 | 重新生成嵌入常量 |

### v2.2.0 (2026-07-19)

| 问题 | 根因 | 修复 |
|------|------|------|
| VM不支持do..end块 | Parser缺少处理 | 添加ast_do_block+作用域隔离 |
| VM不支持repeat..until | Parser缺少处理 | 添加ast_repeat+compile_repeat |
| VM break在循环内不生效 | JMP偏移未修正 | break_jmps栈+循环退出修正 |
| VM type(nil)崩溃 | table.unpack丢失nil | 1-3参数直接传递 |
| VM `{...}` 只打包首个vararg | 无法动态获取数量 | _pack全局闭包 |
| 浮点数加密精度丢失 | 加减法累积误差 | 乘除2的幂（IEEE 754无损）|
| VM多重赋值错误 | 寄存器别名 | 值先复制到临时寄存器 |
| VM CONCAT链脏数据 | CALL参数寄存器间隙 | CONCAT操作数MOVE到连续寄存器 |
| Web端缺少AdvFakeCF/BBSplit | JS重实现遗漏 | 统一架构调用Lua代码 |

### v2.1.0 (2026-07-15 ~ 07-16)

VM闭包upvalue、for..in循环、比较运算、while循环、多重赋值、数组构造器、Fengari API等修复。

### v2.0.0 (2026-07-07 ~ 07-08)

字符串占位符恢复、gsub_safe、数字加密变量名保护、VM for循环JMP、unpack改名、IDIV指令等修复。

---

## TODO

### 已完成

- [x] 10种源码级混淆技术
- [x] VM字节码虚拟化（闭包/for..in/while/repeat/do块/goto/break/多重赋值/比较/数组/CONCAT链/varargs）
- [x] VM+源码混淆组合
- [x] Web前端统一架构（Fengari调用Lua代码）
- [x] 浮点数加密精度修复（IEEE 754无损）
- [x] 模块API
- [x] VM goto/label支持
- [x] CFE/BBSplit goto安全检查
- [x] VM CONCAT性能优化

### 待完成

- [x] 字节码反调试机制（校验和嵌入格式参数，免疫数字加密）
- [ ] Lua 5.3兼容层（需代码生成器将`~`转为`bxor()`，改动量大）

---

## 测试命令

```bash
./lua test_85.lua           # 81项功能测试
./lua test_full.lua         # 119项完整测试
./lua test_closure.lua      # VM闭包测试
bash run_mixed.sh           # 混合模式一致性测试
./lua obfuscator.lua -h     # CLI帮助
```

---

## 技术架构

### 源码混淆流程
```
源码 → extract_strings → mangle_variables → substitute_instructions
     → obfuscate_numbers → inject_advanced_fake_cf → flatten_control_flow
     → inject_bcf → split_basic_blocks → restore_strings
     → inject_junk_comments → add_header → 输出
```

### VM虚拟化流程
```
源码 → Parser(递归下降) → AST → Compiler(指令编码) → 自定义字节码
     → XOR加密 → 嵌入式VM解释器(Lua代码) → 输出
```

### VM指令集（~45条）
- 栈操作: LOADK, MOVE, LOADBOOL, LOADNIL, GETGLOBAL/SET, GETUPVAL/SET
- 运算: ADD, SUB, MUL, DIV, IDIV, MOD, POW, BAND/BOR/BXOR, SHL/SHR
- 比较: EQ, LT, LE, TEST, TESTSET
- 控制流: JMP, CALL, RETURN, CLOSURE, VARARG, FORPREP/LOOP, TFORCALL/LOOP
- 表操作: NEWTABLE, GETTABLE, SETTABLE
