-- **역할 헤더의 칸 수와 훅 자리.** 와우 클라이언트 불필요.
--
-- 스니펫이 도는 것은 여기서 못 본다 (`tests/restricted.lua`는 `Execute`와 `SetFrameRef`만
-- 재생한다). 볼 수 있는 것은 **훅이 어느 프레임에 걸렸는가**이고, 그것이 이 장치가 성립하는
-- 조건이다: `configureChildren`이 매 배치마다 자식 전부에 `unit`을 쓰고 **제일 높은 자식이
-- 그중 마지막**이므로, 훅이 그 자식에 있어야 배치가 끝난 상태를 본다. 그보다 낮은 자식에
-- 있으면 절반쯤 놓인 배치를 읽고, 그것은 조용히 틀린다.
--
-- 게임에서 도는지는 `/debtest`가 본다 (`devdocs/adding-a-role-condition.md` §7).

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local frames = require("wow_frames");

    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "check failed", 2);
        end
    end

    --- `CreateUnitWatchHeader`가 `Options.excludePlayer`를 읽으므로 첫 헤더를 만들기 전에
    --- DB가 서 있어야 한다.
    _G.DebindVars = {
        dbver = Constants.DB_VERSION,
        shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
        characters = { ["Player-1-TESTGUID"] = { layers = {}, switches = {} } },
        migrated = {},
        switches = {},
    };
    DebindPrivate.InitDB();

    --- 헤더가 실제로 들고 있는 자식 수. `unitsPerColumn`과 다른 값이다.
    local function ChildCount(header)
        local i = 0;
        while (header:GetAttribute("child" .. (i + 1))) do
            i = i + 1;
        end
        return i;
    end

    --- 마지막으로 감싼 `OnAttributeChanged`가 걸린 프레임.
    local function LastAttrHookFrame(entries)
        local frame;
        for i = 1, #entries do
            local e = entries[i];
            if (e.kind == "WrapScript" and e.name == "OnAttributeChanged") then
                frame = e.frame;
            end
        end
        return frame;
    end

    test("the hook rides the highest child a header has", function()
        local mark = frames.mark();
        local header = DebindPrivate.EnableUnitWatch("tank");
        check(header ~= nil, "no header");

        local count = ChildCount(header);
        check(count == 2, "children: " .. count);
        check(LastAttrHookFrame(frames.since(mark)) == header:GetAttribute("child" .. count),
            "the hook is not on child" .. count);
    end);

    test("growing a header moves the hook up and lets the layout fill the new slots", function()
        local header = DebindPrivate.EnableUnitWatch("tank");
        local before = ChildCount(header);

        local mark = frames.mark();
        DebindPrivate.EnableUnitWatch("tank", Constants.MAX_ROLE_SLOTS);

        local count = ChildCount(header);
        check(count == Constants.MAX_ROLE_SLOTS, "children: " .. count);
        check(header:GetAttribute("unitsPerColumn") == Constants.MAX_ROLE_SLOTS,
            "unitsPerColumn: " .. tostring(header:GetAttribute("unitsPerColumn")));
        check(LastAttrHookFrame(frames.since(mark)) == header:GetAttribute("child" .. count),
            "the hook is not on child" .. count);

        --- **옛 자식에서 떼는 것은 선택이 아니다.** 이제 배치가 채울 수 있는 칸이라, 남아 있으면
        --- 배치가 절반쯤 놓인 상태에서 한 번 더 돈다.
        local unwrapped = false;
        local entries = frames.since(mark);
        for i = 1, #entries do
            if (entries[i].kind == "UnwrapScript"
                    and entries[i].frame == header:GetAttribute("child" .. before)) then
                unwrapped = true;
            end
        end
        check(unwrapped, "child" .. before .. " kept its hook");
    end);

    --- **드라이버가 헤더에 닿는 유일한 길이다.** `SetRoleUnits`는 맵이 있는 환경에서 자식을
    --- 걸어야 하는데 헤더는 UnitWatch 쪽 것이라, 프레임 핸들을 인자로 넘기면 저쪽에 nil로
    --- 도착한다(게임에서 확인, 2026-08-28). 이 frameref가 빠지면 스니펫이 조용히 빠져나가고
    --- 역할 맵이 영영 비어 있는다.
    test("the driver gets a frameref to each role header", function()
        for alias in pairs(DebindPrivate.ROLE_HEADER_BITS) do
            local header = DebindPrivate.EnableUnitWatch(alias, Constants.MAX_ROLE_SLOTS);
            check(header ~= nil, alias .. ": no header");

            --- 헤더는 세션에 한 번만 만들어지므로 창을 잡지 않고 기록 전체를 본다.
            local wired = false;
            for _, e in ipairs(frames.recorder.entries) do
                if (e.kind == "SetFrameRef" and e.name == "rolehdr_" .. alias
                        and e.frame == DebindPrivate.BindingDriver and e.ref == header) then
                    wired = true;
                end
            end
            check(wired, alias .. ": the driver was never given a frameref");
        end
    end);

    --- 별칭이 없어서 좁은 모양으로 쓸 일이 없다. 켜지면 곧 역할 맵이다.
    test("the damager header is born at full size", function()
        local header = DebindPrivate.EnableUnitWatch("damager");
        check(header ~= nil, "no header");
        check(ChildCount(header) == Constants.MAX_ROLE_SLOTS,
            "children: " .. ChildCount(header));
    end);

    --- `CollectHeaderChildren`은 `SecureGroupHeader_Update`에 걸려 있고 그 함수가 누구 헤더로
    --- 불렸는지 안 가린다. 우리 헤더도 `SecureGroupHeaderTemplate`이라 같은 길을 타므로, 거기
    --- 자식들이 클릭캐스팅 프레임으로 등록되면 역할 맵이 켜질 때 헤더당 마흔 건이 붙는다.
    test("our own headers are not collected as click-cast frames", function()
        local header = DebindPrivate.EnableUnitWatch("healer");
        check(header ~= nil, "no header");

        _G.SecureGroupHeader_Update(header);

        local count = ChildCount(header);
        check(count > 0, "the header had no children to check");
        for i = 1, count do
            local child = header:GetAttribute("child" .. i);
            check(DebindPrivate.ccframes[child] == nil,
                "child" .. i .. " registered: " .. tostring(DebindPrivate.ccframes[child]));
        end
    end);

    --- **거르는 쪽이 너무 넓지 않은가.** 남의 그룹 헤더는 그대로 걷어와야 한다.
    test("a foreign group header still yields its children", function()
        local foreign = CreateFrame("Frame", nil, nil, "SecureFrameTemplate");
        local child = CreateFrame("Button", nil, foreign, "SecureFrameTemplate");
        foreign:SetAttribute("child1", child);

        _G.SecureGroupHeader_Update(foreign);

        check(DebindPrivate.ccframes[child] ~= nil, "the child was not registered");
    end);

    return T;
end
