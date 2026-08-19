# Lua Obfuscator v3.4.0 Release Notes

**发布日期：2026-08-20**

## 概要

- **编辑器光标错位修复**：textarea 不再被 `min-height:100%` 钳在容器高度内，强制以 `scrollHeight` 长高，光标永远停在正确的 gutter 行号上
- **VM 高级模式生效**：`vm_mode='advanced'` 不再被 JS 桥全部推成 boolean / 被 worker 的 `typeof value === 'boolean'` 过滤器丢弃
- **主题切换扩散动画**：基于 `document.startViewTransition`（Chrome 111+/Edge 111+）+ JS fallback，从按钮位置圆形扩散/收缩回按钮位置，0.28s linear
- **UI 设计规范合规（Apple Liquid Glass）**：token 化所有颜色/圆角/阴影/缓动/字号；3 个 panel 视觉统一
- **全局动效统一**：13 处裸 `.15s` transition 全部补 `var(--ease-out-quart)`；loading overlay/scrim 用项目缓动 token
- **可访问性**：`prefers-reduced-motion` / `prefers-reduced-transparency` / `prefers-contrast` 三条 media query 完整覆盖
- **代码健壮性**：9 处隐藏 bug 修复（worker race / Worker race / memory leak / null deref / duplicate resize listener 等）
- **新增 design tokens**：`--danger` / `--warn` / `--dark`-mode 变体全部 5 处硬编码替换

## 修复

### 编辑器光标错位（核心 bug）

`<textarea>` 在 `height:auto + min-height:100% + overflow:hidden` 三者并存时**不会**随内容自动长高 —— 它被钉在 scroll 容器高度处。当用户输入很多行时，文本溢出被隐藏，但 caret 仍画在 textarea box 内。结果：在末行按 Enter 时光标跳到错误的位置（差约一行高）。

**修复**（`index.html`）：
- 移除 `min-height:100%`
- 在每次 `updateLineCount()` 中**强制** `textarea.style.height = textarea.scrollHeight + 'px'`，让 textarea 跟随内容长高

实测对齐偏差从 **22.5px → ≤0.19px**（亚像素圆整）。

### VM 高级模式开关无效

JS→Worker 消息桥把 `options` 中所有 value 都过滤成 boolean（`if (typeof value === 'boolean')`），丢弃了 `vm_mode='advanced'` 等字符串。同时 sync 路径的 `obfuscateLua()` 走相同过滤逻辑。

**修复**：
- Worker 的 `onmessage` 按 `typeof` 分发 boolean / number / string / array / null
- `obfuscateLuaAsync` / `obfuscateLua` 同样改为按类型分发
- 数组（`name_whitelist` / `string_whitelist`）也走 table push

### `_luaObfuscatorReady` 单 flag bug

单一 flag 同时代表 main-thread Lua + Worker 都已初始化。但两者是异步独立完成的：主线程同步，Worker 异步。**Worker 还没 ready 时点击混淆 → 直接拒绝。**

**修复**：拆成三个 flag：
- `_luaMainReady` — 主线程 Lua 已初始化
- `_luaWorkerReady` — Worker 已 postMessage `ready`
- `_luaObfuscatorReady` = `_luaMainReady && _luaWorkerReady`（派生）

### `obfuscateLuaAsync` 快速双击 → 首个 Promise 永远 hang

`obfuscateLuaAsync` 直接覆盖 `_obfuscateCallbacks`，没有 reject 前一个 → 第一个 promise 永远不 resolve。**修复**：覆盖前先 `reject(new Error('新的混淆请求已发起，上一个被取消'))`。

### Worker 内存泄漏

每次 `new Worker(URL.createObjectURL(blob))` 都没 `revokeObjectURL`。`URL.createObjectURL` 是 ObjectURL，每条都持久占用。**修复**：Worker 构造后立即 `revokeObjectURL`（Worker 已快照引用，安全）。

### Worker 报错后 handle 仍占用

`onerror` 设 `_luaObfuscatorReady=false` 但不 terminate worker → 下次 `postMessage` 投到死 handle。**修复**：`onerror` 里 `terminate()` + `_obfuscateWorker = null`，下次自动重建。

### Resizer 拖拽时每帧 `window.matchMedia(...)`

`isMobile()` 在 `mousemove` 高频事件里创建新 MediaQueryList。**修复**：缓存 MQL 到 closure 外层。

### DOM null deref（多处）

- `appendOutput`、`clearOutput`、`doObfuscate` 等：加 null guard
- 删除 `line-count` / `output-status` 后残留的 JS 引用加 null guard

