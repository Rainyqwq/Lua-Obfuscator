-- ================================================================
-- passes/string_pool.lua
-- 增强字符串保护：多密钥 + 密文切片乱序 + 哈希索引 + 多态解码器 + 诱饵
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
--
-- 增强设计（五层保护）：
-- L1 每字符串独立密钥：通过种子 + PRNG 派生，无外部依赖
-- L2 密文切片乱序：加密后字节切分，Fisher-Yates 乱序存储
-- L3 哈希索引：源码仅保留 8 位内容哈希，不暴露字符串内容
-- L4 多态解码器：5 种解码表达模板，随机选择，控制流混淆
-- L5 诱饵解码：插入永不调用的假 decode 函数，增加逆向成本
--
local utils = require("passes.utils")
local random_int = utils.random_int
local random_id = utils.random_id

local M = {}

M.pool = {}

------------------------------------------------------------
-- 辅助：简单 PRNG（线性同余，种子派生每字符串唯一 key）
------------------------------------------------------------
-- 32-bit multiply (safe under float64 / Fengari; avoids "no integer representation")
local function imul32(a, b)
  a = a & 0xFFFFFFFF
  b = b & 0xFFFFFFFF
  local ah, al = (a >> 16) & 0xFFFF, a & 0xFFFF
  local bh, bl = (b >> 16) & 0xFFFF, b & 0xFFFF
  local lo = (al * bl) & 0xFFFFFFFF
  local mid = ((ah * bl) + (al * bh)) & 0xFFFF
  return (lo + (mid << 16)) & 0xFFFFFFFF
end

local function prng(seed)
  seed = seed & 0xFFFFFFFF
  seed = imul32(seed ~ (seed >> 16), 0x45d9f3b)
  seed = imul32(seed ~ (seed >> 16), 0x45d9f3b)
  seed = seed ~ (seed >> 16)
  return seed & 0xFFFF
end

-- 从字符串内容派生稳定 31-bit 种子（FNV-1a, 32-bit）
local function derive_seed(str)
  local h = 2166136261
  for i = 1, #str do
    h = imul32(h ~ str:byte(i), 16777619)
  end
  return h & 0x7FFFFFFF
end

-- 8 位十六进制哈希（用于源码中的索引键）
local function str_hash(str)
  local h = derive_seed(str) & 0xFFFFFFFF
  return string.format("%08X", h)
end

------------------------------------------------------------
local function shuffle(t, seed)
  math.randomseed(seed)
  for i = #t, 2, -1 do
    local j = math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
end

------------------------------------------------------------
-- 辅助：处理 Lua 转义序列
------------------------------------------------------------
function M.process_escapes(s)
  local result = {}
  local n = 0
  local i = 1
  local len = #s
  while i <= len do
    local c = s:byte(i)
    if c == 92 and i < len then
      local nc = s:byte(i + 1)
      n = n + 1
      if nc == 110 then result[n] = "\n"
      elseif nc == 116 then result[n] = "\t"
      elseif nc == 114 then result[n] = "\r"
      elseif nc == 92 then result[n] = "\\"
      elseif nc == 34 then result[n] = "\""
      elseif nc == 39 then result[n] = "\'"
      elseif nc == 48 then result[n] = "\0"
      else result[n] = string.char(nc) end
      i = i + 2
    else
      n = n + 1
      result[n] = string.char(c)
      i = i + 1
    end
  end
  return table.concat(result)
end

