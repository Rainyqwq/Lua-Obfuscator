-- Instrument extract_vm_blocks and restore_vm_blocks on the vm output.
local f = io.open("_vmout.lua", "r")
local code = f:read("*a"); f:close()
local len = #code
print("code length:", len); io.flush()

local function report(tag, i) print(string.format("  [%s] i=%d ctx=%q", tag, i, code:sub(math.max(1,i-30), i+30))); io.flush() end

local vm_blocks = {}
local block_idx = 1
local function extract_vm_blocks(src)
  local result = {}
  local pos = 1
  local len = #src
  local iters = 0
  while pos <= len do
    iters = iters + 1
    if iters > 100000 then report("EXTRACT", pos); return table.concat(result) end
    local prev = pos
    local marker_start = src:find("-- @vm %(protected%)", pos, true)
    if not marker_start then
      result[#result + 1] = src:sub(pos)
      break
    end
    if marker_start > pos then
      result[#result + 1] = src:sub(pos, marker_start - 1)
    end
    local block_end = src:find("\n-- @", marker_start + 1)
    if not block_end then block_end = len + 1 end
    local vm_code = src:sub(marker_start, block_end - 1)
    local placeholder = "__VM_BLOCK_" .. block_idx .. "__"
    vm_blocks[placeholder] = vm_code
    result[#result + 1] = "\n" .. placeholder .. "\n"
    block_idx = block_idx + 1
    pos = block_end
    if pos == prev then report("EXTRACT-STUCK", pos); break end
  end
  print("  extract_vm_blocks iters:", iters, "blocks:", block_idx - 1)
  return table.concat(result)
end

print("extract_vm_blocks..."); io.flush()
local extracted = extract_vm_blocks(code)
print("extracted length:", #extracted); io.flush()

-- Now simulate rename doing nothing, then restore
local function restore_vm_blocks(c)
  for placeholder, vm_code in pairs(vm_blocks) do
    print("  restoring", placeholder, "vm_code len", #vm_code); io.flush()
    local before = #c
    c = c:gsub(placeholder, vm_code)
    print("  gsub done, len", before, "->", #c); io.flush()
  end
  return c
end

print("restore_vm_blocks..."); io.flush()
local restored = restore_vm_blocks(extracted)
print("restored length:", #restored); io.flush()
print("done")
