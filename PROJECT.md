# 项目详细文档

**版本：v2.9.0**

## 架构

### 混淆流程

```
源代码
  → 字符串提取 (string_pool.extract)   — 非 VM 路径：尊重 string_whitelist
  → 字符串 → __SH_xxxx__ 占位符
  → Pass Pipeline（按 order 排序，用户启用的全部执行，不静默禁用）
  → 字符串恢复 (string_pool.restore / restore_raw)
  → 输出
```

> VM 路径下字符串用 VM 自己的 char-pool / 常量编码处理，跳过 string_pool 提取/恢复。

### 保护预设（P1）

| 预设 | 行为 |
|------|------|
| `fast` | str + var + num + junk |
| `balanced` | 默认除 vm/anti_debug 外全开 |
| `max` | 全部开启 |

应用入口：`M.apply_preset` / CLI `--preset` / Web 预设单选。
单独切换 Pass 后预设变为 `custom`。

### 白名单（P1）

- `name_whitelist` → `variable_mangling` 的 `ctx.config.whitelist`
- `string_whitelist` → `string_pool.set_whitelist`（extract 阶段跳过）

### 配置快照

- `export_user_config` / `import_user_config`：preset + pass flags + whitelist + passes 明细
- CLI：`--export-config` / `--import-config`
- Web：JSON 导出/导入

### 设计原则

1. **Pass 独立**：组合失败优先修 Pass，不在流水线静默关闭。
2. **Fengari 安全**：位运算与 hex 前必须 `to_u32` / 手写 hex。
3. **Web / CLI 同源**：`build_bundle.lua` + `build_html.js`。

### 关键模块

| 文件 | 职责 |
|------|------|
| `obfuscator.lua` | CLI、Config、预设、白名单、JS Bridge |
| `pass_manager.lua` | 注册 / 排序 / Pipeline / 超时 |
| `passes/string_pool.lua` | 字符串提取与加密恢复 + 白名单 |
| `passes/var_mangle.lua` | 变量混淆 + 名称白名单 |
| `index.html` | 预设 UI、白名单输入、配置 JSON |

### 构建

```bash
lua build_bundle.lua
node build_html.js
```

### 测试建议

- `tests/test_p0_regression.lua`
- `tests/test_p1_presets_whitelist.lua`
- `tests/test_full.lua`
- Web：Ctrl+F5 后测预设与白名单

## Pipeline 超时

`PassManager:run(code, { max_total_ms = N })` 默认 `120000` ms。Web 异步混淆超时 90 秒。

## License

MIT · Rainy_qwq
