// lua 바이너리 없이 테스트를 돌리기 위한 fengari 러너.
//   npm install fengari && node tests/run.js
// CI는 tests/run.lua를 진짜 lua로 직접 실행한다.

const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const testsDir = __dirname.replace(/\\/g, "/");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// arg[0]을 run.lua의 실제 경로로 채워서 run.lua가 저장소 루트를 찾게 한다.
lua.lua_newtable(L);
lua.lua_pushstring(L, to_luastring(`${testsDir}/run.lua`));
lua.lua_rawseti(L, -2, 0);
lua.lua_setglobal(L, to_luastring("arg"));

const status = lauxlib.luaL_dofile(L, to_luastring(path.join(__dirname, "run.lua")));
if (status !== lua.LUA_OK) {
    const err = lua.lua_tojsstring(L, -1);
    process.stderr.write(`${err}\n`);
    process.exit(1);
}
