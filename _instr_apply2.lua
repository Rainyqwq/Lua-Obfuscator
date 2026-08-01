-- Instrumented copy of var_mangle.apply with phase prints, called on the vm output.
local utils = require("passes.utils")
local random_id = utils.random_id

local f = io.open("_vmout.lua", "r")
local code0 = f:read("*a"); f:close()
print("vmout len:", #code0); io.flush()

local M = {}
M.name = "variable_mangling"
M.config = { whitelist = {} }

local RESERVED = {}
for _, w in ipairs({"and","break","do","else","elseif","end","false","for","function","goto","if","in","local","nil","not","or","repeat","return","then","true","until","while","self","print","require","pcall","xpcall","type","tostring","tonumber","pairs","ipairs","table","string","math","io","os","coroutine","debug","package","rawset","rawget","setmetatable","getmetatable","error","assert","select","unpack","collectgarbage","dofile","load","loadfile","next","rawequal","rawlen","module"}) do RESERVED[w] = true end

local BYTE_DOT = string.byte(".")
local function is_digit(b) return b>=48 and b<=57 end
local function is_id_start(b) return (b>=65 and b<=90) or (b>=97 and b<=122) or b==95 end
local function is_id_char(b) return is_id_start(b) or (b>=48 and b<=57) end

-- IDENTICAL copies of scan_identifiers, collect_local_vars, collect_table_keys
-- from passes/var_mangle.lua (no changes to logic).

local function scan_identifiers(code)
  local ids = {}; local n = 0; local pos = 1; local len = #code
  while pos <= len do
    local b = code:byte(pos)
    if b == 95 and code:sub(pos, pos + 3) == "__ST" then
      local end_pos = code:find("__", pos + 5, true)
      if end_pos then pos = end_pos + 2 else pos = pos + 1 end
    elseif b == 45 and pos < len and code:byte(pos + 1) == 45 then
      local nl = code:find("\n", pos + 2, true)
      pos = nl and (nl + 1) or (len + 1)
    elseif is_id_start(b) then
      local is_scientific_e = false
      if (b == 101 or b == 69) and pos > 1 then
        local prev = code:byte(pos - 1)
        if is_digit(prev) or prev == BYTE_DOT then
          pos = pos + 1
          if pos <= len then local sign = code:byte(pos); if sign == 43 or sign == 45 then pos = pos + 1 end end
          while pos <= len and is_digit(code:byte(pos)) do pos = pos + 1 end
          is_scientific_e = true
        end
      end
      if not is_scientific_e then
        local start = pos; pos = pos + 1
        while pos <= len and is_id_char(code:byte(pos)) do pos = pos + 1 end
        local name = code:sub(start, pos - 1); n = n + 1
        ids[n] = { name = name, start = start, stop = pos - 1 }
      end
    else pos = pos + 1 end
  end
  return ids
end

local function collect_local_vars(code, table_keys)
  local var_map = {}
  local ids = scan_identifiers(code)
  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      local before = code:sub(math.max(1, id.start - 20), id.start - 1)
      if before:match("local%s+$") or before:match("local%s+function%s+$") then var_map[name] = true end
      if before:match(",%s*$") then
        local local_pos = before:find("local%s+", 1, true)
        if local_pos then var_map[name] = true end
      end
    end
  end
  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      local before = code:sub(math.max(1, id.start - 5), id.start - 1)
      if before:match("%(%s*$") or before:match(",%s*$") then
        local ctx = code:sub(math.max(1, id.start - 50), id.start - 1)
        if ctx:match("function%s*[%w_.:]*%s*$") or ctx:match("function%s*[%w_.:]*%s*%([^)]*$") then var_map[name] = true end
      end
    end
  end
  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      local before = code:sub(math.max(1, id.start - 10), id.start - 1)
      if before:match("for%s+$") or before:match(",%s*$") then var_map[name] = true end
    end
  end
  return var_map, ids
end

local function collect_table_keys(code)
  local keys = {__index=true,__newindex=true,__add=true,__sub=true,__mul=true,__div=true,__mod=true,__pow=true,__unm=true,__len=true,__eq=true,__lt=true,__le=true,__concat=true,__call=true,__tostring=true,__gc=true,__ipairs=true,__pairs=true}
  local i = 1; local len = #code
  while i <= len do
    local b = code:byte(i)
    if b == 95 and code:sub(i, i+3) == "__ST" then
      local ep = code:find("__", i+5, true); i = ep and (ep+2) or (i+1)
    elseif b == 45 and i < len and code:byte(i+1) == 45 then
      local nl = code:find("\n", i+2, true); i = nl and (nl+1) or (len+1)
    elseif b == 34 or b == 39 then
      local q = b; i = i + 1
      while i <= len do
        if code:byte(i) == 92 then i = i + 2
        elseif code:byte(i) == q then i = i + 1; break
        else i = i + 1 end
      end
    elseif b == 91 then
      i = i + 1; local depth = 1
      while i <= len and depth > 0 do
        local cb = code:byte(i)
        if cb == 91 then depth = depth + 1
        elseif cb == 93 then depth = depth - 1
        elseif cb == 34 or cb == 39 then
          local q2 = cb; i = i + 1
          while i <= len do
            if code:byte(i) == 92 then i = i + 2
            elseif code:byte(i) == q2 then i = i + 1; break
            else i = i + 1 end
          end
        else i = i + 1 end
      end
    elseif b == 123 then
      i = i + 1; local depth = 1
      while i <= len and depth > 0 do
        local cb = code:byte(i)
        if cb == 123 then depth = depth + 1; i = i + 1
        elseif cb == 125 then depth = depth - 1; i = i + 1
        elseif cb == 34 or cb == 39 then
          local q3 = cb; i = i + 1
          while i <= len do
            if code:byte(i) == 92 then i = i + 2
            elseif code:byte(i) == q3 then i = i + 1; break
            else i = i + 1 end
          end
        elseif (cb >= 65 and cb <= 90) or (cb >= 97 and cb <= 122) or cb == 95 then
          local start = i; i = i + 1
          while i <= len do
            local ib = code:byte(i)
            if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
          end
          local key = code:sub(start, i - 1)
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if code:byte(i) == 61 then keys[key] = true; i = i + 1 end
        else i = i + 1 end
      end
    elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
      local start = i; i = i + 1
      while i <= len do
        local ib = code:byte(i)
        if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
      end
      local idname = code:sub(start, i-1)
      local kw = {["local"]=1,["function"]=1,["if"]=1,["for"]=1,["while"]=1,["return"]=1,["end"]=1,["then"]=1,["do"]=1,["else"]=1,["or"]=1,["and"]=1,["not"]=1,["in"]=1,["repeat"]=1,["until"]=1,["break"]=1,["goto"]=1}
      if not kw[idname] then
        while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
        if code:byte(i) == 46 then
          i = i + 1
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if (code:byte(i) >= 65 and code:byte(i) <= 90) or (code:byte(i) >= 97 and code:byte(i) <= 122) or code:byte(i) == 95 then
            local fstart = i; i = i + 1
            while i <= len do
              local ib = code:byte(i)
              if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
            end
            local fieldname = code:sub(fstart, i-1); keys[fieldname] = true
          end
        end
      end
    else i = i + 1 end
  end
  return keys
end

-- ===== Now the apply phases with prints =====
local function normalize_whitelist(wl) local out = {} if type(wl)~="table" then return out end for k,v in pairs(wl) do if type(k)=="number" and type(v)=="string" and v~="" then out[v]=true elseif type(k)=="string" and k~="" and v then out[k]=true end end return out end

local function apply(code, ctx)
  ctx = ctx or {}
  local cfg = ctx.config or {}
  local whitelist = normalize_whitelist(cfg.whitelist)
  local vm_blocks = {}; local block_idx = 1

  local function extract_vm_blocks(src)
    local result = {}; local pos = 1; local len = #src
    while pos <= len do
      local marker_start = src:find("-- @vm %(protected%)", pos, true)
      if not marker_start then result[#result + 1] = src:sub(pos); break end
      if marker_start > pos then result[#result + 1] = src:sub(pos, marker_start - 1) end
      local block_end = src:find("\n-- @", marker_start + 1)
      if not block_end then block_end = len + 1 end
      local vm_code = src:sub(marker_start, block_end - 1)
      local placeholder = "__VM_BLOCK_" .. block_idx .. "__"
      vm_blocks[placeholder] = vm_code
      result[#result + 1] = "\n" .. placeholder .. "\n"
      block_idx = block_idx + 1
      pos = block_end
    end
    return table.concat(result)
  end
  local function restore_vm_blocks(c)
    for placeholder, vm_code in pairs(vm_blocks) do c = c:gsub(placeholder, vm_code) end
    return c
  end

  print("[1] extract_vm_blocks start"); io.flush()
  code = extract_vm_blocks(code)
  print("[1] extract_vm_blocks done, len=", #code, "blocks=", block_idx-1); io.flush()

  print("[2] collect_table_keys start"); io.flush()
  local table_keys = collect_table_keys(code)
  local nkeys=0; for _ in pairs(table_keys) do nkeys=nkeys+1 end
  print("[2] collect_table_keys done, keys=", nkeys); io.flush()

  print("[3] collect_local_vars start"); io.flush()
  local var_map, ids = collect_local_vars(code, table_keys)
  local nvars=0; for _ in pairs(var_map) do nvars=nvars+1 end
  print("[3] collect_local_vars done, vars=", nvars, "ids=", #ids); io.flush()

  for name in pairs(whitelist) do var_map[name] = nil end
  local rename_map = {}
  for name in pairs(var_map) do rename_map[name] = "_" .. random_id(6) end

  print("[4] segment rebuild start, ids=", #ids); io.flush()
  local segments = {}; local sn = 0; local last_pos = 1
  for k, id in ipairs(ids) do
    local new_name = rename_map[id.name]
    if new_name then
      if id.start > last_pos then sn = sn + 1; segments[sn] = code:sub(last_pos, id.start - 1) end
      sn = sn + 1; segments[sn] = new_name; last_pos = id.stop + 1
    end
    if k % 2000 == 0 then print("  seg", k); io.flush() end
  end
  if last_pos <= #code then sn = sn + 1; segments[sn] = code:sub(last_pos) end
  if sn > 0 then code = table.concat(segments) end
  print("[4] segment rebuild done, sn=", sn); io.flush()

  print("[5] restore_vm_blocks start"); io.flush()
  code = restore_vm_blocks(code)
  print("[5] restore_vm_blocks done, len=", #code); io.flush()
  return code
end

print("calling apply..."); io.flush()
local t0 = os.clock()
local ok, res = pcall(apply, code0, { config = { whitelist = {} } })
print("apply returned ok=", ok, "elapsed=", os.clock()-t0); io.flush()
if not ok then print("ERR:", res) end