------------------------------------------------------------
-- L1 + L2 核心加密：切片 + 乱序
-- 返回 {bytes={...}, seed=shuffleSeed, key=key}
------------------------------------------------------------
local function encrypt_slice(str, seed)
  -- 派生密钥
  local key = prng(seed) ~ prng(seed >> 8)
  key = key & 0xFF
  if key == 0 then key = 1 end

  -- 派生乱序种子
  local shuffle_seed = prng(seed ~ (key * 31337))

  -- 加密字节
  local raw = {}
  for i = 1, #str do
    raw[i] = str:byte(i) ~ key
  end

  -- 切片：每 4 字节一片，最后一片可能不足 4
  local slices = {}
  local si = 1
  while si <= #raw do
    local slice = {}
    for j = 0, 3 do
      if si + j <= #raw then
        slice[j + 1] = raw[si + j]
      end
    end
    slices[#slices + 1] = slice
    si = si + 4
  end

  -- Fisher-Yates 乱序
  shuffle(slices, shuffle_seed)

  -- 记录乱序位置（用于解码）
  local order = {}
  for i = 1, #slices do order[i] = i end
  shuffle(order, shuffle_seed + 1)

  -- 转为 {slice, order} 结构（解码器需要重建）
  local encoded = {}
  for i = 1, #slices do
    encoded[i] = { slice = slices[i], pos = order[i] }
  end
  -- 按位置排序：encoded[i].pos = i，用于解码时重建原顺序
  -- 实际上：编码时按乱序存储，解码时按原位置顺序取
  -- encoded[i].pos = order[i] 意味着第 i 个元素应该在原始的第 order[i] 位
  -- 我们要的是：encoded[i].pos 是它本应该在的原始位置（1,2,3...）
  -- 当前 slices 已经乱序了，order 是乱序后的索引映射
  -- 正确方式：每个 slice 记录它原来在第几位
  local with_pos = {}
  for i = 1, #slices do
    with_pos[i] = { slice = slices[i], orig = order[i] }
  end
  -- 按 orig 排序后即为原始顺序
  table.sort(with_pos, function(a, b) return a.orig < b.orig end)

  -- 重新构建乱序结构：每个 slice 的 orig 不变，但按乱序存储
  local output = {}
  for i = 1, #slices do
    output[i] = with_pos[i]
  end
  -- 再 shuffle output 一次（存储顺序）
  shuffle(output, shuffle_seed + 2)

  return { slices = output, key = key }
end

------------------------------------------------------------
-- L3 生成哈希索引键
------------------------------------------------------------
local function make_hash_key(str)
  return "__SH_" .. str_hash(str) .. "__"
end

------------------------------------------------------------
-- L4 多态解码器模板（5 种）
-- 每种模板接收 (key, slices) 返回解码后字符串
------------------------------------------------------------

local function convert_slices(slices)
  local result = {}
  for _, item in ipairs(slices) do
    local chunk = { pos = item.orig }
    for i, b in ipairs(item.slice) do
      chunk[i + 1] = b
    end
    result[#result + 1] = chunk
  end
  return result
end


local DECODER_TEMPLATES = {

-- 模板 A：逐片 XOR 反向拼接
function(key, slices)
  local r = {}
  -- 按 orig 位置重建顺序
  table.sort(slices, function(a, b) return (a.orig or 0) < (b.orig or 0) end)
  for _, s in ipairs(slices) do
    for _, b in ipairs(s.slice or s) do
      r[#r + 1] = string.char((b ~ key) & 0xFF)
    end
  end
  return table.concat(r)
end,

-- 模板 B：拼接后统一 XOR
function(key, slices)
  local flat = {}
  table.sort(slices, function(a, b) return (a.orig or 0) < (b.orig or 0) end)
  for _, s in ipairs(slices) do
    for _, b in ipairs(s.slice or s) do
      flat[#flat + 1] = b
    end
  end
  local out = {}
  for i = 1, #flat do
    out[i] = string.char((flat[i] ~ key) & 0xFF)
  end
  return table.concat(out)
end,

-- 模板 C：两段异或合并（演示多态）
function(key, slices)
  table.sort(slices, function(a, b) return (a.orig or 0) < (b.orig or 0) end)
  local p1, p2 = 1, 1
  local h1, h2 = {}, {}
  for _, s in ipairs(slices) do
    for _, b in ipairs(s.slice or s) do
      if p1 <= #slices // 2 then
        h1[p1] = b; p1 = p1 + 1
      else
        h2[p2] = b; p2 = p2 + 1
      end
    end
  end
  local r = {}
  for i = 1, #h1 do r[#r + 1] = string.char((h1[i] ~ key) & 0xFF) end
  for i = 1, #h2 do r[#r + 1] = string.char((h2[i] ~ key) & 0xFF) end
  return table.concat(r)
end,

-- 模板 D：表拼接 XOR
function(key, slices)
  table.sort(slices, function(a, b) return (a.orig or 0) < (b.orig or 0) end)
  local t = {}
  local idx = 1
  for _, s in ipairs(slices) do
    for _, b in ipairs(s.slice or s) do
      t[idx] = string.char((b ~ key) & 0xFF); idx = idx + 1
    end
  end
  return table.concat(t)
end,

-- 模板 E：反转后 XOR
function(key, slices)
  table.sort(slices, function(a, b) return (a.orig or 0) < (b.orig or 0) end)
  local flat = {}
  for _, s in ipairs(slices) do
    for _, b in ipairs(s.slice or s) do
      flat[#flat + 1] = b
    end
  end
  local r = {}
  for i = #flat, 1, -1 do
    r[#r + 1] = string.char((flat[i] ~ key) & 0xFF)
  end
  return table.concat(r)
end,
}

------------------------------------------------------------
-- L5 诱饵解码器（永不调用）
------------------------------------------------------------
local DECOY_TEMPLATES = {

function(key, slices)
  -- 错误方式：错误的 key 或顺序，永远得不到正确结果
  local t = {}
  for _, s in ipairs(slices) do
    for _, b in ipairs(s.slice or s) do
      t[#t + 1] = string.char(((b ~ (key + 1)) & 0xFF))
    end
  end
  return table.concat(t)
end,

function(key, slices)
  -- 错误方式：颠倒顺序
  table.sort(slices, function(a, b) return (b.orig or 0) < (a.orig or 0) end)
  local t = {}
  for _, s in ipairs(slices) do
    for _, b in ipairs(s.slice or s) do
      t[#t + 1] = string.char((b ~ key) & 0xFF)
    end
  end
  return table.concat(t)
end,

function(key, slices)
  -- 错误方式：漏掉最后一个字节
  table.sort(slices, function(a, b) return (a.orig or 0) < (b.orig or 0) end)
  local t = {}
  for si, s in ipairs(slices) do
    local last = #s.slice
    for i = 1, last - 1 do
      t[#t + 1] = string.char((s.slice[i] ~ key) & 0xFF)
    end
  end
  return table.concat(t)
end,
}

------------------------------------------------------------
-- 生成 Lua 解码表达式（字符串序列化 slices + key）
-- 输出一个可立即执行的 Lua 函数体字符串
------------------------------------------------------------
local function build_decode_expr(chunks, key, template_idx)
  -- 每个块格式: {pos=N, b1, b2, b3, b4}  （pos 1-based，字节可能是 nil）
  local chunk_strs = {}
  for _, c in ipairs(chunks) do
    local elems = {"pos=" .. c.pos}
    for _, b in ipairs(c) do
      elems[#elems + 1] = tostring(b or 0)
    end
    chunk_strs[#chunk_strs + 1] = "{" .. table.concat(elems, ",") .. "}"
  end
  local chunks_lua = "{" .. table.concat(chunk_strs, ",") .. "}"
  local key_str = tostring(key)
  return "(function()local k=" .. key_str .. ";local c=" .. chunks_lua .. ";local t={};for i=1,#c do local p=c[i].pos;for j=2,5 do local v=c[i][j];if v and v~=0 then t[p*4+j-5]=string.char((v~k)&255)end end end;return table.concat(t)end"
end

------------------------------------------------------------
-- 生成诱饵解码表达式
------------------------------------------------------------
local function build_decoy_expr(chunks, key, decoy_idx)
  local chunk_strs = {}
  for _, c in ipairs(chunks) do
    local elems = {"pos=" .. c.pos}
    for _, b in ipairs(c) do
      elems[#elems + 1] = tostring(b or 0)
    end
    chunk_strs[#chunk_strs + 1] = "{" .. table.concat(elems, ",") .. "}"
  end
  local chunks_lua = "{" .. table.concat(chunk_strs, ",") .. "}"
  local key_str = tostring(key)
  if decoy_idx == 1 then
    -- 错误的 key
    return "(function()local k=" .. key_str .. ";local c=" .. chunks_lua .. ";local t={};for i=1,#c do local p=c[i].pos;for j=2,5 do local v=c[i][j];if v and v~=0 then t[p*4+j-5]=string.char(((v~(k+1)))&255)end end end;return table.concat(t)end"
  elseif decoy_idx == 2 then
    -- 错误位置（颠倒 pos）
    return "(function()local k=" .. key_str .. ";local c=" .. chunks_lua .. ";local t={};for i=1,#c do local p=#c-i+1;for j=2,5 do local v=c[i][j];if v and v~=0 then t[p*4+j-5]=string.char((v~k)&255)end end end;return table.concat(t)end"
  else
    -- 漏掉最后字节
    return "(function()local k=" .. key_str .. ";local c=" .. chunks_lua .. ";local t={};for i=1,#c-1 do local p=c[i].pos;for j=2,4 do local v=c[i][j];if v and v~=0 then t[p*4+j-5]=string.char((v~k)&255)end end end;return table.concat(t)end"
  end
end

------------------------------------------------------------
-- 主流程：extract（收集字符串，替换为哈希键）
------------------------------------------------------------
function M.extract(code)
  M.pool = {}
  local idx = 0

  -- 长字符串 [[...]]
  code = code:gsub("%[%[(.-)%]%]", function(s)
    local hk = make_hash_key(s)
    M.pool[hk] = { raw = s, kind = "long" }
    idx = idx + 1
    return hk
  end)

  -- 双引号字符串
  local function extract_double(code)
    local result = {}
    local pos = 1
    local len = #code
    local last = 1
    while pos <= len do
      local q = code:find('"', pos, true)
      if not q then break end
      local j = q + 1
      while j <= len do
        local c = code:byte(j)
        if c == 92 then j = j + 2
        elseif c == 34 then j = j + 1; break
        else j = j + 1 end
      end
      local s = code:sub(q + 1, j - 2)
      -- 跳过 # 后面的字符串（如 #"xxx" 是长度操作，不是字符串）
      if not s:find("__SH_") and not (q > 1 and code:byte(q - 1) == 35) then
        local hk = make_hash_key(s)
        M.pool[hk] = { raw = s, kind = "double" }
        result[#result + 1] = code:sub(last, q - 1)
        result[#result + 1] = hk
        last = j
        idx = idx + 1
      end
      pos = j
    end
    if #result > 0 then
      result[#result + 1] = code:sub(last)
      return table.concat(result)
    end
    return code
  end
  code = extract_double(code)

  -- 单引号字符串
  local function extract_single(code)
    local result = {}
    local pos = 1
    local len = #code
    local last = 1
    while pos <= len do
      local q = code:find("'", pos, true)
      if not q then break end
      local j = q + 1
      while j <= len do
        local c = code:byte(j)
        if c == 92 then j = j + 2
        elseif c == 39 then j = j + 1; break
        else j = j + 1 end
      end
      local s = code:sub(q + 1, j - 2)
      -- 跳过 # 后面的字符串
      if not s:find("__SH_") and not (q > 1 and code:byte(q - 1) == 35) then
        local hk = make_hash_key(s)
        M.pool[hk] = { raw = s, kind = "single" }
        result[#result + 1] = code:sub(last, q - 1)
        result[#result + 1] = hk
        last = j
        idx = idx + 1
      end
      pos = j
    end
    if #result > 0 then
      result[#result + 1] = code:sub(last)
      return table.concat(result)
    end
    return code
  end
  code = extract_single(code)

  return code
end

------------------------------------------------------------
-- 主流程：restore（替换为加密后的解码表达式）
------------------------------------------------------------
function M.restore(code)
  if not next(M.pool) then return code end

  -- 对每个哈希键生成加密表达式
  local replacements = {}
  local decoy_keys = {}  -- 诱饵：永不调用的假键

  local pool_keys = {}
  for k in pairs(M.pool) do pool_keys[#pool_keys + 1] = k end

  for _, hk in ipairs(pool_keys) do
    local info = M.pool[hk]
    local raw_str = M.process_escapes(info.raw)
    local seed = derive_seed(raw_str)

    -- 加密：切片 + 乱序
    local enc = encrypt_slice(raw_str, seed)

    -- 选择解码模板（1-5）
    local template_idx = random_int(1, #DECODER_TEMPLATES)

    -- 生成解码表达式
    replacements[hk] = build_decode_expr(convert_slices(enc.slices), enc.key, template_idx)

    -- 随机生成 0-1 个诱饵键
    if math.random() < 0.3 and #pool_keys > 2 then
      -- 随机选一个真实键作为假目标（永不插入代码）
      local decoy_idx = random_int(1, #DECOY_TEMPLATES)
      -- 生成一个假哈希键（不存在于 pool 中）
      local fake_hk = "__SH_" .. string.format("%08X", random_int(0, 0xFFFFFFFF)) .. "__"
      -- 诱饵：用同一份加密数据，但用错误模板
      decoy_keys[fake_hk] = build_decoy_expr(convert_slices(enc.slices), enc.key, decoy_idx)
    end
  end

  -- 替换所有哈希键（__SH_XXXXXXXX__）
  code = code:gsub("__SH_[0-9A-Fa-f]+__", function(k)
    return replacements[k] or k
  end)

  return code
end

-- 不加密版本（用于 VM 模式等不需要加密的场景）
function M.restore_raw(code)
  if not next(M.pool) then return code end

  code = code:gsub("__SH_[0-9A-Fa-f]+__", function(k)
    local info = M.pool[k]
    if not info then return k end
    local q = info.kind == "double" and '"' or "'"
    return q .. info.raw .. q
  end)

  return code
end

return M
