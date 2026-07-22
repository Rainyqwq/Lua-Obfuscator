-- passes/call_indirect.lua
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
