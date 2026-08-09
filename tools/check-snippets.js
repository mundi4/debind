// 보안 스니펫 본문의 구문 검사.
//
// 스니펫은 Lua 소스지만 **파일 안에서는 문자열**이다. luacheck은 문자열 안을 안 보므로
// 안쪽 문법 오류가 하나도 안 걸린다. 그리고 그건 조용히 실패한다 - 제한 환경이 본문을
// 컴파일하지 못하면 그 스니펫이 아예 안 걸리고, 증상은 "그 키만 안 먹는다"로 나타난다.
// 게임을 켜야만 알 수 있는 종류라 여기서 미리 잡는다.
//
// **앵커 목록을 손으로 관리하지 않는다.** 호출 형태로 자동 수집한다 - 목록 방식은 새
// 스니펫을 추가할 때 등록을 잊으면 조용히 검사에서 빠지고, 그게 정확히 이 도구가 막으려던
// 실패 방식이다.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const root = path.join(__dirname, "..");
const srcDir = path.join(root, "Debind");

// 인자에 스니펫 본문이 오는 호출들.
const CALLS = /\b(SecureHandlerExecute|SecureHandlerWrapScript|SetAttribute)\s*\(/g;

// `local X_SNIPPET = ... [[본문]] ... or ""` 꼴. 스니펫이 조각으로 나뉠 때 쓰는 관용구라
// (DEBUG 빌드에서만 들어가는 부분) 참조를 풀어서 결합된 형태도 같이 본다.
const SNIPPET_LOCAL = /\blocal\s+([A-Za-z_][\w]*_SNIPPET)\s*=/g;

/** 위치 i에서 시작하는 긴 문자열을 뗀다. 아니면 null. */
function readLongString(src, i) {
    if (src[i] !== "[") return null;
    let j = i + 1;
    while (src[j] === "=") j++;
    if (src[j] !== "[") return null;
    const level = j - i - 1;
    let body = j + 1;
    // 여는 대괄호 바로 뒤의 줄바꿈 하나는 본문에 안 들어간다(Lua 규칙).
    if (src[body] === "\r") body++;
    if (src[body] === "\n") body++;
    const close = "]" + "=".repeat(level) + "]";
    const end = src.indexOf(close, body);
    if (end < 0) return null;
    return { body: src.slice(body, end), next: end + close.length };
}

/**
 * 호출의 여는 괄호부터 짝이 맞는 닫는 괄호까지 훑으며 인자에 실린 본문들을 모은다.
 * 주석·따옴표 문자열·중첩 괄호를 건너뛰는 작은 스캐너다. 정규식으로는 긴 문자열 안의
 * 괄호와 진짜 괄호를 못 가른다.
 *
 * **인자 하나가 본문 하나다.** `..`로 이어진 조각은 한 본문으로 합치고, 인자를 가르는
 * 쉼표에서는 끊는다. `SecureHandlerWrapScript`는 preBody와 postBody를 따로 받으므로
 * 안 끊으면 둘을 이어붙인 엉뚱한 소스를 검사하게 된다.
 */
function collectBodies(src, openParen, snippetLocals) {
    const bodies = [];
    let parts = [];
    let depth = 1;
    let i = openParen + 1;

    const flush = () => {
        if (parts.length) bodies.push(parts);
        parts = [];
    };

    while (i < src.length && depth > 0) {
        const two = src.substr(i, 2);

        if (two === "--") {
            const long = readLongString(src, i + 2);
            if (long) { i = long.next; continue; }
            const nl = src.indexOf("\n", i);
            i = nl < 0 ? src.length : nl + 1;
            continue;
        }

        const long = readLongString(src, i);
        if (long) {
            parts.push({ literal: long.body });
            i = long.next;
            continue;
        }

        const c = src[i];
        if (c === '"' || c === "'") {
            i++;
            while (i < src.length && src[i] !== c) {
                i += src[i] === "\\" ? 2 : 1;
            }
            i++;
            continue;
        }

        if (c === "(") { depth++; i++; continue; }
        if (c === ")") { depth--; i++; continue; }
        if (c === "," && depth === 1) { flush(); i++; continue; }

        const ident = /^[A-Za-z_][\w]*/.exec(src.slice(i));
        if (ident) {
            if (snippetLocals.has(ident[0])) parts.push({ ref: ident[0] });
            i += ident[0].length;
            continue;
        }

        i++;
    }

    flush();
    return bodies;
}

/** 형식 지정자별 대역. 자리만 맞으면 되므로 문법상 그 자리에 올 수 있는 것으로 채운다. */
const FORMAT_FILL = { d: "0", i: "0", o: "0", x: "0", X: "0", q: '"S"', s: "_S" };

/**
 * 실행 전 치환되는 자리들을 메운다.
 *   CONSTANTS.X  applyConstants가 값으로 바꿔 넣는다
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

// 문자열과 주석을 지운다. 아래 토큰 검사가 본문 안의 색 코드("|cffff6666")를 비트 연산으로
// 오해하지 않게 하려는 것이다.
function stripStringsAndComments(src) {
    let out = "";
    let i = 0;
    while (i < src.length) {
        if (src.substr(i, 2) === "--") {
            const long = readLongString(src, i + 2);
            if (long) { i = long.next; continue; }
            const nl = src.indexOf("\n", i);
            i = nl < 0 ? src.length : nl;
            continue;
        }
        const long = readLongString(src, i);
        if (long) { i = long.next; continue; }
        const c = src[i];
        if (c === '"' || c === "'") {
            i++;
            while (i < src.length && src[i] !== c) i += src[i] === "\\" ? 2 : 1;
            i++;
            continue;
        }
        out += c;
        i++;
    }
    return out;
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
    const code = stripStringsAndComments(source);
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

const files = fs.readdirSync(srcDir).filter((f) => f.endsWith(".lua")).sort();
let checked = 0;
let failed = 0;

for (const file of files) {
    const src = fs.readFileSync(path.join(srcDir, file), "utf8");

    // 1. 조각으로 쓰이는 스니펫 지역변수를 먼저 모은다.
    const snippetLocals = new Map();
    SNIPPET_LOCAL.lastIndex = 0;
    let m;
    while ((m = SNIPPET_LOCAL.exec(src))) {
        const long = (() => {
            for (let i = m.index + m[0].length; i < src.length; i++) {
                const s = readLongString(src, i);
                if (s) return s;
                if (src[i] === "\n" && src.slice(m.index, i).includes(";")) return null;
            }
            return null;
        })();
        if (long) snippetLocals.set(m[1], long.body);
    }

    // 2. 호출마다 본문을 모아 파싱한다.
    CALLS.lastIndex = 0;
    while ((m = CALLS.exec(src))) {
        const openParen = m.index + m[0].length - 1;
        const line = src.slice(0, m.index).split("\n").length;

        for (const parts of collectBodies(src, openParen, snippetLocals)) {
            if (!parts.some((p) => p.literal !== undefined)) continue;

            const name = `${file}:${line} ${m[1]}`;

            // 참조가 섞여 있으면 **양쪽 다** 본다. 릴리스 빌드에서는 그 자리가 빈 문자열이
            // 되므로 결합 지점이 달라지고, 한쪽에서만 나는 오류가 실제로 있을 수 있다.
            const hasRef = parts.some((p) => p.ref !== undefined);
            const variants = hasRef
                ? [["DEBUG=on", (p) => (p.ref ? snippetLocals.get(p.ref) : p.literal)],
                   ["DEBUG=off", (p) => (p.ref ? "" : p.literal)]]
                : [["", (p) => p.literal]];

            for (const [label, pick] of variants) {
                checked++;
                const where = `${name}${label ? ` (${label})` : ""}`;
                const source = fillPlaceholders(parts.map(pick).join(""));

                const err = syntaxError(source, name);
                if (err) {
                    console.log(`${where}\n    ${err}`);
                    failed++;
                    continue;
                }

                const violation = lua51Violation(source);
                if (violation) {
                    console.log(`${where}\n    5.1에 없는 문법: ${violation}`);
                    failed++;
                }
            }
        }
    }
}

console.log(failed === 0
    ? `보안 스니펫 ${checked}개 전부 파싱된다.`
    : `보안 스니펫 ${failed}개 실패.`);
process.exit(failed === 0 ? 0 : 1);
