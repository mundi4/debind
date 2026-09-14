local _, DebindPrivate           = ...;
local Constants                    = DebindPrivate.Constants;
local BindingDriver                = DebindPrivate.BindingDriver;
local L                            = DebindPrivate.L;

DebindPrivate.ccframes           = {};
--- The header door's registrations by frame name, mirrored for `Clique.hccframes` (`DebindCliqueFake`):
--- Clique keeps the frames that arrived through `clickcast_register` in a second list keyed by
--- name, since a name is what the restricted side can hand out, and addons walking Clique's
--- registrations read both. Ours are the `hd` rows of `ccframes`; this is the same set in that shape.
DebindPrivate.hccframes          = {};
DebindPrivate.blizzardFrames     = {};
--- Registrations that arrived under lockdown, in the order they arrived. Entries are
--- `{ button, type }`.
DebindPrivate.FrameQueue         = {};
DebindPrivate.RegisterClickQueue = {};

--- 클릭캐스팅이 쓰는 `<접두사>clickbutton<번호>` 이름들. `UpdateBindingsMap`이 리빌드마다
--- 채운다(그쪽이 같은 자리에서 `<접두사>type<번호>`를 굽는다).
---
--- **이것만 비보안 쪽에 있는 이유.** 값이 프레임이라서다. 보안 스니펫이 프레임 핸들로
--- 속성을 쓰면 그 핸들이 그대로 저장되고, 비보안 쪽은 진짜 프레임을 못 얻는다 -
--- `SECURE_ACTIONS.click`이 `delegate:HasAccessConstraints()`에서 nil 호출로 죽는다
--- (SecureTemplates.lua:564). 실제로 그렇게 죽었다.
---
--- 다행히 값이 **언제나 같은 프레임**이라 상태에 안 달렸다. 그래서 전투 밖에 프레임마다
--- 한 번 쓰면 되고, 승자가 바뀔 때 다시 쓸 일이 없다. 승자에 따라 갈리는 것은
--- `<접두사>type<번호>` 하나뿐이고 그건 문자열이라 보안 쪽이 쓴다.


local BLIZZARD_UNITFRAME_OPTIONS   = {
    player = { type = "player" },
    pet = { type = "pet" },
    target = { type = "target" },
    targettarget = { type = "targettarget" },
    focus = { type = "focus" },
    focustarget = { type = "focustarget" },
    boss = {
        type = "boss",
    },
    party = {
        type = "group",
    },
    raid = {
        type = "group",
    },
    arena = {
        type = "arena",
    },
};

--- The client's own unit frames that carry a name, lowercased. **The list `UpdateBlizzardFrames`
--- walks is keyed by the frame**, and it is filled at login; the name door can reach one of these
--- before that, so the names are what answers there. The compact frames and the boss frames are
--- patterns rather than rows and are matched beside this.
local BLIZZARD_FRAME_NAMES         = {
    playerframe = true,
    petframe = true,
    targetframe = true,
    targetframetot = true,
    focusframe = true,
    focusframetot = true,
};

local UNITFRAME_TYPES              = {
    player = Constants.FRAMETYPE_PLAYER,
    pet = Constants.FRAMETYPE_PET,
    group = Constants.FRAMETYPE_GROUP,
    target = Constants.FRAMETYPE_TARGET,
    targettarget = Constants.FRAMETYPE_TARGET, --Constants.FRAMETYPE_TARGETTARGET,
    focus = Constants.FRAMETYPE_TARGET,        --Constants.FRAMETYPE_FOCUS,
    focustarget = Constants.FRAMETYPE_TARGET,  --Constants.FRAMETYPE_FOCUSTARGET,
    boss = Constants.FRAMETYPE_BOSS,
    arena = Constants.FRAMETYPE_ARENA,
    unknown = Constants.FRAMETYPE_UNKNOWN,
};

--- What the frame says it is, for the frames nobody tells us about.
---
--- The Clique protocol another addon registers through has no field for the kind, so
--- `UNITFRAME_TYPES` above is fed by our own Blizzard registration and by nothing else. Every
--- frame any other unit frame addon hands over came in as `unknown` because of that, and the
--- frame was carrying the answer the whole time.
---
--- **Only the tokens that hold still are here.** A header hands its children units and takes them
--- back, so a child's token says which slot it is filling right now and not what the frame is.
--- Every one those slots can hold is a party or raid token, which answers group either way, so a
--- child read on the wrong pass still comes out a group frame. A token that could move a frame
--- from one category to another has no business in this table.
---
--- **A header's own child never reaches this reading at all.** The header door says group for one
--- (`_headerChildren`) and `RegisterFrame` prefers what it was told to what it can read, so the
--- tokens above only ever answer for a frame nobody described.
---
--- **So every `<owner>pet` spelling is out, `playerpet` with the rest.** A pet frame carries `pet`,
--- which is what Blizzard's own pet header gives the slot for your own pet (`GetPetUnit` in
--- `SecureGroupHeaders.lua`) and what `playerpet` never appears as anywhere in the game's code. A
--- frame that does carry `playerpet` got it from an addon counting its slots `player`, `party1`,
--- `party2` and their pets alongside them, which makes that frame a column in a group block and
--- not the pet frame at all.
local UNIT_FRAMETYPES              = {
    pet = Constants.FRAMETYPE_PET,
    target = Constants.FRAMETYPE_TARGET,
    targettarget = Constants.FRAMETYPE_TARGET,
    focus = Constants.FRAMETYPE_TARGET,
    focustarget = Constants.FRAMETYPE_TARGET,
};

for i = 1, MAX_PARTY_MEMBERS do
    UNIT_FRAMETYPES["party" .. i] = Constants.FRAMETYPE_GROUP;
end

for i = 1, MAX_RAID_MEMBERS do
    UNIT_FRAMETYPES["raid" .. i] = Constants.FRAMETYPE_GROUP;
end

for i = 1, MAX_BOSS_FRAMES do
    UNIT_FRAMETYPES["boss" .. i] = Constants.FRAMETYPE_BOSS;
end

for i = 1, MAX_ARENA_ENEMIES do
    UNIT_FRAMETYPES["arena" .. i] = Constants.FRAMETYPE_ARENA;
end

--- The unit frame packs we know by name. A row is `{ name pattern, addon, kind }`.
---
--- **Being on this list is the answer to "is this a unit frame".** What would otherwise have to be
--- read is every secure frame an addon wraps, and the filter that would sort those cannot be
--- checked against addons we have never seen. A name is wrong about nothing else, and when a pack
--- renames one, nothing matches and we are back where we already stood.
---
--- **Lowercase and anchored.** The name is lowercased before it is matched, so a row is written
--- that way. Anchoring is what keeps a row from being a word search: a pack's own prefix sits in
--- every name it makes, so an unanchored pattern would take its action bars along with its unit
--- frames. Patterns rather than prefixes because a numbered name has no fixed count, and the
--- number lives in a file we do not control.
---
--- **The addon is the folder name `C_AddOns.IsAddOnLoaded` takes.**
---
--- **The kind is only for a frame whose unit cannot answer**, and a row that carries one holds it
--- whichever door the frame arrives through. Left empty, the kind is read off the frame
--- (`ReadFrameType`). Reading works for a frame standing for one unit and no other, since the unit
--- is on it before anything else happens to it and cannot move; it does not work for a slot,
--- because the token on a slot says what is filling it this second.
local KNOWN_PACK_FRAMES            = {
    { "^vd%d+h%d+",                         "VuhDo",                 "group" }, -- a panel slot is a group display whatever fills it
    { "^erfpartyselfbutton$",               "EllesmereUIRaidFrames", "group" }, -- a party block's self slot, standalone so the header cannot reorder it
    { "^erffriendlyboss%d+$",               "EllesmereUIRaidFrames", "group" }, -- drawn in the raid block; its boss token would read boss
    { "^erfextraframe%d+$",                 "EllesmereUIRaidFrames", "group" }, -- wired up before it is given a unit
    { "^ellesmereuiunitframes_",            "EllesmereUIUnitFrames" },
    { "^grid2layoutheader%d+unitbutton%d+", "Grid2", "group" },                 -- a layout slot, and the ones no secure header spawns read unknown without this
    { "^elvuf_",                            "ElvUI" },                          -- every frame the pack spawns, headers and their children with them
    -- Cell's rows. **Its group blocks already arrive as header children**, and these are for the
    -- five sets it builds outside a header, which no other door reaches: it writes nothing into
    -- `ClickCastFrames` (that code is commented out in `Core.lua`) and hands no header over. They
    -- get this far because its click casting wraps `OnEnter` on every unit button it owns.
    { "^cellsoloframeplayer$",              "Cell",                  "group" },
    { "^cellsoloframepet$",                 "Cell",                  "group" },
    { "^cellnpcframebutton%d+$",            "Cell",                  "group" },
    { "^cellarenapet%d+$",                  "Cell",                  "group" },
    { "^cell.*unitbutton%d+",               "Cell",                  "group" },
    -- Danders Frames' rows. **It names a frame for what it draws**, so the row can carry a kind
    -- without reading the unit off it: its group blocks are secure header children, and the four
    -- sets it builds outside one say pet or boss in the name. `_TestPet_` is the options panel's
    -- own preview, which is why the pet row is anchored rather than a prefix search.
    { "^danders.*headerunitbutton%d+",      "DandersFrames",         "group" },
    { "^dandersraidframe%d+$",              "DandersFrames",         "group" },
    { "^dandersframes_player$",             "DandersFrames",         "group" }, -- the party block's own slot
    { "^dandersframes_party%d+$",           "DandersFrames",         "group" },
    { "^dandersframes_pet_",                "DandersFrames",         "pet" },
    { "^dandersframes_arenapet_",           "DandersFrames",         "pet" },
    { "^danderspinnedboss%d+%a+_%d+$",      "DandersFrames",         "boss" },
};

