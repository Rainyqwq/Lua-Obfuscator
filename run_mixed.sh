#!/bin/bash
cd /home/work/.openclaw/workspace/lua-obfuscator
TOTAL=0; PASS=0; FAIL=0; FAILURES=""

run_test() {
  local label="$1"; shift
  ./lua obfuscator.lua -i test_85.lua -o /tmp/t_mixed.lua "$@" 2>/dev/null
  if [ $? -ne 0 ]; then TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); printf "  %-25s: ❌ compile error\n" "$label"; return; fi
  result=$(./lua /tmp/t_mixed.lua 2>&1)
  if echo "$result" | grep -q "81/81"; then TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); printf "  %-25s: ✅ 81/81\n" "$label"
  else TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); printf "  %-25s: ❌\n" "$label"; fi
}

echo "--- 单技术 ---"
run_test "var" --no-num --no-str --no-cfe --no-bcf --no-instr --no-advbcf --no-bbsplit --no-junk
run_test "num" --no-var --no-str --no-cfe --no-bcf --no-instr --no-advbcf --no-bbsplit --no-junk
run_test "str" --no-var --no-num --no-cfe --no-bcf --no-instr --no-advbcf --no-bbsplit --no-junk
run_test "cfe" --no-var --no-num --no-str --no-bcf --no-instr --no-advbcf --no-bbsplit --no-junk
run_test "bcf" --no-var --no-num --no-str --no-cfe --no-instr --no-advbcf --no-bbsplit --no-junk
run_test "instr" --no-var --no-num --no-str --no-cfe --no-bcf --no-advbcf --no-bbsplit --no-junk
run_test "ALL" 
echo ""
echo "总计: $TOTAL 测试, $PASS 通过, $FAIL 失败"
