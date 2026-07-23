-- ================================================================
-- passes/call_indirect.lua
-- Function call indirection via runtime lookup table
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- Only rewrites GLOBAL function calls: 'function foo(...)' (not local).
-- Call sites become 'CT.foo(...)'. CT uses __index -> _ENV/_G so the
-- function is resolved at call time (after definition), which keeps
-- recursion and forward references working.

local M = {}

M.name = "call_indirection"
M.title = "Function Call Indirection"
M.version = "1.2.0"
M.order = 85
M.enabled = true

local RESERVED = {
  ["if"] = true, ["then"] = true, ["else"] = true, ["elseif"] = true, ["end"] = true,
  ["for"] = true, ["while"] = true, ["do"] = true, ["repeat"] = true, ["until"] = true,
  ["function"] = true, ["local"] = true, ["return"] = true, ["break"] = true, ["goto"] = true,
  ["in"] = true, ["not"] = true, ["and"] = true, ["or"] = true, ["nil"] = true,
  ["true"] = true, ["false"] = true,
  print = true, pairs = true, ipairs = true, next = true,
  type = true, select = true, unpack = true, tostring = true, tonumber = true,
  require = true, error = true, assert = true, pcall = true, xpcall = true,
  load = true, loadfile = true, dofile = true, setmetatable = true,
  getmetatable = true, rawget = true, rawset = true, rawequal = true,
  collectgarbage = true, table = true, string = true, math = true, io = true, os = true,
  debug = true, coroutine = true, package = true, utf8 = true, bit32 = true,
}

local function gen_name(prefix)
  return prefix .. tostring(math.random(100000, 999999))
end

-- Collect only GLOBAL function definitions (not 'local function')
local function collect_global_funcs(code)
  local funcs = {}
  local pos = 1
  local len = #code
  while pos <= len do
    local s, e, name = code:find("function%s+([%a_][%w_]*)%s*%(", pos)
    if not s then break end
    -- Check for 'local' immediately before 'function'
    local before = code:sub(math.max(1, s - 16), s - 1)
    local is_local = before:match("local%s+$") ~= nil
    if not is_local and not RESERVED[name] then
      funcs[name] = true
    end
    pos = e + 1
  end
  return funcs
end

local function build_prelude(tbl)
  -- Resolve at call time from the chunk environment, never capture nil early.
  return string.format(
    "local %s=setmetatable({},{__index=function(_,k)local e=_ENV or _G;return e[k]end})\n",
    tbl
  )
end

local function is_definition_line(line)
  return line:match("^%s*function%s+[%a_][%w_]*%s*%(")
      or line:match("^%s*local%s+function%s+[%a_][%w_]*%s*%(")
end

local function is_comment_or_empty(line)
  local t = line:match("^%s*(.-)%s*$") or ""
  return t == "" or t:sub(1, 2) == "--"
end

local function replace_calls(code, funcs, tbl)
  local out = {}
  for line in (code .. "\n"):gmatch("(.-)\n") do
    if is_definition_line(line) or is_comment_or_empty(line) then
      out[#out + 1] = line
    else
      local new_line = line:gsub("([%.:]?)([%a_][%w_]*)(%s*)%(", function(prefix, name, ws)
        if prefix == ":" or prefix == "." then
          return prefix .. name .. ws .. "("
        end
        if not funcs[name] or RESERVED[name] then
          return name .. ws .. "("
        end
        return tbl .. "." .. name .. ws .. "("
      end)
      out[#out + 1] = new_line
    end
  end
  return table.concat(out, "\n")
end

function M.apply(code, _ctx)
  local funcs = collect_global_funcs(code)
  if not next(funcs) then return code end

  local tbl = gen_name("CT_")
  local body = replace_calls(code, funcs, tbl)
  return build_prelude(tbl) .. body
end

return M
