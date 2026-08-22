// Bakes a snippet body into the form the game receives.
//
// Three tools need this. `check-snippet-golden.js` locks the bytes a shipped build gets;
// `check-snippets.js` parses those same bytes; `check-state-eval.js` reads a baked body back to
// see that the press path measures each state the way the poll path does. They have to bake
// identically or one of them is guarding a body that never exists.
//
// Every stage comes out of `Snippets.lua` itself, called through fengari. Rewriting the rules in
// JavaScript would be a second copy that can drift, and a drifted copy silently guards something
// other than what gets baked.
const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const srcDir = path.join(__dirname, "..", "..", "Debind");

/** Runs one addon file, handing it the two arguments `local _, DebindPrivate = ...` expects. */
function runAddonFile(L, file, pushPrivate) {
    if (lauxlib.luaL_loadfile(L, to_luastring(path.join(srcDir, file))) !== lua.LUA_OK) {
        throw new Error(`${file} 로드 실패: ${lua.lua_tojsstring(L, -1)}`);
    }
    lua.lua_pushstring(L, to_luastring("Debind"));
    pushPrivate();
    if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK) {
        throw new Error(`${file} 실행 실패: ${lua.lua_tojsstring(L, -1)}`);
    }
}

/** `luaL_dostring` that does not swallow the failure. Everything run through it is written here. */
function dostring(L, source) {
    if (lauxlib.luaL_dostring(L, to_luastring(source)) !== lua.LUA_OK) {
        throw new Error(`shim 실행 실패: ${lua.lua_tojsstring(L, -1)}`);
    }
}

/**
 * Puts `Snippets.lua` in a fengari state and uses its functions as they are.
 *
 * An empty `Constants` is enough here: nothing this state calls looks at a constant's value. That
 * is also why it does not call `BakeSnippet` itself, which does need the real ones -- see
 * `loadWithConstants` below.
 */
function loadSnippetsOnly() {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);

    runAddonFile(L, "Snippets.lua", () => {
        lua.lua_newtable(L);
        lua.lua_newtable(L);
        lua.lua_setfield(L, -2, to_luastring("Constants"));
        lua.lua_pushvalue(L, -1);
        lua.lua_setglobal(L, to_luastring("__private"));
    });

    // `BakeSnippet`에서 상수 치환만 빼낸 것. 이름이 틀리면 게임에서 `assert`가 죽인다.
    dostring(L, `
        local P = __private
        function __bakeLive(body)
            return P.applyProbesForTools(P.StripSnippetComments(body), P.SNIPPET_PROBES_LIVE)
        end
    `);

    return L;
}

// What `Constants.lua` reads from the client while it loads.
//
// **None of these is a rule of ours.** They are the client's own values, so a wrong one here is a
// lie rather than a drift, and there is nothing in the repo to compare it against. Take them from
// `reference/wow-ui-source/` when adding one.
//
// A metatable on `_G` does not guard the list, deliberately: the file also *tests* for globals it
// expects to be absent (`_G.DevTool`), so raising on a nil read would be raising on the normal
// case. A missing one fails the load below by name instead, or leaves a constant nil that
// `constantStringTable` refuses.
const WOW_GLOBALS = `
    format = string.format
    tremove = table.remove
    MAX_PARTY_MEMBERS = 4
    MAX_RAID_MEMBERS = 40
    MAX_ARENA_ENEMIES = 5
    UnitClass = function() return "Warrior", "WARRIOR", 1 end
    -- The class table Constants.lua builds at load (CLASS_IDS). One real answer is enough:
    -- nothing baked reads that table, and what the loop needs is a call that does not raise and
    -- a range that ends.
    C_CreatureInfo = {
        GetClassInfo = function(classID)
            if classID == 1 then return { classFile = "WARRIOR" } end
            return nil
        end,
    }
`;

