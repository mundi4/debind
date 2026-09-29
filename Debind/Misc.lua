local ADDON_NAME, DebindPrivate = ...;
local L                       = DebindPrivate.L;
local Constants               = DebindPrivate.Constants;

--- 착용 슬롯 하나의 **표시 이름과 빈 칸 그림**. `INVSLOT_HEAD`..`INVSLOT_TABARD`.
---
--- 이름은 게임의 것이다. `GetInventorySlotInfoForInvSlot`이 프레임 이름("HeadSlot")을 주고,
--- 그걸 대문자로 올린 전역이 그 언어의 표시 이름이다(`HEADSLOT` = "머리"). 캐릭터 창이
--- 자기 칸에 이름을 붙이는 방식 그대로다.
---
--- **같은 이름을 쓰는 칸이 있어서 번호를 붙인다.** `TRINKET0SLOT`과 `TRINKET1SLOT`이 둘 다
--- "장신구"고 손가락 둘도 그렇다. 캐릭터 창에서는 자리가 그 둘을 갈라주는데 **목록에서는
--- 갈라줄 것이 없다** - 똑같은 줄이 둘 서면 어느 쪽이 어느 칸인지 알 길이 없다. 게임에
--- 번호가 붙은 문자열이 따로 없어서 우리가 붙인다.
---
--- 번호는 **겹치는 것에만** 붙는다. 목록을 한 번 만들어보고 이름이 두 번 나온 것만 번호를
--- 얻으므로, 게임이 언젠가 둘을 다른 이름으로 갈라 부르면 번호가 저절로 사라진다.
local EquipSlotFacts;
do
    local facts;

    local function build()
        facts = {};
        local nameCount = {};

        for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
            local _, texture, _, frameName = C_PaperDollInfo.GetInventorySlotInfoForInvSlot(slot);
            local name = frameName and _G[strupper(frameName)];
            facts[slot] = { name = name, texture = texture };
            if (name) then
                nameCount[name] = (nameCount[name] or 0) + 1;
            end
        end

        local numbered = {};
        for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
            local entry = facts[slot];
            local name = entry.name;
            if (name and nameCount[name] > 1) then
                numbered[name] = (numbered[name] or 0) + 1;
                entry.name = format(L["USESLOT_NUMBERED"], name, numbered[name]);
            end
        end
    end

    --- **처음 물을 때 짓는다.** 파일이 읽히는 시점에는 `_G["HEADSLOT"]`이 아직 없을 수 있고,
    --- 없는 채로 지어진 표는 이름이 통째로 nil인 채 살아남는다.
    function EquipSlotFacts(slot)
        if (not facts) then
            build();
        end
        local entry = facts[slot];
        if (not entry) then
            return nil, nil;
        end
        return entry.name, entry.texture;
    end
end
DebindPrivate.EquipSlotFacts = EquipSlotFacts;

--- What to write where a key goes. **Not for a nil key** -- what an action with no key at all reads
--- as differs by where it is shown, so each of those places says its own word.
---
--- **A key is a binding string and nothing else.** This used to take a second argument and to guard
--- against a number, because a set whose key the reader had not decided sat on one and the heading
--- had to be told separately which key it had come in on. An arrival keeps the key it was sent on,
--- so the key names it (`building-export-import.md` 12절) and there is no second thing left
--- to say.
function DebindPrivate.GetKeyDisplayText(key)
    return GetBindingText(key);
end

--- The one wording of each thing the addon counts. A sentence with a count in it takes this as a
--- `%s`, so "3 actions" is written in one string rather than once per sentence (owner, 2026-09-29).
local COUNT_KEYS = {
    actions = "COUNT_ACTIONS",
    keys = "COUNT_KEYS",
    classes = "COUNT_CLASSES",
    characters = "COUNT_CHARACTERS",
};

--- `n` of `noun`, one of `COUNT_KEYS`'s, in that noun's `COUNT_*` string.
function DebindPrivate.CountText(noun, n)
    return format(L[COUNT_KEYS[noun]], n);
end


--- **The name a character is stored and shown by**, the player's included: `UnitName`'s first
--- return alone is not one on camelot (`JoinUnitName`).
function DebindPrivate.GetUnitFullName(unit)
    local name, second = UnitName(unit);
    -- 12.1 can answer with secrets for units outside our access (arena enemies). A
    -- secret name cannot be formatted or concatenated, and every caller already treats
    -- nil as "nothing to show", so that is what a secret becomes.
    if (issecretvalue and (issecretvalue(name) or issecretvalue(second))) then
        return nil;
    end
    return DebindPrivate.JoinUnitName(name, second);
end

--- A working copy's TOC still holds the packager's keyword unsubstituted, which is what the `@`
--- test catches.
function DebindPrivate.GetVersionLabel()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version");
    if (version and not version:find("@", 1, true)) then
        return version;
    end
    return DebindPrivate.DEV_STAMP or "dev";
end

function DebindPrivate.DisplayMessage(message, r, g, b)
    if (b == nil) then
        local info = ChatTypeInfo["SYSTEM"];
        r, g, b = info.r, info.g, info.b;
    end
    if (Constants.DEBUG) then
        DEFAULT_CHAT_FRAME:AddMessage(GetTime() .. "  " .. L["_MESSAGE_PREFIX"] .. message, r, g, b);
    else
        DEFAULT_CHAT_FRAME:AddMessage(L["_MESSAGE_PREFIX"] .. message, r, g, b);
    end
end

