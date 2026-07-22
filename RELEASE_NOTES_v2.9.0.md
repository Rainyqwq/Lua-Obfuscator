# v2.9.0 Release Notes

## Release Date: 2026-07-23

## New Features

### Anti-Debug Detection (反调试检测)
A new pass that detects and prevents debugging attempts:

- **Debug Hook Detection**: Checks if debug.gethook() returns a hook function
- **Timing Anomaly Detection**: Detects execution time anomalies (debugging slows execution)
- **JIT Status Check**: Detects if LuaJIT JIT compiler is disabled

When debugging is detected, the obfuscated code will terminate with an error.

### Function Call Indirection (函数调用间接化)
A new pass that redirects global function calls through a dispatch table:

- Creates a call table (e.g., `CT_123456`) containing all global functions
- Replaces direct function calls with indirect calls (e.g., `foo()` → `CT_123456.foo()`)
- Adds an indirection layer that increases reverse engineering difficulty

## Usage

Enable anti-debug detection:
```lua
pm:set_enabled("anti_debug", true)
```

Enable function call indirection:
```lua
pm:set_enabled("call_indirection", true)
```

## Changes
- Added `passes/anti_debug.lua` - Anti-debugging detection pass
- Added `passes/call_indirect.lua` - Function call indirection pass
