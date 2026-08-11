// 보안 스니펫 본문을 소스에서 떼어내는 부분. `check-snippets.js`(구문 검사)와
// `check-snippet-golden.js`(구워진 결과 잠그기)가 같은 것을 봐야 하므로 여기 모아 둔다.
//
// **앵커 목록을 손으로 관리하지 않는다.** 호출 형태로 자동 수집한다 - 목록 방식은 새
// 스니펫을 추가할 때 등록을 잊으면 조용히 검사에서 빠지고, 그게 정확히 이 도구들이 막으려던
// 실패 방식이다.
const fs = require("fs");
const path = require("path");

// 인자에 스니펫 본문이 오는 호출들.
//
// **여기에 안 적힌 이름으로 본문을 넘기면 그 스니펫은 조용히 검사 밖이 된다.** `InstallSnippet`을
// 도입하면서 실제로 46개가 43개로 줄었고, 줄어든 셋이 클릭 래퍼였다 - 이 저장소에서 제일 뜨거운
// 경로다. 개수가 줄면 그것부터 의심할 것.
const CALLS = /\b(SecureHandlerExecute|SecureHandlerWrapScript|SetAttribute|InstallSnippet)\s*\(/g;

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

/**
 * 문자열과 주석을 같은 길이의 공백으로 덮는다. **길이와 줄바꿈을 보존하므로** 이 결과에서
 * 찾은 위치를 원본에 그대로 쓸 수 있다.
 *
 * 쓰이는 데가 둘이다. 호출을 찾을 때 - 주석에 적힌 `SecureHandlerWrapScript(...)`를 진짜
 * 호출로 오해하면 안 된다. 그리고 5.1 토큰 검사에서 - 메시지 안의 색 코드("|cffff6666")를
 * 비트 or로 읽으면 안 된다.
 */
function blankNonCode(src) {
    const out = Array.from(src);
    const blank = (from, to) => {
        for (let k = from; k < to && k < out.length; k++) {
            if (out[k] !== "\n" && out[k] !== "\r") out[k] = " ";
        }
    };

    let i = 0;
    while (i < src.length) {
        if (src.substr(i, 2) === "--") {
            const long = readLongString(src, i + 2);
            const end = long ? long.next : (src.indexOf("\n", i) < 0 ? src.length : src.indexOf("\n", i));
            blank(i, end);
            i = end;
            continue;
        }
        const long = readLongString(src, i);
        if (long) { blank(i, long.next); i = long.next; continue; }
        const c = src[i];
        if (c === '"' || c === "'") {
            const start = i;
            i++;
            while (i < src.length && src[i] !== c) i += src[i] === "\\" ? 2 : 1;
            i++;
            blank(start, i);
            continue;
        }
        i++;
    }
    return out.join("");
}

/**
 * `Debind/`의 모든 스니펫 본문을 순서대로 넘긴다. 콜백 인자:
 *   { file, line, call, label, body }
 *
 * `label`은 DEBUG 갈래를 가르는 이름이다. 조각 참조가 섞인 본문은 **양쪽 다** 넘긴다 -
 * 릴리스 빌드에서는 그 자리가 빈 문자열이 되어 결합 지점이 달라지므로, 한쪽에서만 나는
 * 문제가 실제로 있을 수 있다.
 */
function forEachSnippet(srcDir, cb) {
    const files = fs.readdirSync(srcDir).filter((f) => f.endsWith(".lua")).sort();

    for (const file of files) {
        const src = fs.readFileSync(path.join(srcDir, file), "utf8");
        // 위치를 보존하는 마스크. 여기서 찾은 인덱스를 원본에 그대로 쓴다.
        const code = blankNonCode(src);

        // 1. 조각으로 쓰이는 스니펫 지역변수를 먼저 모은다.
        const snippetLocals = new Map();
        SNIPPET_LOCAL.lastIndex = 0;
        let m;
        while ((m = SNIPPET_LOCAL.exec(code))) {
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

        // 2. 호출마다 본문을 모아 넘긴다.
        CALLS.lastIndex = 0;
        while ((m = CALLS.exec(code))) {
            const openParen = m.index + m[0].length - 1;
            const line = src.slice(0, m.index).split("\n").length;

            for (const parts of collectBodies(src, openParen, snippetLocals)) {
                if (!parts.some((p) => p.literal !== undefined)) continue;

                const hasRef = parts.some((p) => p.ref !== undefined);
                const variants = hasRef
                    ? [["DEBUG=on", (p) => (p.ref ? snippetLocals.get(p.ref) : p.literal)],
                       ["DEBUG=off", (p) => (p.ref ? "" : p.literal)]]
                    : [["", (p) => p.literal]];

                for (const [label, pick] of variants) {
                    cb({ file, line, call: m[1], label, body: parts.map(pick).join("") });
                }
            }
        }
    }
}

module.exports = { readLongString, blankNonCode, collectBodies, forEachSnippet, CALLS, SNIPPET_LOCAL };
