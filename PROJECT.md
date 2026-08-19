# 项目详细文档

**版本：v3.4.0**

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
> 高级 VM 模式（vm_mode='advanced'）使用 passes/vm_advanced.lua 的 U 表状态机 + S 表 hex 编码 + 4 模式动态索引生成器，输出结构完全复刻第三方强混淆样本。

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

### Web 架构

```
index.html
├── <head>
│   ├── inline pre-paint theme script  ← 同步设置 :root.dark / :root.light，避免 FOUC
│   ├── inline DESIGN tokens.css       ← :root tokens + dark variants
│   ├── <style>                         ← all component CSS
│   └── fengari-web.js (script src)
├── <body>
│   ├── <header class="glass-nav">     ← 含 theme toggle (moon/sun + ripple)
│   ├── <main>
│   │   ├── <div class="editor">       ← 强制 textarea height = scrollHeight
│   │   │   ├── gutter
│   │   │   ├── editor-scroll
│   │   │   │   ├── <pre> highlight overlay (tokenized Lua)
│   │   │   │   └── <textarea>  (transparent text on top)
│   │   └── <div class="panel-right">
│   │       ├── options-section
│   │       │   ├── segmented preset control
│   │       │   ├── feature toggles
│   │       │   └── whitelist inputs
│   │       ├── btn-group              ← 32px unified buttons
│   │       └── output-section
│   │           ├── output-sink         ← r-card + sh-panel
│   │           └── stats bar
│   └── <div class="theme-ripple">     ← body-level, created by JS on toggle
└── <script>
    ├── initTheme()                    ← 监听 OS 主题、绑定 ripple
    ├── initLuaObfuscator()            ← main-thread Lua
    ├── initObfuscateWorker()           ← Worker init
    ├── initUI()                        ← 事件绑定、UI 生成
    ├── applyTheme(mode, coords)        ← 用 document.startViewTransition 动画
    └── obfuscateLua(source, options)   ← async via Worker
```

### Theme 切换扩散动画

`applyTheme(mode, originCoords)`：

1. **Path 1**: `document.startViewTransition(swap)` → `transition.ready` → WAAPI `clip-path: circle(0 → endRadius)` 在 `::view-transition-new/old(root)` 上动画，0.28s linear
2. **Path 2** (fallback): body 级 `.theme-veil` 元素，`clip-path: circle()` 同样0→endRadius，50% 时 `swap()` + 切 veil 颜色。结束 `display:none` + `opacity:0` 双重隐藏
3. **Flash 修复**: `::view-transition-old(root)` 用 `@keyframes vt-hide` 在 260ms 内淡出 + `transition.skipTransition()` 在 WAAPI `finish` 时强制终止

### 设计原则

1. **Pass 独立**：组合失败优先修 Pass，不在流水线静默关闭。
2. **Fengari 安全**：位运算与 hex 前必须 `to_u32` / 手写 hex。
3. **Web / CLI 同源**：`build_bundle.lua` + `build_html.js`。
4. **Apple Liquid Glass 风格**：所有 token（颜色/圆角/阴影/缓动）走 CSS variables；a11y 三条 media query 完整覆盖；只动画 `transform` + `opacity`（compositor 友好）。
5. **代码健壮性**：worker race / memory leak / null deref / double-bind listener 等隐藏 bug 主动消除；所有 init flag 派生自子系统 flag。

### 关键模块

| 文件 | 职责 |
|------|------|
| `obfuscator.lua` | CLI、Config、预设、白名单、JS Bridge |
| `pass_manager.lua` | 注册 / 排序 / Pipeline / 超时 |
| `passes/string_pool.lua` | 字符串提取与加密恢复 + 白名单 |
| `passes/var_mangle.lua` | 变量混淆 + 名称白名单 |
| `passes/vm_advanced.lua` | 高级 VM 模式（样本模式） |
| `passes/api_indirect.lua` | 全局 API hex 编码间接化 |
| `index.html` | 预设 UI、白名单输入、配置 JSON、theme 动画 |

### 构建

```bash
lua build_bundle.lua
node build_html.js
```

### 测试建议

- `tests/test_p0_regression.lua`
- `tests/test_p1_presets_whitelist.lua`
- `tests/test_full.lua`
- `tests/test_string_pool_regression.lua`
- `tests/test_vm_mangle_string.lua`
- Web：Ctrl+F5 后测预设、白名单、theme 切换动画

## Pipeline 超时

`PassManager:run(code, { max_total_ms = N })` 默认 `120000` ms。Web 异步混淆超时 90 秒。

## License

MIT · Rainy_qwq
