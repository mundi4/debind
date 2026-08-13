// `relativeKey="$parent.X"`가 **뒤에 선언된** 형제를 가리키는지 본다.
//   npm run check:xml-anchors
//
// 이걸 만든 이유: XML은 위에서부터 만들므로, 앵커가 가리키는 키가 아직 nil이면 **그 앵커는
// 조용히 버려진다.** 오류도 경고도 없고, 그 프레임만 화면 어디에도 안 붙은 채로 남는다.
//
// 이미 코드 주석이 세 군데에서 이 얘기를 하고 있다 - `OverviewTab`("탭이 창 어디에도 안 붙고
// 떠 있었다"), `BindModeButton`, `SelectionCount`("이 <Layers>가 <Frames> 뒤에 있어야 하는
// 이유가 여기 있다"). 세 번 적어야 했다는 것이 사람이 기억할 규칙이 아니라는 뜻이고, 실제로
// 작업대 행 템플릿에서 한 파일에 두 번 다시 났다(핀 버튼이 안 보였고, 붙여넣기 거절 사유가
// 안 보였다). check-locales가 같은 이유로 검사가 된 것과 같은 자리다.
//
// **"선언은 됐는데 뒤에 있는" 것만 잡는다.** 아예 안 보이는 키는 물려받은 템플릿의 것일 수
// 있어서(`$parent.TitleText` 같은) 판단하지 않는다. 여기서 잡는 것은 전부 진짜다.

const fs = require("fs");
const path = require("path");

const roots = [
    path.join(__dirname, "..", "Debind"),
    path.join(__dirname, "..", "DebindShare"),
    path.join(__dirname, "..", "DebindTest"),
];

/** 여는 태그 / 닫는 태그 / 자기완결 태그. 주석과 CDATA는 미리 지운다. */
const TAG = /<(\/?)([A-Za-z][\w.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/g;
const ATTR = /([A-Za-z][\w.-]*)\s*=\s*"([^"]*)"/g;

function readAttrs(text) {
    const out = {};
    for (const m of text.matchAll(ATTR)) {
        out[m[1]] = m[2];
    }
    return out;
}

/** 트리를 만든다. 각 노드는 `{ name, attrs, line, parent, children }`. */
function parse(src) {
    const stripped = src
        .replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, " "))
        .replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, (m) => m.replace(/[^\n]/g, " "));

    const root = { name: "#doc", attrs: {}, children: [], parent: null };
    let node = root;

    for (const m of stripped.matchAll(TAG)) {
        const [, closing, name, attrText, selfClosing] = m;
        if (closing) {
            if (node.parent) {
                node = node.parent;
            }
            continue;
        }
        const child = {
            name,
            attrs: readAttrs(attrText),
            line: stripped.slice(0, m.index).split("\n").length,
            children: [],
            parent: node,
        };
        node.children.push(child);
        if (!selfClosing) {
            node = child;
        }
    }

    return root;
}

/**
 * 앵커를 소유한 **프레임**. `<Anchor>`의 `$parent`는 `<Anchors>`가 아니라 그것을 담은
 * 프레임을 기준으로 읽는다.
 */
function ownerOf(anchor) {
    let node = anchor.parent;
    while (node && node.name === "Anchors") {
        node = node.parent;
    }
    return node;
}

/** `node`의 조상 중 `container`의 직속 자식인 것. 형제 차례를 재려면 이것이 필요하다. */
function childOfContainer(node, container) {
    let cur = node;
    while (cur && cur.parent !== container) {
        cur = cur.parent;
    }
    return cur;
}

function walk(node, visit) {
    visit(node);
    for (const child of node.children) {
        walk(child, visit);
    }
}

function checkFile(file, rel) {
    const src = fs.readFileSync(file, "utf8");
    const root = parse(src);
    const problems = [];

    walk(root, (node) => {
        if (node.name !== "Anchor") {
            return;
        }
        const key = node.attrs.relativeKey;
        if (!key || !key.startsWith("$parent")) {
            return;
        }

        const parts = key.split(".");
        let hops = 0;
        while (parts[hops] === "$parent") {
            hops += 1;
        }
        const wanted = parts[hops];
        if (!wanted) {
            return;
        }

        const owner = ownerOf(node);
        if (!owner) {
            return;
        }

        // `$parent`를 hops번 거슬러 올라간 것이 그 키를 들고 있어야 할 컨테이너다.
        let container = owner;
        for (let i = 0; i < hops; i += 1) {
            container = container && container.parent;
        }
        // 문서 밖으로 나갔다 = 이 파일이 모르는 부모다(가상 템플릿의 뿌리, 최상위 프레임).
        // 판단하지 않는다.
        if (!container || container.name === "#doc" || !container.parent) {
            return;
        }

        const mine = childOfContainer(owner, container);
        const siblings = container.children;
        const myIndex = siblings.indexOf(mine);

        let declaredAt = -1;
        for (let i = 0; i < siblings.length; i += 1) {
            if (siblings[i].attrs.parentKey === wanted) {
                declaredAt = i;
                break;
            }
        }

        // **여기 없으면 넘어간다.** 물려받은 템플릿이 준 키일 수 있고, 그건 이 파일이 답할 수
        // 있는 질문이 아니다. 잡는 것은 "여기 있는데 뒤에 있다" 하나뿐이다.
        if (declaredAt === -1 || declaredAt < myIndex) {
            return;
        }

        problems.push({
            line: node.line,
            wanted,
            ownerKey: mine.attrs.parentKey || mine.attrs.name || mine.name,
            declaredLine: siblings[declaredAt].line,
        });
    });

    if (problems.length > 0) {
        console.log(`${rel}: 뒤에 선언된 것을 가리키는 앵커 ${problems.length}개`);
        for (const p of problems) {
            console.log(`  - ${p.line}행: ${p.ownerKey}가 $parent.${p.wanted}를 가리키는데`
                + ` 그건 ${p.declaredLine}행에 있다 (앵커가 조용히 버려진다)`);
        }
    }
    return problems.length;
}

let files = [];
for (const dir of roots) {
    if (!fs.existsSync(dir)) {
        continue;
    }
    for (const name of fs.readdirSync(dir)) {
        if (name.endsWith(".xml")) {
            files.push({ file: path.join(dir, name), rel: path.join(path.basename(dir), name) });
        }
    }
}

let bad = 0;
for (const { file, rel } of files) {
    bad += checkFile(file, rel);
}

if (bad > 0) {
    process.exitCode = 1;
} else {
    console.log(`XML ${files.length}개에서 뒤를 가리키는 앵커가 없다.`);
}
