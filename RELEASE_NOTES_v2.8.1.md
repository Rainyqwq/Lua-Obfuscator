# Lua Obfuscator v2.8.1 Release Notes

**发布日期：2026-07-23**

## 概要

v2.8.1 是一次**紧急稳定性修复**：修复变量名混淆在含表构造输入上的死循环，以及默认功能开关策略调整。

## 修复

### `variable_mangling` 死循环（关键）
- **文件：** `passes/var_mangle.lua`
- **现象：** 浏览器即使用户**不开启 VM**，混淆含 `{ ... }` 的源码（例如仓库内 `passes/instr_sub.lua`）也会页面卡死。
- **根因：** `collect_table_keys` 扫描表构造时，遇到 `{` / `}` 调整 `depth` 却**未推进扫描下标 `i`**，导致无限循环。
- **修复：** 在 `depth + 1` / `depth - 1` 时同步 `i = i + 1`。
- **验证：** 单独变量名混淆约 28ms；默认全开（无 VM）约 156ms 完成。

## 行为变化

### 默认启用的 Pass
除以下两项外，**全部默认开启**：

| 默认关闭 | 说明 |
|---------|------|
| `vm_protect` | VM 字节码虚拟化 |
| `anti_debug` | 反调试检测 |

默认开启包括：字符串加密、变量名混淆、数字加密、指令替换、虚假控制流、控制流平坦化、BCF、基本块拆分、调用间接化、垃圾注释等。

### 版本标识
- CLI / Web / 输出头部统一为 **v2.8.1**

## 升级

```bash
git pull
lua build_bundle.lua
node build_html.js
```

Web 用户请 **Ctrl+F5** 强制刷新。

## 完整变更基线

更完整的 2.8 系列能力与修复见 [RELEASE_NOTES_v2.8.0.md](./RELEASE_NOTES_v2.8.0.md)。

## License

MIT · Author: Rainy_qwq  
https://github.com/Rainyqwq/Lua-Obfuscator