-- ================================================================
-- passes/vm_adv_gen.lua
-- 高级 VM 代码生成器模板
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 用于生成混淆的 VM 代码模板，包含复杂的控制流混淆

local M = {}

-- 将字符串转换为八进制转义的 Lua 字符串 (如 "\115" 表示 's')
local function octal_escape(s)
  local r = {}
  for i = 1, #s do
    local b = string.byte(s, i)
    r[#r + 1] = string.format("\\%03d", b)
  end
  return table.concat(r)
end

-- 数值常量折叠混淆
local function fold_expr(target, seed)
  seed = seed or os.clock()
  math.randomseed(seed)
  local ops = {"+", "-", "*"}
  local depth = math.random(2, 4)
  local expr = tostring(target)
  for i = 1, depth do
    local op = ops[math.random(1, #ops)]
    local n = math.random(1, 99)
    expr = "(" .. expr .. op .. n .. ")"
  end
  return expr
end

-- API 引用混淆
local function api_ref(name)
  return "S[" .. octal_escape(name) .. "]"
end

-- 生成混淆的 VM 代码模板
function M.generate_template(opts)
  opts = opts or {}
  local fragments = opts.fragments or 50

  local code = {}

  -- 全局引用混淆
  table.insert(code, "local S=_G or _ENV or getfenv(0);")
  table.insert(code, "local type=" .. api_ref("type") .. ";")
  table.insert(code, "local error=" .. api_ref("error") .. ";")
  table.insert(code, "local select=" .. api_ref("select") .. ";")
  table.insert(code, "local unpack=unpack or " .. api_ref("table") .. ".unpack;")
  table.insert(code, "local concat=" .. api_ref("table") .. ".concat;")

  -- VM 解释器框架
  table.insert(code, "local function _exec(code,env)")
  table.insert(code, "  local regs={}")
  table.insert(code, "  local pc=1")
  table.insert(code, "  local stack={}")
  table.insert(code, "  while pc<=#code do")
  table.insert(code, "    local op=code[pc]")
  table.insert(code, "    if op==" .. fold_expr(0, 1) .. " then")
  table.insert(code, "      pc=pc+1")
  table.insert(code, "    elseif op==" .. fold_expr(1, 2) .. " then")
  table.insert(code, "      regs[code[pc+1]]=code[pc+2]")
  table.insert(code, "      pc=pc+3")
  table.insert(code, "    elseif op==" .. fold_expr(2, 3) .. " then")
  table.insert(code, "      regs[code[pc+1]]=regs[code[pc+2]]+regs[code[pc+3]]")
  table.insert(code, "      pc=pc+4")
  table.insert(code, "    elseif op==" .. fold_expr(3, 4) .. " then")
  table.insert(code, "      return regs[code[pc+1]]")
  table.insert(code, "    else")
  table.insert(code, "      error(" .. octal_escape("invalid opcode") .. ")")
  table.insert(code, "    end")
  table.insert(code, "  end")
  table.insert(code, "end")

  -- 生成碎片混淆
  for i = 1, fragments do
    local idx = fold_expr(i, 3000 + i)
    local val = fold_expr(math.random(100, 5000), 5000 + i)
    table.insert(code, "[" .. idx .. "]=" .. val)
  end

  -- 返回结果
  table.insert(code, "return _exec({" .. fold_expr(0, 20) .. "," .. fold_expr(1, 21) .. "," .. fold_expr(3, 22) .. "},{})")

  return table.concat(code, ";")
end

return M
