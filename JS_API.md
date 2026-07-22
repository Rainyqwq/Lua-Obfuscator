# JavaScript API 文档

## 概述

Web 端通过 Fengari（JS 实现的 Lua VM）执行混淆。支持同步和异步两种调用方式。

## 核心 API

### `obfuscateLua(sourceCode, options?)`

同步混淆（阻塞主线程）。

```javascript
const code = obfuscateLua(luaSource, {
  string_encryption: true,
  variable_mangling: true,
  constant_encryption: true,
  advanced_fake_cf: true,
  junk_comments: true,
  // 以下默认关闭
  vm_protect: false,
  instruction_substitution: false,
  control_flow_flattening: false,
  bogus_control_flow: false,
});
```

### `obfuscate(sourceCode)`

同步混淆，返回详细统计。

```javascript
const result = obfuscate(sourceCode);
// result.code          - 混淆后代码
// result.elapsed       - 耗时 (ms)
// result.originalSize  - 原始大小
// result.obfuscatedSize - 混淆后大小
```

### `runLua(code, label)`

在独立 Lua 状态机中执行代码（用于运行混淆结果）。

```javascript
const success = runLua(obfuscatedCode, '混淆后运行');
```

## 配置对象

```javascript
const config = {
  vm_protect: false,              // VM 字节码虚拟化
  str_encrypt: true,              // 字符串加密
  var_mangle: true,               // 变量名混淆
  num_encrypt: true,              // 常量数字加密
  adv_fake: true,                 // 虚假控制流增强
  junk_comment: true,             // 垃圾注释注入
  instr_sub: false,               // 指令替换（不稳定）
  cf_flatten: false,              // 控制流平坦化（不稳定）
  bcf: false,                     // BCF 虚假控制流（不稳定）
  bb_split: false,                // 基本块拆分（不稳定）
};
```

### 配置映射

| JS config key | Lua Pass name |
|---------------|---------------|
| `vm_protect` | `vm_protect` |
| `str_encrypt` | `string_encryption` |
| `var_mangle` | `variable_mangling` |
| `num_encrypt` | `constant_encryption` |
| `adv_fake` | `advanced_fake_cf` |
| `junk_comment` | `junk_comments` |
| `instr_sub` | `instruction_substitution` |
| `cf_flatten` | `control_flow_flattening` |
| `bcf` | `bogus_control_flow` |
| `bb_split` | `basic_block_splitting` |

## UI 控制

```javascript
setStatus('完成', 'ok');        // 'ok' | 'warn' | 'err' | 'info'
appendOutput('文本\n', 'info'); // '' | 'info' | 'success' | 'error' | 'warn' | 'dim'
clearOutput();
showLoading('处理中...');
hideLoading();
```

## 错误处理

```javascript
try {
  const result = obfuscate(code);
  displayResult(result.code);
} catch (e) {
  showError('混淆失败: ' + e.message);
}
```

## 性能建议

| 文件大小 | 推荐方式 | 预期耗时 |
|----------|----------|----------|
| < 5KB | 同步 `obfuscate()` | < 1s |
| 5-50KB | 同步 + loading 提示 | 1-10s |
| > 50KB | 同步 + loading + 取消按钮 | 10s+ |

## 架构说明

- **主混淆器**通过 `package.preload` 注册所有 Pass 模块，`require` 从内存加载
- **字符串池**始终运行（提取→Pass处理→恢复），保护字符串不被 Pass 破坏
- **同步执行**在主线程，用 `setTimeout` 让 UI 先更新
- `runLua` 每次创建独立 Lua 状态机，互不影响
- **VM 模式自动禁用**：启用 `vm_protect` 时，`instruction_substitution`、`control_flow_flattening`、`bogus_control_flow` 三个 Pass 自动禁用（正则重写会破坏 VM 字节码解释器）
