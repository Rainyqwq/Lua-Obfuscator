-- ================================================================
-- passes/num_encrypt.lua
-- Constant number encryption (Fengari / Lua 5.3 / 5.4 safe)
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- Replaces numeric literals with equivalent arithmetic expressions.

local utils = require("passes.utils")
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local is_comment = utils.is_comment

local M = {}

M.name    = "constant_encryption"
M.title   = "Constant Number Encryption"
M.version = "1.3.1"
M.order   = 50

------------------------------------------------------------
-- Safe hex formatting (no string.format %X)
------------------------------------------------------------
local HEX = "0123456789ABCDEF"

local function to_u32(x)
  x = tonumber(x)
  if not x or x ~= x then return 0 end
  if x == math.huge or x == -math.huge then return 0 end
  if x >= 0 then x = math.floor(x) else x = math.ceil(x) end
  x = x % 4294967296
  if x < 0 then x = x + 4294967296 end
  local lo = math.floor(x % 65536)
  local hi = math.floor(x / 65536) % 65536
  return hi * 65536 + lo
end

local function to_hex(n)
  n = to_u32(n)
  local t = {}
  for i = 8, 1, -1 do
    local d = math.floor(n % 16)
    t[i] = HEX:sub(d + 1, d + 1)
    n = math.floor(n / 16)
  end
  return table.concat(t)
end

local function hex4(n)
  n = to_u32(n) % 65536
  local t = {}
  for i = 4, 1, -1 do
    local d = math.floor(n % 16)
    t[i] = HEX:sub(d + 1, d + 1)
    n = math.floor(n / 16)
  end
  return table.concat(t)
end

------------------------------------------------------------
-- Byte helpers
------------------------------------------------------------
local BYTE_0 = string.byte("0")
local BYTE_x = string.byte("x")
local BYTE_X = string.byte("X")
local BYTE_DOT = string.byte(".")
local BYTE_UNDERSCORE = string.byte("_")

local function is_digit(b) return b >= 48 and b <= 57 end
local function is_id_start(b)
  return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
end
local function is_id_char(b) return is_id_start(b) or is_digit(b) end

local function is_hex(s, pos)
  if pos + 1 > #s then return false end
  local b1 = s:byte(pos)
  local b2 = s:byte(pos + 1)
  return b1 == BYTE_0 and (b2 == BYTE_x or b2 == BYTE_X)
end

------------------------------------------------------------
-- Safe integer conversion (avoids "no integer representation")
------------------------------------------------------------
local function to_int(x)
  x = tonumber(x)
  if not x or x ~= x then return 0 end
  if x == math.huge or x == -math.huge then return 0 end
  if x >= 0 then return math.floor(x) else return math.ceil(x) end
end

