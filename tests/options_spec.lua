-- **The settings window's rows, as values.** Everything the panel draws is out of reach here --
-- the list, the search box, the Defaults button and the greying itself are the game's -- so what
-- this asks is what the panel would ask: which settings exist, what a row reads, what its setter
-- writes, whether a row is modifiable, whether a row is shown.
--
-- The two things that need the client are in `/debtest`: that the category really appears in the
-- AddOns tab, and that showing it leaves the list's scroll state secure (`issecurevariable` is the
-- client's).

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
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

    _G.DebindVars = {
        dbver = Constants.DB_VERSION,
        shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
        characters = { ["Player-1-TESTGUID"] = { layers = {}, switches = {} } },
        migrated = {},
        switches = {},
    };
    DebindPrivate.InitDB();

    --- **One pack is installed while the list is built, and only while it is built.** The pack rows
    --- are drawn from what is loaded (`LoadedKnownPacks`), which is read once here, so a spec with
    --- nothing installed could only ever measure the seven client windows. Put back straight after,
    --- because the addon list is the shim's and the specs after this one share it.
    local savedLoaded = C_AddOns.IsAddOnLoaded;
    local savedMetadata = C_AddOns.GetAddOnMetadata;
    C_AddOns.IsAddOnLoaded = function(addon) return addon == "Grid2"; end;
    C_AddOns.GetAddOnMetadata = function(addon, field)
        if (addon == "Grid2" and field == "Title") then
            return "Grid2 |cff00ff00Raid Frames|r";
        end
    end;
    DebindPrivate.RegisterOptionsCategory();
    C_AddOns.IsAddOnLoaded = savedLoaded;
    C_AddOns.GetAddOnMetadata = savedMetadata;

    local function setting(variable)
        local s = Settings.GetSetting("DEBIND_" .. variable);
        check(s ~= nil, "no setting for " .. variable);
        return s;
    end

    --- The row an initializer was made for, found by the setting it carries. The shim keeps them
    --- in the order they were registered, which is the order the reader sees.
    local function rowFor(variable)
        for _, row in ipairs(shim.world.settingsRows) do
            if (row.data.setting and row.data.setting.variable == "DEBIND_" .. variable) then
                return row;
            end
        end
    end

    ---------------------------------------------------------------------------
    -- The category, and that every row in the design's table is here
    ---------------------------------------------------------------------------

    test("the category is registered under the addon's own name", function()
        local category = shim.world.settingsCategory;
        check(category ~= nil, "no category");
        check(category.name == DebindPrivate.L["ADDON_NAME"], "named " .. tostring(category.name));
        check(category.registered == true, "never handed to RegisterAddOnCategory");
    end);

    test("every option the menu held has a setting", function()
        local expected = {
            "UNITFRAME_CLICK_EDGE",
            "BLIZZARD_UNIT_FRAMES_PLAYER", "BLIZZARD_UNIT_FRAMES_PET",
            "BLIZZARD_UNIT_FRAMES_TARGET", "BLIZZARD_UNIT_FRAMES_PARTY",
            "BLIZZARD_UNIT_FRAMES_RAID", "BLIZZARD_UNIT_FRAMES_BOSS",
            "BLIZZARD_UNIT_FRAMES_ARENA",
            "SMART_CAST_ENABLED",
            "SMART_CAST_BATTLEREZ", "SMART_CAST_REZ", "SMART_CAST_DISPEL", "SMART_CAST_BUFF",
            "SMART_CAST_REZWITHBATTLEREZ",
            "EXCLUDE_PLAYER_TANK", "EXCLUDE_PLAYER_HEALER",
            "EXCLUDE_PLAYER_MAINTANK", "EXCLUDE_PLAYER_MAINASSIST",
            "STATE_DRIVER_UPDATE_THROTTLE",
        };
        for i = 1, #expected do
            check(Settings.GetSetting("DEBIND_" .. expected[i]) ~= nil, "missing " .. expected[i]);
            check(rowFor(expected[i]) ~= nil, "no row for " .. expected[i]);
        end
    end);

    --- Every row from the first unit frame header up to the one before Smart Cast, as
    --- `{ kind, name }`. A header carries its words in `data.name` the same way a box does.
    local function unitFrameRows()
        local out, taking = {}, false;
        for _, row in ipairs(shim.world.settingsRows) do
            local name = row.data.name;
            if (name == UNITFRAME_LABEL) then
                taking = true;
            elseif (name == DebindPrivate.L["SMART_CAST_DEFAULTS"]) then
                break;
            end
            if (taking) then
                out[#out + 1] = { row.kind, name };
            end
        end
        return out;
    end

    --- **Two headers and one list of boxes under the second.** Grouping is what says which rows
    --- belong together at this depth, and taking `UNITFRAME_LABEL` rather than a key of ours is
    --- what keeps the window and the game from calling one thing two things.
    ---
    --- **The client's seven always stand, so the blacklist header never stands empty.** The pack
    --- rows come after them and only for what is installed, which is Grid2 alone here.
    test("the unit frame rows stand in two headed groups", function()
        local L = DebindPrivate.L;
        local expected = {
            { "header", UNITFRAME_LABEL },
            { "dropdown", L["UNITFRAME_CLICK_EDGE"] },
            { "header", L["LEAVE_UNIT_FRAMES_ALONE"] },
            { "checkbox", L["BLIZZARD_UNIT_FRAMES_PLAYER"] },
            { "checkbox", L["BLIZZARD_UNIT_FRAMES_PET"] },
            { "checkbox", L["BLIZZARD_UNIT_FRAMES_TARGET"] },
            { "checkbox", L["BLIZZARD_UNIT_FRAMES_PARTY"] },
            { "checkbox", L["BLIZZARD_UNIT_FRAMES_RAID"] },
            { "checkbox", L["BLIZZARD_UNIT_FRAMES_BOSS"] },
            { "checkbox", L["BLIZZARD_UNIT_FRAMES_ARENA"] },
            { "checkbox", "Grid2 |cff00ff00Raid Frames|r" },
        };
        local rows = unitFrameRows();
        check(#rows == #expected, "the section holds " .. #rows .. " rows, not " .. #expected);
        for i = 1, #expected do
            check(rows[i][1] == expected[i][1] and rows[i][2] == expected[i][2],
                i .. ": " .. tostring(rows[i][1]) .. " " .. tostring(rows[i][2]));
        end
    end);

    --- **No box here is the parent of another, and a parent is what indentation would say.** Every
    --- one of them only takes something away, so two being off at once needs no explaining; a
    --- nesting would claim the child means nothing while the parent is off, which is not true of
    --- any pair here. Asserting the flatness is what keeps somebody from reaching for a parent box
    --- later without reading why it was left out.
    test("no unit frame row is indented under another", function()
        for _, row in ipairs(shim.world.settingsRows) do
            local variable = row.data.setting and row.data.setting.variable;
            if (variable and strfind(variable, "UNIT_FRAMES", 1, true)) then
                check(row:GetIndent() == 0, variable .. " is indented");
            end
        end
    end);

    ---------------------------------------------------------------------------
    -- What a setter writes, and that the default clears the cell
    ---------------------------------------------------------------------------

    --- **`nil` is one of the three and not the absence of one.** A dropdown cannot hold it, so the
    --- three are folded onto three strings; a fold that dropped one would leave the reader unable
    --- to give the answer back.
    test("the click edge folds three answers onto three strings and back", function()
        local s = setting("UNITFRAME_CLICK_EDGE");
        check(s:GetValue() == "game", "unset reads " .. tostring(s:GetValue()));

        s:SetValue("down");
        check(DebindPrivate.Options.unitframeUseMouseDown == true, "down did not store true");
        check(s:GetValue() == "down", "down did not read back");

        s:SetValue("up");
        check(DebindPrivate.Options.unitframeUseMouseDown == false, "up did not store false");
        check(s:GetValue() == "up", "up did not read back");

        s:SetValue("game");
        check(DebindPrivate.Options.unitframeUseMouseDown == nil,
            "the game's own answer was stored as a value instead of clearing the cell");
    end);

    --- **The box reads the other way round from the cell it writes.** Ticked is "leave alone" and
    --- the stored value is still `false`, which is what makes the change need no migration.
    test("a Blizzard unit frame box stores false and clears back to absent", function()
        local s = setting("BLIZZARD_UNIT_FRAMES_PARTY");
        check(s:GetValue() == false, "unset reads as left alone");

        s:SetValue(true);
        check(DebindPrivate.Options.frameBlacklist.blizzard.party == false, "ticked did not store false");

        s:SetValue(false);
        check(DebindPrivate.Options.frameBlacklist.blizzard.party == nil,
            "unticking left the default in the profile");
    end);

    test("an exclusion stores true and clears back to absent", function()
        local s = setting("EXCLUDE_PLAYER_HEALER");
        check(s:GetValue() == false, "unset reads as excluded");

        s:SetValue(true);
        check(DebindPrivate.Options.excludePlayer.healer == true, "on did not store true");

        s:SetValue(false);
        check(DebindPrivate.Options.excludePlayer.healer == nil,
            "back off left the default in the profile");
    end);

    --- Battle resurrection is the branch that is off by default, so it is the one where "the
    --- default clears the cell" and "false clears the cell" are different rules.
    test("a Smart Cast branch clears the cell at its own default, not at false", function()
        local s = setting("SMART_CAST_BATTLEREZ");
        check(s:GetValue() == false, "battle rez is on by default");

        s:SetValue(true);
        check(DebindPrivate.Options.smartCast.battleRez == true, "on did not store true");

        s:SetValue(false);
        check(DebindPrivate.Options.smartCast.battleRez == nil,
            "back off left the default in the profile");

        local rez = setting("SMART_CAST_REZ");
        check(rez:GetValue() == true, "resurrection is off by default");
        rez:SetValue(false);
        check(DebindPrivate.Options.smartCast.rez == false,
            "false is the stored value for a branch whose default is true");
        rez:SetValue(true);
        check(DebindPrivate.Options.smartCast.rez == nil, "back on left the default in the profile");
    end);

    test("the master switch stores false and clears back to absent", function()
        local s = setting("SMART_CAST_ENABLED");
        check(s:GetValue() == true, "unset reads as off");
        s:SetValue(false);
        check(DebindPrivate.Options.smartCast.enabled == false, "off did not store false");
        check(DebindPrivate.SmartCastEnabled() == false, "the addon still reads it as on");
        s:SetValue(true);
        check(DebindPrivate.Options.smartCast.enabled == nil, "back on left the default in the profile");
    end);

    test("the throttle stores a number and clears at the game's own", function()
        local s = setting("STATE_DRIVER_UPDATE_THROTTLE");
        check(s:GetValue() == Constants.STATE_DRIVER_UPDATETIME_DEFAULT,
            "unset reads " .. tostring(s:GetValue()));

        s:SetValue(0);
        check(DebindPrivate.Options.stateDriverUpdateThrottle == 0, "zero did not store");

        s:SetValue(Constants.STATE_DRIVER_UPDATETIME_DEFAULT);
        check(DebindPrivate.Options.stateDriverUpdateThrottle == nil,
            "the game's own value was stored instead of clearing the cell");
    end);

    --- **A setter never reaches a secure frame.** The panel is pressable during a fight, so the
    --- one thing every setter here may do is write and ask for a rebuild.
    test("a setter writes and queues a rebuild and touches nothing else", function()
        local mark = frames.mark();
        setting("EXCLUDE_PLAYER_TANK"):SetValue(true);
        local entries = frames.since(mark);
        check(#entries == 0, "a setter reached the secure side: " .. tostring(entries[1] and entries[1].kind));
        check(DebindPrivate.IsUpdateBindingsQueued(), "no rebuild was queued");
        setting("EXCLUDE_PLAYER_TANK"):SetValue(false);
    end);

    ---------------------------------------------------------------------------
    -- Which rows are greyed, and which are shown
    ---------------------------------------------------------------------------

    test("the four branches and the battle rez box go dead with the master switch", function()
        local enabled = setting("SMART_CAST_ENABLED");
        for _, branch in ipairs(DebindPrivate.SMART_CAST_BRANCHES) do
            check(rowFor("SMART_CAST_" .. strupper(branch)):IsModifiable(),
                branch .. " is dead with Smart Cast on");
        end

        enabled:SetValue(false);
        for _, branch in ipairs(DebindPrivate.SMART_CAST_BRANCHES) do
            check(not rowFor("SMART_CAST_" .. strupper(branch)):IsModifiable(),
                branch .. " is still live with Smart Cast off");
        end
        check(not rowFor("SMART_CAST_REZWITHBATTLEREZ"):IsModifiable(),
            "the battle rez box is still live with Smart Cast off");
        enabled:SetValue(true);
    end);

    --- **It is resurrection's sub-item, not a fifth branch**, so it stands directly under that row
    --- and a step further in. The settings list has one indent step of its own, which is why the
    --- second one has to be asked for (`Options.lua`).
    test("the battle rez box sits under resurrection, one step deeper", function()
        local rezIndex, withIndex;
        for i, row in ipairs(shim.world.settingsRows) do
            local variable = row.data.setting and row.data.setting.variable;
            if (variable == "DEBIND_SMART_CAST_REZ") then
                rezIndex = i;
            elseif (variable == "DEBIND_SMART_CAST_REZWITHBATTLEREZ") then
                withIndex = i;
            end
        end
        check(rezIndex and withIndex, "one of the two rows is missing");
        check(withIndex == rezIndex + 1,
            format("resurrection is row %d and the battle rez box is row %d", rezIndex, withIndex));

        local rezIndent = rowFor("SMART_CAST_REZ"):GetIndent();
        check(rezIndent > 0, "the branch rows are not indented at all");
        check(rowFor("SMART_CAST_REZWITHBATTLEREZ"):GetIndent() == rezIndent * 2,
            "the battle rez box is not a step deeper than the row it belongs to");
    end);

    test("the battle rez box follows the resurrection box as well", function()
        local row = rowFor("SMART_CAST_REZWITHBATTLEREZ");
        check(row:IsModifiable(), "dead while both are on");
        setting("SMART_CAST_REZ"):SetValue(false);
        check(not row:IsModifiable(), "still live with resurrection off");
        setting("SMART_CAST_REZ"):SetValue(true);
    end);

    --- **Nothing in this section is ever greyed, Clique installed or not.** There is no state to
    --- grey for any more: every unit frame is ours and the reader's only lever is the blacklist, so
    --- a dead box here would be a control they cannot reach over a thing that is running.
    test("no unit frame row carries a modify predicate", function()
        DebindPrivate.CliqueDetected = true;
        local ok, err = pcall(function()
            local rows = { "UNITFRAME_CLICK_EDGE",
                "BLIZZARD_UNIT_FRAMES_PLAYER", "BLIZZARD_UNIT_FRAMES_PET",
                "BLIZZARD_UNIT_FRAMES_TARGET", "BLIZZARD_UNIT_FRAMES_PARTY",
                "BLIZZARD_UNIT_FRAMES_RAID", "BLIZZARD_UNIT_FRAMES_BOSS",
                "BLIZZARD_UNIT_FRAMES_ARENA" };
            for i = 1, #rows do
                local row = rowFor(rows[i]);
                check(row.modifyPredicates == nil, rows[i] .. " carries a modify predicate");
                check(row:IsModifiable(), rows[i] .. " is dead");
            end
        end);
        DebindPrivate.CliqueDetected = nil;
        if (not ok) then
            error(err, 0);
        end
    end);

    --- **A row for an addon the reader does not have says nothing they can act on**, so only the
    --- installed ones are drawn -- one here, out of the twelve `KNOWN_PACK_FRAMES` names.
    test("a pack row stands only for an installed pack, named by its own Title", function()
        local packRows = {};
        for _, row in ipairs(shim.world.settingsRows) do
            local variable = row.data.setting and row.data.setting.variable;
            if (variable and strfind(variable, "DEBIND_PACK_FRAMES_", 1, true)) then
                packRows[#packRows + 1] = { variable, row.data.name };
            end
        end
        check(#packRows == 1, "the list holds " .. #packRows .. " pack rows, not 1");
        check(packRows[1][1] == "DEBIND_PACK_FRAMES_GRID2", packRows[1][1]);
        check(packRows[1][2] == "Grid2 |cff00ff00Raid Frames|r",
            "the row is not named by the addon's own Title: " .. tostring(packRows[1][2]));
    end);

    test("a pack box stores false and clears back to absent", function()
        local s = setting("PACK_FRAMES_GRID2");
        check(s:GetValue() == false, "unset reads as left alone");

        s:SetValue(true);
        check(DebindPrivate.Options.frameBlacklist.addons.Grid2 == false, "ticked did not store false");

        s:SetValue(false);
        check(DebindPrivate.Options.frameBlacklist.addons.Grid2 == nil,
            "unticking left the default in the profile");
    end);

    --- **No row may carry a shown predicate.** `ShouldShow` is read by the panel's `Display` and
    --- `RepairDisplay` outside any secure wrapper, and a predicate we stored is a tainted slot: the
    --- read taints the pass that then rebuilds the list, and the list's scroll state stays tainted
    --- for the session. Measured 2026-09-08 as `Frame:SetHeight()` blocked on a wheel scroll in
    --- combat. The legacy design document's §3 has the path.
    test("no row carries a shown predicate", function()
        for _, row in ipairs(shim.world.settingsRows) do
            check(row.shownPredicates == nil,
                (row.data.name or row.kind) .. " carries a shown predicate");
        end
    end);

    --- **The notice stands first and says the same thing at every moment.** A row that came and
    --- went with combat would be the panel adding and dropping a row, which is the shape the
    --- predicate check above exists for -- so this asks that it is unconditional as well as that
    --- it is there.
    test("the notice is the first row and reads the same in a fight as out of one", function()
        local notice;
        for _, row in ipairs(shim.world.settingsRows) do
            if (row.template == "DebindSettingsNoticeTemplate") then
                notice = row;
            end
        end
        check(notice ~= nil, "no row uses the notice template");
        check(notice == shim.world.settingsRows[1], "the notice is not the first row");
        check(notice.shownPredicates == nil, "the notice carries a shown predicate");

        local frame = shim.newSettingsNoticeFrame();
        DebindSettingsNoticeMixin.Init(frame, notice);
        check(frame.Text.text == notice:GetName(), "the notice did not take the row's name");

        shim.world.inCombat = true;
        local inCombat = shim.newSettingsNoticeFrame();
        DebindSettingsNoticeMixin.Init(inCombat, notice);
        shim.world.inCombat = false;
        check(inCombat.Text.text == frame.Text.text, "the line reads differently during a fight");
    end);

    --- **The colour moves and the row does not.** A fight recolours the words on our own frame,
    --- from our own events; nothing about the row's size or its place in the list changes, which
    --- is what keeps this off the path that tainted the scroll box.
    test("the notice turns red for the fight and back after it", function()
        local notice;
        for _, row in ipairs(shim.world.settingsRows) do
            if (row.template == "DebindSettingsNoticeTemplate") then
                notice = row;
            end
        end

        local frame = shim.newSettingsNoticeFrame();

        local function color()
            return table.concat(frame.Text.color, ",");
        end
        local function highlight()
            return table.concat({ HIGHLIGHT_FONT_COLOR:GetRGB() }, ",");
        end
        local function red()
            return table.concat({ RED_FONT_COLOR:GetRGB() }, ",");
        end

        DebindSettingsNoticeMixin.Init(frame, notice);
        check(color() == highlight(), "the line is already red out of combat");

        -- **Fired at the client, not called on the mixin.** What broke in the game was the
        -- registration and not the recolouring, so a spec that called the handler by hand would
        -- have stayed green through it (`Options.lua`).
        shim.world.inCombat = true;
        check(frames.fireEvent("PLAYER_REGEN_DISABLED") > 0, "nothing listens for the fight");
        check(color() == red(), "the fight did not turn the line red");

        shim.world.inCombat = false;
        check(frames.fireEvent("PLAYER_REGEN_ENABLED") > 0, "nothing listens for the fight ending");
        check(color() == highlight(), "the line stayed red after the fight");

        -- The reader who opens the window with the fight already on never sees an event.
        shim.world.inCombat = true;
        local opened = shim.newSettingsNoticeFrame();
        DebindSettingsNoticeMixin.Init(opened, notice);
        shim.world.inCombat = false;
        check(table.concat(opened.Text.color, ",") == red(),
            "a row drawn during a fight came up in the out-of-combat colour");
    end);

    ---------------------------------------------------------------------------
    -- What actually carries the answer across
    ---------------------------------------------------------------------------

    --- **The setters gave this up, so `ApplyOptions` has to have it.** A rebuild is the only hand
    --- that writes `showPlayer` now, and a value written to the profile with nothing carrying it
    --- is a setting that reads as set and does nothing.
    test("ApplyOptions writes showPlayer from the stored exclusions", function()
        local header = DebindPrivate.EnableUnitWatch("tank");
        check(header ~= nil, "no header to write on");

        setting("EXCLUDE_PLAYER_TANK"):SetValue(true);
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == false,
            "the exclusion never reached the header");

        setting("EXCLUDE_PLAYER_TANK"):SetValue(false);
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == true,
            "taking the exclusion back never reached the header");
    end);

    --- **And it stays off the header during a fight**, which is the whole reason the setters gave
    --- it up: the header is a `SecureGroupHeaderTemplate` and the write would raise.
    test("ApplyOptions leaves the header alone during a fight", function()
        local header = DebindPrivate.EnableUnitWatch("healer");
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == true, "not the value this starts from");

        shim.world.inCombat = true;
        setting("EXCLUDE_PLAYER_HEALER"):SetValue(true);
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == true,
            "the header was written during a fight");

        shim.world.inCombat = false;
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == false,
            "the fight ended and the answer never crossed");
        setting("EXCLUDE_PLAYER_HEALER"):SetValue(false);
    end);

    --- **The blacklist is read once at login, so a rebuild may not carry it anywhere.** It used to,
    --- and only in one direction: ticking a box could not take a wired frame back and so really did
    --- need the reload its tooltip promises, while unticking one reached `UpdateBlizzardFrames`
    --- from here and registered on the spot. `check:reload-options` asks the same thing of the
    --- source; this asks it of what runs.
    test("a rebuild does not carry the frame blacklist anywhere", function()
        local reached = false;
        local real = DebindPrivate.UpdateBlizzardFrames;
        DebindPrivate.UpdateBlizzardFrames = function() reached = true; end;

        setting("BLIZZARD_UNIT_FRAMES_PARTY"):SetValue(true);
        DebindPrivate.ApplyOptions();
        setting("BLIZZARD_UNIT_FRAMES_PARTY"):SetValue(false);
        DebindPrivate.ApplyOptions();

        DebindPrivate.UpdateBlizzardFrames = real;
        check(not reached, "a rebuild still registers the Blizzard frames");
    end);

    ---------------------------------------------------------------------------
    -- 리로드가 필요해졌는가
    ---------------------------------------------------------------------------

    --- **비교지 깃발이 아니다.** 켰다 다시 끄면 로그인 때와 같은 값이고, 그 사람에게 리로드를
    --- 시키는 것은 아무것도 아닌 일로 화면을 날리는 것이다.
    test("IsReloadRequired follows the value and comes back down", function()
        check(DebindPrivate.IsReloadRequired() == false, "아무것도 안 건드렸는데 참이다");

        setting("BLIZZARD_UNIT_FRAMES_PARTY"):SetValue(true);
        check(DebindPrivate.IsReloadRequired() == true, "블랙리스트가 움직였는데 거짓이다");

        setting("BLIZZARD_UNIT_FRAMES_PARTY"):SetValue(false);
        check(DebindPrivate.IsReloadRequired() == false,
            "값을 되돌렸는데도 리로드가 필요하다고 한다");
    end);

    --- 팩 칸도 같은 목록 하나로 들어온다. 없이는 위 케이스가 블리자드 칸만 재고 있어도 초록이다.
    test("IsReloadRequired sees the addon side of the blacklist too", function()
        setting("PACK_FRAMES_GRID2"):SetValue(true);
        check(DebindPrivate.IsReloadRequired() == true, "팩 칸은 안 세고 있다");
        setting("PACK_FRAMES_GRID2"):SetValue(false);
        check(DebindPrivate.IsReloadRequired() == false, "되돌렸는데 참으로 남았다");
    end);

    --- 리로드 목록에 없는 옵션은 그 자리에서 반영되니 이 물음의 답이 아니다. 옵션 이름이 아니라
    --- `options` 전체를 재기 시작하면 스마트 캐스트 상자 하나에 리로드 버튼이 켜진다.
    test("an option that applies at once does not ask for a reload", function()
        setting("SMART_CAST_ENABLED"):SetValue(false);
        check(DebindPrivate.IsReloadRequired() == false,
            "그 자리에서 반영되는 옵션이 리로드를 요구했다");
        setting("SMART_CAST_ENABLED"):SetValue(true);
    end);

    return T;
end
