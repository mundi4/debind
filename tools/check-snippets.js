// 보안 스니펫 본문의 구문 검사.
//
// 스니펫은 Lua 소스지만 **파일 안에서는 문자열**이다. luacheck은 문자열 안을 안 보므로
// 안쪽 문법 오류가 하나도 안 걸린다. 그리고 그건 조용히 실패한다 - 제한 환경이 본문을
// 컴파일하지 못하면 그 스니펫이 아예 안 걸리고, 증상은 "그 키만 안 먹는다"로 나타난다.
// 게임을 켜야만 알 수 있는 종류라 여기서 미리 잡는다.
//
// 본문을 떼어내는 부분은 `lib/snippets.js`에 있다 - 구워진 결과를 잠그는
// `check-snippet-golden.js`와 같은 것을 봐야 한다.
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const { blankNonCode, forEachSnippet } = require("./lib/snippets");

const root = path.join(__dirname, "..");
const srcDir = path.join(root, "Debind");

/** 형식 지정자별 대역. 자리만 맞으면 되므로 문법상 그 자리에 올 수 있는 것으로 채운다. */
const FORMAT_FILL = { d: "0", i: "0", o: "0", x: "0", X: "0", q: '"S"', s: "_S" };

/**
 * 실행 전 치환되는 자리들을 메운다.
 *   CONSTANTS.X  BakeSnippet이 값으로 바꿔 넣는다
 *   %d %q %s ..  format()으로 조립되는 본문
 *
 * 지정자 뒤에 변환 문자가 바로 붙은 것만 본다. 나머지 연산자(`t.groups % (a + b)`)를
 * 건드리지 않기 위해서다.
 */
function fillPlaceholders(body) {
    return body
        .replace(/CONSTANTS\.[\w]+/g, '"C"')
        .replace(/%(?:\d+\$)?([dioxXqs])/g, (_, conv) => FORMAT_FILL[conv]);
}

// **와우는 Lua 5.1이고 이 도구의 파서(fengari)는 5.3이다.** 5.2/5.3에서 들어온 문법은
// 여기서는 멀쩡히 파싱되고 게임에서만 깨진다 - 증상은 "그 스니펫이 통째로 안 걸린다"라
// 진단이 어렵다. 특히 제한 환경에는 `bit` 라이브러리가 없어서(기존 코드가 나머지 연산으로
// 비트를 흉내내는 이유다) 비트 연산자로 손이 가기 쉽다.
const LUA51_FORBIDDEN = [
    [/(^|[^\w.:])goto[\s(]/, "goto (5.2+)"],
    [/::\s*[A-Za-z_]\w*\s*::/, "라벨 :: :: (5.2+)"],
    [/\/\//, "정수 나눗셈 // (5.3+)"],
    [/<<|>>/, "비트 이동 << >> (5.3+)"],
    [/&/, "비트 and & (5.3+). 제한 환경에는 bit 라이브러리가 없다 - 나머지 연산을 쓸 것"],
    [/\|/, "비트 or | (5.3+). 위와 같다"],
    [/~[^=]/, "비트 not/xor ~ (5.3+). ~= 는 5.1에도 있다"],
];

function lua51Violation(source) {
    const code = blankNonCode(source);
    for (const [re, why] of LUA51_FORBIDDEN) {
        if (re.test(code)) return why;
    }
    return null;
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

/** 구문만 본다. 실행하지 않는다. */
function syntaxError(source, name) {
    const status = lauxlib.luaL_loadbuffer(L, to_luastring(source), null, to_luastring("@" + name));
    if (status === lua.LUA_OK) {
        lua.lua_pop(L, 1);
        return null;
    }
    const err = lua.lua_tojsstring(L, -1);
    lua.lua_pop(L, 1);
    return err;
}

let checked = 0;
let failed = 0;

forEachSnippet(srcDir, ({ file, line, call, label, body }) => {
    checked++;
    const name = `${file}:${line} ${call}`;
    const where = `${name}${label ? ` (${label})` : ""}`;
    const source = fillPlaceholders(body);

    const err = syntaxError(source, name);
    if (err) {
        console.log(`${where}\n    ${err}`);
        failed++;
        return;
    }

    const violation = lua51Violation(source);
    if (violation) {
        console.log(`${where}\n    5.1에 없는 문법: ${violation}`);
        failed++;
    }
});

console.log(failed === 0
    ? `보안 스니펫 ${checked}개 전부 파싱된다.`
    : `보안 스니펫 ${failed}개 실패.`);

if (failed > 0) process.exit(1);
