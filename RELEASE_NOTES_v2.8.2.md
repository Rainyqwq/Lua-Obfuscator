# Lua Obfuscator v2.8.2 Release Notes

**发布日期：2026-07-23**

## 概要

P0 工程质量：自动化回归、流水线超时、Web 混淆超时收紧。

## 新增

- `tests/test_p0_regression.lua`：单 Pass / 组合 / 语义对拍 / 大文件防挂死 / VM 冒烟
- `.github/workflows/ci.yml`：CI 跑 P0 + test_full + string_pool 回归
- `PassManager:run(..., { max_total_ms })`：整条流水线总耗时上限
- 主程序默认 `max_total_ms = 120000`
- Web 异步混淆超时 **5 分钟 → 90 秒**，失败可取消并提示

## 升级

```bash
lua tests/test_p0_regression.lua
lua build_bundle.lua && node build_html.js
```

## License

MIT · Rainy_qwq