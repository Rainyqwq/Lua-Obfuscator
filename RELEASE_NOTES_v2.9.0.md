# Lua Obfuscator v2.9.0 Release Notes

**发布日期：2026-07-23**

## 概述

P1 产品能力：保护预设、名称/字符串白名单、配置导入导出（CLI + Web）。

## 新增

### 保护预设
- `fast`：字符串加密 + 变量混淆 + 数字加密 + 垃圾注释（轻量）
- `balanced`：默认全开（除 VM / 反调试）
- `max`：全部开启（含 VM + 反调试）

CLI：`--preset fast|balanced|max`
Web：选项区预设单选

### 白名单
- **名称白名单** `name_whitelist` / `--preserve-name <id>`：变量混淆跳过指定标识符
- **字符串白名单** `string_whitelist` / `--preserve-string <s>`：字符串池保留精确匹配明文

### 配置导入导出
- CLI：`--export-config <file>` / `--import-config <file>`（Lua 表）
- Bridge：`export_user_config` / `import_user_config` / `apply_preset` / `list_presets`
- Web：导出/导入 JSON 配置

## 测试

- `tests/test_p1_presets_whitelist.lua`
- CI 增加 P1 步骤
- 既有 P0 / full / string_pool 保持绿色

## 升级

```bash
lua build_bundle.lua
node build_html.js
lua tests/test_p1_presets_whitelist.lua
```

Web 更新后请 **Ctrl+F5** 强制刷新。

## License

MIT · Rainy_qwq
