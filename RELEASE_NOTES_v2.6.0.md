# v2.6.0 Release Notes

## 性能优化

- **var_mangle**: 单次 scan_identifiers + table.concat 拼接，从 O(n*k) 逐次 sub 拼接优化为 O(n)
- **string_pool**: restore/restore_raw 改为单次 gsub 替代 N 次 gsub 循环，O(n) 替代 O(n*k)
- **pass_manager**: 缓存 os.clock 为局部变量，避免每 pass 重复 nil 检查

## 手机端响应式适配

- 768px + 480px 双断点 CSS
- 移动端面板垂直堆叠（左面板 40vh，右面板 flex:1）
- resizer 移动端跳过鼠标拖拽，resize 时清除 inline flex
- body 从 height:100vh;overflow:hidden 改为移动端 height:auto;overflow:auto

## bb_split 默认开启

- CLI 默认 basic_block_splitting = true（obfuscator.lua）
- Web 端 bb_split toggle default = true（index.html）

## Bug 修复

- **BCF then/else 分支交换修复**: 真实代码放 then（恒真谓词，总执行），假代码放 else，修复混淆后运行错误
- **bb_split JS 模板字面量转义修复**: build_html.js 将 bundle 中反斜杠翻倍后注入 index.html，修复 Fengari 运行时解析错误

## 测试

- test_full.lua: 119/119 通过
- test_repro_web.lua: 100/100 通过
- test_bisect.lua: 7/7 通过