------------------------------------------------------------
-- Encrypt a single integer (guaranteed integer input)
-- All bitwise ops use to_u32() clamping to avoid Fengari errors
------------------------------------------------------------
local function encrypt_int(n)
  if n == 0 then return "(0x0|0)" end
  if n == 1 then return "(0x1&0x1)" end
  if n == -1 then return "(~0x0)" end

  local sign = n < 0 and "-" or ""
  local abs_n = to_int(math.abs(n))

  -- All methods must evaluate to exactly abs_n.
  -- Forbidden (previously buggy):
  --   * (x<<k)>>k when high bits fall out of 32-bit
  --   * hex encoding of sum when sum > 0xFFFFFFFF (to_hex truncates)

  if abs_n <= 0xFFFF then
    local method = random_int(1, 3)
    if method == 1 then
      local a = to_u32(random_int(1, 0xFFFF))
      local xored = to_u32(a ~ abs_n)
      return sign .. "(0x" .. hex4(a) .. "~0x" .. hex4(xored) .. ")"
    elseif method == 2 then
      -- Keep sum within 16 bits so hex4 never truncates
      local max_a = 0xFFFF - abs_n
      if max_a < 1 then
        local a = to_u32(random_int(1, 0xFFFF))
        local xored = to_u32(a ~ abs_n)
        return sign .. "(0x" .. hex4(a) .. "~0x" .. hex4(xored) .. ")"
      end
      local a = random_int(1, max_a)
      local sum = abs_n + a
      return sign .. "(0x" .. hex4(sum) .. "-0x" .. hex4(a) .. ")"
    else
      -- Safe shift only when abs_n << shift still fits in 16 bits
      local shift = random_int(1, 3)
      if abs_n < (0x10000 >> shift) then
        local shifted = abs_n << shift
        return sign .. "(0x" .. hex4(shifted) .. ">>" .. shift .. ")"
      else
        local a = to_u32(random_int(1, 0xFFFF))
        local xored = to_u32(a ~ abs_n)
        return sign .. "(0x" .. hex4(a) .. "~0x" .. hex4(xored) .. ")"
      end
    end
  elseif abs_n <= 0xFFFFFFFF then
    local method = random_int(1, 2)
    if method == 1 then
      -- XOR is bit-exact for full 32-bit range
      local a = to_u32(random_int(1, 0xFFFFFFFF))
      local xored = to_u32(a ~ abs_n)
      return sign .. "(0x" .. to_hex(a) .. "~0x" .. to_hex(xored) .. ")"
    else
      -- Additive: keep sum within 32-bit so to_hex does not truncate
      local max_a = 0xFFFFFFFF - abs_n
      if max_a < 1 then
        -- abs_n == 0xFFFFFFFF: use XOR only
        local a = to_u32(random_int(1, 0xFFFFFFFF))
        local xored = to_u32(a ~ abs_n)
        return sign .. "(0x" .. to_hex(a) .. "~0x" .. to_hex(xored) .. ")"
      end
      local a = to_u32(random_int(1, math.min(max_a, 0xFFFFFF)))
      local sum = abs_n + a
      return sign .. "(0x" .. to_hex(sum) .. "-0x" .. to_hex(a) .. ")"
    end
  else
    -- Beyond 32-bit: pure decimal additive (no bitwise / no hex truncation)
    local a = random_int(1, 0xFFFF)
    local sum = abs_n + a
    return sign .. "(" .. tostring(sum) .. "-" .. tostring(a) .. ")"
  end
end

------------------------------------------------------------
-- Encrypt a number (handles int and float)
------------------------------------------------------------
local function encrypt_number(n)
  -- Float
  if n ~= math.floor(n) then
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
      if abs_int <= 0xFFFF then
        local a = to_u32(random_int(1, 0xFFFF))
        local xored = to_u32(a ~ abs_int)
        int_enc = sign .. "(0x" .. hex4(a) .. "~0x" .. hex4(xored) .. ")"
      else
        int_enc = encrypt_int(int_part)
      end
    end
    return "(" .. int_enc .. "+" .. tostring(frac) .. "*" .. shift .. "/" .. shift .. ")"
  end

  return encrypt_int(n)
end

------------------------------------------------------------
-- Main apply
------------------------------------------------------------
function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}

  for li, line in ipairs(lines) do
    if line == "" or is_comment(line) then
      result[li] = line
    else
      local parts = {}
      local pn = 0
      local pos = 1
      local len = #line

      while pos <= len do
        local b = line:byte(pos)

        -- Skip __STR\d+__ tokens (from string_pool)
        if b == 95 and line:sub(pos, pos + 3) == "__ST" then
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

        -- Skip double-quoted strings
        elseif b == 34 then
          local str_end = pos + 1
          while str_end <= len do
            local sb = line:byte(str_end)
            if sb == 92 then str_end = str_end + 2
            elseif sb == 34 then str_end = str_end + 1; break
            else str_end = str_end + 1 end
          end
          pn = pn + 1
          parts[pn] = line:sub(pos, str_end - 1)
          pos = str_end

        -- Skip single-quoted strings
        elseif b == 39 then
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

        -- Skip hex literals 0x...
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

        -- Numbers (including scientific notation)
        elseif is_digit(b) and not (pos > 1 and is_id_char(line:byte(pos - 1))) then
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
            elseif (nb == 101 or nb == 69) and not has_exp then
              has_exp = true
              num_end = num_end + 1
              if num_end <= len then
                local sign = line:byte(num_end)
                if sign == 43 or sign == 45 then num_end = num_end + 1 end
              end
            else
              break
            end
          end
          local num_str = line:sub(num_start, num_end - 1)
          local num = tonumber(num_str)
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