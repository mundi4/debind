// 보안 스니펫 본문의 구문 검사.
//
// 스니펫은 Lua 소스지만 **파일 안에서는 문자열**이다. luacheck은 문자열 안을 안 보므로
// 안쪽 문법 오류가 하나도 안 걸린다. 그리고 그건 조용히 실패한다 - 제한 환경이 본문을
// 컴파일하지 못하면 그 스니펫이 아예 안 걸리고, 증상은 "그 키만 안 먹는다"로 나타난다.
// 게임을 켜야만 알 수 있는 종류라 여기서 미리 잡는다.
//
// 본문을 떼어내는 부분은 `lib/snippets.js`에, 굽는 부분은 `lib/bake.js`에 있다 - 구워진
// 결과를 잠그는 `check-snippet-golden.js`와 같은 것을 봐야 한다.
const path = require("path");
const { blankNonCode, forEachSnippet } = require("./lib/snippets");
const { bakeLive } = require("./lib/bake");
const { runLuaDriver } = require("./lib/lua51");

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

// **The parser above is the game's 5.1, so it already refuses every one of these.** What it says
// is `unexpected symbol near '&'`, which names the character and stops there. These lines are for
// the message: which version the syntax arrived in, and -- for the bit operators, the ones a hand
// reaches for -- that the restricted environment has no `bit` library, which is why the code
// around them fakes bits with modulo.
const LUA51_FORBIDDEN = [
    [/(^|[^\w.:])goto[\s(]/, "goto (5.2+)"],
    [/::\s*[A-Za-z_]\w*\s*::/, "라벨 :: :: (5.2+)"],
    [/\/\//, "정수 나눗셈 // (5.3+)"],
    [/<<|>>/, "비트 이동 << >> (5.3+)"],
    [/&/, "비트 and & (5.3+). 제한 환경에는 bit 라이브러리가 없다 - 나머지 연산을 쓸 것"],
    [/\|/, "비트 or | (5.3+). 위와 같다"],
    [/~[^=]/, "비트 not/xor ~ (5.3+). ~= 는 5.1에도 있다"],
];

// **What the restricted environment checks against the raw body.** `BuildRestrictedClosure`
// (`Blizzard_RestrictedAddOnEnvironment/RestrictedExecution.lua:58`) runs a plain `body:match`
// substring test -- the one Blizzard's own comment calls "overzealous but it keeps it simple".
// **A hit inside a comment, or inside a longer word, counts.**
//
// So the checks below read the **raw** body, not the one `blankNonCode` has been through.
// Stripping comments first would pass things the game rejects.
//
// A hit means that whole snippet never attaches, and if it is the bootstrap then globals like
// `ccframes` and `DirtyFlags` are never created -- which surfaces **much later, at an unrelated
// line**, as "attempt to index a nil value".
//
// This actually happened (2026-08-12). Wrapping the unit condition checks in a function tripped
// it, and after the function was gone **one word left in a comment** kept tripping it.
const RESTRICTED_FORBIDDEN = [
    [/function/, "`function`은 주석 안에서도 금지다. 제한 환경이 본문 원문을 부분일치로 본다 - "
        + "부르는 자리마다 펴 넣고, 주석에서도 그 낱말을 피할 것"],
    [/[{}]/, "중괄호는 주석 안에서도 금지다. 테이블은 `newtable()`로 만들 것"],
];

// `source` is whatever the stage handed over, and the raw stage is the one that makes
// RESTRICTED_FORBIDDEN mean what it says -- see the STAGES note below. Running it over the baked
// text as well costs nothing and covers the other direction: a substitution that *introduces* a
// forbidden token.
function lua51Violation(source) {
    const code = blankNonCode(source);
    for (const [re, why] of LUA51_FORBIDDEN) {
        if (re.test(code)) return why;
    }
    // Not through `blankNonCode`, deliberately. See the note above.
    for (const [re, why] of RESTRICTED_FORBIDDEN) {
        if (re.test(source)) return why;
    }
    return null;
}

// **줄 끝 주석은 어느 본문에서도 금지고, 이것 말고는 그걸 보는 검사가 없다.**
//
// `StripSnippetComments`는 줄 전체가 주석인 줄만 비우므로 `local a = 1 -- note`는 그대로
// 살아남고, 다음 조각이 그 줄에 이어 붙으면 주석 안으로 들어가 사라진다. 파싱은 여전히 되니
// 위쪽 검사들은 아무 말도 안 한다.
//
// **골든도 못 본다.** 그쪽은 본문을 전부 구워서 잠그는데 실제로 구워지는 본문은 몇 개뿐이라,
// 안 굽는 본문에 줄 끝 주석을 넣으면 골든에는 깎인 모습이 찍히고 게임은 주석을 받는다.
//
// 원문에서 본다. 구운 뒤에는 주석이 없으므로 볼 것이 없고, 규칙은 굽든 안 굽든 같다.
function trailingComment(body) {
    const starts = [];
    const masked = blankNonCode(body, starts);
    for (const at of starts) {
        const lineStart = masked.lastIndexOf("\n", at - 1) + 1;
        if (masked.slice(lineStart, at).trim() !== "") {
            return `${body.slice(0, at).split("\n").length}번째 줄`;
        }
    }
    return null;
}

const syntaxDriver = path.join(__dirname, "lib", "syntax.lua");

/** 구문만 본다. 실행하지 않는다. */
function syntaxError(source, name) {
    return runLuaDriver(syntaxDriver, name, source) || null;
}

// **원문과 구운 본문을 둘 다 본다.** 어느 한쪽만으로는 부족하다.
//
// 게임에 붙는 것은 구운 쪽이다. 배포 갈래에서 값이 `false`인 프로브는 호출이 통째로 지워지므로
// (`Snippets.lua`의 `SNIPPET_PROBES_LIVE`), `local x = PROBE.Winner(i)`는 원문으로는 멀쩡히
// 파싱되고 구우면 `local x = `가 된다. 원문만 보면 그걸 못 본다.
//
// 그렇다고 구운 쪽으로 **바꾸면** RESTRICTED_FORBIDDEN이 헐거워진다. 제한 환경은 본문 원문을
// 부분일치로 보므로 주석 안의 `function` 한 낱말에도 걸리는데, 굽는 첫 단계가 바로 주석
// 제거다 - 구운 본문에는 그 낱말이 없다.
const STAGES = [
    ["원문", (body) => body],
    ["구운 뒤", bakeLive],
];

let checked = 0;
let failed = 0;

forEachSnippet(srcDir, ({ file, line, call, label, body }) => {
    checked++;
    const name = `${file}:${line} ${call}`;
    const where = `${name}${label ? ` (${label})` : ""}`;

    const trailing = trailingComment(body);
    if (trailing) {
        console.log(`${where}\n    ${trailing}에 줄 끝 주석이 있다. 스니펫 본문에서는 금지다 - `
            + `그 줄에 다음 조각이 이어 붙으면 주석 안으로 들어가 조용히 사라진다. `
            + `줄 전체 주석으로 옮길 것`);
        failed++;
        return;
    }

    for (const [stage, prepare] of STAGES) {
        let source;
        try {
            source = fillPlaceholders(prepare(body));
        } catch (e) {
            // `applyProbes`/`StripSnippetComments`의 `assert`가 여기로 온다. 게임에서는 이게
            // 애드온 로드를 끊는다.
            console.log(`${where}\n    굽지 못했다: ${e.message}`);
            failed++;
            return;
        }

        const err = syntaxError(source, name);
        if (err) {
            console.log(`${where}\n    [${stage}] ${err}`);
            failed++;
            return;
        }

        const violation = lua51Violation(source);
        if (violation) {
            console.log(`${where}\n    [${stage}] 5.1에 없는 문법: ${violation}`);
            failed++;
            return;
        }
    }
});

console.log(failed === 0
    ? `보안 스니펫 ${checked}개 전부 파싱된다.`
    : `보안 스니펫 ${failed}개 실패.`);

if (failed > 0) process.exit(1);
