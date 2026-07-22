-- 85项综合验证测试
local pass, fail = 0, 0
local function t(name, expected, actual)
  if expected == actual then pass = pass + 1
  else fail = fail + 1
    io.write(string.format("  FAIL %s: expected=[%s] actual=[%s]\n", name, tostring(expected), tostring(actual)))
  end
end

t("add", 7, 1+2*3); t("sub", 7, 10-3); t("mul", 20, 4*5)
t("mod", 2, 17%5); t("pow", 1024, 2^10); t("idiv", 3, 17//5)
t("neg", -32, -42+10); t("float_add", true, math.abs(0.1+0.2-0.3) < 1e-6)
t("float_mul", true, math.abs(3.14*2 - 6.28) < 0.001)
t("band", 15, 0xFF & 0x0F); t("bor", 255, 0xF0 | 0x0F)
t("bxor", 240, 0xFF ~ 0x0F); t("shl", 256, 1 << 8)
t("shr", 16, 256 >> 4); t("bnot", -1, ~0)
t("concat", "hello world", "hello" .. " " .. "world")
t("len", 5, #"hello"); t("sub_s", "ell", string.sub("hello", 2, 4))
t("rep", "ababab", string.rep("ab", 3))
t("upper", "HI", string.upper("hi")); t("lower", "hi", string.lower("HI"))
t("find", 7, string.find("hello world", "world"))
t("format", "0042", string.format("%04d", 42))
t("byte", 65, string.byte("A")); t("char", "A", string.char(65))
t("gsub", "herro", string.gsub("hello", "l", "r"))
t("match", "123", string.match("abc123", "%d+"))
t("chinese", "你好世界", "你好" .. "世界")
t("mixed", "Hello你好", "Hello" .. "你好")
t("true", true, true); t("false", false, false); t("nil", nil, nil)
t("and", 42, true and 42); t("or", 99, false or 99)
t("not", true, not false); t("dnot", true, not not 1)
t("eq", true, 1 == 1); t("neq", true, 1 ~= 2)
t("lt", true, 1 < 2); t("gt", true, 3 > 2)
t("le", true, 2 <= 2); t("ge", true, 3 >= 2)
local x = 10; t("local", 10, x)
local a, b = 1, 2; t("multi", 3, a + b)
x = 20; t("reassign", 20, x)
do local x = 99 end; t("scope", 20, x)
if true then t("if_t", 1, 1) else t("if_t", 0, 0) end
if false then t("if_f", 0, 0) else t("if_f", 2, 2) end
if false then t("eif", 0, 0) elseif true then t("eif", 2, 2) else t("eif", 3, 3) end
local s = 0; for i = 1, 10 do s = s + i end; t("for", 55, s)
s = 0; for i = 0, 10, 2 do s = s + i end; t("fstep", 30, s)
s = 0; local wi = 1; while wi <= 10 do s = s + wi; wi = wi + 1 end; t("while", 55, s)
s = 0; local ri = 0; repeat ri = ri + 1; s = s + ri until ri >= 10; t("repeat", 55, s)
local br = 0; for i = 1, 100 do if i > 5 then br = i; break end end; t("break", 6, br)
local function fib(n) if n<=1 then return n end; local a,b=0,1; for i=2,n do a,b=b,a+b end; return b end
t("fib", 6765, fib(20))
local function make_adder(x) return function(y) return x+y end end
t("closure", 42, make_adder(10)(32))
local function counter() local n=0; return function() n=n+1; return n end end
local c = counter(); c(); c(); c(); t("ctr", 4, c())
local function sum(...) local r=0; for _,v in ipairs({...}) do r=r+v end; return r end
t("varargs", 15, sum(1,2,3,4,5))
local tbl = {a=1, b=2, c=3}; t("tbl", 6, tbl.a+tbl.b+tbl.c)
local arr = {10, 20, 30}; t("arr", 20, arr[2]); t("tlen", 3, #arr)
local ts = 0; for _,v in pairs(tbl) do ts = ts + v end; t("pairs", 6, ts)
ts = 0; for _,v in ipairs(arr) do ts = ts + v end; t("ipairs", 60, ts)
t("abs", 42, math.abs(-42)); t("max", 3, math.max(1,3,2))
t("min", 1, math.min(1,3,2)); t("floor", 3, math.floor(3.7))
t("ceil", 4, math.ceil(3.2)); t("sqrt", 12, math.floor(math.sqrt(144)))
local ti = {}; table.insert(ti,1); table.insert(ti,2); t("ins", 2, #ti)
t("tconcat", "a,b,c", table.concat({"a","b","c"}, ","))
local ts2 = {3,1,2}; table.sort(ts2); t("sort", 1, ts2[1])
t("type_n", "number", type(42)); t("type_s", "string", type("hi"))
t("type_t", "table", type({})); t("type_f", "function", type(print))
t("type_nil", "nil", type(nil))
t("tostr", "42", tostring(42)); t("tonum", 42, tonumber("42"))
local function qpow(a,n) local r=1; while n>0 do if n%2==1 then r=r*a end; a=a*a; n=n//2 end; return r end
t("qpow", 1024, qpow(2,10))
local bub = {5,3,1,4,2}
for i=1,#bub do for j=1,#bub-i do if bub[j]>bub[j+1] then bub[j],bub[j+1]=bub[j+1],bub[j] end end end
t("bubble", "12345", bub[1]..bub[2]..bub[3]..bub[4]..bub[5])

print(string.format("\n结果: %d/%d 通过, %d 失败", pass, pass+fail, fail))