### 重复的 `window.addEventListener('resize', ...)`

旧 `syncGutterScroll` listener 还在；新的在 `initUI` 里。**修复**：删旧的。

## 新增

### Theme 切换扩散动画

**1. Path 1 — View Transitions API（Chrome 111+/Edge 111+）**

```js
document.startViewTransition(() => {
  swap();  // 切换 :root.dark
});
transition.ready.then(() => {
  // 用 WAAPI 动画 clip-path：从点击位置扩散/收缩回
  document.documentElement.animate(
    { clipPath: isDark ? expand : shrink },
    { duration: 280, easing: 'linear', pseudoElement: '::view-transition-...' }
  );
});
```

- `light → dark`：新 snapshot（dark）从点击位置扩散覆盖 viewport
- `dark → light`：旧 snapshot（dark）从全屏收缩回按钮位置

**2. Path 2 — JS fallback（旧浏览器）**

body 级 `.theme-veil` div，`clip-path: circle()` 从 0 扩到 endRadius（或反向）。veil 颜色 = OLD theme；50% 时 swap class + 切换 veil 颜色 = NEW theme。动画结束 `display:none` + `opacity:0` 双重隐藏，避免合成器残留。

**3. 闪烁修复**

`::view-transition-old(root)` 配 `@keyframes vt-hide { from { opacity:1 } to { opacity:0 } }`，在 260ms 内淡出，配合 `transition.skipTransition()` 在 WAAPI `finish` 事件强制终止 SVT —— 彻底消除"dark→light 末尾黑色闪烁"。

### Startup 进入动画

四个元素 stagger 进入（总时长 < 600ms）：
- `nav` 从 -12px 滑入（delay 0.05s）
- 左 panel 从 +14px 滑入（delay 0.18s）
- 右 panel 从 +14px 滑入（delay 0.30s）
- 动作条 + scale(.96) 弹入（delay 0.46s）

`prefers-reduced-motion` 下所有 delay 归零，立即落到 resting state。

### 实时跟随系统主题

`Theme.userPref` 区分"用户已锁定"和"跟随系统"。`matchMedia.addEventListener('change', ...)` 监听 OS 主题变化；锁定后不再被 OS变化覆盖。带旧浏览器 `addListener` fallback。

### 预渲染主题 class（无 FOUC）

`<head>` 中插入同步小脚本，在 fengari/JS 加载前就根据 locallocalStorage + `prefers-color-scheme` 给 `<html>` 加 `dark`/`light` class —— 首屏渲染前不闪烁。

### Design Tokens 补全

```css
:root {
  --danger:    #ff375f;
  --danger-bg: rgba(255,55,95,.1);
  --warn:      #ff9f0a;
  --warn-bg:   rgba(255,159,10,.1);
}
:root.dark {
  --danger:    #ff5e7a;
  --danger-bg: rgba(255,94,122,.12);
  --warn:      #ffb340;
  --warn-bg:   rgba(255,179,64,.12);
}
```

替换 5 处硬编码 `#ff375f` / `#ff9f0a`：
- `.panel-header .badge.status-err` / `.status-warn`
- `.btn-danger`（含 hover bg）
- `.tok-number`、`.output-sink .error`、`.output-sink .warn`
- `.batch-file-row .fstatus.error`、`.fbtn:hover`

## UI 重做（按 DESIGN 设计规范）

### Segmented control（快速/均衡/最强/自定义）

- pill `::after` 从 `left`+`width` 动画改为 `transform: translateX + scaleX`（compositor 友好）
- duration 0.35s → 0.22s（Apple HIG）
- 移动端 `flex-wrap:wrap` 时隐藏 pill，按钮变 plain chip，避免跨行穿模

### iOS Switch

- track / thumb 统一 0.22s（之前 0.2s + 0.25s 不同步）
- thumb 高度 20px → 18px，更轻盈
- translateX(16px) 落点改精确

### Output panel

- radius `--r-panel` (22px) → `--r-card` (18px)，与邻居面板统一
- shadow `--sh-card` → `--sh-panel`，与邻居面板统一
- 去掉 1px hairline border（shadow 已经分隔了）

### Stats bar

- 左右两栏 padding 统一 `var(--pad-x)`（之前输出栏用 24px，输入栏 22px，1-5px 错位）
- 加 `border-top:1px solid var(--hairline)`

### Action bar

- 所有按钮统一 32px 高（之前主按钮 30px，cluster 34px，4px 错位）
- cluster 用 `inset 0 0 0 1px var(--hairline)` 描边，内部按钮 `-1px 0 0 var(--hairline)` 分隔线
- 图标 `stroke-width:1.75` + `currentColor` + round caps（DESIGN icons.md）
- 隐藏"全选/全不选"按钮（按 DESIGN 简化）

