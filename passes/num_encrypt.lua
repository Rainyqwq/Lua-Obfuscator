-- ================================================================
-- passes/num_encrypt.lua
-- 常量数字加密
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将数字常量替换为等价的数学运算表达式
--
-- 性能优化：
--   - 用 byte 检查代替字符串模式匹配判断十六进制
--   - 减少 strip_strings_from_line 调用次数
--   - 缓存常用值

local utils = require("passes.utils")
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local is_comment = utils.is_comment

local M = {}

M.name    = "constant_encryption"
M.title   = "常量数字加密"
M.version = "1.0.0"
M.order   = 50

-- 预计算常用值
local BYTE_0 = string.byte("0")
local BYTE_x = string.byte("x")
local BYTE_X = string.byte("X")
local BYTE_DOT = string.byte(".")
local BYTE_UNDERSCORE = string.byte("_")

-- 检查一个字节是否是数字
local function is_digit(b)
  return b >= 48 and b <= 57  -- '0' to '9'
end

-- 检查是否是十六进制字面量
local function is_hex(s, pos)
  if pos + 1 > #s then return false end
  local b1 = s:byte(pos)
  local b2 = s:byte(pos + 1)
  return b1 == BYTE_0 and (b2 == BYTE_x or b2 == BYTE_X)
end

-- 将数字 n 转换为混淆表达式
local function encrypt_number(n)
  if n == 0 then return "(0x0|0)" end
  if n == 1 then return "(0x1&0x1)" end
  if n == -1 then return "(~0x0)" end

  -- 浮点数
  if n ~= math.floor(n) then
    -- 科学计数法原样返回，避免破坏 e+/e- 语法
    local s = tostring(n)
    if s:find("e", 1, true) or s:find("E", 1, true) then
      return s
    end
    local int_part = math.floor(n)
    local frac = n - int_part
    local shift = 2 ^ random_int(1, 8)
    local int_enc
    if int_part == 0 then
      int_enc = "(0x0|0)"
    else
      local abs_int = math.abs(int_part)
      local sign = int_part < 0 and "-" or ""
      local a = random_int(1, 0xFFFF)
      int_enc = string.format("%s(0x%X~0x%X)", sign, a, a ~ abs_int)
    end
    return string.format("(%s+%.15g*%d/%d)", int_enc, frac, shift, shift)
  end

  local abs_n = math.abs(n)
  local sign = n < 0 and "-" or ""
  local method = random_int(1, 4)

  if method == 1 then
    local a = random_int(1, 0xFFFF)
    return string.format("%s(0x%X~0x%X)", sign, a, a ~ abs_n)
  elseif method == 2 then
    local a = random_int(1, 0xFFFF)
    return string.format("%s(0x%X-0x%X)", sign, abs_n + a, a)
  elseif method == 3 and abs_n > 1 then
    local shift = random_int(1, 4)
    return string.format("%s(0x%X>>%d)", sign, abs_n << shift, shift)
  else
    -- 因数分解
    if abs_n > 2 and abs_n < 10000 then
      for f = 2, math.min(abs_n - 1, 30) do
        if abs_n % f == 0 then
          return string.format("%s(0x%X*0x%X)", sign, f, abs_n // f)
        end
      end
    end
    local a = random_int(1, 0xFFFF)
    return string.format("%s(0x%X~0x%X)", sign, a, a ~ abs_n)
  end
end

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}

  for li, line in ipairs(lines) do
    -- 跳过空行和注释
    if line == "" or is_comment(line) then
      result[li] = line
    else
      -- 逐字符扫描，跳过字符串占位符、十六进制和字符串字面量
      local parts = {}
      local pn = 0
      local pos = 1
      local len = #line

      while pos <= len do
        local b = line:byte(pos)

        -- 跳过字符串占位符 __STR\d+__
        if b == 95 and line:sub(pos, pos + 3) == "__ST" then  -- '_'
          local end_pos = line:find("__", pos + 5, true)
          if end_pos then
            pn = pn + 1
            parts[pn] = line:sub(pos, end_pos + 1)
            pos = end_pos + 2
          else
            pn = pn + 1
            parts[pn] = string.char(b)
            pos = pos + 1
          end

        -- 跳过双引号字符串
        elseif b == 34 then  -- '"'
          local str_end = pos + 1
          while str_end <= len do
            local sb = line:byte(str_end)
            if sb == 92 then str_end = str_end + 2  -- '\\' skip escape
            elseif sb == 34 then str_end = str_end + 1; break
            else str_end = str_end + 1 end
          end
          pn = pn + 1
          parts[pn] = line:sub(pos, str_end - 1)
          pos = str_end

        -- 跳过单引号字符串
        elseif b == 39 then  -- "'"
          local str_end = pos + 1
          while str_end <= len do
            local sb = line:byte(str_end)
            if sb == 92 then str_end = str_end + 2
            elseif sb == 39 then str_end = str_end + 1; break
            else str_end = str_end + 1 end
          end
          pn = pn + 1
          parts[pn] = line:sub(pos, str_end - 1)
          pos = str_end

        -- 跳过十六进制 0x...
        elseif is_hex(line, pos) then
          local hx_end = pos + 2
          while hx_end <= len do
            local hb = line:byte(hx_end)
            if is_digit(hb) or (hb >= 65 and hb <= 70) or (hb >= 97 and hb <= 102) then
              hx_end = hx_end + 1
            else
              break
            end
          end
          pn = pn + 1
          parts[pn] = line:sub(pos, hx_end - 1)
          pos = hx_end

        -- 数字（包括科学计数法）
        elseif is_digit(b) then
          local num_start = pos
          local num_end = pos
          local has_dot = false
          local has_exp = false
          while num_end <= len do
            local nb = line:byte(num_end)
            if is_digit(nb) then
              num_end = num_end + 1
            elseif nb == BYTE_DOT and not has_dot and not has_exp then
              has_dot = true
              num_end = num_end + 1
            elseif (nb == 101 or nb == 69) and not has_exp then  -- 'e' or 'E'
              has_exp = true
              num_end = num_end + 1
              -- 指数部分可能有 +/-
              if num_end <= len then
                local sign = line:byte(num_end)
                if sign == 43 or sign == 45 then num_end = num_end + 1 end  -- '+' or '-'
              end
            else
              break
            end
          end
          local num_str = line:sub(num_start, num_end - 1)
          local num = tonumber(num_str)
          -- 跳过科学计数法（1e10, 1.5e-3 等），直接原样保留
          if has_exp then
            pn = pn + 1
            parts[pn] = num_str
          elseif num and num ~= 0 and num ~= 1 and num ~= -1 then
            pn = pn + 1
            parts[pn] = encrypt_number(num)
          else
            pn = pn + 1
            parts[pn] = num_str
          end
          pos = num_end

        else
          pn = pn + 1
          parts[pn] = string.char(b)
          pos = pos + 1
        end
      end

      result[li] = table.concat(parts)
    end
  end

  return join_lines(result)
end

return M
