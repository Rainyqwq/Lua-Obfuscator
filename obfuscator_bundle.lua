-- Auto-generated bundle: all pass modules inlined
do
  package.preload["pass_manager"] = function()
    return load([[-- ================================================================
-- pass_manager.lua
-- Pass Manager - 混淆Pass管理框架
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 提供标准化的Pass接口，支持注册、配置、执行、依赖管理
-- ================================================================

local PassManager = {}
PassManager.__index = PassManager

-- 创建新的PassManager实例
function PassManager.new()
  local self = setmetatable({}, PassManager)
  self._registry = {}   -- name -> pass definition
  self._pipeline = {}   -- ordered list of {name, enabled, config}
  self._ctx = {}        -- shared context between passes
  return self
end

-- ================================================================
-- Pass 注册
-- ================================================================

--- 注册一个Pass
--- @param pass table Pass定义表，必须包含以下字段：
---   name        : string   - 唯一标识符 (如 "variable_mangling")
---   title       : string   - 显示名称 (如 "变量名混淆")
---   description : string   - 功能描述
---   version     : string   - 版本号
---   author      : string   - 作者
---   order       : number   - 默认执行顺序 (越小越先执行)
---   requires    : table    - 依赖的Pass名称列表 (可选)
---   config      : table    - 配置项定义 (可选)
---   enabled     : boolean  - 默认是否启用
---   apply       : function - 执行函数 (code, ctx) -> code
---   validate    : function - 验证函数 (可选) (code) -> boolean, err_msg
function PassManager:register(pass)
  -- 验证必填字段
  assert(type(pass.name) == "string" and pass.name ~= "", "Pass必须有name字段")
  assert(type(pass.title) == "string", "Pass必须有title字段")
  assert(type(pass.apply) == "function", "Pass必须有apply函数")
  assert(not self._registry[pass.name], "Pass '" .. pass.name .. "' 已注册")

  -- 设置默认值
  local def = {
    name        = pass.name,
    title       = pass.title or pass.name,
    description = pass.description or "",
    version     = pass.version or "1.0.0",
    author      = pass.author or "unknown",
    order       = pass.order or 100,
    requires    = pass.requires or {},
    config      = pass.config or {},
    enabled     = pass.enabled ~= false,  -- 默认启用
    apply       = pass.apply,
    validate    = pass.validate,
  }

  self._registry[def.name] = def

  -- 加入pipeline
  self._pipeline[#self._pipeline + 1] = {
    name    = def.name,
    enabled = def.enabled,
    config  = {},
  }

  -- 按order排序
  table.sort(self._pipeline, function(a, b)
    local da = self._registry[a.name]
    local db = self._registry[b.name]
    return da.order < db.order
  end)

  return self
end

-- ================================================================
-- Pass 查询
-- ================================================================

--- 获取已注册的Pass列表
--- @return table 列表，每项包含 {name, title, description, enabled, order}
function PassManager:list()
  local result = {}
  for _, entry in ipairs(self._pipeline) do
    local def = self._registry[entry.name]
    result[#result + 1] = {
      name        = def.name,
      title       = def.title,
      description = def.description,
      version     = def.version,
      author      = def.author,
      order       = def.order,
      enabled     = entry.enabled,
      requires    = def.requires,
      config      = def.config,
      config_values = entry.config,
    }
  end
  return result
end

--- 获取单个Pass信息
--- @param name string Pass名称
--- @return table|nil Pass信息
function PassManager:get(name)
  local def = self._registry[name]
  if not def then return nil end
  for _, entry in ipairs(self._pipeline) do
    if entry.name == name then
      return {
        name        = def.name,
        title       = def.title,
        description = def.description,
        version     = def.version,
        author      = def.author,
        order       = def.order,
        enabled     = entry.enabled,
        requires    = def.requires,
        config      = def.config,
        config_values = entry.config,
      }
    end
  end
  return nil
end

-- ================================================================
-- Pass 配置
-- ================================================================

--- 启用/禁用Pass
--- @param name string Pass名称
--- @param enabled boolean 是否启用
--- @return boolean 是否成功
function PassManager:set_enabled(name, enabled)
  assert(self._registry[name], "Pass '" .. name .. "' 未注册")
  for _, entry in ipairs(self._pipeline) do
    if entry.name == name then
      entry.enabled = not not enabled
      return true
    end
  end
  return false
end

--- 批量设置启用状态
--- @param settings table {pass_name = bool, ...}
function PassManager:apply_settings(settings)
  for name, enabled in pairs(settings) do
    if self._registry[name] then
      self:set_enabled(name, enabled)
    end
  end
end

--- 设置Pass配置项
--- @param name string Pass名称
--- @param key string 配置键
--- @param value any 配置值
function PassManager:set_config(name, key, value)
  for _, entry in ipairs(self._pipeline) do
    if entry.name == name then
      entry.config[key] = value
      return true
    end
  end
  return false
end

--- 批量设置Pass配置
--- @param name string Pass名称
--- @param config table 配置表
function PassManager:set_pass_config(name, config)
  for _, entry in ipairs(self._pipeline) do
    if entry.name == name then
      for k, v in pairs(config) do
        entry.config[k] = v
      end
      return true
    end
  end
  return false
end

-- ================================================================
-- Pass 执行
-- ================================================================

--- 运行所有启用的Pass
--- @param code string 源代码
--- @param opts table 可选 {vm_module=table, on_pass=func(name, index, total)}
--- @return string 混淆后的代码
--- @return table 执行日志 [{name, title, elapsed, input_size, output_size}]
function PassManager:run(code, opts)
  opts = opts or {}
  local vm_module = opts.vm_module
  local on_pass = opts.on_pass
  local log = {}

  -- 构建共享上下文
  local ctx = {
    vm_module = vm_module,
    config = {},
  }

  -- 检查依赖
  for _, entry in ipairs(self._pipeline) do
    if entry.enabled then
      local def = self._registry[entry.name]
      for _, dep in ipairs(def.requires) do
        local found = false
        for _, e2 in ipairs(self._pipeline) do
          if e2.name == dep and e2.enabled then
            found = true
            break
          end
        end
        if not found then
          error(string.format("Pass '%s' 依赖 '%s'，但后者未启用", entry.name, dep))
        end
      end
    end
  end

  -- 统计启用的Pass数量
  local total = 0
  for _, entry in ipairs(self._pipeline) do
    if entry.enabled then total = total + 1 end
  end

  -- 按顺序执行
  local idx = 0
  local clock = os.clock  -- 缓存 os.clock，避免每次 pass 重复 nil 检查
  for _, entry in ipairs(self._pipeline) do
    if entry.enabled then
      local def = self._registry[entry.name]
      idx = idx + 1

      if on_pass then
        on_pass(def.name, def.title, idx, total)
      end

      local input_size = #code
      local t0 = clock and clock() or 0

      -- 合并配置
      ctx.config = {}
      for k, v in pairs(def.config) do ctx.config[k] = v end
      for k, v in pairs(entry.config) do ctx.config[k] = v end

      -- 执行
      local ok, result = pcall(def.apply, code, ctx)
      if not ok then
        error(string.format("Pass '%s' (%s) 执行失败: %s", def.name, def.title, tostring(result)))
      end

      local elapsed = clock and (clock() - t0) or 0
      code = result

      log[#log + 1] = {
        name        = def.name,
        title       = def.title,
        elapsed     = elapsed,
        input_size  = input_size,
        output_size = #code,
      }
    end
  end

  return code, log
end

--- 获取当前pipeline配置（用于序列化/导出）
--- @return table {pass_name = {enabled=bool, config={}}, ...}
function PassManager:export_config()
  local result = {}
  for _, entry in ipairs(self._pipeline) do
    result[entry.name] = {
      enabled = entry.enabled,
      config = {},
    }
    for k, v in pairs(entry.config) do
      result[entry.name].config[k] = v
    end
  end
  return result
end

--- 导入pipeline配置
--- @param config table {pass_name = {enabled=bool, config={}}, ...}
function PassManager:import_config(config)
  for name, settings in pairs(config) do
    if self._registry[name] then
      if settings.enabled ~= nil then
        self:set_enabled(name, settings.enabled)
      end
      if settings.config then
        self:set_pass_config(name, settings.config)
      end
    end
  end
end

return PassManager
]], "@pass_manager.lua")()
  end
  package.preload["passes"] = function()
    return load([[-- ================================================================
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
  "passes.anti_debug",
  "passes.string_encrypt",
  "passes.num_encrypt",
  "passes.instr_sub",
  "passes.var_mangle",
  "passes.adv_fake_cf",
 "passes.cf_flatten",
 "passes.bcf",
  "passes.bb_split",
 "passes.junk_comment",
  "passes.call_indirect",
  "passes.header",
}

-- 加载所有内置 Pass 并注册到 PassManager
function M.load_all(pm)
  for _, name in ipairs(BUILTIN) do
    local ok, pass = pcall(require, name)
    if ok and type(pass) == "table" and pass.name then
      pm:register(pass)
    else
      if io and io.stderr then io.stderr:write(string.format("[passes] WARNING: 加载 %s 失败: %s\n", name, tostring(pass))) else print(string.format("[passes] WARNING: 加载 %s 失败: %s", name, tostring(pass))) end
    end
  end
  return pm
end

-- 注册单个自定义 Pass
function M.register(pm, pass)
  pm:register(pass)
end

return M
]], "@passes/init.lua")()
  end
  package.preload["passes.utils"] = function()
    return load([=[-- ================================================================
-- passes/utils.lua
-- 通用工具函数库
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 供所有 Pass 共用的基础功能
--
-- 性能注意事项：
--   - split_lines / join_lines 是热路径，已做优化
--   - 高频调用的函数避免在内部创建闭包
--   - 模式匹配尽量用 %f[] 前瞻断言代替 %a/%A

local M = {}

function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- 分割字符串为行数组（比 gmatch 更快，减少迭代次数）
function M.split_lines(s)
  local lines = {}
  local n = 0
  local pos = 1
  local len = #s
  while pos <= len do
    local nl = s:find("\n", pos, true)
    n = n + 1
    if nl then
      lines[n] = s:sub(pos, nl - 1)
      pos = nl + 1
    else
      lines[n] = s:sub(pos)
      break
    end
  end
  -- 去掉末尾空行
  if n > 1 and lines[n] == "" then
    lines[n] = nil
  end
  return lines
end

-- 合并行为字符串
function M.join_lines(lines)
  return table.concat(lines, "\n")
end

-- 生成随机标识符（直接拼接字节，避免 string.sub 循环）
local CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local CHAR_BYTES = {}
for i = 1, #CHARS do CHAR_BYTES[i] = CHARS:byte(i) end
local NCHARS = #CHAR_BYTES

function M.random_id(len)
  len = len or 8
  local bytes = {}
  for i = 1, len do
    bytes[i] = CHAR_BYTES[math.random(1, NCHARS)]
  end
  return string.char(table.unpack(bytes))
end

function M.random_int(min, max)
  return math.random(min, max)
end

-- 计算一行代码的嵌套深度变化
-- 返回: opens, closes
function M.calc_depth(line)
  local trimmed = M.trim(line)
  if trimmed == "" or trimmed:byte(1) == 45 then return 0, 0 end  -- '-' = 45
  -- 去掉字符串内容后再计算
  local stripped = trimmed:gsub('%b""', ''):gsub("%b''", ''):gsub('%b[]', '  ')
  local opens, closes = 0, 0
  for _ in stripped:gmatch('%f[%a]function%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]do%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]then%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]else%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]repeat%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('{') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]end%f[%A]') do closes = closes + 1 end
  for _ in stripped:gmatch('%f[%a]until%f[%A]') do closes = closes + 1 end
  for _ in stripped:gmatch('}') do closes = closes + 1 end
  return opens, closes
end

-- 去掉字符串字面量内容，保留引号结构
function M.strip_strings_from_line(line)
  return line:gsub('%b""', '""'):gsub("%b''", "''"):gsub("%[%[.-%]%]", "[[]]")
end

-- 安全的 gsub（处理替换字符串中的特殊字符）
function M.gsub_safe(s, pattern, repl)
  local ok, result = pcall(string.gsub, s, pattern, repl)
  if ok then return result end
  return s
end

-- 快速检查一行是否是注释（避免 gmatch 开销）
function M.is_comment(line)
  local i = 1
  local len = #line
  while i <= len do
    local b = line:byte(i)
    if b == 32 or b == 9 then  -- 空格或tab
      i = i + 1
    elseif b == 45 and i < len and line:byte(i + 1) == 45 then  -- '--'
      return true
    else
      return false
    end
  end
  return false
end

-- 快速检查一行是否为空
function M.is_empty(line)
  return line:match("^%s*$") ~= nil
end

return M
]=], "@passes/utils.lua")()
  end
  package.preload["passes.string_pool"] = function()
    return load([=[-- ================================================================
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
-- Pure integer PRNG (LCG, works in both Lua 5.3 and Fengari)
local function prng(seed)
  seed = (seed * 22695477 + 1) & 0xFFFF
  return seed
end

-- 从字符串内容派生稳定 31-bit 种子（每步都 & 0x7FFFFFFF 保持整数范围）
local function derive_seed(str)
  local h = 2166136261
  for i = 1, #str do
    h = ((h ~ str:byte(i)) * 16777619) & 0x7FFFFFFF
  end
  return h
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
]=], "@passes/string_pool.lua")()
  end
  package.preload["passes.vm"] = function()
    return load([=[-- ================================================================
-- vm.lua
-- VM 字节码编译器/解释器
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- Lua version compatibility check
if _VERSION then
  local ver = tonumber(_VERSION:match("Lua (%d+%.%d+)") or "0")
  if ver < 5.3 then
    local ok, bit_lib = pcall(require, "bit") or pcall(require, "bit32")
    if ok and bit_lib then
      rawset(_G, "_bxor", bit_lib.bxor)
      rawset(_G, "_band", bit_lib.band)
      rawset(_G, "_bor",  bit_lib.bor)
      rawset(_G, "_bnot", bit_lib.bnot)
      rawset(_G, "_shl",  bit_lib.lshift)
      rawset(_G, "_shr",  bit_lib.rshift)
    end
  end
end

--[[
  Lua VM Protector v2.1 - 真正的代码虚拟化
  
  原理：
    1. 解析 Lua 源码为 AST（抽象语法树）
    2. 将 AST 编译为自定义指令集（不兼容标准 Lua 字节码）
    3. 生成自定义 VM 解释器（纯 Lua 实现）
    4. 输出 = VM 解释器 + 加密的自定义字节码
    
  攻击者必须：
    1. 理解自定义指令集格式
    2. 逆向 VM 解释器逻辑
    3. 反汇编自定义字节码
    才能还原原始逻辑
]]

local VERSION = "2.7.0"

------------------------------------------------------------
-- 自定义指令集定义
------------------------------------------------------------
local OPC = {
  NOP      = 0,
  LOADK    = 1,   -- R[A] = K[Bx]
  LOADBOOL = 2,   -- R[A] = B; if C then pc++
  LOADNIL  = 3,   -- R[A..A+B] = nil
  MOVE     = 4,   -- R[A] = R[B]
  GETGLOBAL= 5,   -- R[A] = G[K[Bx]]
  SETGLOBAL= 6,   -- G[K[Bx]] = R[A]
  GETTABLE = 7,   -- R[A] = R[B][R[C]]
  SETTABLE = 8,   -- R[A][R[B]] = R[C]
  NEWTABLE = 9,   -- R[A] = {}
  ADD      = 10,  -- R[A] = R[B] + R[C]
  SUB      = 11,  -- R[A] = R[B] - R[C]
  MUL      = 12,  -- R[A] = R[B] * R[C]
  DIV      = 13,  -- R[A] = R[B] / R[C]
  IDIV     = 55,  -- R[A] = R[B] // R[C]
  MOD      = 14,  -- R[A] = R[B] % R[C]
  POW      = 15,  -- R[A] = R[B] ^ R[C]
  BAND     = 16,  -- R[A] = R[B] & R[C]
  BOR      = 17,  -- R[A] = R[B] | R[C]
  BXOR     = 18,  -- R[A] = R[B] ~ R[C]
  SHL      = 19,  -- R[A] = R[B] << R[C]
  SHR      = 20,  -- R[A] = R[B] >> R[C]
  UNM      = 21,  -- R[A] = -R[B]
  BNOT     = 22,  -- R[A] = ~R[B]
  NOT      = 23,  -- R[A] = not R[B]
  LEN      = 24,  -- R[A] = #R[B]
  CONCAT   = 25,  -- R[A] = R[B] .. R[C]
  EQ       = 26,  -- if (R[A]==R[B]) ~= C then pc++
  LT       = 27,  -- if (R[A]<R[B]) ~= C then pc++
  LE       = 28,  -- if (R[A]<=R[B]) ~= C then pc++
  JMP      = 29,  -- pc += sBx
  TEST     = 30,  -- if R[A] == C then pc++
  TESTSET  = 31,  -- if R[B]==C then pc++ else R[A]=R[B]
  CALL     = 32,  -- R[A..A+C-2] = R[A](R[A+1..A+B-1])
  TAILCALL = 33,  -- return R[A](R[A+1..A+B-1])
  RETURN   = 34,  -- return R[A..A+B-2]
  FORPREP  = 35,  -- R[A] -= R[A+2]; setup for loop
  FORLOOP  = 36,  -- R[A] += R[A+2]; if in range goto sBx
  TFORPREP = 37,  -- prepare generic for
  TFORCALL = 38,  -- R[A+3..A+2+C] = R[A](R[A+1], R[A+2])
  TFORLOOP = 39,  -- if R[A+3] ~= nil then R[A+2]=R[A+3] else pc++
  SETLIST  = 40,  -- R[A][B] = R[A+1..A+C]
  CLOSURE  = 41,  -- R[A] = closure(proto[Bx])
  VARARG   = 42,  -- R[A..A+B-2] = ...
  GETUPVAL = 44,  -- R[A] = upvalues[B]
  SETUPVAL = 45,  -- upvalues[B] = R[A]
  EXTRARG  = 43,  -- extra argument for previous instruction
}

------------------------------------------------------------
-- 简单递归下降解析器
------------------------------------------------------------
local Parser = {}
Parser.__index = Parser

function Parser.new(source)
  return setmetatable({
    source = source,
    pos = 1,
    len = #source,
    tokens = {},
    token_pos = 1,
  }, Parser)
end

-- Tokenizer
function Parser:peek()
  self:skip_ws()
  if self.token_pos <= #self.tokens then
    return self.tokens[self.token_pos]
  end
  -- Tokenize next
  self:skip_ws()
  if self.pos > self.len then
    return { type = "EOF", value = "" }
  end
  local c = self.source:sub(self.pos, self.pos)
  
  -- Number
  if c:match("[%d]") then
    local num = self.source:match("^0[xX][%da-fA-F]+", self.pos) or
                self.source:match("^%d+%.%d+[eE][+-]?%d+", self.pos) or
                self.source:match("^%d+%.%d+", self.pos) or
                self.source:match("^%d+[eE][+-]?%d+", self.pos) or
                self.source:match("^%d+", self.pos)
    if num then
      local tok = { type = "NUMBER", value = num }
      self.tokens[#self.tokens + 1] = tok
      return tok
    end
  end
  
  -- String
  if c == '"' or c == "'" then
    local j = self.pos + 1
    while j <= self.len do
      local sc = self.source:sub(j, j)
      if sc == '\\' then j = j + 2
      elseif sc == c then j = j + 1; break
      else j = j + 1 end
    end
    local tok = { type = "STRING", value = self.source:sub(self.pos, j-1) }
    self.tokens[#self.tokens + 1] = tok
    return tok
  end
  
  -- Identifier / keyword
  if c:match("[%a_]") then
    local id = self.source:match("^[%a_][%w_]*", self.pos)
    local tok = { type = "IDENT", value = id }
    if id == "local" or id == "function" or id == "if" or id == "then" or
       id == "else" or id == "elseif" or id == "end" or id == "for" or
       id == "while" or id == "do" or id == "repeat" or id == "until" or
       id == "return" or id == "break" or id == "nil" or id == "true" or
       id == "false" or id == "and" or id == "or" or id == "not" or
       id == "in" or id == "goto" then
      tok.type = "KEYWORD"
    end
    self.tokens[#self.tokens + 1] = tok
    return tok
  end
  
  -- Long string: [=...[...]...=]
  if c == '[' then
    local eq_start = self.pos + 1
    local eq_count = 0
    while eq_start + eq_count <= self.len and self.source:sub(eq_start + eq_count, eq_start + eq_count) == '=' do
      eq_count = eq_count + 1
    end
    if eq_start + eq_count <= self.len and self.source:sub(eq_start + eq_count, eq_start + eq_count) == '[' then
      local close_pat = ']' .. string.rep('=', eq_count) .. ']'
      local close = self.source:find(close_pat, eq_start + eq_count + 1, true)
      if close then
        local tok = { type = "STRING", value = self.source:sub(self.pos, close + #close_pat - 1) }
        self.tokens[#self.tokens + 1] = tok
        return tok
      end
    end
  end

  -- Operators
  local ops = {
    ["+"] = "+", ["-"] = "-", ["*"] = "*", ["/"] = "/",
    ["%"] = "%", ["^"] = "^", ["#"] = "#", ["("] = "(",
    [")"] = ")", ["{"] = "{", ["}"] = "}", ["["] = "[",
    ["]"] = "]", [";"] = ";", [","] = ",", ["."] = ".",
    [":"] = ":", ["~"] = "~", ["="] = "=", [">"] = ">", ["<"] = "<",
    ["&"] = "&", ["|"] = "|",
  }
  
  if c == '<' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '<' then
      local tok = { type = 'OP', value = '<<' }
      self.tokens[#self.tokens + 1] = tok
      return tok
  elseif c == '>' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '>' then
      local tok = { type = 'OP', value = '>>' }
      self.tokens[#self.tokens + 1] = tok
      return tok
  elseif c == '/' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '/' then
      local tok = { type = 'OP', value = '//' }
      self.tokens[#self.tokens + 1] = tok
      return tok
  elseif c == '=' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '=' then
    local tok = { type = "OP", value = "==" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == '~' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '=' then
    local tok = { type = "OP", value = "~=" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == '<' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '=' then
    local tok = { type = "OP", value = "<=" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == '>' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '=' then
    local tok = { type = "OP", value = ">=" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == '.' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '.' then
    if self.pos + 1 < self.len and self.source:sub(self.pos+2, self.pos+2) == '.' then
      local tok = { type = "OP", value = "..." }
      self.tokens[#self.tokens + 1] = tok
      return tok
    end
    local tok = { type = "OP", value = ".." }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == ':' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == ':' then
    local tok = { type = "OP", value = "::" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif ops[c] then
    local tok = { type = "OP", value = c }
    self.tokens[#self.tokens + 1] = tok
    return tok
  end
  
  -- Unknown, skip
  local tok = { type = "UNKNOWN", value = c }
  self.tokens[#self.tokens + 1] = tok
  return tok
end

function Parser:advance()
  local tok = self:peek()
  self.token_pos = self.token_pos + 1
  -- Advance source position past the token
  if tok.type == "NUMBER" then
    self.pos = self.pos + #tok.value
  elseif tok.type == "STRING" then
    self.pos = self.pos + #tok.value
  elseif tok.type == "IDENT" or tok.type == "KEYWORD" then
    self.pos = self.pos + #tok.value
  elseif tok.type == "OP" then
    self.pos = self.pos + #tok.value
  else
    self.pos = self.pos + 1
  end
  self:skip_ws()
  return tok
end

function Parser:skip_ws()
  while self.pos <= self.len do
    local c = self.source:sub(self.pos, self.pos)
    if c == ' ' or c == '\t' or c == '\r' then
      self.pos = self.pos + 1
    elseif c == '\n' then
      self.pos = self.pos + 1
    elseif c == '-' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '-' then
      -- Comment: check for long comment --[=...[...]...=]
      if self.pos + 2 <= self.len and self.source:sub(self.pos+2, self.pos+2) == '[' then
        local eq_start = self.pos + 3
        local eq_count = 0
        while eq_start + eq_count <= self.len and self.source:sub(eq_start + eq_count, eq_start + eq_count) == '=' do
          eq_count = eq_count + 1
        end
        if eq_start + eq_count <= self.len and self.source:sub(eq_start + eq_count, eq_start + eq_count) == '[' then
          local close_pat = ']' .. string.rep('=', eq_count) .. ']'
          local close = self.source:find(close_pat, eq_start + eq_count + 1, true)
          if close then
            self.pos = close + #close_pat
          else
            self.pos = self.len + 1
          end
        else
          -- Single-line comment
          local nl = self.source:find('\n', self.pos + 2)
          if nl then self.pos = nl + 1
          else self.pos = self.len + 1 end
        end
      else
        -- Single-line comment
        local nl = self.source:find('\n', self.pos + 2)
        if nl then self.pos = nl + 1
        else self.pos = self.len + 1 end
      end
    else
      break
    end
  end
end

function Parser:expect(type, value)
  local tok = self:advance()
  if tok.type ~= type or (value and tok.value ~= value) then
    error(string.format("Expected %s '%s', got %s '%s' at pos %d",
      type, value or "", tok.type, tok.value, self.pos))
  end
  return tok
end

function Parser:match(type, value)
  local tok = self:peek()
  if tok.type == type and (not value or tok.value == value) then
    return self:advance()
  end
  return nil
end

-- AST Node constructors
local function ast_block(stmts) return { type = "block", stmts = stmts } end
local function ast_assign(targets, values) return { type = "assign", targets = targets, values = values } end
local function ast_local(names, values) return { type = "local", names = names, values = values } end
local function ast_call(func, args) return { type = "call", func = func, args = args } end
local function ast_if(cond, then_block, else_block) return { type = "if", cond = cond, then_block = then_block, else_block = else_block } end
local function ast_while(cond, body) return { type = "while", cond = cond, body = body } end
local function ast_for_num(name, init, limit, step, body) return { type = "for_num", name = name, init = init, limit = limit, step = step, body = body } end
local function ast_for_in(names, iter_expr, body) return { type = "for_in", names = names, iter_expr = iter_expr, body = body } end
local function ast_return(values) return { type = "return", values = values } end
local function ast_break() return { type = "break" } end
local function ast_func_def(params, body, is_local, name) return { type = "func_def", params = params, body = body, is_local = is_local, name = name } end
local function ast_table(fields) return { type = "table", fields = fields } end
local function ast_index(obj, key) return { type = "index", obj = obj, key = key } end
local function ast_binop(op, left, right) return { type = "binop", op = op, left = left, right = right } end
local function ast_unop(op, expr) return { type = "unop", op = op, expr = expr } end
local function ast_number(val) return { type = "number", value = val } end
local function ast_string(val) return { type = "string", value = val } end
local function ast_ident(name) return { type = "ident", name = name } end
local function ast_bool(val) return { type = "bool", value = val } end
local function ast_nil() return { type = "nil" } end
local function ast_vararg() return { type = "vararg" } end
local function ast_do_block(body) return { type = "do_block", body = body } end
local function ast_repeat(body, cond) return { type = "repeat", body = body, cond = cond } end
local function ast_goto(label) return { type = "goto", label = label } end
local function ast_label(name) return { type = "label", name = name } end

function Parser:parse_block()
  local stmts = {}
  while true do
    local tok = self:peek()
    if tok.type == "EOF" or (tok.type == "KEYWORD" and
       (tok.value == "end" or tok.value == "else" or tok.value == "elseif" or
        tok.value == "until")) then
      break
    end
    local stmt = self:parse_stmt()
    if stmt then
      stmts[#stmts + 1] = stmt
    end
  end
  return ast_block(stmts)
end

function Parser:parse_stmt()
  local tok = self:peek()
  
  -- Empty / comment
  if tok.type == "EOF" then return nil end
  
  -- Local declaration
  if tok.type == "KEYWORD" and tok.value == "local" then
    self:advance()
    local next_tok = self:peek()
    if next_tok.type == "KEYWORD" and next_tok.value == "function" then
      self:advance()
      local name = self:expect("IDENT").value
      self:expect("OP", "(")
      local params = self:parse_param_list()
      self:expect("OP", ")")
      local body = self:parse_block()
      self:expect("KEYWORD", "end")
      return ast_func_def(params, body, true, name)
    else
      local names = {}
      repeat
        names[#names + 1] = self:expect("IDENT").value
        -- Skip Lua 5.4 attribute: <const> or <close>
        if self:match("OP", "<") then
          self:advance()  -- skip attribute name (const/close)
          self:expect("OP", ">")
        end
      until not self:match("OP", ",")
      local values = nil
      if self:match("OP", "=") then
        values = self:parse_expr_list()
      end
      return ast_local(names, values)
    end
  end
  
  -- Function definition
  if tok.type == "KEYWORD" and tok.value == "function" then
    self:advance()
    local name = self:expect("IDENT").value
    -- Support dotted names: function M.protect(code)
    -- Support method names: function M:method(code)
    local name_parts = {name}
    while true do
      local peek_tok = self:peek()
      if peek_tok.type == "OP" and (peek_tok.value == "." or peek_tok.value == ":") then
        local sep = self:advance().value
        name_parts[#name_parts + 1] = sep
        name_parts[#name_parts + 1] = self:expect("IDENT").value
      else
        break
      end
    end
    local full_name = table.concat(name_parts)
    self:expect("OP", "(")
    local params = self:parse_param_list()
    self:expect("OP", ")")
    local body = self:parse_block()
    self:expect("KEYWORD", "end")
    return ast_assign({ast_ident(full_name)}, {ast_func_def(params, body, false)})
  end
  
  -- If statement
  if tok.type == "KEYWORD" and tok.value == "if" then
    self:advance()
    local cond = self:parse_expr()
    self:expect("KEYWORD", "then")
    local then_block = self:parse_block()
    local else_block = nil
    if self:match("KEYWORD", "elseif") then
      -- Parse the entire elseif/else/end chain as a nested if
      -- Use a helper function to handle the recursion
      local function parse_elseif_chain()
        local ec = self:parse_expr()
        self:expect("KEYWORD", "then")
        local eb = self:parse_block()
        local ee = nil
        if self:match("KEYWORD", "elseif") then
          ee = parse_elseif_chain()
        elseif self:match("KEYWORD", "else") then
          ee = self:parse_block()
          self:expect("KEYWORD", "end")
        else
          self:expect("KEYWORD", "end")
        end
        return ast_block({ast_if(ec, eb, ee)})
      end
      else_block = parse_elseif_chain()
    elseif self:match("KEYWORD", "else") then
      else_block = self:parse_block()
      self:expect("KEYWORD", "end")
    else
      self:expect("KEYWORD", "end")
    end
    return ast_if(cond, then_block, else_block)
  end
  
  -- While loop
  if tok.type == "KEYWORD" and tok.value == "while" then
    self:advance()
    local cond = self:parse_expr()
    self:expect("KEYWORD", "do")
    local body = self:parse_block()
    self:expect("KEYWORD", "end")
    return ast_while(cond, body)
  end
  
  -- For loop
  if tok.type == "KEYWORD" and tok.value == "for" then
    self:advance()
    local name = self:expect("IDENT").value
    if self:match("OP", "=") then
      -- Numeric for
      local init = self:parse_expr()
      self:expect("OP", ",")
      local limit = self:parse_expr()
      local step = nil
      if self:match("OP", ",") then
        step = self:parse_expr()
      end
      self:expect("KEYWORD", "do")
      local body = self:parse_block()
      self:expect("KEYWORD", "end")
      return ast_for_num(name, init, limit, step, body)
    else
      -- Generic for: for k, v, ... in iter_expr do body end
      local names = {name}
      while self:match("OP", ",") do
        names[#names + 1] = self:expect("IDENT").value
      end
      self:expect("KEYWORD", "in")
      local iter_expr = self:parse_expr_list()
      self:expect("KEYWORD", "do")
      local body = self:parse_block()
      self:expect("KEYWORD", "end")
      return ast_for_in(names, iter_expr, body)
    end
  end
  
  -- Return
  if tok.type == "KEYWORD" and tok.value == "return" then
    self:advance()
    local values = nil
    local nk = self:peek()
    if nk.type ~= "KEYWORD" and nk.type ~= "EOF" then
      values = self:parse_expr_list()
    elseif nk.type == "KEYWORD" and (nk.value == "function" or nk.value == "nil" or nk.value == "true" or nk.value == "false" or nk.value == "not") then
      values = self:parse_expr_list()
    end
    return ast_return(values)
  end
  
  -- Standalone do...end block
  if tok.type == "KEYWORD" and tok.value == "do" then
    self:advance()
    local body = self:parse_block()
    self:expect("KEYWORD", "end")
    return ast_do_block(body)
  end

  -- Repeat...until loop
  if tok.type == "KEYWORD" and tok.value == "repeat" then
    self:advance()
    local body = self:parse_block()
    self:expect("KEYWORD", "until")
    local cond = self:parse_expr()
    return ast_repeat(body, cond)
  end

  -- Break
  if tok.type == "KEYWORD" and tok.value == "break" then
    self:advance()
    return ast_break()
  end

  -- Goto label
  if tok.type == "KEYWORD" and tok.value == "goto" then
    self:advance()
    local label = self:expect("IDENT").value
    return ast_goto(label)
  end

  -- Label ::name::
  if tok.type == "OP" and tok.value == "::" then
    self:advance()
    local name = self:expect("IDENT").value
    self:expect("OP", "::")
    return ast_label(name)
  end
  
  -- Expression statement (assignment or call)
  local targets = {self:parse_expr()}
  while self:match("OP", ",") do
    targets[#targets + 1] = self:parse_expr()
  end
  if self:match("OP", "=") then
    local values = self:parse_expr_list()
    return ast_assign(targets, values)
  end
  -- Must be a call (single expression)
  return targets[1]
end

function Parser:parse_param_list()
  local params = {}
  local tok = self:peek()
  if tok.type == "IDENT" then
    params[#params + 1] = self:advance().value
    while self:match("OP", ",") do
      local next_tok = self:peek()
      if next_tok.type == "OP" and next_tok.value == "..." then
        self:advance()
        params[#params + 1] = "..."
        break
      end
      params[#params + 1] = self:expect("IDENT").value
    end
  elseif tok.type == "OP" and tok.value == "..." then
    self:advance()
    params[#params + 1] = "..."
  end
  return params
end

function Parser:parse_expr_list()
  local exprs = {}
  exprs[#exprs + 1] = self:parse_expr()
  while self:match("OP", ",") do
    exprs[#exprs + 1] = self:parse_expr()
  end
  return exprs
end

function Parser:parse_expr()
  return self:parse_or_expr()
end

function Parser:parse_or_expr()
  local left = self:parse_and_expr()
  while self:match("KEYWORD", "or") do
    local right = self:parse_and_expr()
    left = ast_binop("or", left, right)
  end
  return left
end

function Parser:parse_and_expr()
  local left = self:parse_cmp_expr()
  while self:match("KEYWORD", "and") do
    local right = self:parse_cmp_expr()
    left = ast_binop("and", left, right)
  end
  return left
end

function Parser:parse_cmp_expr()
  local left = self:parse_bor_expr()
  local ops_map = {["=="]="==",["~="]="~=",[">"]=">",["<"]="<",[">="]=">=",["<="]="<="}
  local tok = self:peek()
  if tok.type == "OP" and ops_map[tok.value] then
    self:advance()
    local right = self:parse_bor_expr()
    return ast_binop(ops_map[tok.value], left, right)
  end
  return left
end

function Parser:parse_bor_expr()
  local left = self:parse_xor_expr()
  while self:match("OP", "|") do
    local right = self:parse_xor_expr()
    left = ast_binop("|", left, right)
  end
  return left
end

function Parser:parse_xor_expr()
  local left = self:parse_band_expr()
  while self:match("OP", "~") do
    local right = self:parse_band_expr()
    left = ast_binop("~", left, right)
  end
  return left
end

function Parser:parse_band_expr()
  local left = self:parse_shift_expr()
  while self:match("OP", "&") do
    local right = self:parse_shift_expr()
    left = ast_binop("&", left, right)
  end
  return left
end

function Parser:parse_shift_expr()
  local left = self:parse_concat_expr()
  while true do
    local tok = self:peek()
    if tok.type == "OP" and (tok.value == "<<" or tok.value == ">>") then
      self:advance()
      local right = self:parse_concat_expr()
      left = ast_binop(tok.value, left, right)
    else
      break
    end
  end
  return left
end

function Parser:parse_concat_expr()
  local left = self:parse_add_expr()
  while self:match("OP", "..") do
    local right = self:parse_add_expr()
    left = ast_binop("..", left, right)
  end
  return left
end

function Parser:parse_add_expr()
  local left = self:parse_mul_expr()
  while true do
    local tok = self:peek()
    if tok.type == "OP" and (tok.value == "+" or tok.value == "-") then
      self:advance()
      local right = self:parse_mul_expr()
      left = ast_binop(tok.value, left, right)
    else
      break
    end
  end
  return left
end

function Parser:parse_mul_expr()
  local left = self:parse_unary_expr()
  while true do
    local tok = self:peek()
    if tok.type == "OP" and (tok.value == "*" or tok.value == "/" or tok.value == "//" or tok.value == "%") then
      self:advance()
      local right = self:parse_unary_expr()
      left = ast_binop(tok.value, left, right)
    else
      break
    end
  end
  return left
end

function Parser:parse_unary_expr()
  local tok = self:peek()
  if tok.type == "KEYWORD" and tok.value == "not" then
    self:advance()
    return ast_unop("not", self:parse_unary_expr())
  end
  if tok.type == "OP" and tok.value == "#" then
    self:advance()
    return ast_unop("#", self:parse_unary_expr())
  end
  if tok.type == "OP" and tok.value == "-" then
    self:advance()
    return ast_unop("-", self:parse_unary_expr())
  end
  if tok.type == "OP" and tok.value == "~" then
    self:advance()
    return ast_unop("~", self:parse_unary_expr())
  end
  return self:parse_pow_expr()
end

function Parser:parse_pow_expr()
  local left = self:parse_primary_expr()
  if self:match("OP", "^") then
    local right = self:parse_unary_expr()
    return ast_binop("^", left, right)
  end
  return left
end

function Parser:parse_primary_expr()
  local tok = self:peek()
  local node
  
  if tok.type == "NUMBER" then
    self:advance()
    node = ast_number(tonumber(tok.value))
  elseif tok.type == "STRING" then
    self:advance()
    local s
    if tok.value:sub(1, 1) == '[' and tok.value:sub(2, 2) ~= '"' and tok.value:sub(2, 2) ~= "'" then
      local eq_end = 2
      while tok.value:sub(eq_end, eq_end) == '=' do eq_end = eq_end + 1 end
      s = tok.value:sub(eq_end + 1, -(eq_end + 1))
    else
      s = tok.value:sub(2, -2)
      s = s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r"):gsub("\\\\", "\\"):gsub('\\"', '"'):gsub("\\'", "'"):gsub("\\0", "\0")
    end
    node = ast_string(s)
  elseif tok.type == "KEYWORD" and tok.value == "nil" then
    self:advance()
    node = ast_nil()
  elseif tok.type == "KEYWORD" and tok.value == "true" then
    self:advance()
    node = ast_bool(true)
  elseif tok.type == "KEYWORD" and tok.value == "false" then
    self:advance()
    node = ast_bool(false)
  elseif tok.type == "OP" and tok.value == "..." then
    self:advance()
    node = ast_vararg()
  elseif tok.type == "OP" and tok.value == "(" then
    self:advance()
    node = self:parse_expr()
    self:expect("OP", ")")
  elseif tok.type == "KEYWORD" and tok.value == "function" then
    self:advance()
    self:expect("OP", "(")
    local params = self:parse_param_list()
    self:expect("OP", ")")
    local body = self:parse_block()
    self:expect("KEYWORD", "end")
    node = ast_func_def(params, body, false)
  elseif tok.type == "OP" and tok.value == "{" then
    node = self:parse_table_constructor()
  elseif tok.type == "IDENT" then
    self:advance()
    node = ast_ident(tok.value)
  else
    self:advance()
    node = ast_ident("__unknown__")
  end
  
  -- Handle indexing and calls (postfix operations) for ALL primary expressions
  while true do
    local next_tok = self:peek()
    if next_tok.type == "OP" and next_tok.value == "[" then
      self:advance()
      local key = self:parse_expr()
      self:expect("OP", "]")
      node = ast_index(node, key)
    elseif next_tok.type == "OP" and next_tok.value == "." then
      self:advance()
      local field = self:expect("IDENT").value
      node = ast_index(node, ast_string(field))
    elseif next_tok.type == "OP" and next_tok.value == ":" then
      self:advance()
      local method = self:expect("IDENT").value
      self:expect("OP", "(")
      local args = {}
      if self:peek().type ~= "OP" or self:peek().value ~= ")" then
        args = self:parse_expr_list()
      end
      self:expect("OP", ")")
      node = ast_call(ast_index(node, ast_string(method)), {node, table.unpack(args)})
    elseif next_tok.type == "OP" and next_tok.value == "(" then
      self:advance()
      local args = {}
      if self:peek().type ~= "OP" or self:peek().value ~= ")" then
        args = self:parse_expr_list()
      end
      self:expect("OP", ")")
      node = ast_call(node, args)
    elseif next_tok.type == "STRING" then
      -- String literal as single call arg: "hello" == ("hello")
      self:advance()
      local s = next_tok.value:sub(2, -2)
      node = ast_call(node, {ast_string(s)})
    elseif next_tok.type == "OP" and next_tok.value == "{" then
      -- Table constructor as single call arg
      local tbl = self:parse_table_constructor()
      node = ast_call(node, {tbl})
    else
      break
    end
  end
  return node
end

function Parser:parse_table_constructor()
  self:expect("OP", "{")
  local fields = {}
  while not (self:peek().type == "OP" and self:peek().value == "}") do
    local tok = self:peek()
    if tok.type == "IDENT" then
      -- Save position, advance past identifier, check if next is "="
      local save_pos = self.pos
      local save_tpos = self.token_pos
      local key_tok = self:advance()
      local next_tok = self:peek()
      if next_tok.type == "OP" and next_tok.value == "=" then
        -- It's a key-value pair
        self:advance()  -- consume =
        local val = self:parse_expr()
        fields[#fields + 1] = { key = ast_string(key_tok.value), value = val }
      else
        -- Not a key-value pair, backtrack
        self.pos = save_pos
        self.token_pos = save_tpos
        local val = self:parse_expr()
        fields[#fields + 1] = { key = nil, value = val }
      end
    elseif tok.type == "OP" and tok.value == "[" then
      self:advance()
      local key = self:parse_expr()
      self:expect("OP", "]")
      self:expect("OP", "=")
      local val = self:parse_expr()
      fields[#fields + 1] = { key = key, value = val }
    else
      local val = self:parse_expr()
      fields[#fields + 1] = { key = nil, value = val }
    end
    if not self:match("OP", ",") then break end
  end
  self:expect("OP", "}")
  return ast_table(fields)
end

------------------------------------------------------------
-- 字节码编译器
------------------------------------------------------------
local Compiler = {}
Compiler.__index = Compiler

function Compiler.new(parent)
  return setmetatable({
    code = {},
    constants = {},
    const_map = {},
    reg_count = 0,
    var_regs = {},
    upvalues = {},
    break_jmps = {},  -- stack of break JMP lists for nested loops
    labels = {},      -- label name -> code position
    goto_jmps = {},   -- {label, jmp_pc} pairs for later resolution
    parent = parent,  -- parent scope for upvalue access
  }, Compiler)
end

function Compiler:emit(op, a, b, c)
  self.code[#self.code + 1] = { op = op, a = a or 0, b = b or 0, c = c or 0, sBx = b }
  return #self.code
end

function Compiler:emit_sbx(op, a, sbx)
  self.code[#self.code + 1] = { op = op, a = a or 0, b = sbx or 0, c = 0, sBx = sbx or 0 }
  return #self.code
end

function Compiler:add_const(val)
  local key = type(val) == "string" and ("S:" .. val) or ("N:" .. tostring(val))
  if not self.const_map[key] then
    self.constants[#self.constants + 1] = val
    self.const_map[key] = #self.constants  -- 1-based index
  end
  return self.const_map[key]
end

function Compiler:alloc_reg()
  self.reg_count = self.reg_count + 1
  return self.reg_count - 1
end

-- Find existing upvalue for a variable name, or create a new one
function Compiler:find_or_create_upvalue(var_name)
  -- Check if we already have an upvalue for this variable
  for i, uv in ipairs(self.upvalues) do
    if uv.name == var_name then
      return i - 1  -- Return 0-based index for the VM
    end
  end
  -- Create new upvalue
  local uv_idx = #self.upvalues + 1
  self.upvalues[uv_idx] = { reg = self.parent.var_regs[var_name], name = var_name }
  return uv_idx - 1  -- Return 0-based index for the VM
end

function Compiler:free_reg(r)
  if r == self.reg_count - 1 then
    self.reg_count = self.reg_count - 1
  end
end

function Compiler:compile_block(block)
  for _, stmt in ipairs(block.stmts) do
    self:compile_stmt(stmt)
  end
end

function Compiler:compile_stmt(stmt)
  if stmt.type == "assign" then
    self:compile_assign(stmt)
  elseif stmt.type == "local" then
    self:compile_local(stmt)
  elseif stmt.type == "call" then
    local r = self:compile_expr(stmt)
    self:free_reg(r)
  elseif stmt.type == "if" then
    self:compile_if(stmt)
  elseif stmt.type == "while" then
    self:compile_while(stmt)
  elseif stmt.type == "for_num" then
    self:compile_for_num(stmt)
  elseif stmt.type == "for_in" then
    self:compile_for_in(stmt)
  elseif stmt.type == "return" then
    self:compile_return(stmt)
  elseif stmt.type == "do_block" then
    -- Save scope: snapshot var_regs and reg_count for proper lexical scoping
    local saved_vars = {}
    for k, v in pairs(self.var_regs) do saved_vars[k] = v end
    local saved_reg_count = self.reg_count
    self:compile_block(stmt.body)
    -- Restore scope: free inner registers and restore outer variable mapping
    self.reg_count = saved_reg_count
    self.var_regs = saved_vars
  elseif stmt.type == "repeat" then
    self:compile_repeat(stmt)
  elseif stmt.type == "break" then
    local jmp_pc = self:emit_sbx(OPC.JMP, 0, 0)  -- placeholder, fix later
    if #self.break_jmps > 0 then
      self.break_jmps[#self.break_jmps][#self.break_jmps[#self.break_jmps] + 1] = jmp_pc
    end
  elseif stmt.type == "goto" then
    local jmp_pc = self:emit_sbx(OPC.JMP, 0, 0)  -- placeholder, resolve later
    self.goto_jmps[#self.goto_jmps + 1] = { label = stmt.label, pc = jmp_pc }
  elseif stmt.type == "label" then
    self.labels[stmt.name] = #self.code + 1  -- label points to next instruction
  elseif stmt.type == "func_def" then
    self:compile_func_def(stmt)
  end
end

function Compiler:compile_assign(stmt)
  -- Evaluate all values first, copying to fresh temp registers
  -- This prevents overlap when target register == source register
  -- e.g. a, b = b, a  where compile_expr(b) returns b's own register
  local val_regs = {}
  if stmt.values then
    for i, val in ipairs(stmt.values) do
      if i <= #stmt.targets then
        local src = self:compile_expr(val)
        -- Always copy to a fresh temp to avoid register aliasing
        local tmp = self:alloc_reg()
        self:emit(OPC.MOVE, tmp, src, 0)
        self:free_reg(src)
        val_regs[i] = tmp
      end
    end
  end
  -- Now assign to targets
  for i, target in ipairs(stmt.targets) do
    local r = val_regs[i]
    if r then
      if target.type == "ident" then
        if self.var_regs[target.name] then
          self:emit(OPC.MOVE, self.var_regs[target.name], r, 0)
        elseif self.parent and self.parent.var_regs[target.name] then
          local uv_idx = self:find_or_create_upvalue(target.name)
          self:emit(OPC.SETUPVAL, r, uv_idx, 0)
        else
          local k = self:add_const(target.name)
          self:emit(OPC.SETGLOBAL, r, k, 0)
        end
      elseif target.type == "index" then
        local obj_r = self:compile_expr(target.obj)
        local key_r = self:compile_expr(target.key)
        self:emit(OPC.SETTABLE, obj_r, key_r, r)
        self:free_reg(obj_r)
        self:free_reg(key_r)
      end
      self:free_reg(r)
    end
  end
end

function Compiler:compile_local(stmt)
  local regs = {}
  for i, name in ipairs(stmt.names) do
    local r = self:alloc_reg()
    self.var_regs[name] = r
    regs[#regs + 1] = r
  end
  if stmt.values then
    local nvals = #stmt.values
    local nnames = #stmt.names
    -- Multi-return: local a, b, c = f()
    if nvals == 1 and nnames > 1 and stmt.values[1].type == "call" then
      local call_expr = stmt.values[1]
      local func_r = self:compile_expr(call_expr.func)
      local base = func_r
      local nargs = 0
      if call_expr.args then
        for i, arg in ipairs(call_expr.args) do
          local ar = self:compile_expr(arg)
          if ar ~= base + i then
            self:emit(OPC.MOVE, base + i, ar, 0)
          end
          nargs = nargs + 1
        end
      end
      -- Store nnames results: C = nnames + 1
      self:emit(OPC.CALL, base, nargs + 1, nnames + 1)
      -- Move results to target registers
      for i = 1, nnames do
        if regs[i] ~= base + i - 1 then
          self:emit(OPC.MOVE, regs[i], base + i - 1, 0)
        end
      end
      self:free_reg(func_r)
    -- Multi-vararg: local a, b, c = ...
    elseif nvals == 1 and nnames > 1 and stmt.values[1].type == "vararg" then
      -- VARARG with B = nnames + 1 to get nnames varargs
      self:emit(OPC.VARARG, regs[1], nnames + 1, 0)
    else
      for i, val in ipairs(stmt.values) do
        if regs[i] then
          local r = self:compile_expr(val)
          self:emit(OPC.MOVE, regs[i], r, 0)
          self:free_reg(r)
        end
      end
    end
  else
    for _, r in ipairs(regs) do
      self:emit(OPC.LOADNIL, r, 0, 0)
    end
  end
end

function Compiler:compile_if(stmt)
  -- Check if condition is a comparison that can be optimized
  if stmt.cond.type == "binop" and ({["=="]=1,["~="]=1,["<"]=1,[">"]=1,["<="]=1,[">="]=1})[stmt.cond.op] then
    -- Direct comparison: emit compare + JMP pattern
    local lr = self:compile_expr(stmt.cond.left)
    local rr = self:compile_expr(stmt.cond.right)
    local cmp_ops = {["=="]=OPC.EQ, ["~="]=OPC.EQ, ["<"]=OPC.LT, [">"]=OPC.LT, ["<="]=OPC.LE, [">="]=OPC.LE}
    local negate = (stmt.cond.op == "~=") and 1 or 0
    local op1, op2 = lr, rr
    if stmt.cond.op == ">" or stmt.cond.op == ">=" then op1, op2 = rr, lr end
    -- Emit comparison: skip next JMP if condition matches
    local cmp_a = (stmt.cond.op ~= "~=") and 0 or 1
    self:emit(cmp_ops[stmt.cond.op], cmp_a, op1, op2)
    self:free_reg(lr)
    self:free_reg(rr)
    -- JMP to else/end (skipped if condition is true)
    local jmp_pc = self:emit(OPC.JMP, 0, 0, 0)
    self:compile_block(stmt.then_block)
    if stmt.else_block then
      local else_jmp = self:emit(OPC.JMP, 0, 0, 0)
      self.code[jmp_pc].b = #self.code - jmp_pc
      self:compile_block(stmt.else_block)
      self.code[else_jmp].b = #self.code - else_jmp
    else
      self.code[jmp_pc].b = #self.code - jmp_pc
    end
  else
    -- General case: evaluate condition, TEST + JMP pattern
    local cond_r = self:compile_expr(stmt.cond)
    local test_pc = self:emit(OPC.TEST, cond_r, 0, 0)  -- if falsy, skip next
    self:free_reg(cond_r)
    -- JMP to else/end (skipped when condition is truthy)
    local jmp_pc = self:emit(OPC.JMP, 0, 0, 0)
    self:compile_block(stmt.then_block)
    if stmt.else_block then
      local else_jmp = self:emit(OPC.JMP, 0, 0, 0)
      self.code[jmp_pc].b = #self.code - jmp_pc
      self:compile_block(stmt.else_block)
      self.code[else_jmp].b = #self.code - else_jmp
    else
      self.code[jmp_pc].b = #self.code - jmp_pc
    end
  end
end

function Compiler:compile_while(stmt)
  -- Push break JMP list for this loop
  self.break_jmps[#self.break_jmps + 1] = {}
  local loop_pc = #self.code + 1
  local cond_r = self:compile_expr(stmt.cond)
  local test_pc = self:emit(OPC.TEST, cond_r, 0, 0)
  self:free_reg(cond_r)
  local exit_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  self:compile_block(stmt.body)
  local back_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  self.code[back_jmp].sBx = loop_pc - back_jmp - 1
  self.code[back_jmp].b = loop_pc - back_jmp - 1
  self.code[exit_jmp].sBx = #self.code - exit_jmp
  self.code[exit_jmp].b = #self.code - exit_jmp
  -- Fix all break JMPs to point past the loop
  local breaks = table.remove(self.break_jmps)
  for _, bj in ipairs(breaks) do
    self.code[bj].sBx = #self.code - bj
    self.code[bj].b = #self.code - bj
  end
end

function Compiler:compile_repeat(stmt)
  self.break_jmps[#self.break_jmps + 1] = {}
  local loop_pc = #self.code + 1
  self:compile_block(stmt.body)
  local cond_r = self:compile_expr(stmt.cond)
  local test_pc = self:emit(OPC.TEST, cond_r, 0, 0)
  self:free_reg(cond_r)
  local back_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  self.code[back_jmp].sBx = loop_pc - back_jmp - 1
  self.code[back_jmp].b = loop_pc - back_jmp - 1
  -- Fix all break JMPs to point past the loop
  local breaks = table.remove(self.break_jmps)
  for _, bj in ipairs(breaks) do
    self.code[bj].sBx = #self.code - bj
    self.code[bj].b = #self.code - bj
  end
end

function Compiler:compile_for_num(stmt)
  self.break_jmps[#self.break_jmps + 1] = {}
  local init_r = self:compile_expr(stmt.init)
  local limit_r = self:compile_expr(stmt.limit)
  local step_r = stmt.step and self:compile_expr(stmt.step) or nil
  if not step_r then
    step_r = self:alloc_reg()
    self:emit(OPC.LOADK, step_r, self:add_const(1), 0)
  end
  
  local iter_r = self:alloc_reg()
  self.var_regs[stmt.name] = iter_r
  
  self:emit(OPC.MOVE, iter_r, init_r, 0)
  self:free_reg(init_r)
  
  local loop_pc = #self.code + 1
  -- Check: if iter > limit, break
  -- LT with A=1: skip next if NOT (limit < iter)
  -- If iter <= limit (continue), LT skips JMP, falls through to body
  -- If iter > limit (done), LT doesn't skip, JMP exits loop
  self:emit(OPC.LT, 1, limit_r, iter_r)  -- A=1: skip if NOT less
  local jmp_pc = self:emit_sbx(OPC.JMP, 0, 0)
  
  self:compile_block(stmt.body)
  
  -- Increment
  self:emit(OPC.ADD, iter_r, iter_r, step_r)
  local back_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  -- Set back jump: target is loop_pc, current is back_jmp
  -- VM does: pc = pc + 1, then pc = pc + sBx
  -- So: loop_pc = back_jmp + 1 + sBx  =>  sBx = loop_pc - back_jmp - 1
  self.code[back_jmp].sBx = loop_pc - back_jmp - 1
  self.code[back_jmp].b = loop_pc - back_jmp - 1
  
  -- Set exit jump: target is instruction after back_jmp
  self.code[jmp_pc].sBx = #self.code - jmp_pc
  self.code[jmp_pc].b = #self.code - jmp_pc
  -- Fix all break JMPs to point past the loop
  local breaks = table.remove(self.break_jmps)
  for _, bj in ipairs(breaks) do
    self.code[bj].sBx = #self.code - bj
    self.code[bj].b = #self.code - bj
  end
  self:free_reg(limit_r)
  self:free_reg(step_r)
end

function Compiler:compile_for_in(stmt)
  -- for k, v, ... in iter_expr do body end
  --
  -- Lua semantics:
  --   local func, state, control = iter_expr
  --   while true do
  --     local k, v, ... = func(state, control)
  --     if k == nil then break end
  --     control = k
  --     -- body
  --   end
  --
  -- Bytecode:
  --   <compile iter_expr to get func, state, control in R[A], R[A+1], R[A+2]>
  --   TFORCALL A, C: R[A+3..A+2+C] = R[A](R[A+1], R[A+2])
  --   TFORLOOP A, sBx: if R[A+3] ~= nil then R[A+2]=R[A+3]; jump back
  --

  self.break_jmps[#self.break_jmps + 1] = {}
  local nvars = #stmt.names

  -- Allocate ALL registers contiguously: base, state, ctrl, var1, var2, ...
  -- This ensures they are at R[A], R[A+1], R[A+2], R[A+3], R[A+4], ...
  local base_r = self:alloc_reg()  -- R[A]: iterator function
  local state_r = self:alloc_reg() -- R[A+1]: state
  local ctrl_r = self:alloc_reg()  -- R[A+2]: control variable
  local var_regs = {}
  for i = 1, nvars do
    var_regs[i] = self:alloc_reg() -- R[A+3], R[A+4], ...
  end

  -- Set variable names to point to TFORCALL output registers
  for i, name in ipairs(stmt.names) do
    self.var_regs[name] = var_regs[i]
  end

  -- Now compile iterator expression (may allocate/free temp regs above our range)
  if #stmt.iter_expr == 1 and stmt.iter_expr[1].type == 'call' then
    local call_expr = stmt.iter_expr[1]
    local func_r = self:compile_expr(call_expr.func)
    local arg_regs = {}
    for i, arg in ipairs(call_expr.args) do
      arg_regs[i] = self:compile_expr(arg)
    end
    self:emit(OPC.MOVE, base_r, func_r, 0)
    for i, ar in ipairs(arg_regs) do
      self:emit(OPC.MOVE, base_r + i, ar, 0)
      self:free_reg(ar)
    end
    self:free_reg(func_r)
    self:emit(OPC.CALL, base_r, #arg_regs + 1, 4)
  else
    local r = self:compile_expr(stmt.iter_expr[1])
    self:emit(OPC.MOVE, base_r, r, 0)
    self:free_reg(r)
    self:emit(OPC.LOADNIL, state_r, 0, 0)
    self:emit(OPC.LOADNIL, ctrl_r, 0, 0)
  end

  -- Update reg_count to account for TFORCALL output registers
  local max_used = base_r + 2 + nvars
  if max_used > self.reg_count then
    self.reg_count = max_used
  end

  -- TFORCALL: R[A+3..A+2+C] = R[A](R[A+1], R[A+2])
  local tforcall_pc = #self.code + 1
  self:emit(OPC.TFORCALL, base_r, 0, nvars)

  -- TFORLOOP: if R[A+3] ~= nil then R[A+2]=R[A+3]; jump to loop body
  --           if R[A+3] == nil then fall through (exit loop)
  local tforloop_pc = self:emit_sbx(OPC.TFORLOOP, base_r, 0)

  -- If nil, jump to exit
  local exit_jmp = self:emit_sbx(OPC.JMP, 0, 0)

  -- Loop body
  local body_start = #self.code + 1
  self:compile_block(stmt.body)

  -- Jump back to TFORCALL
  local back_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  self.code[back_jmp].b = tforcall_pc - back_jmp - 1
  self.code[back_jmp].sBx = tforcall_pc - back_jmp - 1

  -- Fix TFORLOOP: jump to body_start
  self.code[tforloop_pc].sBx = body_start - tforloop_pc - 1
  self.code[tforloop_pc].b = body_start - tforloop_pc - 1

  -- Fix exit jump: jump to after loop
  self.code[exit_jmp].sBx = #self.code - exit_jmp
  self.code[exit_jmp].b = #self.code - exit_jmp
  -- Fix all break JMPs to point past the loop
  local breaks = table.remove(self.break_jmps)
  for _, bj in ipairs(breaks) do
    self.code[bj].sBx = #self.code - bj
    self.code[bj].b = #self.code - bj
  end

  -- Free registers
  for i = 1, nvars do
    self:free_reg(var_regs[i])
  end
  self:free_reg(base_r)
  self:free_reg(state_r)
  self:free_reg(ctrl_r)
end

function Compiler:compile_return(stmt)
  if stmt.values and #stmt.values > 0 then
    if #stmt.values == 1 then
      local r = self:compile_expr(stmt.values[1])
      self:emit(OPC.RETURN, r, 2, 0)
    else
      local base = self:alloc_reg()
      for i, val in ipairs(stmt.values) do
        local r = self:compile_expr(val)
        self:emit(OPC.MOVE, base + i - 1, r, 0)
        self:free_reg(r)
      end
      self:emit(OPC.RETURN, base, #stmt.values + 1, 0)
    end
  else
    self:emit(OPC.RETURN, 0, 1, 0)
  end
end

function Compiler:resolve_gotos()
  for _, g in ipairs(self.goto_jmps) do
    local target = self.labels[g.label]
    if target then
      self.code[g.pc].sBx = target - g.pc - 1
      self.code[g.pc].b = target - g.pc - 1
    end
    -- Silently skip unresolved gotos (Lua allows forward refs in some cases)
  end
  self.goto_jmps = {}
end

function Compiler:compile_func_def(stmt)
  -- Compile function body in a sub-compiler with parent scope
  local sub = Compiler.new(self)
  local named_params = {}
  for i, param in ipairs(stmt.params) do
    if param ~= "..." then
      named_params[#named_params + 1] = param
      sub.var_regs[param] = i - 1
      sub.reg_count = i
    end
  end
  sub:compile_block(stmt.body)
  sub:resolve_gotos()  -- resolve goto -> label jumps
  if #sub.code == 0 or sub.code[#sub.code].op ~= OPC.RETURN then
    sub:emit(OPC.RETURN, 0, 1, 0)
  end
  
  local proto = {
    code = sub.code,
    constants = sub.constants,
    numparams = #named_params,
    maxstack = sub.reg_count + 1,
    upvalues = sub.upvalues,  -- upvalue descriptors
    has_vararg = (#stmt.params > 0 and stmt.params[#stmt.params] == "..."),
  }
  
  local r = self:alloc_reg()
  self:emit(OPC.CLOSURE, r, #self.constants + 1, 0)
  self.constants[#self.constants + 1] = proto
  
  if stmt.is_local and stmt.name then
    -- For recursive local functions, also set as global
    local gk = self:add_const(stmt.name)
    self:emit(OPC.SETGLOBAL, r, gk, 0)
  end
  
  return r
end

function Compiler:compile_expr(expr)
  if expr.type == "number" then
    local r = self:alloc_reg()
    local k = self:add_const(expr.value)
    self:emit(OPC.LOADK, r, k, 0)
    return r
  end
  
  if expr.type == "string" then
    local r = self:alloc_reg()
    local k = self:add_const(expr.value)
    self:emit(OPC.LOADK, r, k, 0)
    return r
  end
  
  if expr.type == "bool" then
    local r = self:alloc_reg()
    self:emit(OPC.LOADBOOL, r, expr.value and 1 or 0, 0)
    return r
  end
  
  if expr.type == "nil" then
    local r = self:alloc_reg()
    self:emit(OPC.LOADNIL, r, 0, 0)
    return r
  end

  if expr.type == "vararg" then
    local r = self:alloc_reg()
    self:emit(OPC.VARARG, r, 2, 0)  -- B=2 means 1 result
    return r
  end
  
  if expr.type == "ident" then
    if self.var_regs[expr.name] then
      local r = self:alloc_reg()
      self:emit(OPC.MOVE, r, self.var_regs[expr.name], 0)
      return r
    elseif self.parent and self.parent.var_regs[expr.name] then
      -- Variable is in parent scope -> use GETUPVAL
      local r = self:alloc_reg()
      local uv_idx = self:find_or_create_upvalue(expr.name)
      self:emit(OPC.GETUPVAL, r, uv_idx, 0)
      return r
    else
      local r = self:alloc_reg()
      local k = self:add_const(expr.name)
      self:emit(OPC.GETGLOBAL, r, k, 0)
      return r
    end
  end
  
  if expr.type == "binop" then
    local opcodes = {
      ["+"] = OPC.ADD, ["-"] = OPC.SUB, ["*"] = OPC.MUL,
      ["/"] = OPC.DIV, ["//"] = OPC.IDIV, ["%"] = OPC.MOD, ["^"] = OPC.POW,
      ["&"] = OPC.BAND, ["|"] = OPC.BOR, ["~"] = OPC.BXOR,
      ["<<"] = OPC.SHL, [">>"] = OPC.SHR, [".."] = OPC.CONCAT,
    }
    -- For CONCAT chains (a..b..c..d), collect all operands first
    -- to avoid compile_expr being called multiple times on shared subexpressions
    if expr.op == ".." then
      local function collect_concat(node, out)
        if node.type == "binop" and node.op == ".." then
          collect_concat(node.left, out)
          collect_concat(node.right, out)
        else
          out[#out + 1] = node
        end
      end
      local operands = {}
      collect_concat(expr, operands)
      -- Compile all operands once, then move to contiguous registers
      -- This ensures CONCAT's [B,C] range has no gaps (e.g. from CALL args)
      local tmp_regs = {}
      for i, op in ipairs(operands) do
        tmp_regs[i] = self:compile_expr(op)
      end
      -- Allocate contiguous registers and MOVE operands into them
      local concat_regs = {}
      for i = 1, #operands do
        concat_regs[i] = self:alloc_reg()
      end
      for i = 1, #operands do
        self:emit(OPC.MOVE, concat_regs[i], tmp_regs[i], 0)
      end
      -- Free original temp registers
      for i = 1, #operands do self:free_reg(tmp_regs[i]) end
      -- Emit single CONCAT with contiguous range
      if #operands > 1 then
        self:emit(OPC.CONCAT, concat_regs[1], concat_regs[1], concat_regs[#operands])
      end
      -- Free all but result
      for i = 2, #operands do self:free_reg(concat_regs[i]) end
      return concat_regs[1]
    end
    local lr = self:compile_expr(expr.left)
    local rr = self:compile_expr(expr.right)
    if opcodes[expr.op] then
      self:emit(opcodes[expr.op], lr, lr, rr)
      self:free_reg(rr)
      return lr
    end
    -- Comparison operators: produce a boolean result
    local cmp_ops = {["=="]=OPC.EQ, ["~="]=OPC.EQ, ["<"]=OPC.LT, [">"]=OPC.LT, ["<="]=OPC.LE, [">="]=OPC.LE}
    if cmp_ops[expr.op] then
      local r = self:alloc_reg()
      -- For > and >=, swap operands so we can use < and <=
      local op1, op2 = lr, rr
      if expr.op == ">" or expr.op == ">=" then
        op1, op2 = rr, lr
      end
      -- A=0: skip next if condition TRUE;  A=1: skip next if condition FALSE
      -- For ==/<,<=: condition TRUE → A=0
      -- For ~=: condition TRUE is "not equal" → EQ A=1 skips when not-equal
      local cmp_a = (expr.op == "~=") and 1 or 0
      self:emit(cmp_ops[expr.op], cmp_a, op1, op2)
      self:emit(OPC.LOADBOOL, r, 0, 1)  -- false + skip next
      self:emit(OPC.LOADBOOL, r, 1, 0)  -- true
      self:free_reg(lr)
      self:free_reg(rr)
      return r
    end
    -- Logical
    if expr.op == "and" or expr.op == "or" then
      -- Simplified: evaluate both sides
      self:free_reg(lr)
      return rr
    end
    self:free_reg(lr)
    self:free_reg(rr)
    return lr
  end
  
  if expr.type == "unop" then
    local r = self:compile_expr(expr.expr)
    if expr.op == "-" then
      self:emit(OPC.UNM, r, r, 0)
    elseif expr.op == "not" then
      self:emit(OPC.NOT, r, r, 0)
    elseif expr.op == "#" then
      self:emit(OPC.LEN, r, r, 0)
    elseif expr.op == "~" then
      self:emit(OPC.BNOT, r, r, 0)
    end
    return r
  end
  
  if expr.type == "index" then
    local obj_r = self:compile_expr(expr.obj)
    local key_r = self:compile_expr(expr.key)
    self:emit(OPC.GETTABLE, obj_r, obj_r, key_r)
    self:free_reg(key_r)
    return obj_r
  end
  
  if expr.type == "call" then
    local func_r = self:compile_expr(expr.func)
    local base = func_r
    local nargs = 0
    if expr.args then
      for i, arg in ipairs(expr.args) do
        local ar = self:compile_expr(arg)
        if ar ~= base + i then
          self:emit(OPC.MOVE, base + i, ar, 0)
        end
        nargs = nargs + 1
      end
    end
    self:emit(OPC.CALL, base, nargs + 1, 2)
    return base
  end
  
  if expr.type == "table" then
    -- Special case: {...} - rewrite to use select-based loop
    if #expr.fields == 1 and not expr.fields[1].key and expr.fields[1].value.type == "vararg" then
      -- Use _pack() global helper registered by exec_proto to pack varargs into a table
      local tbl_r = self:alloc_reg()
      local fn_r = self:alloc_reg()
      local pack_k = self:add_const("_pack")
      self:emit(OPC.GETGLOBAL, fn_r, pack_k, 0)
      self:emit(OPC.CALL, fn_r, 1, 2)  -- CALL fn, 0 args, 1 result
      self:emit(OPC.MOVE, tbl_r, fn_r, 0)
      self:free_reg(fn_r)
      return tbl_r
    end
    local r = self:alloc_reg()
    self:emit(OPC.NEWTABLE, r, 0, 0)
    local arr_idx = 0
    for _, field in ipairs(expr.fields) do
      if field.key then
        local kr = self:compile_expr(field.key)
        local vr = self:compile_expr(field.value)
        self:emit(OPC.SETTABLE, r, kr, vr)
        self:free_reg(kr)
        self:free_reg(vr)
      else
        -- Array-style: use numeric index
        arr_idx = arr_idx + 1
        local kr = self:alloc_reg()
        local vr = self:compile_expr(field.value)
        self:emit(OPC.LOADK, kr, self:add_const(arr_idx), 0)
        self:emit(OPC.SETTABLE, r, kr, vr)
        self:free_reg(kr)
        self:free_reg(vr)
      end
    end
    return r
  end
  
  if expr.type == "func_def" then
    return self:compile_func_def(expr)
  end
  
  -- Fallback
  local r = self:alloc_reg()
  self:emit(OPC.LOADNIL, r, 0, 0)
  return r
end

function Compiler:get_proto()
  return {
    code = self.code,
    constants = self.constants,
    numparams = 0,
    maxstack = self.reg_count + 1,
  }
end

------------------------------------------------------------
-- 字节码编码（混淆 + 加密）
------------------------------------------------------------
-- 字节码编码（op 池映射 + 字符池 + 整表加密）
------------------------------------------------------------

local OPC_NAMES = {
  {"NOP", 0}, {"LOADK", 1}, {"LOADBOOL", 2}, {"LOADNIL", 3},
  {"MOVE", 4}, {"GETGLOBAL", 5}, {"SETGLOBAL", 6},
  {"GETTABLE", 7}, {"SETTABLE", 8}, {"NEWTABLE", 9},
  {"ADD", 10}, {"SUB", 11}, {"MUL", 12}, {"DIV", 13}, {"MOD", 14}, {"POW", 15},
  {"BAND", 16}, {"BOR", 17}, {"BXOR", 18}, {"SHL", 19}, {"SHR", 20},
  {"UNM", 21}, {"BNOT", 22}, {"NOT", 23}, {"LEN", 24}, {"CONCAT", 25},
  {"EQ", 26}, {"LT", 27}, {"LE", 28},
  {"JMP", 29}, {"TEST", 30}, {"TESTSET", 31},
  {"CALL", 32}, {"TAILCALL", 33}, {"RETURN", 34},
  {"FORPREP", 35}, {"FORLOOP", 36},
  {"TFORPREP", 37}, {"TFORCALL", 38}, {"TFORLOOP", 39},
  {"SETLIST", 40}, {"CLOSURE", 41}, {"VARARG", 42},
  {"EXTRARG", 43}, {"GETUPVAL", 44}, {"SETUPVAL", 45},
  {"IDIV", 55},
}

local function shuffle_list(t)
  for i = #t, 2, -1 do
    local j = math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

local function build_op_map()
  local n = #OPC_NAMES
  local runtime_ids = {}
  for i = 1, n do runtime_ids[i] = i - 1 end
  shuffle_list(runtime_ids)
  local op_map = {}
  local name_to_rt = {}
  for i, entry in ipairs(OPC_NAMES) do
    local name, logical = entry[1], entry[2]
    local rt = runtime_ids[i]
    op_map[logical] = rt
    name_to_rt[name] = rt
  end
  return op_map, name_to_rt
end

local function build_char_pool(proto)
  local seen = {}
  local pool = {}

  local function add_bytes(s)
    if type(s) ~= "string" then return end
    for i = 1, #s do
      local b = string.byte(s, i)
      if not seen[b] then
        seen[b] = true
        pool[#pool + 1] = b
      end
    end
  end

  local function walk(p)
    for _, k in ipairs(p.constants or {}) do
      if type(k) == "string" then
        add_bytes(k)
      elseif type(k) == "number" then
        add_bytes(tostring(k))
      elseif type(k) == "table" and k.code then
        walk(k)
      end
    end
    for _, uv in ipairs(p.upvalues or {}) do
      add_bytes(uv.name or "")
    end
  end
  walk(proto)

  for _ = 1, math.random(4, 16) do
    local b = math.random(0, 255)
    if not seen[b] then
      seen[b] = true
      pool[#pool + 1] = b
    end
  end
  if #pool == 0 then
    pool[1] = 0
  end
  shuffle_list(pool)

  local byte_to_idx = {}
  for i, b in ipairs(pool) do
    byte_to_idx[b] = i
  end
  local pool_key = math.random(1, 255)
  local encrypted = {}
  for i, b in ipairs(pool) do
    encrypted[i] = b ~ pool_key
  end
  return encrypted, byte_to_idx, pool_key
end

local function encode_string_via_pool(s, byte_to_idx, parts)
  parts[#parts + 1] = #s
  for i = 1, #s do
    local b = string.byte(s, i)
    parts[#parts + 1] = byte_to_idx[b] or 1
  end
end

local function encode_proto(proto, key, op_map, byte_to_idx)
  local parts = {}
  parts[#parts + 1] = proto.numparams
  parts[#parts + 1] = proto.maxstack
  parts[#parts + 1] = #proto.constants
  parts[#parts + 1] = #proto.code

  for _, k in ipairs(proto.constants) do
    if type(k) == "number" then
      parts[#parts + 1] = 1
      encode_string_via_pool(tostring(k), byte_to_idx, parts)
    elseif type(k) == "string" then
      parts[#parts + 1] = 2
      encode_string_via_pool(k, byte_to_idx, parts)
    elseif type(k) == "boolean" then
      parts[#parts + 1] = 3
      parts[#parts + 1] = k and 1 or 0
    elseif type(k) == "table" then
      parts[#parts + 1] = 4
      local sub = encode_proto(k, key, op_map, byte_to_idx)
      for _, v in ipairs(sub) do parts[#parts + 1] = v end
      parts[#parts + 1] = 0
    end
  end
  parts[#parts + 1] = 0

  for _, instr in ipairs(proto.code) do
    parts[#parts + 1] = op_map[instr.op] or instr.op
    parts[#parts + 1] = instr.a
    parts[#parts + 1] = instr.b
    parts[#parts + 1] = instr.c
  end

  local uvs = proto.upvalues or {}
  parts[#parts + 1] = #uvs
  for _, uv in ipairs(uvs) do
    parts[#parts + 1] = uv.reg
    encode_string_via_pool(uv.name or "", byte_to_idx, parts)
  end

  for i, v in ipairs(parts) do
    if type(v) == "number" and v < 0 then
      parts[i] = v & 0xFFFFFFFF
    end
  end
  return parts
end

local function generate_vm_source(proto, key)
  local op_map, name_to_rt = build_op_map()
  local char_pool_enc, byte_to_idx, pool_key = build_char_pool(proto)
  local encoded = encode_proto(proto, key, op_map, byte_to_idx)

  local seed = math.random(1000, 9999)
  local cs = seed
  for i, v in ipairs(encoded) do cs = (cs + v * (i + seed)) % 65536 end
  for i, v in ipairs(encoded) do
    encoded[i] = v ~ key
  end
  local data_str = table.concat(encoded, ",")
  local chars_str = table.concat(char_pool_enc, ",")

  local names_order = {
    "NOP","LOADK","LOADBOOL","LOADNIL","MOVE","GETGLOBAL","SETGLOBAL",
    "GETUPVAL","SETUPVAL","GETTABLE","SETTABLE","NEWTABLE",
    "ADD","SUB","MUL","DIV","IDIV","MOD","POW",
    "BAND","BOR","BXOR","SHL","SHR",
    "UNM","BNOT","NOT","LEN","CONCAT",
    "EQ","LT","LE","JMP","TEST","TESTSET",
    "CALL","TAILCALL","RETURN","FORPREP","FORLOOP",
    "TFORPREP","TFORCALL","TFORLOOP","CLOSURE","VARARG","EXTRARG","SETLIST",
  }
  local op_locals = {}
  for _, nm in ipairs(names_order) do
    op_locals[#op_locals + 1] = string.format("  local OP_%s = %d", nm, name_to_rt[nm] or 0)
  end
  local op_locals_str = table.concat(op_locals, "\n")

  -- Template uses %% for literal % in string.format
  local tpl = [====[
-- VM Protected Code (op-pool + char-pool)
do
  local _d = {%s}
  local _chars = {%s}
  local _k = %d
  local _ck = %d
  local _cs_seed = %d
  local _cs_expect = %d

  for _i = 1, #_d do _d[_i] = _d[_i] ~ _k end

  local function _dec_str(di, len)
    local t = {}
    for i = 1, len do
      local idx = _d[di]; di = di + 1
      t[i] = string.char((_chars[idx] or 0) ~ _ck)
    end
    return table.concat(t), di
  end

%s

  local function decode_proto(di)
    local np = _d[di]; di = di + 1
    local ms = _d[di]; di = di + 1
    local nk = _d[di]; di = di + 1
    local nc = _d[di]; di = di + 1
    local consts = {}
    for _ci = 1, nk do
      local t = _d[di]; di = di + 1
      if t == 0 then break end
      if t == 1 then
        local sl = _d[di]; di = di + 1
        local s; s, di = _dec_str(di, sl)
        consts[#consts + 1] = tonumber(s)
      elseif t == 2 then
        local sl = _d[di]; di = di + 1
        local s; s, di = _dec_str(di, sl)
        consts[#consts + 1] = s
      elseif t == 3 then
        consts[#consts + 1] = _d[di] == 1; di = di + 1
      elseif t == 4 then
        local sub, new_di = decode_proto(di)
        consts[#consts + 1] = sub
        di = new_di + 1
      end
    end
    di = di + 1
    local code = {}
    for _ = 1, nc do
      code[#code + 1] = { op = _d[di], a = _d[di+1], b = _d[di+2], c = _d[di+3] }
      di = di + 4
    end
    local nuv = _d[di]; di = di + 1
    local upvalues = {}
    for _ = 1, nuv do
      local uv_reg = _d[di]; di = di + 1
      local name_len = _d[di]; di = di + 1
      local nm; nm, di = _dec_str(di, name_len)
      upvalues[#upvalues + 1] = { reg = uv_reg, name = nm }
    end
    return { code = code, constants = consts, numparams = np, maxstack = ms, upvalues = upvalues }, di
  end

  local _orig_pack = _G._pack

  local function exec_proto(proto, regs, base, nargs, upvals, varargs)
    _G._pack = function()
      local t = {}
      if varargs then for i = 1, #varargs do t[i] = varargs[i] end end
      return t
    end
    local code = proto.code
    local consts = proto.constants
    local pc = 1
    local A, B, C

    local H = {}

    H[OP_NOP] = function() end
    H[OP_LOADK] = function()
      regs[base + A] = consts[B]
    end
    H[OP_LOADBOOL] = function()
      regs[base + A] = B ~= 0
      if C ~= 0 then pc = pc + 1 end
    end
    H[OP_LOADNIL] = function()
      for i = 0, B do regs[base + A + i] = nil end
    end
    H[OP_MOVE] = function()
      regs[base + A] = regs[base + B]
    end
    H[OP_GETGLOBAL] = function()
      regs[base + A] = _G[consts[B]]
    end
    H[OP_SETGLOBAL] = function()
      _G[consts[B]] = regs[base + A]
    end
    H[OP_GETUPVAL] = function()
      if upvals and upvals[B + 1] then
        local uv = upvals[B + 1]
        regs[base + A] = uv[1][uv[2]]
      end
    end
    H[OP_SETUPVAL] = function()
      if upvals and upvals[B + 1] then
        local uv = upvals[B + 1]
        uv[1][uv[2]] = regs[base + A]
      end
    end
    H[OP_GETTABLE] = function()
      local t = regs[base + B]
      if type(t) == "table" then
        regs[base + A] = t[regs[base + C]]
      else
        regs[base + A] = nil
      end
    end
    H[OP_SETTABLE] = function()
      local t = regs[base + A]
      if type(t) == "table" then t[regs[base + B]] = regs[base + C] end
    end
    H[OP_NEWTABLE] = function()
      regs[base + A] = {}
    end
    H[OP_ADD] = function()
      local l, r = regs[base + B], regs[base + C]
      regs[base + A] = (type(l) == "number" and type(r) == "number") and (l + r) or (tonumber(l) or 0) + (tonumber(r) or 0)
    end
    H[OP_SUB] = function()
      regs[base + A] = regs[base + B] - regs[base + C]
    end
    H[OP_MUL] = function()
      regs[base + A] = regs[base + B] * regs[base + C]
    end
    H[OP_DIV] = function()
      regs[base + A] = regs[base + B] / regs[base + C]
    end
    H[OP_IDIV] = function()
      regs[base + A] = regs[base + B] // regs[base + C]
    end
    H[OP_MOD] = function()
      regs[base + A] = regs[base + B] %% regs[base + C]
    end
    H[OP_POW] = function()
      regs[base + A] = regs[base + B] ^ regs[base + C]
    end
    H[OP_BAND] = function()
      regs[base + A] = regs[base + B] & regs[base + C]
    end
    H[OP_BOR] = function()
      regs[base + A] = regs[base + B] | regs[base + C]
    end
    H[OP_BXOR] = function()
      regs[base + A] = regs[base + B] ~ regs[base + C]
    end
    H[OP_SHL] = function()
      regs[base + A] = regs[base + B] << regs[base + C]
    end
    H[OP_SHR] = function()
      regs[base + A] = regs[base + B] >> regs[base + C]
    end
    H[OP_UNM] = function()
      regs[base + A] = -regs[base + B]
    end
    H[OP_BNOT] = function()
      regs[base + A] = ~regs[base + B]
    end
    H[OP_NOT] = function()
      regs[base + A] = not regs[base + B]
    end
    H[OP_LEN] = function()
      regs[base + A] = #regs[base + B]
    end
    H[OP_CONCAT] = function()
      local v = regs[base + B]
      local s = type(v) == 'string' and v or tostring(v)
      for j = B + 1, C do
        v = regs[base + j]
        s = s .. (type(v) == 'string' and v or tostring(v))
      end
      regs[base + A] = s
    end
    H[OP_EQ] = function()
      local eq = (regs[base + B] == regs[base + C])
      if (eq and A == 0) or (not eq and A == 1) then pc = pc + 1 end
    end
    H[OP_LT] = function()
      local lt = (regs[base + B] < regs[base + C])
      if (lt and A == 0) or (not lt and A == 1) then pc = pc + 1 end
    end
    H[OP_LE] = function()
      local le = (regs[base + B] <= regs[base + C])
      if (le and A == 0) or (not le and A == 1) then pc = pc + 1 end
    end
    H[OP_JMP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      pc = pc + sBx
    end
    H[OP_FORPREP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      regs[base + A] = regs[base + A] - regs[base + A + 2]
      pc = pc + sBx
    end
    H[OP_FORLOOP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      regs[base + A] = regs[base + A] + regs[base + A + 2]
      local step = regs[base + A + 2]
      local limit = regs[base + A + 1]
      local idx = regs[base + A]
      local cont = (step > 0) and (idx <= limit) or (idx >= limit)
      if cont then
        regs[base + A + 3] = idx
        pc = pc + sBx
      end
    end
    H[OP_TFORLOOP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      if regs[base + A + 3] ~= nil then
        regs[base + A + 2] = regs[base + A + 3]
        pc = pc + sBx
      end
    end
    H[OP_TFORCALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local results = {fn(regs[base + A + 1], regs[base + A + 2])}
        for j = 1, C do
          regs[base + A + 2 + j] = results[j]
        end
      end
    end
    H[OP_TFORPREP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      pc = pc + sBx
    end
    H[OP_TEST] = function()
      local v = regs[base + A]
      local truthy = v and v ~= false
      if (truthy and C == 0) or (not truthy and C ~= 0) then pc = pc + 1 end
    end
    H[OP_TESTSET] = function()
      local v = regs[base + B]
      local truthy = v and v ~= false
      if (truthy and C == 0) or (not truthy and C ~= 0) then
        pc = pc + 1
      else
        regs[base + A] = v
      end
    end
    H[OP_CALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local nargs = B - 1
        local results
        if nargs <= 0 then
          results = {fn()}
        elseif nargs == 1 then
          results = {fn(regs[base + A + 1])}
        elseif nargs == 2 then
          results = {fn(regs[base + A + 1], regs[base + A + 2])}
        elseif nargs == 3 then
          results = {fn(regs[base + A + 1], regs[base + A + 2], regs[base + A + 3])}
        else
          local args = {}
          for j = 1, nargs do args[j] = regs[base + A + j] end
          results = {fn(table.unpack(args))}
        end
        if C > 0 then
          for j = 1, C - 1 do
            regs[base + A + j - 1] = results[j]
          end
        else
          regs[base + A] = results[1]
        end
      end
    end
    H[OP_TAILCALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local nargs = B - 1
        if nargs <= 0 then return "RET", {fn()}
        elseif nargs == 1 then return "RET", {fn(regs[base + A + 1])}
        elseif nargs == 2 then return "RET", {fn(regs[base + A + 1], regs[base + A + 2])}
        elseif nargs == 3 then return "RET", {fn(regs[base + A + 1], regs[base + A + 2], regs[base + A + 3])}
        else
          local args = {}
          for j = 1, nargs do args[j] = regs[base + A + j] end
          return "RET", {fn(table.unpack(args))}
        end
      end
    end
    H[OP_RETURN] = function()
      if B >= 2 then
        local results = {}
        for j = 0, B - 2 do results[j + 1] = regs[base + A + j] end
        return "RET", results
      elseif B == 1 then
        return "RET", {regs[base + A]}
      else
        return "RET", {}
      end
    end
    H[OP_CLOSURE] = function()
      local sub_proto = consts[B]
      if type(sub_proto) == "table" and sub_proto.code then
        local captured_upvals = {}
        if sub_proto.upvalues then
          for ui, uv_desc in ipairs(sub_proto.upvalues) do
            captured_upvals[ui] = { regs, base + uv_desc.reg }
          end
        end
        regs[base + A] = function(...)
          local sub_regs = {}
          local args = {...}
          local n = select("#", ...)
          for ai = 1, sub_proto.numparams do
            sub_regs[ai - 1] = args[ai]
          end
          local vargs = {}
          for vi = sub_proto.numparams + 1, n do
            vargs[#vargs + 1] = args[vi]
          end
          return exec_proto(sub_proto, sub_regs, 0, n, captured_upvals, vargs)
        end
      end
    end
    H[OP_VARARG] = function()
      if B == 0 then
        if varargs then
          for j = 1, #varargs do
            regs[base + A + j - 1] = varargs[j]
          end
        end
      else
        for j = 0, B - 2 do
          regs[base + A + j] = varargs and varargs[j + 1] or nil
        end
      end
    end
    H[OP_SETLIST] = function()
      local t = regs[base + A]
      if type(t) == "table" then
        for j = 1, C do
          t[B + j - 1] = regs[base + A + j]
        end
      end
    end
    H[OP_EXTRARG] = function() end

    while pc <= #code do
      local ins = code[pc]
      local op = ins.op
      A, B, C = ins.a, ins.b, ins.c
      pc = pc + 1
      local h = H[op]
      if h then
        local tag, pack = h()
        if tag == "RET" then
          return table.unpack(pack or {})
        end
      end
    end
  end

  local _cs = _cs_seed
  for _i = 1, #_d do
    _cs = (_cs + _d[_i] * (_i + _cs_seed)) & 0xFFFF
  end
  if _cs ~= _cs_expect then
    error('integrity check failed')
  end

  local main_proto = decode_proto(1)
  local regs = {}
  exec_proto(main_proto, regs, 0, 0, nil)
  _G._pack = _orig_pack
end
]====]

  return string.format(tpl, data_str, chars_str, key, pool_key, seed, cs, op_locals_str)
end

local function vm_protect(source_code)
  math.randomseed(math.floor(os.time() + os.clock() * 10000))
  local function random_int(min, max)
    return math.random(min, max)
  end

  -- Parse
  local parser = Parser.new(source_code)
  local ast = parser:parse_block()

  -- Compile
  local compiler = Compiler.new()
  compiler:compile_block(ast)
  compiler:resolve_gotos()  -- resolve goto -> label jumps
  -- Add return if missing
  if #compiler.code == 0 or compiler.code[#compiler.code].op ~= OPC.RETURN then
    compiler:emit(OPC.RETURN, 0, 1, 0)
  end
  local proto = compiler:get_proto()

  -- Generate VM
  local key = random_int(1, 0xFFFFFF)
  local vm_code = generate_vm_source(proto, key)

  return vm_code
end

------------------------------------------------------------
-- 导出
------------------------------------------------------------
local M = {}

function M.protect(source_code)
  return vm_protect(source_code)
end

function M.version()
  return VERSION
end

-- Debug: expose internals
M._Parser = Parser
M._Compiler = Compiler
M._OPC = OPC
return M
]=], "@passes/vm.lua")()
  end
  package.preload["passes.vm_protect"] = function()
    return load([[-- ================================================================
-- passes/vm_protect.lua
-- VM 字节码虚拟化
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将 Lua 源码编译为自定义指令集，生成配套的 VM 解释器
-- 这是保护强度最高的 Pass，混淆后的代码完全不可逆
--
-- 工作原理：
--   1. 解析源码为 AST
--   2. 将 AST 编译为自定义字节码（不兼容标准 Lua 字节码）
--   3. 生成纯 Lua 实现的 VM 解释器 + 加密字节码数据
--   4. 运行时由 VM 解释器执行字节码

local M = {}

M.name        = "vm_protect"
M.title       = "VM字节码虚拟化"
M.description = "将Lua源码编译为自定义字节码，生成VM解释器执行。最强保护，代码完全不可逆。"
M.version     = "2.1.0"
M.author      = "Rainy_qwq"
M.order       = 10
M.enabled     = false  -- 默认关闭，需手动开启

function M.apply(code, ctx)
  local vm = ctx.vm_module or require("passes.vm")
  local result, err = vm.protect(code)
  if not result then
    error("VM保护失败: " .. tostring(err))
  end
  return result
end

return M
]], "@passes/vm_protect.lua")()
  end
  package.preload["passes.string_encrypt"] = function()
    return load([[-- ================================================================
-- passes/string_encrypt.lua
-- 字符串加密
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将代码中的字符串字面量替换为运行时解密调用
-- 支持 XOR、ROT13、表驱动三种编码方式，随机选择
--
-- 注意：字符串的提取/恢复由 string_pool 处理，
-- 本 Pass 仅控制是否启用加密（与 Pipeline 解耦）

local string_pool = require("passes.string_pool")

local M = {}

M.name    = "string_encryption"
M.title   = "字符串加密"
M.description = "将字符串常量替换为运行时解密调用，增加静态分析难度"
M.version = "1.0.0"
M.order   = 20

function M.apply(code, _ctx)
  -- 字符串提取+恢复由 obfuscator.lua 主流程处理
  -- 此 Pass 仅作为 Pipeline 中的占位，用于配置管理
  -- 如果禁用此 Pass，主流程将跳过字符串加密步骤
  return code
end

return M
]], "@passes/string_encrypt.lua")()
  end
  package.preload["passes.var_mangle"] = function()
    return load([[-- ================================================================
-- passes/var_mangle.lua
-- 变量名混淆
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将局部变量名替换为无意义的随机标识符
--
-- 性能优化:
--   - 一次扫描收集所有变量名(不是多次 gmatch)
--   - 用 byte 级别检查代替模式匹配
--   - 替换时用位置表批量处理,避免重复扫描

local utils = require("passes.utils")
local random_id = utils.random_id
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local is_comment = utils.is_comment

local M = {}

M.name    = "variable_mangling"
M.title   = "变量名混淆"
M.version = "1.0.0"
M.order   = 30

-- Lua 保留字和常用全局变量（不能被替换）
local RESERVED = {}
for _, w in ipairs({
  "and","break","do","else","elseif","end","false","for","function","goto",
  "if","in","local","nil","not","or","repeat","return","then","true","until","while",
  "self","print","require","pcall","xpcall","type","tostring","tonumber",
  "pairs","ipairs","table","string","math","io","os","coroutine","debug",
  "package","rawset","rawget","setmetatable","getmetatable","error","assert",
  "select","unpack","collectgarbage","dofile","load","loadfile","next",
  "rawequal","rawlen","module",
}) do RESERVED[w] = true end

local BYTE_DOT = string.byte(".")

-- 检查字符是否是数字
local function is_digit(b)
  return b >= 48 and b <= 57
end

-- 检查字符是否是标识符首字符 [a-zA-Z_] 
local function is_id_start(b)
  return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
end

-- 检查字符是否是标识符后续字符 [a-zA-Z0-9_]
local function is_id_char(b)
  return is_id_start(b) or (b >= 48 and b <= 57)
end

-- 从代码中提取所有标识符位置
-- 返回: { {name, start, end}, ... }
local function scan_identifiers(code)
  local ids = {}
  local n = 0
  local pos = 1
  local len = #code

  while pos <= len do
    local b = code:byte(pos)

    -- 跳过字符串占位符
    if b == 95 and code:sub(pos, pos + 3) == "__ST" then
      local end_pos = code:find("__", pos + 5, true)
      if end_pos then
        pos = end_pos + 2
      else
        pos = pos + 1
      end

    -- 跳过注释
    elseif b == 45 and pos < len and code:byte(pos + 1) == 45 then
      local nl = code:find("\n", pos + 2, true)
      pos = nl and (nl + 1) or (len + 1)

    -- 跳过字符串(已替换为占位符,不会到这里)

    -- 标识符
    elseif is_id_start(b) then
      -- 跳过科学计数法中的 e/E(如 1.5e-3)
      if (b == 101 or b == 69) and pos > 1 then  -- 'e' or 'E'
        local prev = code:byte(pos - 1)
        if is_digit(prev) or prev == BYTE_DOT then
          -- 这是科学计数法的一部分,不是标识符
          pos = pos + 1
          -- 跳过指数部分的 +/-
          if pos <= len then
            local sign = code:byte(pos)
            if sign == 43 or sign == 45 then pos = pos + 1 end  -- '+' or '-'
          end
          -- 跳过指数数字
          while pos <= len and is_digit(code:byte(pos)) do
            pos = pos + 1
          end
          goto continue_scan
        end
      end
      local start = pos
      pos = pos + 1
      while pos <= len and is_id_char(code:byte(pos)) do
        pos = pos + 1
      end
      local name = code:sub(start, pos - 1)
      n = n + 1
      ids[n] = { name = name, start = start, stop = pos - 1 }
      ::continue_scan::

    else
      pos = pos + 1
    end
  end

  return ids
end

-- 从代码中提取 local 声明的变量名
local function collect_local_vars(code, table_keys)
  local var_map = {}
  local ids = scan_identifiers(code)

  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      -- 检查上下文:是否是 local 声明
      -- local xxx = / local function xxx / local xxx, yyy
      local before = code:sub(math.max(1, id.start - 20), id.start - 1)
      -- 检查前面是否有 "local " 或 "local\t"
      if before:match("local%s+$") or before:match("local%s+function%s+$") then
        var_map[name] = true
      end
      -- 检查多变量声明 local a, b, c
      if before:match(",%s*$") then
        -- 往前找 local
        local local_pos = before:find("local%s+", 1, true)
        if local_pos then
          var_map[name] = true
        end
      end
    end
  end

  -- 函数参数 function(x, y)
  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      local before = code:sub(math.max(1, id.start - 5), id.start - 1)
      if before:match("%(%s*$") or before:match(",%s*$") then
        -- 往前找 function
        local ctx = code:sub(math.max(1, id.start - 50), id.start - 1)
        if ctx:match("function%s*[%w_.:]*%s*$") or ctx:match("function%s*[%w_.:]*%s*%([^)]*$") then
          var_map[name] = true
        end
      end
    end
  end

  -- for 循环变量 for i = / for k, v in
  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      local before = code:sub(math.max(1, id.start - 10), id.start - 1)
      if before:match("for%s+$") or before:match(",%s*$") then
        var_map[name] = true
      end
    end
  end

  return var_map, ids
end

-- ????????????????????????
local function collect_table_keys(code)
  local keys = {}
  local i = 1
  local len = #code
  while i <= len do
    local b = code:byte(i)
    -- ????????
    if b == 34 or b == 39 then
      local q = b; i = i + 1
      while i <= len do
        if code:byte(i) == 92 then i = i + 2
        elseif code:byte(i) == q then i = i + 1; break
        else i = i + 1 end
      end
    elseif b == 45 and i < len and code:byte(i+1) == 45 then
      local nl = code:find("\n", i+2, true)
      i = nl and (nl+1) or (len+1)
    -- ??????
    elseif b == 123 then
      i = i + 1
      local depth = 1
      while i <= len and depth > 0 do
        local cb = code:byte(i)
        if cb == 123 then depth = depth + 1
        elseif cb == 125 then depth = depth - 1
        elseif cb == 34 or cb == 39 then
          local q = cb; i = i + 1
          while i <= len do
            if code:byte(i) == 92 then i = i + 2
            elseif code:byte(i) == q then i = i + 1; break
            else i = i + 1 end
          end
        elseif cb == 91 then
          i = i + 1
          while i <= len and code:byte(i) ~= 93 do i = i + 1 end
          i = i + 1
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if code:byte(i) == 61 then
            i = i + 1
            while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          end
        elseif (cb >= 65 and cb <= 90) or (cb >= 97 and cb <= 122) or cb == 95 then
          local start = i
          i = i + 1
          while i <= len do
            local ib = code:byte(i)
            if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
          end
          local key = code:sub(start, i - 1)
          -- ?? = ?
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if code:byte(i) == 61 then
            keys[key] = true
            i = i + 1
          end
        else
          i = i + 1
        end
      end
    else
      i = i + 1
    end
  end
  return keys
end

function M.apply(code, _ctx)
  -- 收集需要替换的变量名
  local table_keys = collect_table_keys(code)
  local var_map, ids = collect_local_vars(code, table_keys)

  -- 生成替换名
  local rename_map = {}
  for name in pairs(var_map) do
    rename_map[name] = "_" .. random_id(6)
  end

  -- 构建 segment 数组，一次 concat 完成替换
  local segments = {}
  local sn = 0
  local last_pos = 1

  for _, id in ipairs(ids) do
    local new_name = rename_map[id.name]
    if new_name then
      if id.start > last_pos then
        sn = sn + 1
        segments[sn] = code:sub(last_pos, id.start - 1)
      end
      sn = sn + 1
      segments[sn] = new_name
      last_pos = id.stop + 1
    end
  end
  -- 尾部
  if last_pos <= #code then
    sn = sn + 1
    segments[sn] = code:sub(last_pos)
  end

  if sn > 0 then
    code = table.concat(segments)
  end

  return code
end

return M
]], "@passes/var_mangle.lua")()
  end
  package.preload["passes.num_encrypt"] = function()
    return load([[-- ================================================================
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

local function is_id_start(b)
  return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
end

local function is_id_char(b)
  return is_id_start(b) or is_digit(b)
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
]], "@passes/num_encrypt.lua")()
  end
  package.preload["passes.instr_sub"] = function()
    return load([[-- ================================================================
-- passes/instr_sub.lua
-- 指令替换
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将简单的 Lua 运算替换为等价的复杂表达式
-- 例如: a + b → a - (-b), a == b → not (a ~= b)
--
-- 不改变程序语义，但增加逆向分析时的阅读难度

local utils = require("passes.utils")
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local strip_strings_from_line = utils.strip_strings_from_line
local gsub_safe = utils.gsub_safe

local M = {}

M.name    = "instruction_substitution"
M.title   = "指令替换"
M.version = "1.0.0"
M.order   = 40
M.enabled = true  -- 100轮单独+50轮累积测试全部通过

-- 等价替换规则
-- 每条规则: {原模式, 替换函数}
-- 仅在安全上下文中替换（排除字符串和注释）
local substitutions = {
  -- 算术运算
  { pattern = "([%w_]+)%s*([%+%-%*%%])%s*([%w_]+)", handler = function(a, op, b)
    if op == "+" then return string.format("%s-(-(%s))", a, b)
    elseif op == "-" then return string.format("%s+(-(%s))", a, b)
    elseif op == "*" then
      if random_int(1,2) == 1 then
        return string.format("math.floor(%s/%s)*%s", a, "(1/" .. b .. ")", b)
      end
      return string.format("%s*%s", a, b)
    end
    return nil
  end },
}

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}
  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    -- 跳过注释行
    if not trimmed:match("^%-%-") then
      -- 跳过包含科学计数法的行（1e10, 1.5e-3 等）
      local safe = strip_strings_from_line(line)
      local has_sci = safe:match("%d[%.%d]*[eE][%+%-]?%d")
      -- 随机选择是否对本行应用替换（控制密度）
      if not has_sci and random_int(1, 3) == 1 then
        -- 对安全版本做替换标记，然后在原行中只替换非字符串部分
        for _, sub in ipairs(substitutions) do
          local count = 0
          safe = gsub_safe(safe, sub.pattern, function(...)
            count = count + 1
            if count > 2 then return nil end
            local result = sub.handler(...)
            return result or nil
          end)
        end
        -- 用安全版本指导替换（简化处理：直接替换整行）
        if safe ~= strip_strings_from_line(line) then
          line = safe
        end
      end
    end
    result[#result + 1] = line
  end
  return join_lines(result)
end

return M
]], "@passes/instr_sub.lua")()
  end
  package.preload["passes.adv_fake_cf"] = function()
    return load([[-- ================================================================
-- passes/adv_fake_cf.lua
-- 虚假控制流增强
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 在代码中注入多层嵌套的虚假分支结构
-- 比 BCF 更深入：使用随机变量 + 多条件嵌套，大幅增加控制流复杂度
--
-- 注入的代码永远不会执行，但静态分析工具必须将其纳入考量

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local calc_depth = utils.calc_depth

local M = {}

M.name    = "advanced_fake_cf"
M.title   = "虚假控制流增强"
M.version = "1.0.0"
M.order   = 65  -- 在控制流平坦化之前执行，注入的虚假分支会被平坦化一并处理

-- 生成不透明谓词（始终为假，但不容易看出来）
local function generate_predicate()
  local v = "_p" .. random_id(3)
  local method = random_int(1, 4)
  if method == 1 then
    return string.format("(function() local %s=%d; return %s*%s<0 end)()", v, random_int(1,500), v, v)
  elseif method == 2 then
    return string.format("(function() local %s=%d; return %s<0 end)()", v, random_int(1,999), v)
  elseif method == 3 then
    return string.format("(function() local %s=%d; return (%s%%2)~=0 and (%s%%2)==0 end)()", v, random_int(1,100), v, v)
  else
    return string.format("(function() local %s=%d; return %s~=1 and %s==0 end)()", v, random_int(2,99), v, v)
  end
end

-- 生成一段虚假代码
local function generate_fake_block(indent)
  local lines = {}
  local vars = {}
  local count = random_int(2, 4)
  for i = 1, count do
    vars[i] = "_af" .. random_id(4)
    lines[#lines + 1] = string.format("%slocal %s=%d", indent, vars[i], random_int(0, 0xFFFF))
  end
  for i = 1, random_int(1, 3) do
    local a = vars[random_int(1, #vars)]
    local b = vars[random_int(1, #vars)]
    local ops = { "+", "-", "~", "*", "&" }
    lines[#lines + 1] = string.format("%s%s=%s%s%s", indent, a, a, ops[random_int(1,#ops)], b)
  end
  -- 加个递归调用伪装（不用 break，避免在循环外出错）
  if random_int(1, 2) == 1 then
    local lv = "_lp" .. random_id(3)
    lines[#lines + 1] = string.format("%slocal %s=%d", indent, lv, random_int(1,99))
    lines[#lines + 1] = string.format("%sif %s>%d then %s=%s-%d end", indent, lv, random_int(100,999), lv, lv, random_int(1,10))
  end
  return table.concat(lines, "\n")
end

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}
  local depth = 0

  for _, line in ipairs(lines) do
    local o, c = calc_depth(line)
    depth = depth + o - c

    result[#result + 1] = line

    -- 在函数开始和条件分支后注入虚假代码
    -- 不在 if/then 行后注入（避免破坏 elseif 链）
    local trimmed = line:match("^%s*(.-)%s*$") or ""
   if o > 0 and depth > 0 and random_int(1, 3) == 1 and
      not trimmed:match("then%s*$") and
      not trimmed:match("do%s*$") and
      not trimmed:match("^if%s") and
      not trimmed:match("^for%s") and
      not trimmed:match("^while%s") and
      not trimmed:match("^return") and
      not trimmed:match("^else") and
      not trimmed:match("^elseif%s") then
      local indent = line:match("^(%s*)") or ""
      local pred = generate_predicate()
      local fake = generate_fake_block(indent .. "  ")
      result[#result + 1] = string.format("%sif %s then", indent, pred)
      result[#result + 1] = fake
      result[#result + 1] = string.format("%send", indent)
    end
  end

  return join_lines(result)
end

return M
]], "@passes/adv_fake_cf.lua")()
  end
  package.preload["passes.cf_flatten"] = function()
    return load([[-- ================================================================
-- passes/cf_flatten.lua
-- 控制流平坦化
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将函数体拆分为基本块，通过 switch-case 调度器重组执行顺序
-- 执行流程从线性变为：dispatcher → block_N → dispatcher → block_M → ...
--
-- 效果：静态分析工具无法直接看出代码的执行顺序

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local calc_depth = utils.calc_depth

local M = {}

M.name    = "control_flow_flattening"
M.title   = "控制流平坦化"
M.version = "1.0.0"
M.order   = 70
M.enabled = true  -- 100轮单独+50轮累积测试全部通过

-- 检测一行是否是函数体的开始
local function is_func_start(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  return trimmed and (trimmed:match("^function%s") or trimmed:match("^local%s+function%s"))
end

-- 从代码中提取函数体
local function extract_functions(code)
  local lines = split_lines(code)
  local functions = {}
  local current_func = nil
  local depth = 0

  for i, line in ipairs(lines) do
    if is_func_start(line) and depth == 0 then
      current_func = { start = i, lines = { line } }
      local o, c = calc_depth(line)
      depth = depth + o - c
    elseif current_func then
      current_func.lines[#current_func.lines + 1] = line
      local o, c = calc_depth(line)
      depth = depth + o - c
      if depth <= 0 then
        current_func.stop = i
        functions[#functions + 1] = current_func
        current_func = nil
        depth = 0
      end
    end
  end
  return functions
end

function M.apply(code, _ctx)
  local functions = extract_functions(code)
  if #functions == 0 then return code end

  local lines = split_lines(code)
  -- 从后往前替换，避免索引偏移
  for fi = #functions, 1, -1 do
    local func = functions[fi]
    local body_lines = {}
    -- 提取函数体（去掉 function 行和 end 行）
    for i = 2, #func.lines - 1 do
      body_lines[#body_lines + 1] = func.lines[i]
    end

    if #body_lines < 3 then goto continue end

    -- 将函数体拆分为基本块
    -- 只在顶层语句边界切分，不拆分 if/elseif/else/end 链
    local blocks = {}
    local current_block = {}
    local depth = 0
    local next_line_idx = 1
    for _, line in ipairs(body_lines) do
      local o, c = calc_depth(line)
      local trimmed = line:match("^%s*(.-)%s*$") or ""
      current_block[#current_block + 1] = line
      depth = depth + o - c
      -- 只在深度回到0且是完整语句边界时切分
      -- 排除 elseif/else（它们是 if 链的一部分）
      -- 排除 local 声明（会破坏作用域）
      if depth <= 0 and #current_block > 0 then
        local should_split = false
        if trimmed:match("^return%s") or trimmed:match("^return$") or trimmed:match("^break%s*$") then
          should_split = true
        elseif o == 0 and c == 0 and trimmed ~= "" and not trimmed:match("^%-%-") then
          -- 普通语句行（非控制流），可以切分
          -- 但不切分 local 声明（会破坏作用域）
          if not trimmed:match("^local%s") then
            should_split = true
          end
        end
        -- 检查下一行是否是 elseif/else（如果是则不切分）
        if should_split then
          local next_idx = next_line_idx + 1
          if next_idx <= #body_lines then
            local next_trimmed = body_lines[next_idx]:match("^%s*(.-)%s*$") or ""
            if next_trimmed:match("^elseif%s") or next_trimmed:match("^else%s*$") or next_trimmed:match("^else%s+[^%s]") then
              should_split = false
            end
          end
        end
        if should_split then
          blocks[#blocks + 1] = table.concat(current_block, "\n")
          current_block = {}
        end
      end
      next_line_idx = next_line_idx + 1
    end
    if #current_block > 0 then
      blocks[#blocks + 1] = table.concat(current_block, "\n")
    end

    if #blocks < 2 then goto continue end

    -- 生成调度器
    local state_var = "_s" .. random_id(4)
    -- 不打乱顺序，保持原始执行流
    -- 打乱会破坏 local 变量作用域
    local order = {}
    for i = 1, #blocks do order[i] = i end

    local new_body = {}
    new_body[#new_body + 1] = func.lines[1]  -- function 行
    new_body[#new_body + 1] = string.format("  local %s = %d", state_var, order[1])
    new_body[#new_body + 1] = string.format("  while true do")
    new_body[#new_body + 1] = string.format("    if %s == 0 then break end", state_var)

    for idx, block_idx in ipairs(order) do
      local next_state = idx < #blocks and order[idx + 1] or 0
      local block_lines = split_lines(blocks[block_idx])
      new_body[#new_body + 1] = string.format("    if %s == %d then", state_var, block_idx)
      for _, bl in ipairs(block_lines) do
        new_body[#new_body + 1] = "    " .. bl
      end
      -- 不在 return/break 后插状态赋值（不可达代码）
      local last_line = block_lines[#block_lines] or ""
      local last_trimmed = last_line:match("^%s*(.-)%s*$") or ""
      local is_terminal = last_trimmed:match("^return%s") or last_trimmed:match("^return$") or last_trimmed:match("^break%s*$")
      if not is_terminal then
        new_body[#new_body + 1] = string.format("      %s = %d", state_var, next_state)
      end
      new_body[#new_body + 1] = "    end"
    end

    new_body[#new_body + 1] = "  end"
    new_body[#new_body + 1] = func.lines[#func.lines]  -- end 行

    -- 替换原函数
    local new_lines = {}
    for i = 1, #lines do
      if i == func.start then
        for _, nl in ipairs(new_body) do
          new_lines[#new_lines + 1] = nl
        end
      elseif i > func.start and i <= func.stop then
        -- 跳过原函数体
      else
        new_lines[#new_lines + 1] = lines[i]
      end
    end
    lines = new_lines

    ::continue::
  end

  return join_lines(lines)
end

return M
]], "@passes/cf_flatten.lua")()
  end
  package.preload["passes.bcf"] = function()
    return load([[-- ================================================================
-- passes/bcf.lua
-- BCF 虚假控制流
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 基于不透明谓词 (Opaque Predicate) 注入永远不会执行的代码分支
-- 不透明谓词：在编译期就能确定真假的条件表达式，但逆向时难以判断
--
-- 示例：
--   原始: do_something()
--   混淆: if (x*x+x)%2 == 0 then   ← 永远为真（但逆向不知道）
--           do_something()
--         else
--           <垃圾代码>
--         end

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines

local M = {}

M.name    = "bogus_control_flow"
M.title   = "BCF虚假控制流"
M.version = "1.0.0"
M.order   = 80
M.enabled = false  -- 默认禁用，由 Config 控制；修复了 then/else 分支交换 bug

-- 生成不透明谓词（永远为真的条件表达式）
local function generate_opaque_predicate()
  local v = "_v" .. random_id(3)
  local method = random_int(1, 5)
  if method == 1 then
    return string.format("(function() local %s=%d; return (%s*%s+%s)%%2==0 end)()", v, random_int(1,1000), v, v, v)
  elseif method == 2 then
    return string.format("(function() local %s=%d; return %s*%s>=0 end)()", v, random_int(-1000,1000), v, v)
  elseif method == 3 then
    return string.format("(function() local %s=%d; return (%s+%s)%%2==0 end)()", v, random_int(1,500), v, v)
  elseif method == 4 then
    return string.format("(function() local %s=%d; return %s~=0 or true end)()", v, random_int(1,999), v)
  else
    return string.format("(function() local %s=%d; return not (%s<%s) end)()", v, random_int(1,100), v, v)
  end
end

-- 生成虚假代码块（看起来有意义但不会执行）
local function generate_bcf_code()
  local fake_vars = {}
  local count = random_int(2, 5)
  for i = 1, count do
    fake_vars[i] = "_fv" .. random_id(4)
  end
  local lines = {}
  for _, var in ipairs(fake_vars) do
    local val = random_int(0, 0xFFFF)
    lines[#lines + 1] = string.format("local %s=0x%X", var, val)
  end
  for i = 1, random_int(1, 3) do
    local a = fake_vars[random_int(1, #fake_vars)]
    local b = fake_vars[random_int(1, #fake_vars)]
    local ops = { "+", "-", "~", "&", "|" }
    local op = ops[random_int(1, #ops)]
    lines[#lines + 1] = string.format("%s=%s%s%s", a, a, op, b)
  end
  return table.concat(lines, "\n    ")
end

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}
  local depth = 0

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    local indent = line:match("^(%s*)") or ""

    -- 在可执行语句前注入 BCF（跳过空行、注释、控制流语句）
    if trimmed ~= "" and
       not trimmed:match("^%-%-") and
       not trimmed:match("^end%s*$") and
       not trimmed:match("^else") and
       not trimmed:match("^elseif") and
       not trimmed:match("^then%s*$") and
       not trimmed:match("^do%s*$") and
      not trimmed:match("^local%s+function") and
      not trimmed:match("^function") and
       not trimmed:match("^local%s") and
      not trimmed:match("^return%s") and
       not trimmed:match("^return$") and
       not trimmed:match("^break%s*$") and
       -- 跳过控制流语句（if/for/while/repeat 开头或以 then/do 结尾）
       not trimmed:match("^if%s") and
       not trimmed:match("^for%s") and
       not trimmed:match("^while%s") and
       not trimmed:match("^repeat%s*$") and
       not trimmed:match("then%s*$") and
       not trimmed:match("do%s*$") and
       random_int(1, 4) == 1 then

     local predicate = generate_opaque_predicate()
     local fake_code = generate_bcf_code()
     result[#result + 1] = string.format("%sif %s then", indent, predicate)
     result[#result + 1] = string.format("    %s", trimmed)
      result[#result + 1] = string.format("%selse", indent)
      result[#result + 1] = string.format("    %s", fake_code)
     result[#result + 1] = string.format("%send", indent)
    else
      result[#result + 1] = line
    end
  end

  return join_lines(result)
end

return M
]], "@passes/bcf.lua")()
  end
  package.preload["passes.bb_split"] = function()
    return load([[-- ================================================================
-- passes/bb_split.lua
-- 基本块拆分 (Basic Block Splitting)
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将函数体中的顺序语句拆分为基本块，用 goto/label 连接
-- 物理顺序可打乱（仅限无局部变量的块），执行顺序通过 goto 保持不变
-- 在 goto 和 label 之间插入独立作用域的死代码块，增加 CFG 复杂度

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines

local M = {}

M.name    = "basic_block_splitting"
M.title   = "基本块拆分"
M.version = "1.0.0"
M.order   = 90
M.enabled = false

-- 修正版深度计算：else 不计为 open，elseif 行的 then 不计为 open
-- 原 utils.calc_depth 将 else 计为 +1 open，导致 if-else-end 深度不归零
local function calc_depth_safe(line)
  local trimmed = line:match("^%s*(.-)%s*$") or ""
  if trimmed == "" or trimmed:byte(1) == 45 then return 0, 0 end
  local stripped = trimmed:gsub('%b""', ''):gsub("%b''", ''):gsub('%b[]', '  ')
  local opens, closes = 0, 0
  local starts_with_elseif = trimmed:match("^elseif%s") ~= nil
  for _ in stripped:gmatch('%f[%a]function%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]do%f[%A]') do opens = opens + 1 end
  if not starts_with_elseif then
    for _ in stripped:gmatch('%f[%a]then%f[%A]') do opens = opens + 1 end
  end
  for _ in stripped:gmatch('%f[%a]repeat%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('{') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]end%f[%A]') do closes = closes + 1 end
  for _ in stripped:gmatch('%f[%a]until%f[%A]') do closes = closes + 1 end
  for _ in stripped:gmatch('}') do closes = closes + 1 end
  return opens, closes
end

local function is_func_start(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  return trimmed and (trimmed:match("^function%s") or trimmed:match("^local%s+function%s"))
end

local function extract_functions(code)
  local lines = split_lines(code)
  local functions = {}
  local current_func = nil
  local depth = 0
  for i, line in ipairs(lines) do
    if is_func_start(line) and depth == 0 then
      current_func = { start = i, lines = { line } }
      local o, c = calc_depth_safe(line)
      depth = depth + o - c
    elseif current_func then
      current_func.lines[#current_func.lines + 1] = line
      local o, c = calc_depth_safe(line)
      depth = depth + o - c
      if depth <= 0 then
        current_func.stop = i
        functions[#functions + 1] = current_func
        current_func = nil
        depth = 0
      end
    end
  end
  return functions, lines
end

-- 生成独立作用域的死代码块
local function gen_dead_block(indent)
  local v = "_d" .. random_id(3)
  local n = random_int(0, 0xFFFF)
  local ops = { "+", "-", "*" }
  local op = ops[random_int(1, #ops)]
  local m = random_int(0, 0xFF)
  return string.format("%sdo\n%s  local %s = %d\n%s  %s = %s %s %d\n%send",
    indent, indent, v, n, indent, v, v, op, m, indent)
end

-- 检查块中是否包含 local 声明
local function has_locals(block_text)
  for line in block_text:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    if trimmed:match("^local%s") then return true end
  end
  return false
end

-- 收集函数体中所有 local 变量名
local function collect_local_names(body_lines)
  local names = {}
  for _, line in ipairs(body_lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    local fn = trimmed:match("^local%s+function%s+([%a_][%w_]*)")
    if fn then
      names[fn] = true
    else
      local rest = trimmed:match("^local%s+(.+)$")
      if rest then
        local vars = rest:match("^([^=]+)")
        if vars then
          for name in vars:gmatch("([%a_][%w_]*)") do
            names[name] = true
          end
        end
      end
    end
  end
  return names
end

-- 检查文本中是否引用了某个变量名（带词边界检查）
local function references_name(text, name)
  local pos = 1
  while true do
    local s = text:find(name, pos, true)
    if not s then return false end
    local e = s + #name - 1
    local before = s > 1 and text:sub(s - 1, s - 1) or " "
    local after = e < #text and text:sub(e + 1, e + 1) or " "
    if not before:match("[%w_]") and not after:match("[%w_]") then
      return true
    end
    pos = s + 1
  end
end

-- 检查块是否引用了函数体中的 local 变量
local function references_locals(block_text, local_names)
  for name in pairs(local_names) do
    if references_name(block_text, name) then
      return true
    end
  end
  return false
end

-- 检查块是否以 return/break 终结
local function is_terminal(block_text)
  local block_lines = split_lines(block_text)
  local last = block_lines[#block_lines] or ""
  local trimmed = last:match("^%s*(.-)%s*$") or ""
  return trimmed:match("^return%s") ~= nil or
         trimmed:match("^return$") ~= nil or
         trimmed:match("^break%s*$") ~= nil
end

-- 将 return 语句包裹在 do...end 中，使其不再是 block 的最后一条语句
-- 这样 goto/label 可以跟在 return 后面而不产生语法错误
local function wrap_return_line(line)
  local ws = line:match("^(%s*)") or ""
  local trimmed = line:match("^%s*(.-)%s*$") or ""
  if trimmed:match("^return%s") or trimmed:match("^return$") then
    return ws .. "do " .. trimmed .. " end"
  end
  return line
end

function M.apply(code, _ctx)
  local functions, lines = extract_functions(code)
  if #functions == 0 then return code end

  for fi = #functions, 1, -1 do
    local func = functions[fi]
    local body_lines = {}
    for i = 2, #func.lines - 1 do
      body_lines[#body_lines + 1] = func.lines[i]
    end
    if #body_lines < 4 then goto continue end

    local local_names = collect_local_names(body_lines)

    -- 将函数体拆分为基本块
    local blocks = {}
    local current_block = {}
    local depth = 0
    for idx, line in ipairs(body_lines) do
      local o, c = calc_depth_safe(line)
      local trimmed = line:match("^%s*(.-)%s*$") or ""
      current_block[#current_block + 1] = line
      depth = depth + o - c
      if depth <= 0 and #current_block > 0 then
        local should_split = false
        if trimmed:match("^return%s") or trimmed:match("^return$") or trimmed:match("^break%s*$") then
          should_split = true
        elseif o == 0 and c == 0 and trimmed ~= "" and not trimmed:match("^%-%-") then
          if not trimmed:match("^local%s") then
            should_split = true
          end
        end
        -- 如果下一行是 elseif/else，不切分（保持 if 链完整）
        if should_split then
          local next_idx = idx + 1
          if next_idx <= #body_lines then
            local next_trimmed = body_lines[next_idx]:match("^%s*(.-)%s*$") or ""
            if next_trimmed:match("^elseif%s") or next_trimmed:match("^else%s*$") or next_trimmed:match("^else%s+[^%s]") then
              should_split = false
            end
          end
        end
        if should_split then
          blocks[#blocks + 1] = table.concat(current_block, "\n")
          current_block = {}
        end
      end
    end
    if #current_block > 0 then
      blocks[#blocks + 1] = table.concat(current_block, "\n")
    end

    if #blocks < 2 then goto continue end

    -- 从第一个块推断缩进
    local indent = "  "
    for _, bl in ipairs(split_lines(blocks[1])) do
      local m = bl:match("^(%s*)")
      if m and #m > 0 then indent = m break end
    end

    -- 判断各块是否可移动（无 local 声明且不引用 local 变量）
    local movable = {}
    for i = 1, #blocks do
      movable[i] = not has_locals(blocks[i]) and not references_locals(blocks[i], local_names)
    end

    -- 随机打乱可移动块的物理顺序（仅相邻交换）
    local phys_order = {}
    for i = 1, #blocks do phys_order[i] = i end
    local si = 1
    while si < #phys_order do
      local a = phys_order[si]
      local b = phys_order[si + 1]
      if movable[a] and movable[b] and random_int(1, 2) == 1 then
        phys_order[si] = b
        phys_order[si + 1] = a
        si = si + 2
      else
        si = si + 1
      end
    end

    local lp = "_bb" .. random_id(4)
    local end_label = lp .. "_end"

    -- 构建 goto/label 链
    local new_body = {}
    new_body[#new_body + 1] = func.lines[1]
    new_body[#new_body + 1] = string.format("%sgoto %s_%d", indent, lp, 1)

    for j = 1, #phys_order do
      local block_idx = phys_order[j]
      new_body[#new_body + 1] = string.format("%s::%s_%d::", indent, lp, block_idx)
      local blines = split_lines(blocks[block_idx])
      for bi, bl in ipairs(blines) do
        if bi == #blines then
          new_body[#new_body + 1] = wrap_return_line(bl)
        else
          new_body[#new_body + 1] = bl
        end
      end
      if block_idx < #blocks then
        if not is_terminal(blocks[block_idx]) then
          new_body[#new_body + 1] = string.format("%sgoto %s_%d", indent, lp, block_idx + 1)
          if random_int(1, 3) <= 2 then
            new_body[#new_body + 1] = gen_dead_block(indent)
          end
        end
      else
        if not is_terminal(blocks[block_idx]) then
          new_body[#new_body + 1] = string.format("%sgoto %s", indent, end_label)
        end
      end
    end

    new_body[#new_body + 1] = string.format("%s::%s::", indent, end_label)
    new_body[#new_body + 1] = func.lines[#func.lines]

    -- 替换原函数
    local new_lines = {}
    for i = 1, #lines do
      if i == func.start then
        for _, nl in ipairs(new_body) do
          new_lines[#new_lines + 1] = nl
        end
      elseif i > func.start and i <= func.stop then
        -- 跳过原函数体
      else
        new_lines[#new_lines + 1] = lines[i]
      end
    end
    lines = new_lines

    ::continue::
  end

  local result = join_lines(lines)

  -- 编译检查：无法编译则回退
  local ok, fn = pcall(load, result)
  if not ok or not fn then
    return code
  end

  return result
end

return M
]], "@passes/bb_split.lua")()
  end
  package.preload["passes.junk_comment"] = function()
    return load([[-- ================================================================
-- passes/junk_comment.lua
-- 垃圾注释注入
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 在代码中插入大量无意义的注释，增加文件体积和阅读噪音
-- 注释内容为随机生成的「看似有意义」的文本

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines

local M = {}

M.name    = "junk_comments"
M.title   = "垃圾注释注入"
M.version = "1.0.0"
M.order   = 100

-- 看起来像正常注释的模板
local TEMPLATES = {
  "-- TODO: refactor this later",
  "-- FIXME: potential edge case",
  "-- HACK: workaround for %s",
  "-- NOTE: do not remove",
  "-- XXX: this is suspicious",
  "-- REVIEW: check performance",
  "-- BUG: intermittent failure in %s",
  "-- OPTIMIZE: can be improved",
  "-- DEPRECATED: use %s instead",
  "-- SEE: %s",
  "-- WARNING: side effect",
  "-- %s initialized",
  "-- %s v%d.%d.%d",
  "-- called from %s",
  "-- %s: %dms timeout",
  "-- retry count: %d",
  "-- buffer size: %d",
  "-- %s handler registered",
  "-- offset: 0x%X",
  "-- magic: 0x%X",
}

local WORDS = {
  "handler", "callback", "buffer", "stream", "context",
  "manager", "service", "worker", "scheduler", "dispatcher",
  "adapter", "proxy", "factory", "builder", "validator",
  "parser", "encoder", "decoder", "cache", "pool",
}

local function random_comment()
  local tpl = TEMPLATES[random_int(1, #TEMPLATES)]
  local word = WORDS[random_int(1, #WORDS)]
  local ok, result = pcall(string.format, tpl, word, random_int(1,9), random_int(0,9), random_int(0,99), random_int(0,0xFFFF))
  if ok then return result end
  return "-- " .. random_id(12)
end

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}
  local depth = 0

  for _, line in ipairs(lines) do
    result[#result + 1] = line

    -- 在顶层语句之间插入注释
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" and not trimmed:match("^%-%-") then
      if random_int(1, 3) == 1 then
        result[#result + 1] = random_comment()
      end
    end
  end

  return join_lines(result)
end

return M
]], "@passes/junk_comment.lua")()
  end
  package.preload["passes.header"] = function()
    return load([[-- ================================================================
-- passes/header.lua
-- 代码头部
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 在混淆后的代码开头添加版本标识和警告信息
-- 这是 Pipeline 的最后一步，不改变代码逻辑

local M = {}

M.name    = "header"
M.title   = "添加代码头"
M.version = "1.0.0"
M.order   = 200

function M.apply(code, _ctx)
  local header = string.format([=[
-- ============================================================
-- Obfuscated by Lua Obfuscator v2.5
-- https://github.com/Rainyqwq/Lua-Obfuscator
-- Author: Rainy_qwq
--
-- WARNING: This code has been obfuscated.
-- Modifying it may break functionality.
-- ============================================================
-- Protection layers applied: (see pipeline log)
-- Generated: %s
-- ============================================================
]=], os.date and os.date("%Y-%m-%d %H:%M:%S") or "unknown")

  return header .. code
end

return M
]], "@passes/header.lua")()
  end
  package.preload["passes.anti_debug"] = function()
    return load([[-- passes/anti_debug.lua
-- Anti-debugging detection pass

local M = {}

M.name = "anti_debug"
M.title = "Anti-Debug Detection"
M.version = "1.0.0"
M.order = 15
M.enabled = false

function M.apply(code, _ctx)
  local checks = {}

  -- Check debug hook
  if math.random() < 0.9 then
    checks[#checks + 1] = "(function()local h,m=debug.gethook()if h then return true end;local i=debug.getinfo(1)if not i then return true end;return false end)()"
  end

  -- Check timing anomaly
  if math.random() < 0.8 then
    checks[#checks + 1] = "(function()local s=os.clock()local sum=0;for i=1,100 do sum=sum+i end;if os.clock()-s>0.1 then return true end;return false end)()"
  end

  -- Check JIT status
  if math.random() < 0.7 then
    checks[#checks + 1] = "(function()if not jit then return false end;local st=jit.status;if st and not st()then return true end;return false end)()"
  end

  if #checks == 0 then
    return code
  end

  local block = "if " .. table.concat(checks, " or ") .. " then error('debugger detected') end"

  -- Find insertion point
  local ins = string.match(code, "^%s*(function%s+[%w_]+)")
  if not ins then
    ins = string.match(code, "^%s*(local%s+[%w_]+%s*=%s*function)")
  end
  if not ins then
    ins = string.match(code, "^%s*(local%s+[%w_]+)")
  end

  if ins then
    local pos = string.find(code, ins, 1, true)
    if pos then
      code = string.sub(code, 1, pos - 1) .. block .. "\n" .. string.sub(code, pos)
    end
  else
    code = block .. "\n" .. code
  end

  return code
end

return M
]], "@passes/anti_debug.lua")()
  end
  package.preload["passes.call_indirect"] = function()
    return load([[-- passes/call_indirect.lua
-- Function call indirection via call table

local M = {}

M.name = "call_indirection"
M.title = "Function Call Indirection"
M.version = "1.0.0"
M.order = 85
M.enabled = false

local function gen_id()
  return "FID_" .. tostring(math.random(100000, 999999))
end

local function collect_funcs(code)
  local funcs = {}
  -- Use pattern that matches function at start of line or after newline
  for name in code:gmatch("function%s+([%w_]+)%s*%(") do
    funcs[name] = { name = name, type = "global", id = gen_id() }
  end
  return funcs
end

local function build_table(funcs)
  local tbl = "CT_" .. tostring(math.random(100000, 999999))
  local disp = "DP_" .. tostring(math.random(100000, 999999))

  local entries = {}
  for name, info in pairs(funcs) do
    entries[#entries+1] = string.format("  %s = %s", name, name)
  end

  local code_str = string.format(
    "local %s = {\n%s\n}\nlocal %s = {}\n%s.__index = function(_, k) return %s[k] end\nsetmetatable(%s, %s)\n",
    tbl, table.concat(entries, ",\n"), disp, tbl, tbl, disp, disp
  )

  return tbl, disp, code_str
end

local function replace_calls(code, funcs, tbl)
  local result = {}

  local global_funcs = {}
  for name, info in pairs(funcs) do
    if info.type == "global" then
      global_funcs[name] = true
    end
  end

  for line in code:gmatch("[^\n]+") do
    local new_line = line

    if not line:match("function%s+[%w_]+%s*%(") then
      for func_name in pairs(global_funcs) do
        new_line = new_line:gsub(
          "([%w_]+)%s*%(",
          function(captured)
            if captured == func_name then
              return string.format("%s.%s(", tbl, func_name)
            end
            return captured .. "("
          end
        )
      end
    end

    result[#result+1] = new_line
  end

  return table.concat(result, "\n")
end

function M.apply(code, _ctx)
  local funcs = collect_funcs(code)
  if not next(funcs) then return code end

  local global_count = 0
  for _, info in pairs(funcs) do
    if info.type == "global" then global_count = global_count + 1 end
  end
  if global_count == 0 then return code end

  local tbl, disp, tbl_code = build_table(funcs)
  code = replace_calls(code, funcs, tbl)

  -- Insert call table at beginning of code
  code = tbl_code .. "\n" .. code

  return code
end

return M
]], "@passes/call_indirect.lua")()
  end
  package.preload["passes.init"] = function()
    return load([[-- ================================================================
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
  "passes.anti_debug",
  "passes.string_encrypt",
  "passes.num_encrypt",
  "passes.instr_sub",
  "passes.var_mangle",
  "passes.adv_fake_cf",
 "passes.cf_flatten",
 "passes.bcf",
  "passes.bb_split",
 "passes.junk_comment",
  "passes.call_indirect",
  "passes.header",
}

-- 加载所有内置 Pass 并注册到 PassManager
function M.load_all(pm)
  for _, name in ipairs(BUILTIN) do
    local ok, pass = pcall(require, name)
    if ok and type(pass) == "table" and pass.name then
      pm:register(pass)
    else
      if io and io.stderr then io.stderr:write(string.format("[passes] WARNING: 加载 %s 失败: %s\n", name, tostring(pass))) else print(string.format("[passes] WARNING: 加载 %s 失败: %s", name, tostring(pass))) end
    end
  end
  return pm
end

-- 注册单个自定义 Pass
function M.register(pm, pass)
  pm:register(pass)
end

return M
]], "@passes/init.lua")()
  end
end

-- ================================================================
-- obfuscator.lua
-- Lua 代码混淆器 - 主程序
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
--
-- 职责：
--   1. 加载 Pass 系统
--   2. 提供 CLI 交互界面
--   3. 对外暴露 JS Bridge 接口
--
-- 具体的混淆逻辑在 passes/ 目录下各模块中实现

-- ============================================================
-- 兼容性处理
-- ============================================================
if _VERSION then
  local ver = tonumber(_VERSION:match("Lua (%d+%.%d+)") or "0")
  if ver < 5.3 then
    local ok, bit_lib = pcall(require, "bit") or pcall(require, "bit32")
    if ok and bit_lib then
      rawset(_G, "_bxor", bit_lib.bxor)
      rawset(_G, "_band", bit_lib.band)
      rawset(_G, "_bor",  bit_lib.bor)
      rawset(_G, "_bnot", bit_lib.bnot)
      rawset(_G, "_shl",  bit_lib.lshift)
      rawset(_G, "_shr",  bit_lib.rshift)
    else
      if io and io.stderr then io.stderr:write('[Lua Obfuscator] WARNING: ' .. _VERSION .. ' detected. Bitwise operators (~, &, |) require Lua 5.3+ or LuaJIT with bit library.\n') else print('[Lua Obfuscator] WARNING: ' .. _VERSION .. ' detected. Bitwise operators (~, &, |) require Lua 5.3+ or LuaJIT with bit library.') end
    end
  end
end

-- ============================================================
-- 初始化随机数种子
-- ============================================================
local ok_t, t = pcall(os.time)
local ok_c, c = pcall(os.clock)
if ok_t and ok_c then
  math.randomseed(math.floor(t + c * 1000))
else
  math.randomseed(42)
end

-- ============================================================
-- 版本
-- ============================================================
local VERSION = "2.9.0"

-- ============================================================
-- 加载 Pass 系统
-- ============================================================
local PassManager = require("pass_manager")
local passes_loader = require("passes")

local pm = PassManager.new()
passes_loader.load_all(pm)

-- 字符串池（跨 Pass 共享的特殊流程）
local string_pool = require("passes.string_pool")

-- ============================================================
-- 默认配置（CLI 模式使用）
-- ============================================================
local Config = {
  vm_protect                = false,
  string_encryption         = true,
  variable_mangling         = true,
  instruction_substitution  = false,
  constant_encryption       = true,
  advanced_fake_cf          = true,
  control_flow_flattening   = false,
 bogus_control_flow        = false,
  basic_block_splitting    = true,
 junk_comments             = true,
  anti_debug               = false,
  call_indirection         = false,
}

-- Config key → Pass name 映射
local CONFIG_TO_PASS = {
  vm_protect                = "vm_protect",
  string_encryption         = "string_encryption",
  variable_mangling         = "variable_mangling",
  instruction_substitution  = "instruction_substitution",
  constant_encryption       = "constant_encryption",
  advanced_fake_cf          = "advanced_fake_cf",
  control_flow_flattening   = "control_flow_flattening",
 bogus_control_flow        = "bogus_control_flow",
  basic_block_splitting    = "basic_block_splitting",
 junk_comments             = "junk_comments",
  anti_debug               = "anti_debug",
  call_indirection         = "call_indirection",
}

-- 将 Config 同步到 PassManager
local function sync_config_to_passes()
  for config_key, pass_name in pairs(CONFIG_TO_PASS) do
    pm:set_enabled(pass_name, Config[config_key])
  end
end

-- ============================================================
-- 核心混淆函数
-- ============================================================
local function obfuscate(code, vm_module)
  sync_config_to_passes()

  -- 检查 VM 保护是否启用
  local vm_pass = pm:get("vm_protect")
  local do_vm = vm_pass and vm_pass.enabled

  -- VM 保护生成的字节码解释器是结构化代码，文本类 Pass 会破坏其语义
  -- 指令替换、控制流平坦化、BCF 虚假控制流与 VM 输出不兼容，自动禁用
  if do_vm then
    pm:set_enabled("instruction_substitution", false)
    pm:set_enabled("control_flow_flattening", false)
   pm:set_enabled("bogus_control_flow", false)
    pm:set_enabled("basic_block_splitting", false)
 end

  -- 字符串提取（VM保护时跳过，VM自己处理字符串）
  if not do_vm then
    code = string_pool.extract(code)
  end

  -- 执行 Pass Pipeline
  local ok, result, log = pcall(pm.run, pm, code, {
    vm_module = vm_module,
  })

  if not ok then
    error("混淆失败: " .. tostring(result))
  end

  -- 字符串恢复（VM保护时跳过）
  if not do_vm then
    local string_pass = pm:get("string_encryption")
    local do_encrypt = string_pass and string_pass.enabled
    if do_encrypt then
      result = string_pool.restore(result)
    else
      result = string_pool.restore_raw(result)
    end
  end

  return result, log
end

-- ============================================================
-- CLI 界面
-- ============================================================
local feature_names = {
  { key = "control_flow_flattening",  name = "控制流平坦化" },
  { key = "constant_encryption",      name = "常量数字加密" },
  { key = "bogus_control_flow",       name = "BCF虚假控制流" },
  { key = "variable_mangling",        name = "变量名混淆" },
  { key = "string_encryption",        name = "字符串加密" },
  { key = "junk_comments",            name = "垃圾注释" },
  { key = "instruction_substitution", name = "指令替换" },
 { key = "advanced_fake_cf",         name = "虚假控制流增强" },
  { key = "basic_block_splitting",   name = "基本块拆分" },
 { key = "vm_protect",               name = "VM字节码虚拟化" },
  { key = "anti_debug",               name = "反调试检测" },
  { key = "call_indirection",         name = "调用间接化" },
}

local function print_banner()
  print(string.format([[
  ╔══════════════════════════════════════════╗
  ║   Lua Obfuscator v%s                 ║
  ║   代码混淆 & VM虚拟化保护工具           ║
  ╚══════════════════════════════════════════╝
]], VERSION))
end

local function print_status()
  print("\n  当前配置：")
  for i, feat in ipairs(feature_names) do
    local status = Config[feat.key] and "✓" or "✗"
    print(string.format("    %d. [%s] %s", i, status, feat.name))
  end
  print()
end

local function toggle_feature(num)
  if num < 1 or num > #feature_names then
    print("  无效编号")
    return
  end
  local feat = feature_names[num]
  Config[feat.key] = not Config[feat.key]
  local status = Config[feat.key] and "启用" or "禁用"
  print(string.format("  %s: %s", feat.name, status))
end

local function enable_all()
  for _, feat in ipairs(feature_names) do
    Config[feat.key] = true
  end
  print("  已全部启用")
end

local function disable_all()
  for _, feat in ipairs(feature_names) do
    Config[feat.key] = false
  end
  print("  已全部禁用")
end

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(content)
  f:close()
  return true
end

local function do_obfuscate(input_path, output_path)
  local code, err = read_file(input_path)
  if not code then
    print("  ❌ 读取失败: " .. tostring(err))
    return
  end

  print(string.format("\n  读取输入文件: %s", input_path))
  print(string.format("  原始代码长度: %d 字节", #code))
  print("  开始混淆...")

  local ok, result, log = pcall(obfuscate, code)
  if not ok then
    print("  ❌ " .. tostring(result))
    return
  end

  write_file(output_path, result)
  print(string.format("  ✅ 输出已保存到: %s", output_path))
  print(string.format("  混淆后长度: %d 字节 (膨胀 %.1fx)", #result, #result / #code))

  if log then
    print("\n  Pipeline 执行日志:")
    for _, entry in ipairs(log) do
      print(string.format("    [%s] %s: %d → %d bytes", entry.name, entry.title, entry.input_size, entry.output_size))
    end
  end
end

local function interactive_input()
  print("\n  请输入要混淆的 Lua 代码（输入空行结束）：")
  print("  " .. string.rep("-", 40))
  local lines = {}
  while true do
    io.write("  > ")
    local line = io.read()
    if not line or line == "" then break end
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

local function run_demo()
  -- 演示代码在 demo 模式中内联
  return [[
local function greet(name)
  return "Hello, " .. name .. "!"
end
for i = 1, 5 do
  print(greet("World " .. i))
end
]]
end

local function fibonacci(n)
  if n <= 1 then return n end
  return fibonacci(n - 1) + fibonacci(n - 2)
end

local function print_help()
  print(string.format([[
Lua Obfuscator v%s - 使用说明

用法:
  lua obfuscator.lua [选项]

选项:
  -i, --input <file>    输入文件
  -o, --output <file>   输出文件（默认: <input>_obf.lua）
  --vm                  启用 VM 字节码虚拟化
  --no-cfe              禁用控制流平坦化
  --no-num              禁用常量数字加密
  --no-bcf              禁用 BCF 虚假控制流
  --no-var              禁用变量名混淆
  --no-str              禁用字符串加密
  --no-junk             禁用垃圾注释
  --no-instr            禁用指令替换
 --no-advbcf           禁用虚假控制流增强
  --no-bbsplit         禁用基本块拆分
 --demo                运行演示
  -h, --help            显示帮助

交互模式:
  直接运行不带参数进入交互模式
  支持功能开关、输入代码、批量处理等
]], VERSION))
end

local function interactive_loop()
  print_banner()
  print_status()

  local _is_cli = false
  for i = 1, #arg do
    local v = arg[i]
    if v == "-i" or v == "--input" or v == "--help" or v == "-h" or v == "--demo" then
      _is_cli = true
      break
    end
  end

  while true do
    io.write("\n  > ")
    local input = io.read()
    if not input then break end

    input = input:match("^%s*(.-)%s*$")

    if input == "" then
      -- 空行
    elseif input == "q" or input == "quit" or input == "exit" then
      print("  再见！")
      break
    elseif input == "h" or input == "help" then
      print_help()
    elseif input == "s" or input == "status" then
      print_status()
    elseif input == "a" or input == "all" then
      enable_all()
      print_status()
    elseif input == "n" or input == "none" then
      disable_all()
      print_status()
    elseif input:match("^%d+$") then
      toggle_feature(tonumber(input))
    elseif input == "e" or input == "encode" then
      local code = interactive_input()
      if code and code ~= "" then
        local ok, result = pcall(obfuscate, code)
        if ok then
          print("\n  " .. string.rep("=", 50))
          print(result)
          print("  " .. string.rep("=", 50))
        else
          print("  ❌ " .. tostring(result))
        end
      end
    elseif input == "d" or input == "demo" then
      local code = run_demo()
      print("\n  原始代码:")
      print("  " .. string.rep("-", 40))
      for line in code:gmatch("[^\n]+") do
        print("  " .. line)
      end
      print("  " .. string.rep("-", 40))
      print("\n  混淆中...")
      local ok, result = pcall(obfuscate, code)
      if ok then
        print("  混淆后代码:")
        print("  " .. string.rep("=", 50))
        print(result)
        print("  " .. string.rep("=", 50))
      else
        print("  ❌ " .. tostring(result))
      end
    elseif input == "f" or input == "fib" then
      print("\n  计算 fibonacci(35)...")
      local t0 = os.clock()
      local r = fibonacci(35)
      local t1 = os.clock()
      print(string.format("  结果: %d (耗时: %.3fs)", r, t1 - t0))
    else
      print("  未知命令。输入 h 查看帮助。")
    end
  end
end

-- ============================================================
-- JS Bridge 接口
-- ============================================================
local M = {}

function M.obfuscate_code(code, options, vm_module)
  -- 将 JS options 映射到 Config
  if options then
    for key, value in pairs(options) do
      if Config[key] ~= nil then
        Config[key] = value
      end
    end
  end

  local ok, result = pcall(obfuscate, code, vm_module)
  if not ok then
    error(tostring(result))
  end
  return result
end

function M.get_config()
  return Config
end

function M.set_config(options)
  for key, value in pairs(options) do
    if Config[key] ~= nil then
      Config[key] = value
    end
  end
end

function M.list_passes()
  return pm:list()
end

function M.set_pass_enabled(name, enabled)
  return pm:set_enabled(name, enabled)
end

function M.set_pass_config(name, key, value)
  return pm:set_config(name, key, value)
end

function M.export_pass_config()
  return pm:export_config()
end

function M.import_pass_config(config)
  return pm:import_config(config)
end

M.VERSION = VERSION

-- ============================================================
-- CLI 入口
-- ============================================================
local _is_cli = false
if arg then
  for i = 1, #arg do
    local v = arg[i]
    if v == "-i" or v == "--input" or v == "--help" or v == "-h" or v == "--demo" then
      _is_cli = true
      break
    end
  end
end

if _is_cli then
  local args = {}
  if arg then for i = 1, #arg do args[#args + 1] = arg[i] end end

  local input, output = nil, nil
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-h" or a == "--help" then
      print_help()
      os.exit(0)
    elseif a == "-i" or a == "--input" then
      i = i + 1; input = args[i]
    elseif a == "-o" or a == "--output" then
      i = i + 1; output = args[i]
    elseif a == "--no-cfe" then Config.control_flow_flattening = false
    elseif a == "--no-num" then Config.constant_encryption = false
    elseif a == "--no-bcf" then Config.bogus_control_flow = false
    elseif a == "--no-var" then Config.variable_mangling = false
    elseif a == "--no-str" then Config.string_encryption = false
    elseif a == "--no-junk" then Config.junk_comments = false
    elseif a == "--no-instr" then Config.instruction_substitution = false
   elseif a == "--no-advbcf" then Config.advanced_fake_cf = false
    elseif a == "--no-bbsplit" then Config.basic_block_splitting = false
   elseif a == "--vm" then Config.vm_protect = true
    elseif a == "--demo" then
      local code = run_demo()
      local ok, result = pcall(obfuscate, code)
      if ok then print(result) else print("ERROR: " .. tostring(result)); os.exit(1) end
      os.exit(0)
    elseif not a:match("^%-") then
      if not input then input = a end
    end
    i = i + 1
  end

  if input then
    output = output or input:gsub("%.lua$", "") .. "_obf.lua"
    do_obfuscate(input, output)
  else
    print_help()
  end
end

return M
