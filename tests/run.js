// lua 바이너리 없이 테스트를 돌리기 위한 fengari 러너.
//   npm install fengari && node tests/run.js
// CI는 tests/run.lua를 진짜 lua로 직접 실행한다.

const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const testsDir = __dirname.replace(/\\/g, "/");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// arg[0]을 run.lua의 실제 경로로 채워서 run.lua가 저장소 루트를 찾게 한다.
// arg[1..]은 명령줄 그대로 - `--bench`와 `--update-golden`이 이 길로 온다.
lua.lua_newtable(L);
lua.lua_pushstring(L, to_luastring(`${testsDir}/run.lua`));
lua.lua_rawseti(L, -2, 0);
process.argv.slice(2).forEach((value, index) => {
    lua.lua_pushstring(L, to_luastring(value));
    lua.lua_rawseti(L, -2, index + 1);
});
lua.lua_setglobal(L, to_luastring("arg"));

// **fengari has no `io.open`.** It gives `io.write` and nothing that opens a file, so the emission
// golden -- which is a file the specs read and sometimes rewrite -- has no way through the standard
// library here. These two hand that back, and `run.lua` prefers `io.open` where there is one, so a
// real interpreter never touches them.
//
// Bytes go across as bytes. `to_luastring` would re-encode, and the golden carries the Korean
// comments that are inside the snippet bodies -- a round trip through a JS string is a place for
// that to change without anybody asking.
lua.lua_pushjsfunction(L, (state) => {
    const file = lua.lua_tojsstring(state, 1);
    let contents;
    try {
        contents = fs.readFileSync(file);
    } catch (err) {
        lua.lua_pushnil(state);
        lua.lua_pushstring(state, to_luastring(String(err.message)));
        return 2;
    }
    lua.lua_pushstring(state, new Uint8Array(contents));
    return 1;
});
lua.lua_setglobal(L, to_luastring("__hostReadFile"));

lua.lua_pushjsfunction(L, (state) => {
    const file = lua.lua_tojsstring(state, 1);
    fs.writeFileSync(file, Buffer.from(lua.lua_tostring(state, 2)));
    return 0;
});
lua.lua_setglobal(L, to_luastring("__hostWriteFile"));

const status = lauxlib.luaL_dofile(L, to_luastring(path.join(__dirname, "run.lua")));
if (status !== lua.LUA_OK) {
    const err = lua.lua_tojsstring(L, -1);
    process.stderr.write(`${err}\n`);
    process.exit(1);
}
