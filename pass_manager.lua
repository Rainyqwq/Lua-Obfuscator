-- ================================================================
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
  -- Optional total pipeline budget (ms). Prevents runaway passes hanging hosts.
  local max_total_ms = tonumber(opts.max_total_ms or opts.timeout_ms)
  local pipeline_t0 = (os.clock and os.clock()) or 0
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

      if max_total_ms and os.clock then
        local elapsed_ms = (os.clock() - pipeline_t0) * 1000
        if elapsed_ms > max_total_ms then
          error(string.format("pipeline timeout: exceeded %.0fms (at pass '%s')", max_total_ms, def.name))
        end
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
