// Bakes a snippet body into the form the game receives.
//
// Two tools need this. `check-snippet-golden.js` locks the bytes a shipped build gets;
// `check-snippets.js` parses those same bytes. They have to bake identically or one of them is
// guarding a body that never exists.
//
// Both stages come out of `Snippets.lua` itself, called through fengari. Rewriting the rules in
// JavaScript would be a second copy that can drift, and a drifted copy silently guards something
// other than what gets baked.
const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const srcDir = path.join(__dirname, "..", "..", "Debind");

/**
 * `Snippets.lua`를 fengari에 올리고 그 안의 함수를 그대로 쓴다.
 *
 * `Constants`는 빈 테이블로 충분하다 - 여기서 부르는 것들은 상수 값을 안 본다. `BakeSnippet`
 * 전체를 부르지 않는 이유이기도 하다(그쪽은 진짜 상수가 필요하다).
 */
function loadSnippetsLua() {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);

    if (lauxlib.luaL_loadfile(L, to_luastring(path.join(srcDir, "Snippets.lua"))) !== lua.LUA_OK) {
        throw new Error(`Snippets.lua 로드 실패: ${lua.lua_tojsstring(L, -1)}`);
    }

    // `local _, DebindPrivate = ...` 규약대로 두 인자를 넘긴다.
    lua.lua_pushstring(L, to_luastring("Debind"));
    lua.lua_newtable(L);
    lua.lua_newtable(L);
    lua.lua_setfield(L, -2, to_luastring("Constants"));
    lua.lua_pushvalue(L, -1);
    lua.lua_setglobal(L, to_luastring("__private"));

    if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK) {
        throw new Error(`Snippets.lua 실행 실패: ${lua.lua_tojsstring(L, -1)}`);
    }

    // `BakeSnippet`에서 상수 치환만 빼낸 것. 이름이 틀리면 게임에서 `assert`가 죽인다.
    lauxlib.luaL_dostring(L, to_luastring(`
        local P = __private
        function __bakeLive(body)
            return P.applyProbesForTools(P.StripSnippetComments(body), P.SNIPPET_PROBES_LIVE)
        end
    `));

    return (body) => {
        lua.lua_getglobal(L, to_luastring("__bakeLive"));
        lua.lua_pushstring(L, to_luastring(body));
        if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) {
            const err = lua.lua_tojsstring(L, -1);
            lua.lua_pop(L, 1);
            throw new Error(err);
        }
        const out = to_jsstring(lua.lua_tostring(L, -1));
        lua.lua_pop(L, 1);
        return out;
    };
}

/**
 * 주석 제거 → 프로브 치환. **`CONSTANTS.*` 치환은 안 한다** - 그 값은 `Constants`가 실제로
 * 실려 있어야 나오고, 부르는 쪽 둘 다 상수 값에는 관심이 없다. 검사는 그 자리를 문법상 올 수
 * 있는 것으로 메우고, 골든은 토큰 그대로 박제한다.
 *
 * 배포 갈래에서 값이 `false`인 프로브는 **호출이 통째로 사라진다.** 원문에서 멀쩡하던
 * `local x = PROBE.Winner(i)`가 `local x = `가 되는 자리라, 여기를 통과한 본문만 게임에서
 * 컴파일된다고 말할 수 있다.
 */
const bakeLive = loadSnippetsLua();

module.exports = { bakeLive };