// **WoW is Lua 5.1 and fengari is 5.3.** `BakeSnippet` writes a constant out with `tostring`,
// and under 5.3 `2 ^ 2` is a float, so `Constants.GROUP_RAID` comes out as "4.0" where the game
// says "4". What this state bakes has to be the bytes the game receives, so numbers are put back
// to 5.1's format (`%.14g`).
//
// Only this state needs it. Nothing `bakeLive` does renders a number at all.
const LUA51_NUMBERS = `
    local rawtostring = tostring
    tostring = function(v)
        if type(v) == "number" then return string.format("%.14g", v) end
        return rawtostring(v)
    end
`;

/**
 * A second state, with `Constants.lua` really loaded, so `BakeSnippet` itself can run -- the
 * `CONSTANTS.*` substitution included.
 *
 * That substitution is exactly what `bakeLive` above leaves undone, and on purpose: the golden
 * locks those places as tokens rather than as values, so that editing one constant does not shake
 * every body it appears in. Comparing measurements is the other way round. It only means anything
 * once the values are in, because `Constants.STATE_EVAL_EXPRESSIONS` holds strings with the
 * numbers already interpolated.
 */
function loadWithConstants() {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    dostring(L, WOW_GLOBALS);
    dostring(L, LUA51_NUMBERS);

    const pushPrivate = () => {
        lua.lua_getglobal(L, to_luastring("__private"));
    };
    lua.lua_newtable(L);
    lua.lua_setglobal(L, to_luastring("__private"));

    // The order is not free: `Snippets.lua` takes `DebindPrivate.Constants` as a local at load.
    runAddonFile(L, "Constants.lua", pushPrivate);
    runAddonFile(L, "Snippets.lua", pushPrivate);

    return L;
}

const liveState = loadSnippetsOnly();

// Built on first use. A tool that never asks for a constant has no reason to die with a
// `Constants.lua` that failed to load.
let constantsState = null;
function withConstants() {
    constantsState = constantsState || loadWithConstants();
    return constantsState;
}

/**
 * Calls the function already on the stack with one string and takes one string back.
 *
 * `extraPops` is whatever the caller left underneath it -- both paths out of here have to clear
 * the same amount, and a state that keeps a little rubbish per call grows for the whole run.
 */
function callStringToString(L, extraPops, body) {
    lua.lua_pushstring(L, to_luastring(body));
    if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) {
        const err = lua.lua_tojsstring(L, -1);
        lua.lua_pop(L, 1 + extraPops);
        throw new Error(err);
    }
    const out = to_jsstring(lua.lua_tostring(L, -1));
    lua.lua_pop(L, 1 + extraPops);
    return out;
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
function bakeLive(body) {
    lua.lua_getglobal(liveState, to_luastring("__bakeLive"));
    return callStringToString(liveState, 0, body);
}

/** What the game actually receives: `BakeSnippet` itself, `CONSTANTS.*` turned into values. */
function bakeShipped(body) {
    const L = withConstants();
    lua.lua_getglobal(L, to_luastring("__private"));
    lua.lua_getfield(L, -1, to_luastring("BakeSnippet"));
    return callStringToString(L, 1, body);
}

/**
 * Reads one of `Constants`' string tables out as it stands.
 *
 * Folded onto tab and newline and fetched in one go. Walking a table through fengari's stack API
 * is a lot of code for one table, and what is read here is single-line expressions, so there is
 * no fold to land inside a value.
 */
function constantStringTable(name) {
    const L = withConstants();
    const quoted = JSON.stringify(name);
    dostring(L, `
        local t = __private.Constants[${quoted}]
        assert(t, "no such constant table: " .. ${quoted})
        local out = {}
        for k, v in pairs(t) do
            assert(type(v) == "string", ${quoted} .. "." .. k .. " is not a string")
            out[#out + 1] = k .. string.char(9) .. v
        end
        table.sort(out)
        __constantTable = table.concat(out, string.char(10))
    `);

    lua.lua_getglobal(L, to_luastring("__constantTable"));
    const dump = to_jsstring(lua.lua_tostring(L, -1));
    lua.lua_pop(L, 1);

    const out = {};
    if (dump.length === 0) return out;
    for (const row of dump.split("\n")) {
        const at = row.indexOf("\t");
        out[row.slice(0, at)] = row.slice(at + 1);
    }
    return out;
}

module.exports = { bakeLive, bakeShipped, constantStringTable };
