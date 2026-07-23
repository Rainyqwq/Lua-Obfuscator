-- tests/test_p1_presets_whitelist.lua
-- P1: presets + name/string whitelist + config export/import
package.path = "./?.lua;./?/init.lua;" .. package.path

local o = require("obfuscator")

local function blank()
  return {
    vm_protect = false, anti_debug = false,
    string_encryption = false, variable_mangling = false,
    instruction_substitution = false, constant_encryption = false,
    advanced_fake_cf = false, control_flow_flattening = false,
    bogus_control_flow = false, basic_block_splitting = false,
    junk_comments = false, call_indirection = false,
  }
end

local pass, fail = 0, 0
local function check(name, cond, msg)
  if cond then
    pass = pass + 1
    print("  OK  " .. name)
  else
    fail = fail + 1
    print("  FAIL " .. name .. " :: " .. tostring(msg))
  end
end

print("=== P1 presets / whitelist ===")

-- list presets
local presets = o.list_presets()
check("list_presets", type(presets) == "table" and #presets == 3)

-- apply fast
local okp = o.apply_preset("fast")
check("apply_preset fast", okp == true)
local cfg = o.get_config()
check("fast no cfe", cfg.control_flow_flattening == false)
check("fast has str", cfg.string_encryption == true)
check("fast no vm", cfg.vm_protect == false)
check("fast preset name", cfg.preset == "fast")

-- apply max
okp = o.apply_preset("max")
cfg = o.get_config()
check("max vm", cfg.vm_protect == true)
check("max anti", cfg.anti_debug == true)
check("max preset", cfg.preset == "max")

-- balanced default-ish
okp = o.apply_preset("balanced")
cfg = o.get_config()
check("balanced cfe", cfg.control_flow_flattening == true)
check("balanced no vm", cfg.vm_protect == false)

-- name whitelist: keep `keep_me` under mangling
local src = [[
local keep_me = 1
local other = 2
print(keep_me + other)
]]
local opts = blank()
opts.variable_mangling = true
opts.name_whitelist = { "keep_me" }
local out = o.obfuscate_code(src, opts)
check("name wl keeps keep_me", out:find("keep_me", 1, true) ~= nil, out:sub(1,200))
check("name wl mangles other", out:find("other", 1, true) == nil, "other still present")

-- string whitelist
src = [[
print("KEEP_PLAIN")
print("secret_value")
]]
opts = blank()
opts.string_encryption = true
opts.string_whitelist = { "KEEP_PLAIN" }
out = o.obfuscate_code(src, opts)
check("string wl keeps KEEP_PLAIN", out:find("KEEP_PLAIN", 1, true) ~= nil)
check("string wl encrypts secret", out:find("secret_value", 1, true) == nil)

-- semantic with whitelist
src = [[
local keep_me = 40
local x = 2
print(keep_me + x)
print("KEEP_PLAIN")
]]
opts = blank()
opts.variable_mangling = true
opts.string_encryption = true
opts.constant_encryption = true
opts.name_whitelist = { "keep_me" }
opts.string_whitelist = { "KEEP_PLAIN" }
out = o.obfuscate_code(src, opts)
local captured = {}
local real_print = print
local fn, err = load(out, "=p1", "t", setmetatable({
  print = function(...)
    local t = {...}
    for i=1,#t do t[i]=tostring(t[i]) end
    captured[#captured+1] = table.concat(t, "\t")
  end,
}, { __index = _G }))
check("whitelist load", fn ~= nil, err)
if fn then
  local rok, rerr = pcall(fn)
  check("whitelist run", rok, rerr)
  check("whitelist output", table.concat(captured, "\n") == "42\nKEEP_PLAIN", table.concat(captured, "\n"))
end
-- ensure global print intact
check("print intact", print == real_print)

-- export / import user config
o.apply_preset("fast")
o.set_config({ name_whitelist = { "alpha" }, string_whitelist = { "BETA" } })
local snap = o.export_user_config()
check("export has version", type(snap.version) == "string")
check("export whitelist", snap.name_whitelist[1] == "alpha")
check("export preset or custom", snap.preset == "custom" or snap.preset == "fast")

o.apply_preset("max")
local ok_imp = o.import_user_config(snap)
check("import ok", ok_imp == true)
cfg = o.get_config()
check("import restored name wl", cfg.name_whitelist[1] == "alpha")
check("import restored str wl", cfg.string_whitelist[1] == "BETA")
check("import restored fast-like cfe", cfg.control_flow_flattening == false)

-- unknown preset
local ok_bad, err_bad = o.apply_preset("nope")
check("bad preset", ok_bad == false)

print(string.format("=== result: %d pass, %d fail ===", pass, fail))
if fail > 0 then os.exit(1) end
print("P1 regression OK")
