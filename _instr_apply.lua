-- Monkey-patch var_mangle by loading its source and injecting prints.
-- Simpler: require it and call apply, but first patch os.clock? No.
-- We'll require the module and call apply with a co-yielding watchdog? Can't preempt.
-- Instead: copy the apply function with prints at each phase.

local vm = require("passes.vm")
local var_mangle_src = require("passes.var_mangle")

local f = io.open("_vmout.lua", "r")
local vmout = f:read("*a"); f:close()
print("vmout len:", #vmout); io.flush()

-- Re-implement apply with prints, using the module's internal functions via dofile trick.
-- The module doesn't expose internals. So load the source file fresh in an env where
-- we can hook. Easiest: read passes/var_mangle.lua, prepend instrumentation by
-- wrapping collect_table_keys. But they're locals.
--
-- Alternative: add prints by reading the file and running it with a modified apply.
-- Let's just read the file, and exec a version where we add print statements.
local vmsrc = io.open("passes/var_mangle.lua","r"):read("*a")

-- Inject a print before "local table_keys = collect_table_keys(code)"
vmsrc = vmsrc:gsub("local table_keys = collect_table_keys%(code%)",
  'print("[phase] collect_table_keys start"); io.flush(); local table_keys = collect_table_keys(code); print("[phase] collect_table_keys done, keys=", (function() local n=0 for _ in pairs(table_keys) do n=n+1 end return n end)()); io.flush()')
vmsrc = vmsrc:gsub("local var_map, ids = collect_local_vars%(code, table_keys%)",
  'print("[phase] collect_local_vars start"); io.flush(); local var_map, ids = collect_local_vars(code, table_keys); print("[phase] collect_local_vars done"); io.flush()')
vmsrc = vmsrc:gsub("code = extract_vm_blocks%(code%)",
  'print("[phase] extract_vm_blocks start"); io.flush(); code = extract_vm_blocks(code); print("[phase] extract_vm_blocks done, len=", #code); io.flush()')
vmsrc = vmsrc:gsub("code = restore_vm_blocks%(code%)",
  'print("[phase] restore_vm_blocks start"); io.flush(); code = restore_vm_blocks(code); print("[phase] restore_vm_blocks done"); io.flush()')
-- the segment rebuild loop:
vmsrc = vmsrc:gsub("for _, id in ipairs%(ids%) do",
  'print("[phase] segment rebuild start, ids=", #ids); io.flush(); local __seg_i=0; for _, id in ipairs(ids) do __seg_i=__seg_i+1; if __seg_i % 500 == 0 then print("  seg", __seg_i); io.flush() end')

local fn, err = load(vmsrc, "@var_mangle_instr")
if not fn then print("load err:", err); os.exit(1) end
fn()
local M = _G.M or M  -- the module sets local M and returns it; but we ran at chunk level

-- Actually the module is `local M = {} ... return M`. We need its return value.
-- load() returns the chunk; calling it runs the file but the return value is lost.
-- Workaround: append `M` to globals.
print("loaded"); io.flush()