--- HealBot's rows, built rather than written out, because it makes two names per prefix and the
--- pair is not spelled the same way. `HealBot_Action_CreateNewButton` names the heal button
--- `<prefix>HealUnit<n>` and its emergency twin `<prefix>EmergUnit<n>`, and on the way to the
--- second it swaps `HealBot_` for `HB_` and leaves every other prefix as it is.
---
--- **`hbTest_` is left out, and this list is the only thing that leaves it out.** Those are the
--- bars the options panel shows while somebody is arranging the display. They are made by the same
--- call and carry the same shape, so nothing about a frame tells them apart -- only the name does.
---
--- Pinned to `group` for VuhDo's reason: a HealBot button is a slot the panel fills and empties as
--- the roster moves, so the token on it says what it is holding this second.
local HEALBOT_PREFIXES             = {
    "healbot_", "hbpet_", "hbvehicle_", "hbprivtar_", "hbunittar_", "hbenemy_", "hbextra_",
};

for i = 1, #HEALBOT_PREFIXES do
    local prefix = HEALBOT_PREFIXES[i];
    local emergency = (prefix == "healbot_") and "hb_" or prefix;
    KNOWN_PACK_FRAMES[#KNOWN_PACK_FRAMES + 1] =
        { "^" .. prefix .. "healunit%d+$", "HealBot", "group" };
    KNOWN_PACK_FRAMES[#KNOWN_PACK_FRAMES + 1] =
        { "^" .. emergency .. "emergunit%d+$", "HealBot", "group" };
end

--- Names that are a unit frame in every way a frame can be read and are still not one to hold a
--- binding. **Only a name can say so**, which is why they are here rather than in a test on the
--- frame: `hbTest_` bars are made by the call that makes the real ones (`HealBot_Action_-
--- CreateNewButton`) and carry the same shape, and what they are is the picture the options panel
--- draws while somebody arranges the display.
---
--- Read where a name is read, so nothing further down can take one of these.
local NEVER_OURS_FRAMES            = {
    "^hbtest_",
};

--- Which pack a frame's name belongs to, or nothing for a name no row covers.
function DebindPrivate.PackAddonForFrameName(name)
    if (type(name) ~= "string") then
        return;
    end

    name = strlower(name);
    for i = 1, #KNOWN_PACK_FRAMES do
        if (strfind(name, KNOWN_PACK_FRAMES[i][1])) then
            return KNOWN_PACK_FRAMES[i][2];
        end
    end
end

--- The packs on the list this board has a folder for, by folder name, as `{ addon, title }`. What
--- the option menu offers a box for.
---
--- **Sorted here rather than in `KNOWN_PACK_FRAMES`.** Three readers walk that table from the top
--- and stop at the first row that matches, so its order is which pattern wins where two cover one
--- name -- `^cellspotlightframeunitbutton%d+$` sits under `^cell.*unitbutton%d+` for exactly that
--- reason. Reordering it to tidy a menu would silently change which row answers.
---
--- **By the folder name and not by the title**, which is the same name the row above was found
--- with. A title carries colour escapes and the client's language, so `|cff00ff00Grid2|r` sorts
--- under the pipe and the same addon lands somewhere else on a different client.
---
--- **Installed, not loaded.** A reader who turns a pack off in the addon list still has a stored
--- `false` for it, and asking whether it is loaded took the box away while the value stayed --
--- so the next time they turned that pack back on, a decision they could no longer see came back
--- with it. The client parses every addon's `.toc` at startup whether it loads it or not, which is
--- what makes the question answerable for one that is off.
---
--- **The title is the addon's own `Title`.** A name we made up for somebody else's addon is a name
--- the reader has seen nowhere else, and the one they know is the one in their addon list.
---
--- Under `pcall`, and the name is tested rather than trusted: the documentation says every return
--- here is non-nilable, and an addon the client has never heard of is the case that says otherwise.
function DebindPrivate.InstalledKnownPacks()
    local packs, seen = {}, {};
    if (not C_AddOns or not C_AddOns.GetAddOnInfo) then
        return packs;
    end

    for i = 1, #KNOWN_PACK_FRAMES do
        local addon = KNOWN_PACK_FRAMES[i][2];
        if (not seen[addon]) then
            seen[addon] = true;
            local ok, folder, title = pcall(C_AddOns.GetAddOnInfo, addon);
            if (ok and type(folder) == "string" and folder ~= "") then
                packs[#packs + 1] = {
                    addon,
                    (type(title) == "string" and title ~= "") and title or addon,
                    folder,
                };
            end
        end
    end

    sort(packs, function(a, b)
        return a[3] < b[3];
    end);
    return packs;
end

--@debug@
--- **A row the test kit adds and takes back.** The pack switch is a gate every registration
--- passes, and a case about it that needed one of these packs installed could only ever run on a
--- board that has it. Returns the call that takes the row off again.
function DebindPrivate.AddKnownPackFrameRow(pattern, addon, frameType)
    local row = { pattern, addon, frameType };
    KNOWN_PACK_FRAMES[#KNOWN_PACK_FRAMES + 1] = row;
    return function()
        for i = #KNOWN_PACK_FRAMES, 1, -1 do
            if (KNOWN_PACK_FRAMES[i] == row) then
                tremove(KNOWN_PACK_FRAMES, i);
                return;
            end
        end
    end;
end
--@end-debug@

local function NameOf(frame)
    return frame:GetName();
end

--- The same question asked of a frame.
---
--- Under `pcall` for the reason `SetPropagateOne` gives: on 12.1 a frame answering `IsForbidden`
--- false is no longer proof that touching it will not raise. `GetName` in particular is the call
--- this file was already burnt by (see `DeriveFrameType`).
--- The answer per frame, kept because a frame's name never changes and the question is now asked
--- at the door, at the gate and on the way out for the same frame, on every header update. `false`
--- is "no pack"; a name that could not be read is not kept, so it is asked again.
local _packOf = setmetatable({}, { __mode = "k" });

local function PackAddonForFrame(frame)
    local known = _packOf[frame];
    if (known ~= nil) then
        return known or nil;
    end
    local ok, name = pcall(NameOf, frame);
    if (not ok) then
        return;
    end
    local pack = DebindPrivate.PackAddonForFrameName(name);
    _packOf[frame] = pack or false;
    return pack;
end

--- The words that name a slot in a group frame set. Asked of `player` and of nothing else.
local GROUP_NAME_WORDS             = { "party", "raid" };

--- The frames a group header has told us are its children.
---
--- **Being a header's child is what the frame is, so it outranks every other answer.** A header
--- hands a child whichever unit it is filling and takes it back, so reading that child gives the
--- slot it holds this second: `player` in the self slot of a party block, and nothing at all in a
--- spare the header has emptied. Neither is what the frame is.
---
--- **The other doors reach these same frames and cannot say so.** oUF writes every object it builds
--- into `ClickCastFrames`, header children included, and `CollectOUFFrames` fetches the ones that
--- write never reached - both through the Clique shape, which has no field for the kind. So the
--- header's answer has to survive them rather than be the most recent one.
---
--- **`IsGroupHeaderChild` below is the same answer arrived at without being told**, for a frame
--- that reaches us through some other door before its header has laid out. This table wins where
--- both can answer, because being told is not a guess.
---
--- **Never emptied, and weak so a frame can still go.** Registration is taken away and given back
--- while the frame stays what it is: an addon reclaiming a frame writes `nil` into
--- `ClickCastFrames` and adds it again later, and between those two the row this would otherwise
--- live on is gone.
local _headerChildren              = setmetatable({}, { __mode = "k" });

--- The frames a group header handed over itself, through the Clique header protocol.
---
--- **A mark on the frame rather than an argument, because a registration can be queued.** The
--- header door reaches `RegisterFrame` like every other door now, so a child offered during a
--- fight goes into `FrameQueue` and is registered when it ends -- and the queue carries the
--- arguments the call had, not who made it. `_headerChildren` above solves the same problem the
--- same way.
---
--- What it becomes on the row is `hd`, which is the row's own record that the header door put it
--- there, and what `hccframes` is the name-keyed shape of.
local _headerOwned                 = setmetatable({}, { __mode = "k" });

--- Said before the frame is offered, the way `CollectHeaderChildren` marks a child before it
--- offers one. Group is what the header knows and the frame cannot say: a child holds whichever
--- unit it is filling right now.
function DebindPrivate.MarkHeaderOwned(button)
    _headerOwned[button] = true;
    _headerChildren[button] = true;
end

--- Puts the mark on the row, and the row's name in the list Clique exposes as `hccframes`.
---
--- **Called from every place `RegisterFrame` can leave with a row standing**, the early return
--- included. A frame another door had already registered as a group frame stops at that return,
--- and stopping there used to mean the header's own claim never reached the row, so the frame was
--- missing from the list Clique exposes as `hccframes`.
local function ClaimForHeader(button, row)
    if (type(row) ~= "table" or not _headerOwned[button]) then
        return;
    end
    row.hd = true;
    local name = button.GetName and button:GetName();
    if (name) then
        DebindPrivate.hccframes[name] = button;
    end
end

--- Whether the frame is a slot in a `SecureGroupHeaderTemplate` header.
---
--- **Asked before the unit, because the unit on a header child answers only sometimes.** The
--- header writes the slot's unit and takes it away again (`SecureGroupHeaders.lua` clears every
--- slot it is not showing), so a child handed over while the header is showing nobody carries no
--- unit at all -- which is exactly when a unit frame addon registers it, from its own styling
--- pass. Reading the unit there gave `unknown` and nothing came back to ask again.
---
--- **The parent's script is the test.** Blizzard's own `OnEvent` is what makes a header a header,
--- and it is one value that no other frame in the client shares. An addon's header carries it
--- because the template it inherits does, so this recognises a pack's own group header as well as
--- the client's own.
---
--- **A pet header's children are group frames too**, which is what the header door
--- (`clickcast_register`) already calls every child that arrives through it. Every slot either
--- header can hold is a group unit or a group member's pet, so there is no slot here that another
--- category would fit better.
local function IsGroupHeaderChild(button)
    local parent = button.GetParent and button:GetParent();
    if (not parent or not parent.GetScript) then
        return false;
    end

    local onEvent = parent:GetScript("OnEvent");
    return onEvent ~= nil
        and (onEvent == SecureGroupHeader_OnEvent or onEvent == SecureGroupPetHeader_OnEvent);
end

--- **`player` is the one unit that does not settle it.** Every other token here is the frame:
--- something showing `target` is the target frame and cannot turn into a boss frame. `player` is
--- also what a party frame set gives its own slot, since such a set has five slots and there are
--- only four party units. Blizzard's compact container does exactly that
--- (`Blizzard_CompactRaidFrameContainer.lua` hands the self slot `"player"`), and a unit frame
--- addon drawing its own party block does the same, sometimes writing the token on the frame for
--- good. So that one token gets a second question, and the frame's name answers it: a self slot is
--- named for the set it is drawn in.
---
--- **The name is asked there and nowhere else**, because an addon's own prefix sits in every name
--- it makes. A pack named for one of these words hands that word to its player frame, its target
--- frame and all the rest, so reading the name first would have believed the prefix over the unit.
--- Under `player` a misread needs the pack to be named for a group frame as well, and what it
--- costs is the difference between two answers the unit could not tell apart anyway.
---
--- **`GetAttribute`, not `GetEffectiveAttribute`.** What we want is the unit the frame owns, and
--- following `useparent-unit` up to a header would answer with the slot the header is filling.
---
--- **The unit may not be there to read yet.** A frame library can hand the frame over from its
--- styling pass and write the unit attribute only after that pass returns, so the first call on
--- such a frame sees no unit at all. That is why an `unknown` answer is never treated as settled -
--- see `RegisterFrame`.
local function ReadFrameType(button)
    if (IsGroupHeaderChild(button)) then
        return Constants.FRAMETYPE_GROUP;
    end

    local name = button.GetName and button:GetName();
    name = type(name) == "string" and strlower(name) or nil;

    if (name) then
        for i = 1, #KNOWN_PACK_FRAMES do
            local row = KNOWN_PACK_FRAMES[i];
            if (row[3] and strfind(name, row[1])) then
                return UNITFRAME_TYPES[row[3]];
            end
        end
    end

    local unit = button:GetAttribute("unit");
    if (type(unit) ~= "string") then
        return;
    end

    unit = strlower(unit);
    if (unit ~= "player") then
        return UNIT_FRAMETYPES[unit];
    end

    if (name) then
        for i = 1, #GROUP_NAME_WORDS do
            if (strfind(name, GROUP_NAME_WORDS[i], 1, true)) then
                return Constants.FRAMETYPE_GROUP;
            end
        end
    end

    return Constants.FRAMETYPE_PLAYER;
end

--- **Under `pcall` for the same reason `SetPropagateOne` is.** `GetName` is the call this file was
--- already burnt by - the compact frame hook carries an `ignoreCUFNameRequirement` guard because
--- it raised "calling 'GetName' on bad self" - and on 12.1 `IsForbidden` answering false at the
--- gate above no longer means a frame can be touched. A frame that cannot answer forfeits the
--- derivation and registers as `unknown`, which is where it stood before any of this.
local function DeriveFrameType(button)
    local ok, frameType = pcall(ReadFrameType, button);
    if (ok) then
        return frameType;
    end
end


--- 이미 `OnEnter`/`OnLeave`를 감싼 프레임. 아래 `_wrapped`와 같은 물건이고, 같은 이유로
--- 비운 적이 없다.
---
--- **등록이 풀려도 안 뗀다.** `SecureHandlerUnwrapScript`이 떼는 것은 맨 위 래퍼인데
--- (`SecureHandlers.lua`의 `RemoveWrapper`가 `frame:GetScript`으로 지금 걸린 것을 잡는다),
--- 그것이 우리 것이라는 보장이 없다. 남이 나중에 같은 스크립트를 감쌌으면 우리가 부르는 그
--- 호출은 **남의 것을 떼고 우리 것은 남긴다.** 그러면 `ccframes`에 행이 없는 프레임에서 우리
--- 본문이 계속 돌고, 남의 래퍼는 영영 사라진다. 우리가 감싼 `OnClick`이 진작 이렇게 하고
--- 있었고 `OnEnter`/`OnLeave`만 안 그랬다.
---
--- **그래서 해제는 본문이 한다.** `ccframes[self]`에 행이 없으면 `setup_onenter`는 물러나고,
--- 물러나면서 호버 슬롯을 비운다. 추적 안 하는 프레임 안에 커서가 있다는 것 자체가 우리가
--- 마지막으로 적어둔 프레임 안에는 없다는 뜻이라, 그 빈 자리가 곧 맞는 답이다.
local _hoverWrapped = setmetatable({}, { __mode = "k" });

--- 이미 `OnClick`을 감싼 프레임. **`ccframes` 엔트리로는 못 센다** - 우리는 래퍼를 떼지 않는데
--- 해제 때 그 엔트리는 사라지므로, 다시 등록되면 두 번 감싸게 된다.
local _wrapped = setmetatable({}, { __mode = "k" });

---------------------------------------------------------------------------
-- Standing on top of another addon's wrappers
--
-- `devdocs/legacy/standing-on-top-of-foreign-wrappers.md`.
---------------------------------------------------------------------------

--- The three scripts we wrap, and the only ones the hooks below answer for.
local REASSEMBLED_SCRIPTS = { OnEnter = true, OnLeave = true, OnClick = true };

--- The frame a reassembly is in the middle of. **Read before anything else in the hooks**, and set
--- and cleared synchronously: two engines that both re-wrap on being wrapped over pile up on the
--- call stack rather than over time, so deferring the judgement to a timer leaves the stack to grow
--- in between. Measured without a guard: 198 frames deep and a C stack overflow.
---
--- **A depth and not a flag, so that an inner pass cannot lift an outer one's guard.** Zero is
--- written back as `nil` rather than left as a number, because `ContestedNow` asks whether the row
--- is there and a `0` answers yes.
local _reassembling = setmetatable({}, { __mode = "k" });
local _warnedContested = false;

--- Hands the restricted side the one leave body our own wrapper has to run for the frame, or
--- clears it where there is none.
---
--- **`OnLeave` is the only script that needs this, and only because the client will not do it.**
--- Everything this pass takes off goes straight back on, so `OnEnter` and `OnClick` run out of the
--- chain the way they always did. `Wrapped_OnLeave` clears `_wrapentered` before it descends, so
--- once we are outermost the body that used to be is never reached, and a handle restricted
--- attributes refuse to write (`_` prefix) is what rules out putting the flag back.
---
--- **The header arrives through a frame ref** rather than as an argument: a frame handle comes out
--- nil through `RunAttribute`'s varargs (measured 2026-08-28), and a header is a frame.
--- `over_leave_keep` is what says whether to read it, because a wrapper is free to carry no pre
--- and `SecureHandlerSetFrameRef` has no way to hand over nothing.
---
--- Clearing has to leave nothing behind, because the leave path reads `Overs[button]` first and a
--- row that exists costs it a second lookup for nothing.
local STORE_OVERS_SNIPPET = [=[
	local button = self:GetFrameRef("clickcast_button")
	if (not self:GetAttribute("over_leave_keep")) then
		Overs[button] = nil
		return
	end

	local over = Overs[button]
	if (not over) then
		over = newtable()
		Overs[button] = over
	end
	over.handle = self:GetFrameRef("over_leave")
	over.pre = self:GetAttribute("over_leave_pre")
	over.post = self:GetAttribute("over_leave_post")
]=];

--- What the leave body we run is given. The client compiles a motion post as `self,message`;
--- running it through `RunFor` gives it `self,...` instead, so the name it expects is declared for
--- it here.
---
--- **The pre half needs none.** `Wrapped_OnLeave` compiles a pre with the signature `self` alone,
--- so there is no argument to name, and inventing one would put that body's own names one place
--- out.
local OVER_POST_PROLOGUE = "local message = ...\n";

local Reassemble;

--- Declared here and written further down, with the other two doors that go and find a frame
--- nobody handed over. The wrap hook below is one of the moments it listens on.
local TakeNamedFrame;

--- Our own pre and post for one script. **Only the leave pair has a post**, and it has one only to
--- run the leave body the client will not reach (`STORE_OVERS_SNIPPET`).
local function OurBodies(script)
	if (script == "OnClick") then
		return DebindPrivate.UnitFrameClickPre;
	end
	if (script == "OnEnter") then
		return BindingDriver:GetAttribute("setup_onenter");
	end
	return BindingDriver:GetAttribute("setup_onleave_wrap"),
		BindingDriver:GetAttribute("setup_onleave_post");
end

--- Whether this script on this frame is one we put a wrapper on.
---
--- **The row is not the question.** A frame gets its motion wrappers and its click wrapper at
--- different moments -- `RegisterFrame` does the first pair, `ApplyDebindRouting` the second, and
--- a frame that was refused a click wrapper still has a row.
local function WrappedByUs(button, script)
	if (script == "OnClick") then
		return _wrapped[button] and true or false;
	end
	return _hoverWrapped[button] and true or false;
end

--- **Steps off a frame rather than trading the top with another engine forever.**
---
--- **The refusal sentinel is what makes it stick, and `nil` is not one.** `RegisterFrame` reads
--- `== false` for a frame it has already refused; clearing the row instead leaves it looking like a
--- frame nobody has met, so the next header update, `TakeNamedFrame` or `ClickCastFrames` write
--- registers it again, re-arms the same contest, and stands down again -- with `DeinitFrame` firing
--- each round and the warning suppressed after the first.
---
--- The wrapper stays where it is, as every wrapper of ours does, and the body it runs stands down on
--- its own once the restricted row is gone. The other addon's wrappers are untouched, because every
--- one of them was put back on the frame where it was; the leave body we hold a second copy of goes
--- on being run too, since stopping it is the one thing that would break the addon we stood down
--- for.
local function StandDown(button)
	local row = DebindPrivate.ccframes[button];
	DebindPrivate.ccframes[button] = false;
	if (row and row.hd) then
		local name = button.GetName and button:GetName();
		if (name) then
			DebindPrivate.hccframes[name] = nil;
		end
	end

	if (row and not InCombatLockdown()) then
		SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "clickcast_button", button);
		SecureHandlerExecute(DebindPrivate.BindingDriver, [=[
			local button = self:GetFrameRef("clickcast_button")
			self:RunFor(button, self:GetAttribute("DeinitFrame"))
		]=]);
	end

	if (not _warnedContested) then
		_warnedContested = true;
		DebindPrivate.DisplayMessage(L["WARNING_MESSAGE_UNIT_FRAME_CONTESTED"]);
	end
end

--- Takes the wrappers another addon put on this script off, puts every one of them back where it
--- was, and lays ours on top.
---
--- **The chain is left doing its own work.** `SecureHandlerWrapScript` stacks rather than replaces,
--- so unwrapping down to our own header and wrapping the same bodies again in reverse order gives
--- the frame back the chain it had, minus our wrapper, which then goes on top. Everything the
--- client did -- running each pre outermost first, stopping the descent on `false`, unwinding the
--- posts it owes, carrying a renamed click button down -- it goes on doing, because those bodies
--- are still wrappers and not entries in a list of ours.
---
--- **The walk stops at our own header, and our own has already come off by then** -- the call that
--- reported it is the call that removed it. Reaching nil instead means nothing of ours was on this
--- script, which is the first registration, or that somebody took our wrapper off.
---
--- **`OnLeave` is the one that cannot be left to the chain**, and the reason is
--- `STORE_OVERS_SNIPPET`. The body that was outermost is handed to the restricted side as well as
--- put back, so our own leave body can run it; putting it back is what keeps it from being lost
--- when a later pass finds a newer one above us.
--- The body of one reassembly. **Split out so the guards around it come off whatever happens**:
--- every call in here reaches the secure handler API, which raises on a frame the client has turned
--- forbidden since we last looked, and a `movingOwnScripts` left standing would silence all three
--- hooks for the rest of the session.
local function ReassembleBody(button, script, pre, post)
	local headers, pres, posts = {}, {}, {};
	local taken, metOurs = 0, false;
	while (true) do
		local header, tookPre, tookPost = SecureHandlerUnwrapScript(button, script);
		if (not header) then
			break;
		end
		if (header == BindingDriver) then
			metOurs = true;
			break;
		end
		taken = taken + 1;
		headers[taken], pres[taken], posts[taken] = header, tookPre, tookPost;
	end

	for i = taken, 1, -1 do
		SecureHandlerWrapScript(button, script, headers[i], pres[i], posts[i]);
	end

	-- **What we hold stands until this pass finds a new outermost.** Taking nothing while our own
	-- header was still there means the chain below us is the one we already answered for; taking
	-- nothing without meeting ours means there is no leave body left to run at all.
	if (script == "OnLeave" and (taken > 0 or not metOurs)) then
		BindingDriver:SetAttribute("over_leave_keep", taken > 0);
		if (taken > 0) then
			SecureHandlerSetFrameRef(BindingDriver, "over_leave", headers[1]);
			BindingDriver:SetAttribute("over_leave_pre", pres[1]);
			BindingDriver:SetAttribute("over_leave_post",
				posts[1] and (OVER_POST_PROLOGUE .. posts[1]) or nil);
		end
		SecureHandlerSetFrameRef(BindingDriver, "clickcast_button", button);
		SecureHandlerExecute(BindingDriver, STORE_OVERS_SNIPPET);
	end
end

function Reassemble(button, script)
	local pre, post = OurBodies(script);
	if (type(pre) ~= "string") then
		return;
	end

	_reassembling[button] = (_reassembling[button] or 0) + 1;
	-- **Every wrap and unwrap in the body is ours.** `ClickCastTable.lua` listens on both globals to
	-- hear a holder let a frame go, and `OnForeignWrap` would read our own re-attaching as an engine
	-- wrapping over us and stand the frame down. Neither can tell from the arguments -- an unwrap
	-- carries no header and a re-attached wrap carries the other addon's -- so the flag is what says
	-- so, the same way `RewrapUnitFrames` says it. Restored rather than cleared, because that
	-- function is one of the callers that reaches here with it already up.
	local wasMovingOwn = DebindPrivate.movingOwnScripts;
	DebindPrivate.movingOwnScripts = true;

	local ok, err = pcall(ReassembleBody, button, script, pre, post);

	DebindPrivate.movingOwnScripts = wasMovingOwn;

	-- **Nothing of ours goes back on a frame that raised.** What the body touches is the secure
	-- handler API, so a frame it could not take apart is one this call would raise on again, and the
	-- error goes on to the caller either way.
	--
	-- **The re-entry guard is still up for this one call**, because an engine that answers our wrap
	-- with its own does it from inside it, and that is the whole definition `ContestedNow` reads.
	local wrapOk, wrapErr = true, nil;
	if (ok) then
		wrapOk, wrapErr = pcall(SecureHandlerWrapScript, button, script, BindingDriver, pre, post);
	end

	local depth = _reassembling[button] - 1;
	_reassembling[button] = depth > 0 and depth or nil;

	if (not ok) then
		error(err, 0);
	elseif (not wrapOk) then
		error(wrapErr, 0);
	end
end

--- Whether this pass is somebody wrapping over us **because** we wrapped, and steps off if it is.
---
--- **That is the whole definition of a fight, and it is synchronous by construction.** The hooks
--- fire inside `SecureHandlerWrapScript`, so an engine that answers our wrap with its own does it
--- while our reassembly of that frame is still on the stack. Nothing is counted: a count cannot
--- tell that engine from one re-laying its own wrapper on a schedule, and Clique does exactly that
--- -- `ApplyAttributes` unwraps and rewraps both hover scripts on every frame it holds, and the
--- seven callers of it include entering and leaving combat, a party member doing either, and any
--- profile or binding change (read from Clique v5.0.14, 2026-09-11). A budget of eight per session
--- stood us down from every Blizzard frame on the third loading screen (code review, 2026-09-08).
local function ContestedNow(button)
	if (_reassembling[button]) then
		StandDown(button);
		return true;
	end

	return false;
end

--- Somebody wrapped one of the three scripts on a frame we are on, so we are no longer the
--- outermost. Take the top back and carry what they left.
--- **Two jobs on one hook, and they are about different frames.** A wrap is also one of the
--- moments a pack's own frame passes on its way into its own click casting, which is the only
--- moment the name door has to catch one (`TakeNamedFrame`). Ours is not a discovery, so that half
--- sits under the same header test.
local function OnForeignWrap(frame, script, header)
	if (header == BindingDriver or header == DebindPrivate.UnitWatch) then
		return;
	end

	-- **Our own re-attaching carries their header**, so the test above cannot tell it from an
	-- engine wrapping over us, and reading it that way would stand the frame down mid reassembly.
	if (DebindPrivate.movingOwnScripts) then
		return;
	end

	-- **Registering is itself a reassembly of every script**, and the wrapper being reported is
	-- already on the frame when a hook fires, so the call above has dealt with it and the rest of
	-- this function would be a second pass over the same script.
	local wasOurs = DebindPrivate.ccframes[frame] ~= nil;
	TakeNamedFrame(frame);
	if (not wasOurs and DebindPrivate.ccframes[frame] ~= nil) then
		return;
	end

	if (not REASSEMBLED_SCRIPTS[script]) then
		return;
	end
	if (not DebindPrivate.ccframes[frame] or not WrappedByUs(frame, script)) then
		return;
	end
	if (InCombatLockdown()) then
		return;
	end
	if (ContestedNow(frame)) then
		return;
	end
	Reassemble(frame, script);
end

--- The frames whose top has to be taken back on the next tick, by script.
---
--- **Nothing of ours is on those scripts while a row sits here.** An engine took our wrapper off and
--- we have not put it back yet, so between the unwrap and the tick that frame's hover and click are
--- the other addon's alone. `_hoverWrapped` and `_wrapped` go on saying we wrapped it, which is what
--- lets the tick find it again and what keeps `RegisterFrame` from laying a second one.
local _retop = setmetatable({}, { __mode = "k" });
local _retopQueued;
local RetopPending;

--- **One pass per tick.** An engine re-lays every frame it holds in one go, and each of those would
--- otherwise book its own.
local function QueueRetop()
	if (_retopQueued) then
		return;
	end
	_retopQueued = true;
	C_Timer.After(0, function()
		_retopQueued = false;
		RetopPending();
	end);
end

--- Somebody unwrapped one. The top was ours, so what came off was ours, and **the wrapper that call
--- meant to take is still on the frame.**
---
--- **So the call is passed on rather than read.** One more `SecureHandlerUnwrapScript` takes their
--- outermost, which is exactly what that call would have taken had we never been on this frame, and
--- then we go back on top. Nothing here asks who called or what they wanted: an unwrap carries no
--- header (`SecureHandlerUnwrapScript(frame, script)`), so the only answer available is the one the
--- game would have given without us.
---
--- **What that costs, and why it is the smaller cost.** Where the wrapper we pass the call on to
--- belongs to a third addon rather than to the caller, it comes off for a call that was never about
--- it. That is the same thing the game does on a frame we are not on, so it is a cost the reader
--- already had; reading the call as "they are done with this frame" or as "they are replacing their
--- own" instead would be a guess, and a guess is wrong on whichever of the two this call was not.
--- The cases and what was measured are in `.zzz/answering-a-foreign-unwrap.md`.
---
--- **Going back on top is deferred by a tick, and that is not a tidiness.** An engine that unwraps
--- in a loop until the chain is empty would never see it empty: every pass would take ours and we
--- would put ours straight back. Deferred, that loop ends and we arrive after it.
---
--- **Combat cannot reach here.** `SecureHandlerUnwrapScript` works by writing attributes on
--- `LOCAL_API_Frame`, which is protected, and `API_OnAttributeChanged` raises on
--- `InCombatLockdown()` before doing anything (`SecureHandlers.lua`).
---
--- **`_reassembling` is not one of the tests here, and that is the whole difference from what it
--- used to be.** Every unwrap of ours is bracketed by `movingOwnScripts`, so the only unwrap
--- that can arrive while our reassembly is on the stack is somebody else's answer to it -- a fight,
--- which is `ContestedNow`'s to name. Testing it up here returned first and left that call
--- unreachable, so an engine that answers a wrap by taking the top back was ignored: our new
--- wrapper was gone from the frame while `WrappedByUs` went on saying it was there.
local function OnForeignUnwrap(frame, script)
	if (DebindPrivate.movingOwnScripts) then
		return;
	end
	if (not REASSEMBLED_SCRIPTS[script]) then
		return;
	end
	if (not DebindPrivate.ccframes[frame] or not WrappedByUs(frame, script)) then
		return;
	end
	if (ContestedNow(frame)) then
		return;
	end

	local wasMovingOwn = DebindPrivate.movingOwnScripts;
	DebindPrivate.movingOwnScripts = true;
	local ok, err = pcall(SecureHandlerUnwrapScript, frame, script);
	DebindPrivate.movingOwnScripts = wasMovingOwn;
	if (not ok) then
		error(err, 0);
	end

	local scripts = _retop[frame];
	if (not scripts) then
		scripts = {};
		_retop[frame] = scripts;
	end
	scripts[script] = true;
	QueueRetop();
end

--- Takes the top back on every frame an unwrap passed through last tick.
---
--- **In combat the pass is kept rather than dropped.** A tick is long enough for a fight to start,
--- and `Events.PLAYER_REGEN_ENABLED` calls this again.
--- **The frames are taken out of the table before any of them is answered for.** Each reassembly
--- wraps, every other addon hooking that global is called from inside it, and one that answers by
--- unwrapping a frame of its own puts a new key in here -- which is what Lua 5.1 leaves `next`
--- undefined for.
function RetopPending()
	if (InCombatLockdown()) then
		return;
	end

	local pending = {};
	local n = 0;
	for frame, scripts in pairs(_retop) do
		n = n + 1;
		pending[n] = { frame, scripts };
		_retop[frame] = nil;
	end

	for i = 1, n do
		local frame, scripts = pending[i][1], pending[i][2];
		for script in pairs(scripts) do
			if (DebindPrivate.ccframes[frame] and WrappedByUs(frame, script)) then
				--- **One frame may not take the rest of the batch with it.** `Reassemble` re-raises
				--- so a foreign wrap or unwrap hears what happened inside its own call; here there
				--- is no such caller, and the rows are already out of `_retop` (above), so a raise
				--- escaping this loop drops every frame after it for good while `_hoverWrapped`
				--- goes on saying we are on them.
				---
				--- It also escaped `Events.PLAYER_REGEN_ENABLED`, which calls this second and does
				--- the frame queue, the click queue, the click edge and the suspended rebuild after
				--- it. A frame problem left a fight's worth of bindings unbuilt.
				---
				--- DEBUG-only surfacing, the reason `_walkRefused` gives: a release reader can do
				--- nothing with it, and what it costs is this one frame's hover and click.
				local ok, err = pcall(Reassemble, frame, script);
				if (Constants.DEBUG and not ok) then
					print(format("[Debind] RetopPending: %s on %s raised: %s",
						script, tostring(frame.GetName and frame:GetName() or frame), tostring(err)));
				end
			end
		end
	end
end

DebindPrivate.RetopPending = RetopPending;

--- **Hooked at file scope, ahead of any profile being readable, because both of these ask for a
--- row before they act** and a frame we have no row for leaves them at their first check.
hooksecurefunc("SecureHandlerWrapScript", OnForeignWrap);
hooksecurefunc("SecureHandlerUnwrapScript", OnForeignUnwrap);

function DebindPrivate.RegisterFrame(button, type)
    --- **The blacklist is asked here and nowhere else, because every door comes through here.**
    --- A frame the reader has ticked gets no row, so nothing wraps it and nothing reassembles it,
    --- whether it arrived through the Clique table, a header, a library list or the name door.
    ---
    --- **That sentence was false until the header door was folded in.** `clickcast_register` used
    --- to register from inside the restricted environment and write our row from `CallMethod`, so
    --- it never passed this gate and a pack the reader had ticked went on registering through its
    --- group headers. What the box did depended on which layout that reader had picked
    --- (`devdocs/legacy/drawing-the-unit-frame-option-boundary.md`).
    ---
    --- **A name no row covers is answered by the last box instead of by nobody**
    --- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md` decided the first half; the
    --- second is `Any Other Addon`). Blizzard's seven are asked one door earlier
    --- (`registerBlizzardFrame`) and are exempt here for that reason: `blizzardFrames` holds every
    --- frame that door has seen, `false` in it meaning a compact frame it could not sort, which is
    --- still not somebody else's addon.
    ---
    --- **It takes every addon we do not know by name, the ones that hand their frames over
    --- included.** Refusing only the frames nobody offered would be a line no tooltip can draw:
    --- "offered" is the vocabulary of the Clique API, and a reader ticking this has something
    --- broken and needs the blunt answer.
    local pack = PackAddonForFrame(button);
    if (pack) then
        if (not DebindPrivate.TakesPackFrames(pack)) then
            return;
        end
    elseif (DebindPrivate.blizzardFrames[button] == nil
            and not DebindPrivate.TakesOtherAddonFrames()) then
        return;
    end

    if (DebindPrivate.ccframes[button] == false) then
        return;
    end

    --- **`unknown` is the absence of an answer, so it does not close the question.** An addon
    --- registers the same frame more than once, and the second call is often the one that can be
    --- answered: a frame library registers from its styling pass and only writes the unit
    --- attribute after it, and the addon on top of that library registers again once the frame is
    --- finished. Standing down on `type` matching alone spent the second call on a frame we had
    --- already given up on.
    ---
    --- **And what is compared is the answer, not the argument the caller happened to pass.** The
    --- same frame arrives under different arguments from different doors - `"group"` off its
    --- header, `true` through the Clique shape - and comparing those had a header's child
    --- re-registered on every pass that reached it, with the frame read afresh each time
    --- (`_headerChildren` says why that reading is wrong).
    ---
    --- What `seen.hd` says is that the header door registered this frame, which is the same
    --- sentence it always said -- only the writer moved. It used to be the snippet's word for
    --- "I have been here"; now it is this function's.
    local seen = DebindPrivate.ccframes[button];
    local told = _headerChildren[button] and Constants.FRAMETYPE_GROUP or UNITFRAME_TYPES[type];
    if (seen and (seen.hd or (seen.frameType ~= Constants.FRAMETYPE_UNKNOWN
            and (told == nil or told == seen.frameType)))) then
        ClaimForHeader(button, seen);
        return;
    end

    if (not button.IsProtected or not button:IsProtected()) then
        DebindPrivate.ccframes[button] = false;
        return;
    end

    if (button.IsForbidden and button:IsForbidden()) then
        DebindPrivate.ccframes[button] = false;
        return;
    end

    if (button.IsAnchoringRestricted and button:IsAnchoringRestricted()) then
        DebindPrivate.ccframes[button] = false;
        return;
    end

    if (not button.RegisterForClicks) then
        DebindPrivate.ccframes[button] = false;
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.FrameQueue, { button, type });
        if (#DebindPrivate.FrameQueue == 1) then
            DebindPrivate.DisplayMessage(L["UNABLE_TO_REGISTER_UNIT_FRAME_IN_COMBAT"]);
        end
        return;
    end

    local frameType = told or DeriveFrameType(button) or UNITFRAME_TYPES.unknown;
    button:SetAttribute("debind_frametype", frameType);

    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "clickcast_button", button);
    SecureHandlerExecute(DebindPrivate.BindingDriver, [=[
		local button = self:GetFrameRef("clickcast_button")
		self:RunFor(button, self:GetAttribute("InitFrame"))
		ccframes[button].frameType = button:GetAttribute("debind_frametype")
	]=]);

    --- **The row goes down before the first wrap, not after.** `OnForeignWrap` opens with
    --- `not ccframes[frame]`, so an engine that answers our wrap by wrapping over it -- the very
    --- behaviour the contest handling exists for -- was rejected at that gate when it happened
    --- during registration. `ContestedNow` was never asked, nothing was said, and we were left
    --- underneath their `OnLeave` with the hover slot never cleared. `OnClick` never had the
    --- problem because `UpdateRegisteredClicks` runs after this line.
    local row = { type = type, frameType = frameType };
    DebindPrivate.ccframes[button] = row;

    if (not _hoverWrapped[button]) then
        _hoverWrapped[button] = true;
        Reassemble(button, "OnEnter");
        Reassemble(button, "OnLeave");
    end

    --- **The contest can fire from inside those two now that the row is down first**, and standing
    --- down puts the refusal sentinel in its place. Going on to claim would write the header name
    --- back for a frame we just stepped off.
    if (DebindPrivate.ccframes[button] == row) then
        ClaimForHeader(button, row);
        DebindPrivate.UpdateRegisteredClicks(button);
    end
end

--- A forbidden object errors on **any** method call from addon-tainted code, so the whole branch
--- is skipped rather than just the call - descending into its children would raise the same error
--- one level down. `IsForbidden` is the one method that stays answerable there.
---
--- The check at the registration gate (`IsForbidden` above) is not enough: it sees the button we
--- were handed, and what turns up forbidden here is a **child** of a Blizzard frame that passed it.
---
--- **`IsForbidden` answering false no longer means the call is safe.** On 12.1, private-aura
--- frames attached to unit frames answer false and still raise the forbidden-object error from
--- `SetPropagateMouseMotion` (access constraints without the explicit mark - observed in an
--- arena, where such a frame sat under every Grid2 button). And a 12.1 `GetChildren` can hand
--- back secret values, which blow up on the `not frame` test itself. There is no pre-check that
--- covers those, so each frame is handled under `pcall`: everything that touches the frame is
--- inside, and a frame that cannot be touched forfeits its subtree - same policy as the
--- forbidden skip, which stays as the cheap first gate.
local function SetPropagateOne(frame)
    if (not frame or (frame.IsForbidden and frame:IsForbidden())) then
        return;
    end
    if (frame.SetPropagateMouseMotion) then
        frame:SetPropagateMouseMotion(true);
    end
    if (frame.GetChildren) then
        return frame:GetChildren();
    end
end

local SetPropagate;

--- Counted across the whole recursion, reported per registered frame at the call site.
--- DEBUG-only surfacing: a release user can do nothing with it, and the cost of a refused
--- frame is only that hover may release over that subtree - which was already true of every
--- frame the walk could not see.
local _walkRefused = 0;

--- Only a frame whose own handling succeeded gets its children walked; the varargs pass
--- `GetChildren`'s returns through without a table in between.
local function Descend(ok, ...)
    if (ok) then
        SetPropagate(...);
    else
        _walkRefused = _walkRefused + 1;
    end
end

function SetPropagate(...)
    local n = select("#", ...);
    for i = 1, n do
        Descend(pcall(SetPropagateOne, (select(i, ...))));
    end
end

--- 우리 자리를 프레임에 얹는다.
---
--- **남의 자리를 안 건드리는 것이 요점이다.** 접미사가 `-debind1`이라 블리자드의 `type1`/`type2`와
--- 겹치지 않는다. 값이 상태에 안 달려서(언제나 같은 프레임) 등록 때 한 번 쓰면 끝이고, 승자가
--- 바뀌어도 다시 쓸 일이 없다 - 어느 액션인가는 래퍼가 클릭 순간에 정한다.
---
--- 그 래퍼가 `nil`을 반환하면 버튼 이름이 그대로 남아 프레임의 원래 동작으로 떨어진다. 우리가
--- 아무 자리도 안 뺏었으므로 되돌릴 것이 없다.
local function ApplyDebindRouting(button)
    button:SetAttribute("*type-debind1", "click");
    button:SetAttribute("*clickbutton-debind1", DebindPrivate.DefaultClickFrame);

    if (not _wrapped[button] and DebindPrivate.UnitFrameClickPre) then
        _wrapped[button] = true;
        Reassemble(button, "OnClick");
    end
end

--- 본문이 다시 구워졌을 때(테스트 키트의 프로브 스위치) 감싼 것을 새 본문으로 갈아준다.
---
--- 여기서는 떼도 된다. **재베이크는 테스트 세션에서만 도는 길이고** 전투 밖이다. 실제 플레이에
--- 이 함수가 도달하는 경로는 없다.
function DebindPrivate.RewrapUnitFrames()
    -- **우리 호출을 남의 것으로 듣지 않게 하는 표시.** `DebindCliqueFake`가 wrap과 unwrap을
    -- 다 후킹해서 홀더가 프레임을 잡고 놓는 순간을 듣는데, **unwrap 쪽은 인자에 헤더가
    -- 없다**(`SecureHandlers.lua`의 `SecureHandlerUnwrapScript(frame, script)`). wrap 쪽에서
    -- 우리 것을 걸러내는 헤더 비교가 거기서는 언제나 nil을 보므로 아무 일도 안 한다.
    --
    -- 그러면 아래 루프가 우리 프레임마다 "홀더가 놓았다"를 한 번씩 내보내고, 다음 틱에
    -- 전부 다시 물어보게 된다. 인자로는 못 가르니 부르는 쪽이 말해준다.
    -- 아래 `_reassertingClicks`가 같은 이유로 있는 같은 수법이다.
    DebindPrivate.movingOwnScripts = true;

    for button in pairs(_wrapped) do
        _wrapped[button] = nil;
        SecureHandlerUnwrapScript(button, "OnClick");
    end

    DebindPrivate.movingOwnScripts = nil;

    for button, entry in pairs(DebindPrivate.ccframes) do
        if (entry) then
            ApplyDebindRouting(button);
        end
    end
end

--- Frames whose click input we are listening to, and the guard that keeps our own calls from
--- being heard as somebody else's. Never emptied, for the reason `_hoverWrapped` is not: a hook
--- is not removable, so forgetting one only means installing a second.
local _clickHooked                 = {};
local _reassertingClicks           = false;

--- **Both edges, because this call has no owner.** `RegisterForClicks` is the frame's state rather
--- than a subscription, so the last addon to call it decides for every wrapper on that frame.
--- Asking for the release alone left us with nothing at all on a frame somebody else had since
--- moved to the press, and the failure is silent: the key stops working and no error is raised
--- anywhere.
---
--- **It is not us overruling the frame's own choice of edge.** A frame library leaves this to
--- whoever takes the frame for click casting - oUF never calls it at all, and a UI pack built on
--- oUF registers the left and right buttons for its own menu and says in as many words that the
--- click-cast engine sets its own. Widening it is also what makes a binding on the middle or thumb
--- buttons arrive: a frame registered for left and right delivers nothing else.
---
--- **It does not make the frame's own action fire twice.** Delivery and action are separate:
--- `SecureActionButton_OnClick` computes
--- `clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)`, so the frame acts on
--- exactly one of the two edges however many are delivered, and `useOnKeyDown` falls back to
--- `ActionButtonUseKeyDown`. Registering an edge only decides what arrives.
---
--- Which of the two we answer on is the reader's, and the click wrapper's to apply
--- (`SecureBindings.lua`).
---
--- **The wheel is set here with them**, because the two travel together: an addon that narrows
--- the click registration on a frame turns the wheel off in the next line, so putting only the
--- edges back leaves a wheel binding dead.
local function ReassertClickInput(button)
    _reassertingClicks = true;
    button:RegisterForClicks("AnyUp", "AnyDown");
    button:EnableMouseWheel(true);
    _reassertingClicks = false;
end

--- **Somebody else has narrowed the frame, so put it back.**
---
--- A click-casting addon carries an edge of its own and writes it onto every frame it takes, ours
--- among them, and it rewrites it on every re-registration rather than only when its setting moves.
--- Turning its own click casting off is the same thing again, with the wheel going off beside the
--- edges. Left alone, a frame stops delivering what the reader bound and their bindings go quietly
--- dead there. Waiting for the next loading screen or the end of the fight does not cover it.
---
--- **Both methods reach here, and each puts both back.** They are called one after the other, so
--- answering only for the one that was called would be undone by the next line.
---
--- **`hooksecurefunc`, which is what keeps this clean.** The wrapper it installs calls the original
--- and then `securecall`s this, so no execution that reaches the frame afterwards carries our
--- taint. What it does not lift is that `RegisterForClicks` is protected, so a call of our own is
--- refused in combat and goes to the queue that already exists for it. And `securecall` swallows
--- whatever is raised in here without a word, which is why there is so little of it.
local function OnFrameClickInputChanged(button)
    if (_reassertingClicks or not DebindPrivate.ccframes[button]) then
        return;
    end

    if (InCombatLockdown()) then
        tinsert(DebindPrivate.RegisterClickQueue, button);
        return;
    end

    ReassertClickInput(button);
end

function DebindPrivate.UpdateRegisteredClicks(button)
    if (InCombatLockdown()) then
        tinsert(DebindPrivate.RegisterClickQueue, button)
        return
    end

    ApplyDebindRouting(button);

    if (not _clickHooked[button]) then
        _clickHooked[button] = true;
        hooksecurefunc(button, "RegisterForClicks", OnFrameClickInputChanged);
        hooksecurefunc(button, "EnableMouseWheel", OnFrameClickInputChanged);
    end

    ReassertClickInput(button);

    -- 프레임 내에 마우스에 반응하는 자식 프레임이 있는 경우 그 자식 프레임으로 마우스를 올렸을 때
    -- 부모 프레임에서 onleave 스크립트가 호출되지 않게 함.
    _walkRefused = 0;
    SetPropagate(button:GetChildren());
    if (Constants.DEBUG and _walkRefused > 0) then
        print(format("[Debind] SetPropagate: %d refused frame(s) under %s",
            _walkRefused, button:GetName() or tostring(button)));
    end
end

---------------------------------------------------------------------------
-- The three doors nobody hands a frame through
--
-- `devdocs/legacy/standing-on-top-of-foreign-wrappers.md`. A pack running click casting of its own
-- registers nothing with anybody, so these are the ways a frame reaches us without its owner
-- offering it. Standing on top of whatever that pack wraps is what makes taking one of them safe.
--
-- **None of the three asks anything of its own**: `RegisterFrame` holds the one gate, and a frame
-- the blacklist covers leaves it before anything is touched.
---------------------------------------------------------------------------

--- The libraries to ask, keyed by the global each publishes itself under, valued by how far into
--- its list we have got. `{ ["oUF_Foo"] = 12 }`.
---
--- **Built once, because the answer cannot change.** `X-oUF` is read out of the `.toc`, which the
--- client parses for every addon at startup whether it loads it or not - the addon list draws icons
--- and categories for disabled addons off the same call. So the walk over `GetNumAddOns()` happens
--- on the first pass and never again, and what is left after it is one or two entries.
---
--- Keyed by the name and not by the library, because an addon that has not loaded yet has no
--- global at all. Its entry sits here reading nil until it does.
---
--- **The number is a mark and not a "have we run yet" flag.** `objects` is appended to for as long
--- as the session lasts - a header gets more children as the roster grows, and a frame spawned
--- later lands on the end - so a pass that ran once would only ever see what existed at that
--- moment. Starting from the mark means every pass takes the new tail and leaves the frames already
--- offered alone, which is what makes running this on every `PLAYER_ENTERING_WORLD` cost nothing.
--- One mark each, because two addons carrying their own copy of oUF are two separate lists.
---
--- **`X-oUF` is oUF's own contract and not an addon name.** An addon shipping the library declares
--- the global it wants the library under, and the library reads that field and installs itself
--- there (`local global = C_AddOns.GetAddOnMetadata(parent, "X-oUF")`, then `_G[global] = oUF`).
--- Asking every loaded addon the same question is asking oUF where it is, whoever is carrying it,
--- so no UI pack's name is written down here.
---
--- **`objects` is all of them, whatever its own comment says.** oUF documents the field as the
--- frames `Spawn` made, and `initObject` appends to it before the branch that separates a spawned
--- frame from a header's child, so a header's children are in there too. Which is what we want:
--- the header hands its children over itself only if its addon speaks a protocol, and this reaches
--- them either way. `headers` is left alone for that reason - it holds nothing `objects` does not.
local _oufLibraries;

function DebindPrivate.CollectOUFFrames()
    if (not _oufLibraries) then
        _oufLibraries = {};
        for i = 1, C_AddOns.GetNumAddOns() do
            local global = C_AddOns.GetAddOnMetadata(i, "X-oUF");
            if (type(global) == "string" and global ~= "") then
                _oufLibraries[global] = 0;
            end
        end
    end

    for global, seen in pairs(_oufLibraries) do
        local library = _G[global];
        local objects = type(library) == "table" and library.objects;

        if (type(objects) == "table") then
            for j = seen + 1, #objects do
                -- Handed over the way the Clique protocol hands one over, since that is the door
                -- these frames were aimed at. Everything a frame can be turned away for is
                -- `RegisterFrame`'s: a refusal it already recorded, unprotected, forbidden,
                -- anchor-tied, or unable to take a click.
                --
                -- Under `pcall` for the reason `SetPropagateOne` gives: on 12.1 a frame answering
                -- `IsForbidden` false is no longer proof that touching it will not raise. A frame
                -- that cannot be looked at is left where it already stood.
                pcall(DebindPrivate.RegisterFrame, objects[j], true);
            end
            _oufLibraries[global] = #objects;
        end
    end
end

--- **Caught as the pack wires the frame up, because that is the only moment there is.** A pack
--- builds these when they are first needed rather than at login, so a look on any event of ours
--- finds only whatever happened to exist by then. `SecureUnitButtonTemplate` carries no `OnLoad`
--- and a global appearing announces nothing, so what is left is the calls a frame passes on its way
--- into somebody's click casting.
---
--- **Several doors, because none of them is compulsory.** A pack is free to skip any one of these -
--- nothing in the game makes a unit frame call `SecureUnitButton_OnLoad` or `RegisterUnitWatch` -
--- so listening on one would be betting on a habit. Listening on all of them costs nothing: a frame
--- already registered leaves `RegisterFrame` on the row it has, before any of the checks, and a
--- name no row covers never gets that far.
---
--- **The hook only decides when, and `KNOWN_PACK_FRAMES` decides what.** Everything arriving at
--- these is an addon's doing, which is exactly why no test on the frame itself would do - it would
--- have to be right about addons we have never seen. The name is asked instead.
---
--- **A wrap of our own is not a discovery.** `RegisterFrame` wraps through `BindingDriver` on the
--- very frames the table matches, and the row it is about to write is not there yet.
--- Whether the frame was built from `SecureUnitButtonTemplate`.
---
--- **The template hangs the global function itself on `OnClick`**
--- (`SecureTemplates.xml`: `<OnClick function="SecureUnitButton_OnClick"/>`), while
--- `SecureActionButtonTemplate` carries an inline body, so a cast button's handler is a closure of
--- its own and never this object. That is what makes the comparison answer "unit frame" rather
--- than "secure button", which no other test on the frame can do -- a cast button is protected,
--- takes clicks, and can carry a `unit` attribute of its own.
---
--- **A false answer here is always the safe direction.** An addon that replaced the script, or a
--- wrapper already standing on it, reads as "not one of ours" and the frame is left alone.
local function IsUnitButtonTemplate(frame)
    if (not SecureUnitButton_OnClick or not frame.GetScript) then
        return false;
    end
    local ok, handler = pcall(frame.GetScript, frame, "OnClick");
    return ok and handler == SecureUnitButton_OnClick;
end

--- Whether the client's own door owns this frame.
---
--- Blizzard's unit frames carry the same template, so the test above says yes to all of them. They
--- have their own door and their own seven boxes (`registerBlizzardFrame`), and a frame taken here
--- instead would answer to `Any Other Addon` -- the reader would tick "Party Frames" and nothing
--- would happen.
---
--- **`ignoreCUFNameRequirement` is Blizzard's own mark on the ones with no name**, the nameplate
--- unit frame among them, and the compact hook already leaves on it for that reason.
local function IsBlizzardsOwn(frame, name)
    if (DebindPrivate.blizzardFrames[frame] ~= nil or frame.ignoreCUFNameRequirement) then
        return true;
    end
    return strfind(name, "^compact") ~= nil
        or strfind(name, "^boss%d+targetframe$") ~= nil
        or BLIZZARD_FRAME_NAMES[name] == true;
end

function TakeNamedFrame(frame)
    -- Under `pcall` for the reason `SetPropagateOne` gives: on 12.1 a frame answering
    -- `IsForbidden` false is no longer proof that touching it will not raise. `GetName` in
    -- particular is the call this file was already burnt by (see `DeriveFrameType`).
    local ok, name = pcall(NameOf, frame);
    if (not ok or type(name) ~= "string") then
        return;
    end

    name = strlower(name);
    for i = 1, #KNOWN_PACK_FRAMES do
        local row = KNOWN_PACK_FRAMES[i];
        if (strfind(name, row[1])) then
            pcall(DebindPrivate.RegisterFrame, frame, row[3] or true);
            return;
        end
    end

    for i = 1, #NEVER_OURS_FRAMES do
        if (strfind(name, NEVER_OURS_FRAMES[i])) then
            return;
        end
    end

    if (IsUnitButtonTemplate(frame) and not IsBlizzardsOwn(frame, name)) then
        pcall(DebindPrivate.RegisterFrame, frame, true);
    end
end

--- The frame here is the third argument: the one being handed to a secure header, rather than the
--- header doing the handing.
local function OnSecureFrameRef(header, _, frame)
    if (header == BindingDriver or header == DebindPrivate.UnitWatch) then
        return;
    end
    if (frame) then
        TakeNamedFrame(frame);
    end
end

--- **The children of a group header, taken off the header itself.**
---
--- Every other way we hear about one of these depends on its addon connecting to us. The header
--- protocol connection is made once, when the header is built, by reading a global we have to be
--- standing in at that moment (`Public.lua`); a header built before that, or one whose addon does
--- not speak the protocol at all, is never joined and none of its children ever arrive. The table
--- is no better: whoever holds its name at the time gets the writes.
---
--- **A header knows its children exactly.** `configureChildren` puts each unit button in a `child<i>`
--- attribute as it makes it (`SecureGroupHeaders.lua`), so the attributes enumerate the unit buttons
--- and nothing else. `GetChildren()` would hand back the backgrounds and textures with them.
---
--- **They are group frames, all of them.** A header hands its children whichever unit they are
--- filling right now and takes it back, so the token on a child says which slot it is and not what
--- the frame is. The pet headers are here for the same answer: what someone reading "pet frame"
--- pictures is their own pet's frame, not a grid of other people's pets.
local function CollectHeaderChildren(header)
    -- **Ours are group headers too, and the hook below cannot tell.** `UnitWatch.lua` builds its
    -- role watchers out of `SecureGroupHeaderTemplate`, so they come through here like anyone
    -- else's, and their children pass every gate `RegisterFrame` has. Registering them wires
    -- click-casting onto frames that have no size and are never on screen.
    if (DebindPrivate.OwnGroupHeaders[header]) then
        return;
    end

    local i = 1;
    while (true) do
        local child = header:GetAttribute("child" .. i);
        if (not child) then
            return;
        end
        -- **Marked before it is offered, and the mark stays.** This is the only door that knows
        -- these frames are a header's, and the answer has to hold for the doors that do not
        -- (`_headerChildren`).
        _headerChildren[child] = true;
        -- Under `pcall` for the reason `SetPropagateOne` gives: on 12.1 a frame answering
        -- `IsForbidden` false is no longer proof that touching it will not raise.
        pcall(DebindPrivate.RegisterFrame, child, "group");
        i = i + 1;
    end
end

--- **Two hooks per header kind, because one of them may never fire.** `OnLoad` is the earliest a
--- header can be caught and the only one that catches a header that is never shown, but the
--- template names it in XML and what that binds is not ours to see. `SecureGroupHeader_Update` is
--- named from Lua by `SecureGroupHeader_OnEvent` and `_OnAttributeChanged`, so hooking it resolves
--- at the call and is certain. It is also where the children are made, which makes it the re-walk:
--- a header gains children as the group does, and this runs the moment after it did.
---
--- Both are cheap to run twice. A child already registered leaves `RegisterFrame` on the row it
--- already has, before any of the checks.
hooksecurefunc("SecureGroupHeader_OnLoad", CollectHeaderChildren);
hooksecurefunc("SecureGroupHeader_Update", CollectHeaderChildren);
hooksecurefunc("SecureGroupPetHeader_OnLoad", CollectHeaderChildren);
hooksecurefunc("SecureGroupPetHeader_Update", CollectHeaderChildren);

hooksecurefunc("SecureHandlerSetFrameRef", OnSecureFrameRef);
hooksecurefunc("RegisterStateDriver", TakeNamedFrame);
hooksecurefunc("RegisterAttributeDriver", TakeNamedFrame);
-- **Each one asked for, because a global that is not there raises.** These live in addons the
-- client loads at startup rather than in the frame code proper, and a build that ships without
-- one would take the whole file down on load.
if (SecureUnitButton_OnLoad) then
    hooksecurefunc("SecureUnitButton_OnLoad", TakeNamedFrame);
end
if (RegisterUnitWatch) then
    hooksecurefunc("RegisterUnitWatch", TakeNamedFrame);
end
if (UnitFrame_Initialize) then
    hooksecurefunc("UnitFrame_Initialize", TakeNamedFrame);
end

--- **The one door named after a single addon, because HealBot shuts every other one.** It writes
--- nothing into `ClickCastFrames`, speaks no header protocol, hangs its buttons off a plain
--- `SecureFrameTemplate` frame rather than a group header, and ships no oUF. Its buttons are
--- reachable only through its own code (`devdocs/how-unit-frames-reach-us.md` §6).
---
--- **`HealBot_Action_RegisterUnitEvents` is the call, because it is the moment a button becomes a
--- unit frame.** HealBot writes the unit attribute and then registers that button's unit events in
--- the same pass, so the frame arrives here already carrying what `ReadFrameType` would read. It is
--- also what keeps the test bars out on their own: they are handed a plain field instead of a unit
--- and never reach this call.
---
--- **The emergency button is fetched rather than waited for.** HealBot builds the pair together and
--- gives both the same unit, but registers events on the heal button alone -- so its twin would
--- never come through this door. `HealBot_Emerg_Button` is keyed by the id HealBot stamps on both.
---
--- **Nothing here was promised to us**, which is the difference between this door and the oUF one:
--- `objects` is a field oUF publishes for whoever wants it, and this is a function name inside
--- somebody's addon. A rename leaves the hook uninstalled, takes no frame of theirs, and raises
--- nothing -- and no check of ours can see it (§8).
local function TakeHealBotButton(button)
    TakeNamedFrame(button);

    local pair = type(button) == "table" and button.id
        and HealBot_Emerg_Button and HealBot_Emerg_Button[button.id];
    if (pair) then
        TakeNamedFrame(pair);
    end
end

--- **Asked for at login rather than at file scope, because the global is somebody else's.** Load
--- order between two addons that declare no dependency on each other is not ours to know, so this
--- waits for `PLAYER_LOGIN`, by which every addon the client loads at startup has run its files.
--- HealBot's first button comes later still: it is built on a refresh its own timers drive, and
--- that refresh cannot have run before the roster events that raise its flag.
function DebindPrivate.AttachPackHooks()
    if (HealBot_Action_RegisterUnitEvents) then
        hooksecurefunc("HealBot_Action_RegisterUnitEvents", TakeHealBotButton);
    end
end

--- **Ticking a box does not take the frame back.** A ticked box is a set we do not register from
--- next login rather than one we hand back now. The boxes say so themselves (`REQUIRES_RELOAD` in
--- `SettingsTab.lua`), and reading the login snapshot rather than the stored table is what makes that
--- true in both directions - unticking used to register on the spot under the same tooltip.
--- **The snapshot may have no shape at all**, which is why the table is asked for rather than
--- walked through. `StandDown` hands out an empty profile and never takes a snapshot, but it does
--- call `BindDerivedTables`, so `DebindPrivate.Options` stands and the `CompactUnitFrame_SetUpFrame`
--- hook's gate on it passes. `TakesPackFrames` guards the same way.
local function registerBlizzardFrame(frame, category)
    local blacklist = DebindPrivate.optionsAtLogin.frameBlacklist;
    if (blacklist == nil or blacklist.blizzard[category] ~= false) then
        local options = BLIZZARD_UNITFRAME_OPTIONS[category];
        DebindPrivate.RegisterFrame(frame, options and options.type);
    end
end

--- **These seven are ours whether or not Clique is installed.** Blizzard handed its unit frames to
--- nobody: Clique picks them up itself (`Clique/modules/Blizzard_utils.lua`) exactly as we do, and
--- both of them going through `ClickCastFrames` on the way is Clique's implementation rather than a
--- door the frame came in by (`devdocs/legacy/coexisting-with-clique.md` §5). What the reader
--- decides here is the seven boxes.
function DebindPrivate.UpdateBlizzardFrames(firstTime)

    if (firstTime) then
        local function addFrame(frame, frameType)
            if (frame) then
                DebindPrivate.blizzardFrames[frame] = frameType;
            end
        end

        addFrame(PlayerFrame, "player");
        addFrame(PetFrame, "pet");
        addFrame(TargetFrame, "target");
        addFrame(TargetFrameToT, "target");
        addFrame(FocusFrame, "target");
        addFrame(FocusFrameToT, "target");

        for i = 1, MAX_PARTY_MEMBERS do
            addFrame(PartyFrame["MemberFrame" .. i], "party");
        end

        for i = 1, MAX_BOSS_FRAMES do
            addFrame(_G["Boss" .. i .. "TargetFrame"], "boss");
        end
    end

    for frame, category in pairs(DebindPrivate.blizzardFrames) do
        if (category) then
            registerBlizzardFrame(frame, category);
        end
    end
end

--- **Blizzard's compact frames, and they are ours whether or not Clique is installed**, for the
--- reason `UpdateBlizzardFrames` gives.
hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
    -- **The flag is Blizzard's own exemption from the name requirement**, and the frames that
    -- carry it are the ones we must not call `GetName` on. `CompactUnitFrame.lua:26` reads
    -- `if not self.ignoreCUFNameRequirement and not self:GetName()`, and the templates that
    -- set it are the nameplate unit frame, the raid-frame settings preview, and the compact
    -- frame container. The nameplate is the one that showed up here, as
    -- "calling 'GetName' on bad self".
    --
    -- None of the three is a frame click-casting has any business on, so leaving the branch
    -- is the whole of what is needed. Testing for a nameplate by name would be the wrong
    -- shape twice over: the name is what cannot be read, and Blizzard already keeps the list.
    if (frame.ignoreCUFNameRequirement) then
        return;
    end

    local category = DebindPrivate.blizzardFrames[frame];
    if (category == nil) then
        local name = frame:GetName();
        if (name) then
            local m1 = name:match("^Compact([A-Za-z]+)Frame[A-Za-z]*%d+$");
            if (m1 == "Party" or m1 == "Raid" or m1 == "Arena") then
                category = strlower(m1);
            elseif (name:match("^CompactRaidGroup%d+Member%d+$")) then
                category = "raid";
            end
        end

        DebindPrivate.blizzardFrames[frame] = category or false;

        if (category) then
            if (DebindPrivate.Options) then
                registerBlizzardFrame(frame, category);
            end
        end
    end
end);