### Whitelist input

- radius `--r-chip` (6px) → `--r-thumb` (12px)
- focus `box-shadow: 0 0 0 3px` halo + `z-index:1`（不被 `.unified-panel` 的 `overflow:hidden` 截断）

### Placeholder

- 重命名 `.ic` → `.placeholder-icon`（避免与 utility `.ic` 冲突）
- HTML 用 `.placeholder-icon` / `.placeholder-title` / `.placeholder-hint` 三个 scoped class

## 全局动效统一

| 位置 | 旧 | 新 |
|------|---|----|
| 13 处 `.15s` transition | 无 easing（默认 `ease`） | 加 `var(--ease-out-quart)` |
| `.loading-overlay` / `.drawer-scrim` | `ease` | `var(--ease-out-quart)` |
| `.btn:active` | `100ms` 裸数字 | `80ms var(--ease-out-quart)` |
| `.btn` transition | 多 duration/easing 混合 | 统一 `transform .22s var(--ease-out-quart)` |

## 可访问性

三条 media query 完整覆盖：

```css
@media (prefers-reduced-motion: reduce) {
  /* 所有 transition / animation: none */
}
@media (prefers-reduced-transparency: reduce) {
  /* glass / backdrop-filter 退化为实色 */
}
@media (prefers-contrast: more) {
  /* border 加粗，开关描边可见 */
}
```

Editor 块下的 `.enter-nav / .enter-panel / .enter-cta` 也在 reduced-motion 下用 0.01s 动画立即落到 resting state。

## 版本

| 模块 | 版本 |
|---|---|
| index.html (Web) | **v3.4.0** |
| package.json | **3.4.0** |
| package-lock.json | **3.4.0** |
| obfuscator.lua | v3.3.0 |
| passes/vm.lua | v3.3.0 |
| passes/vm_advanced.lua | v3.1.0 |
| passes/vm_protect.lua | v2.9.2 |
| passes/num_encrypt.lua | v1.4.0 |
| passes/header.lua | v1.1.1 |
| passes/api_indirect.lua | v1.0.0 |
| passes/string_pool.lua | v1.2.0 |
| passes/var_mangle.lua | v1.2.0 |
| passes/cf_flatten.lua | v1.0.0 |
| passes/bcf.lua | v1.0.0 |
| passes/bb_split.lua | v1.0.0 |
| passes/adv_fake_cf.lua | v1.1.1 |
| passes/junk_comment.lua | v1.0.1 |
| passes/anti_debug.lua | v1.0.0 |
| passes/call_indirect.lua | v1.0.0 |
| passes/string_restore.lua | v1.0.0 |

## 测试

- 编辑器：headless Edge 实测 caret 对齐 ≤ 0.19px 偏差（27 / 28 / 31 行）
- 混淆：`obfuscate('local x = 1')` 在 JS fallback 路径 OK，veils 元素创建成功
- Theme：headless Edge 实测 `startViewTransition=true`，Theme.mq 监听器绑定成功
- 可访问性：`prefers-reduced-motion` 下动画时长 0.01ms

## 构建

- `obfuscator_bundle.lua`：22 模块
- `index.html`：Web 版本同步更新
- 体积：index.html 编辑器 CSS + JS 总长 ≈ 50KB（含 FENGARI_SOURCE / OBFUSCATOR_LUA / build_html.js 注入的 ≈ 220KB 之外）

## Migration

无破坏性变更。从 v3.3.0 升级：

1. 替换 `index.html`
2. `package.json` / `package-lock.json` 的 version 字段更新（npm install 不会重新装，只是 metadata）
3. 主题切换体验变化：之前是瞬时切换，现在是 0.28s linear wipe 动画（如果用户希望关闭，`prefers-reduced-motion: reduce` 已自动跳过）
4. 可访问性：reduced-motion / reduced-transparency / contrast 用户体验改善

## Known Issues

- Worker 在 `file://` 协议下仍打印 `"Unsafe attempt to load URL from frame with URL file://..."` —— Chrome 同源策略限制（每个 file: URL 是独立 opaque origin）。Worker 仍正常运行，警告仅是信息性。发行版打包为 Electron 或用 `chrome://flags/#unsafely-treat-insecure-origin-as-secure` 启动可消除。

## License

MIT · Author: Rainy_qwq · [GitHub](https://github.com/Rainyqwq/Lua-Obfuscator)