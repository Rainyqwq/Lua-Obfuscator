-- ================================================================
-- passes/init.lua
-- Pass 加载器
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 扫描 passes/ 目录，加载所有 Pass 模块并注册到 PassManager
--
-- 用法：
--   local PassManager = require("pass_manager")
--   local pm = PassManager.new()
--   require("passes").load_all(pm)

local M = {}

-- 内置 Pass 列表（显式声明，不依赖文件系统扫描）
-- 顺序不影响执行顺序（由各 Pass 的 order 字段控制）
local BUILTIN = {
  "passes.vm_protect",
  "passes.string_encrypt",
  "passes.num_encrypt",
  "passes.instr_sub",
  "passes.var_mangle",
  "passes.adv_fake_cf",
  "passes.cf_flatten",
  "passes.bcf",
  "passes.junk_comment",
  "passes.header",
}

-- 加载所有内置 Pass 并注册到 PassManager
function M.load_all(pm)
  for _, name in ipairs(BUILTIN) do
    local ok, pass = pcall(require, name)
    if ok and type(pass) == "table" and pass.name then
      pm:register(pass)
    else
      io.stderr:write(string.format("[passes] WARNING: 加载 %s 失败: %s\n", name, tostring(pass)))
    end
  end
  return pm
end

-- 注册单个自定义 Pass
function M.register(pm, pass)
  pm:register(pass)
end

return M
