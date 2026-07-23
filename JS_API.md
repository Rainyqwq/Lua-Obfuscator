# JavaScript API 文档

**版本：v2.9.0**

## 概述

Web 端通过 Fengari（JS 实现的 Lua VM）执行混淆。支持同步与 Worker 异步。

## 核心 API

### `obfuscateLua(sourceCode, options?)`

同步混淆。

```javascript
const code = obfuscateLua(luaSource, {
  string_encryption: true,
  variable_mangling: true,
  constant_encryption: true,
  advanced_fake_cf: true,
  junk_comments: true,
  basic_block_splitting: true,
  // 默认关闭
  vm_protect: false,
  instruction_substitution: false,
  control_flow_flattening: false,
  bogus_control_flow: false,
  anti_debug: false,
  call_indirection: false,
});
```

### `runLua(code, label)`

在独立 Lua 状态机中执行代码（用于运行混淆结果）。内置指令计数超时保护，避免死循环卡死页面。

```javascript
const success = runLua(obfuscatedCode, '混淆后运行');
```

### Worker 异步混淆

页面通过 Worker 加载 bundle，避免长时混淆阻塞 UI。超时约 5 分钟可取消。

## 选项键名

与 CLI `Config` / Pass 名映射一致，见 `PASS_API.md` 与 `obfuscator.lua` 中 `CONFIG_TO_PASS`。

## 构建

```bash
lua build_bundle.lua
node build_html.js
```

注入后请 **Ctrl+F5** 强制刷新，避免浏览器缓存旧 bundle。

## P1 选项扩展

`obfuscateLua` / Worker 选项除 Pass 开关外支持:

```javascript
{
  preset: 'balanced',           // fast | balanced | max | custom
  name_whitelist: ['keep_me'],  // 名称白名单（变量混淆跳过）
  string_whitelist: ['OK'],     // 字符串白名单（精确保留明文）
}
```

Web UI 提供预设单选、白名单输入、配置 JSON 导出/导入。
