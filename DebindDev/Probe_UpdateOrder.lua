-- Probe_UpdateOrder.lua
-- In which order the client runs frames' OnUpdate, and whether a frame of ours can be put right
-- before SecureStateDriverManager's so that the two time one pass of it.
--
--   /debuo [n]   the next n frames (default 120): which rule orders OnUpdate. Groups of three
--                frames of ours, set up so that each candidate rule predicts a different order.
--                Written to DebindDevDB.updateOrderRule.
--     ABC  created hidden, script set A C B, then shown B A C (Show comes last)
--     DEF  created hidden, shown E F D, then script set F D E (the script comes last)
--     GHI  created shown and never hidden, no script, HookScript I G H
--     JKL  created shown with their scripts in that order, then J shown again while shown
--     M    the post-hook on the manager, for where ours fall against it
--   Measured 2026-10-10: each of the first three runs in the reverse order of the event that made
--   its frames updatable last, and the groups and the manager in the reverse order of setup. A
--   frame that becomes updatable goes to the front. JKL came out L K J: a Show on a shown frame
--   moves nothing, which matters because the manager calls Show on every registration.
--
--   /debhs       what takes an updatable frame out of the list, so that a Show puts it in front.
--                60 frames, written to DebindDevDB.hideShow. Two groups of three frames of ours:
--     STU  on frame 20, S hides T and U shows it again: one frame, and the walk passes T hidden
--     VWX  on frame 20, X hides W, and on frame 21 V shows it: across a frame boundary, and the
--          walk never reaches W hidden
--     A group whose middle frame moved to the front says what does it: the frame ending, or the
--     walk finding it hidden.
--   Measured 2026-10-10: STU stayed and T still ran on frame 20 after S hid it; VWX moved, W did
--   not run on frame 21 and ran first from 22. Hide and Show take effect when the frame ends, so a
--   pair inside one frame cancels, and a frame hidden across one boundary leaves the list.
--
--   /debud       watch the manager's passes until stopped, in combat or out, and our beat's share
--                of them. Starts by itself `LOGIN_DELAY` after login (after the combat a reload
--                came back into); the command starts it again after a stop. Nothing is kept per
--                frame: each quantity is a running count, sum, min, max and a histogram of 1 us
--                bins.
--   /debud show  print the figures so far and keep watching. They stand in the top left corner too,
--                twice a second.
--   /debud stop  print them, write them to DebindDevDB.updateOrder and stop. /reload after: the
--                hooks and the marker's driver stay. Logging out or reloading while watching
--                writes them the same way.
--
-- **A Hide and a Show in one frame move nothing** (measured 2026-10-10, and /debhs says why).
-- Frames already updatable, hidden and shown again in the call that set their scripts, ran in the
-- reverse order of the scripts and not of the Shows, and the manager stayed where it was, behind
-- every frame that became updatable since it did: the 33 us measured then between our frame and
-- the manager were other addons' OnUpdates.
--
-- So /debud hides the manager, lets `HIDDEN_FRAMES` frames go by, shows it, and puts two fresh
-- frames of ours in that same call. The manager goes to the front and ours in front of it;
-- anything that becomes updatable afterwards goes in front of all three, and a registration's Show
-- on the manager does not move it (JKL). Measured 2026-10-10 with three frames hidden: P-M 3.7 us
-- median where Q-P was 3.3, so nothing stood between, and the pass came to 88 us. For those frames
-- the manager does not run and its pass waits. Combat starting while it is hidden would leave
-- every state driver stopped, so the Show then waits for the end of combat.
--
-- **A placement is checked, not trusted.** Started at login, the same steps left P-M at 49.6 us
-- against Q-P 5.9 (2026-10-10): a registration's Show while the manager is hidden undoes the hide,
-- or puts it back early, and the login's frames take the place between. So nothing is counted
-- until `HEALTH_FRAMES` idle frames say P-M stays within `HEALTH_EXCESS_US` of Q-P, and a
-- placement that does not is taken again.
--
-- Each frame records, in the order they ran:
--   Q  a second frame of ours, set right after P: Q to P is what one OnUpdate to the next costs
--   P  our frame's OnUpdate
--   D  a marker driver of ours resolved inside the pass: present only on a frame where the
--      manager's throttle ran out and it walked its drivers
--   M  the post-hook on the manager
-- Every mark takes its time last, so the record a frame opens (always in Q) falls in neither gap.
--
-- Our beat's time comes from `DebindPrivate.OnBeatTimed` (`DebindBeatStart`, `DebindBeatEnd` in
-- `Debind.lua`), summed over the frame. It holds one `RunAttribute` a shipped build does not pay.
--
-- What to read:
--   order    the sequences seen and how often. "QPDM" and "QPM" alone say the three stand in order
--   idle     Q-P and P-M on frames without D. P-M near Q-P says nothing is between
--   pass     on a frame with D, P-M less that frame's Q-P (what one mark and one hand-over cost):
--            the pass, the marker's own driver included. All, out of combat and in combat, each
--            with ours and our share of the summed time

local TAG = "|cff66ccff[UD]|r ";
local HIDDEN_FRAMES = 3;
--- A placement is read over this many idle frames, and taken again when P-M runs past Q-P by
--- more than `HEALTH_EXCESS_US` on average: something then stands between ours and the manager.
--- Seen 2026-10-10: 0.4 us over on mainline, 4 us on classic_beta (whether anything stood between
--- there is not known), and 44 us for a placement that had failed.
local HEALTH_FRAMES = 120;
local HEALTH_EXCESS_US = 10;
local MAX_PLACEMENTS = 5;
--- How long after login the first placement waits, for the login's own registrations and the
--- frames it shows to settle: a registration's Show while the manager is hidden undoes the hide.
local LOGIN_DELAY = 5;
local MARK_ATTRIBUTE = "debudpass";
--- The histogram's last bin, in microseconds: a value past it is counted there, and `max` still
--- holds it.
local BINS = 2000;
local WHERE = { "all", "ooc", "combat" };

local installed = false;
local beatHooked = false;
local watching = false;
local current;
local currentTime;
local stats;

local function NewStat()
    return { n = 0, sum = 0, bins = {} };
end

local function Add(stat, ms)
    stat.n = stat.n + 1;
    stat.sum = stat.sum + ms;
    if (not stat.min or ms < stat.min) then
        stat.min = ms;
    end
    if (not stat.max or ms > stat.max) then
        stat.max = ms;
    end
    local bin = math.min(BINS, math.max(0, math.floor(ms * 1000)));
    stat.bins[bin] = (stat.bins[bin] or 0) + 1;
end

--- The lower edge, in microseconds, of the bin where the count reaches `p` of the samples.
local function Quantile(stat, p)
    local target = math.max(1, math.ceil(stat.n * p));
    local seen = 0;
    for bin = 0, BINS do
        seen = seen + (stat.bins[bin] or 0);
        if (seen >= target) then
            return bin;
        end
    end
    return BINS;
end

local function Summary(stat)
    if (stat.n == 0) then
        return { n = 0 };
    end
    return {
        n = stat.n,
        meanUs = stat.sum / stat.n * 1000,
        medianUs = Quantile(stat, 0.5),
        p95Us = Quantile(stat, 0.95),
        minUs = stat.min * 1000,
        maxUs = stat.max * 1000,
        sumMs = stat.sum,
    };
end

local function Line(label, stat)
    if (stat.n == 0) then
        return label .. " none";
    end
    return format("%s %d: mean %.1f us, median %d, p95 %d, min %.1f, max %.1f", label, stat.n,
        stat.sum / stat.n * 1000, Quantile(stat, 0.5), Quantile(stat, 0.95), stat.min * 1000,
        stat.max * 1000);
end

local function NewStats()
    local s = { frames = 0, orders = {}, idleQP = NewStat(), idlePM = NewStat() };
    for _, where in ipairs(WHERE) do
        s[where] = { pass = NewStat(), ours = NewStat() };
    end
    return s;
end

local Begin;

--- Where the placement stands: "placing" while the manager is hidden, "checking" while the first
--- `HEALTH_FRAMES` idle frames are read, "ok", or "FAILED" after `MAX_PLACEMENTS`.
local placement = { state = "none", tries = 0, n = 0, excess = 0 };

local function Close(r)
    if (not (r.Q and r.P and r.M)) then
        return;
    end
    local qp, pm = r.P - r.Q, r.M - r.P;
    if (placement.state ~= "ok") then
        if (placement.state == "checking" and not r.D) then
            placement.n = placement.n + 1;
            placement.excess = placement.excess + (pm - qp);
            if (placement.n >= HEALTH_FRAMES) then
                if (placement.excess / placement.n * 1000 > HEALTH_EXCESS_US) then
                    Begin();
                else
                    placement.state = "ok";
                end
            end
        end
        return;
    end
    stats.frames = stats.frames + 1;
    stats.orders[r.seq] = (stats.orders[r.seq] or 0) + 1;
    if (not r.D) then
        Add(stats.idleQP, qp);
        Add(stats.idlePM, pm);
        return;
    end
    local pass, ours = pm - qp, r.ours or 0;
    for _, where in ipairs({ "all", r.combat and "combat" or "ooc" }) do
        Add(stats[where].pass, pass);
        Add(stats[where].ours, ours);
    end
end

local function Mark(tag)
    if (not watching) then
        return;
    end
    local now = GetTime();
    if (now ~= currentTime) then
        currentTime = now;
        if (current) then
            Close(current);
        end
        current = { seq = "", combat = InCombatLockdown() };
    end
    current.seq = current.seq .. tag;
    if (not current[tag]) then
        current[tag] = debugprofilestop();
    end
end

local function OnBeat(ms)
    if (watching and current) then
        current.ours = (current.ours or 0) + ms;
    end
end

local function Report()
    local seqs = {};
    for seq, count in pairs(stats.orders) do
        seqs[#seqs + 1] = { seq = seq, count = count };
    end
    sort(seqs, function(a, b) return a.count > b.count; end);
    local parts = {};
    for i = 1, math.min(#seqs, 6) do
        parts[i] = format("%s x%d", seqs[i].seq, seqs[i].count);
    end
    print(TAG .. format("placement %s, try %d", placement.state, placement.tries));
    print(TAG .. format("%d frames. order: %s", stats.frames, table.concat(parts, ", ")));
    print(TAG .. Line("idle Q-P", stats.idleQP));
    print(TAG .. Line("idle P-M", stats.idlePM));
    for _, where in ipairs(WHERE) do
        local s = stats[where];
        print(TAG .. Line(where .. " pass", s.pass));
        if (s.pass.n > 0) then
            print(TAG .. Line(where .. " ours", s.ours) .. format(", share %.1f%%", s.ours.sum / s.pass.sum * 100));
        end
    end
end

local function Save()
    local saved = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        updatetime = SecureStateDriverManager:GetAttribute("updatetime"),
        placement = placement.state,
        placementTries = placement.tries,
        frames = stats.frames,
        orders = stats.orders,
        idleQP = Summary(stats.idleQP),
        idlePM = Summary(stats.idlePM),
    };
    for _, where in ipairs(WHERE) do
        saved[where] = { pass = Summary(stats[where].pass), ours = Summary(stats[where].ours) };
    end
    DebindDevDB = DebindDevDB or {};
    DebindDevDB.updateOrder = saved;
end

local anchorP, anchorQ;
local waiter = CreateFrame("Frame");

--- Shows the manager, which has been out of the OnUpdate list across a frame boundary, and puts two
--- fresh frames of ours in front of it. Fresh, because one already in the list keeps its place.
local function Place()
    SecureStateDriverManager:Show();
    if (anchorP) then
        anchorP:SetScript("OnUpdate", nil);
        anchorQ:SetScript("OnUpdate", nil);
    end
    anchorP = CreateFrame("Frame");
    anchorP:SetScript("OnUpdate", function()
        Mark("P");
    end);
    anchorQ = CreateFrame("Frame");
    anchorQ:SetScript("OnUpdate", function()
        Mark("Q");
    end);
    placement.state = "checking";
    placement.n, placement.excess = 0, 0;
    stats = NewStats();
    current, currentTime = nil, nil;
end

--- Takes the manager out of the list and places again `HIDDEN_FRAMES` later. Out of combat only;
--- a combat that starts while the manager is hidden leaves every state driver stopped until it
--- ends, so the Show waits for that.
function Begin()
    local function OnRegen(after)
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED");
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents();
            after();
        end);
    end
    if (InCombatLockdown()) then
        placement.state = "waiting for combat to end";
        OnRegen(Begin);
        return;
    end
    placement.tries = placement.tries + 1;
    if (placement.tries > MAX_PLACEMENTS) then
        placement.state = "FAILED";
        print(TAG .. format("could not put a frame right before the manager in %d tries", MAX_PLACEMENTS));
        return;
    end
    placement.state = "placing";
    SecureStateDriverManager:Hide();
    local passed = 0;
    waiter:SetScript("OnUpdate", function(self)
        passed = passed + 1;
        if (passed < HIDDEN_FRAMES) then
            return;
        end
        self:SetScript("OnUpdate", nil);
        if (InCombatLockdown()) then
            print(TAG .. "combat began while the manager was hidden: it is shown when combat ends");
            OnRegen(Place);
            return;
        end
        Place();
    end);
end

local function Install()
    SecureStateDriverManager:HookScript("OnUpdate", function()
        Mark("M");
    end);

    local marker = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate,SecureHandlerAttributeTemplate");
    marker.DebindDevPassMark = function()
        Mark("D");
    end
    marker:SetAttribute("_onattributechanged", format([[
        if (name == %q and value ~= 0) then
            self:CallMethod("DebindDevPassMark")
            self:SetAttribute(%q, 0)
        end
    ]], MARK_ATTRIBUTE, MARK_ATTRIBUTE));
    RegisterAttributeDriver(marker, MARK_ATTRIBUTE, "a");
    installed = true;
end

local display, ticker;

local function Mean(stat)
    return stat.n > 0 and stat.sum / stat.n * 1000 or 0;
end

local function DisplayText()
    local status = placement.state;
    if (status == "checking") then
        status = format("checking %d/%d", placement.n, HEALTH_FRAMES);
    end
    local lines = { format("state driver pass, us%s  [placement %s, try %d]", watching and "" or " (stopped)",
        status, placement.tries) };
    for _, where in ipairs(WHERE) do
        local s = stats[where];
        if (s.pass.n > 0) then
            lines[#lines + 1] = format("%s  n %d  mean %.1f  med %d  p95 %d  max %.1f", where, s.pass.n,
                Mean(s.pass), Quantile(s.pass, 0.5), Quantile(s.pass, 0.95), s.pass.max * 1000);
            lines[#lines + 1] = format("    ours  mean %.1f  med %d  share %.1f%%", Mean(s.ours),
                Quantile(s.ours, 0.5), s.ours.sum / s.pass.sum * 100);
        else
            lines[#lines + 1] = where .. "  -";
        end
    end
    lines[#lines + 1] = format("idle  Q-P %.1f  P-M %.1f", Mean(stats.idleQP), Mean(stats.idlePM));
    return table.concat(lines, "\n");
end

--- Refreshed from a ticker rather than an OnUpdate, so the display never joins the OnUpdate list
--- and never stands between the marks.
local function ShowDisplay()
    if (not display) then
        display = CreateFrame("Frame", nil, UIParent);
        display:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -8);
        display:SetSize(1, 1);
        display:SetFrameStrata("TOOLTIP");
        display.text = display:CreateFontString(nil, "OVERLAY");
        display.text:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE");
        display.text:SetPoint("TOPLEFT");
        display.text:SetJustifyH("LEFT");
    end
    display:Show();
    if (ticker) then
        ticker:Cancel();
    end
    ticker = C_Timer.NewTicker(0.5, function()
        display.text:SetText(DisplayText());
    end);
end

local function Start()
    local private = _G.DebindPrivate;
    if (private and not beatHooked) then
        beatHooked = true;
        local previous = private.OnBeatTimed;
        private.OnBeatTimed = function(ms)
            if (previous) then
                previous(ms);
            end
            OnBeat(ms);
        end
    end
    if (not installed) then
        Install();
    end
    stats = NewStats();
    current, currentTime = nil, nil;
    watching = true;
    placement.tries = 0;
    Begin();
    ShowDisplay();
    print(TAG .. "watching. /debud show for the figures so far, /debud stop to end.");
    if (not private) then
        print(TAG .. "Debind is not a development build: no beat times, ours stays empty");
    end
end

SLASH_DEBUD1 = "/debud";
SlashCmdList["DEBUD"] = function(msg)
    msg = strlower(strtrim(msg or ""));
    if (msg == "show" or msg == "stop") then
        if (not stats) then
            print(TAG .. "not watching");
            return;
        end
        Report();
        if (msg == "stop" and watching) then
            -- The frame in progress is left out: the slash command came in the middle of it.
            watching = false;
            current = nil;
            ticker:Cancel();
            display.text:SetText(DisplayText());
            Save();
            print(TAG .. "saved to DebindDevDB.updateOrder. /reload now.");
        end
        return;
    end
    if (watching) then
        print(TAG .. "already watching");
        return;
    end
    if (not installed and InCombatLockdown()) then
        print(TAG .. "out of combat to start: it registers a driver and hides the manager");
        return;
    end
    Start();
end

--- Watching starts `LOGIN_DELAY` after login, or when the combat a reload came back into ends.
local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_LOGIN");
events:RegisterEvent("PLAYER_LOGOUT");
events:SetScript("OnEvent", function(self, event)
    if (event == "PLAYER_LOGOUT") then
        if (watching) then
            Save();
        end
        return;
    end
    local function Try()
        if (watching) then
            return;
        end
        if (InCombatLockdown()) then
            self:RegisterEvent("PLAYER_REGEN_ENABLED");
            return;
        end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED");
        Start();
    end
    if (event == "PLAYER_LOGIN") then
        C_Timer.After(LOGIN_DELAY, Try);
    else
        Try();
    end
end);

local RULE_FRAMES = 120;
local ruleBuilt = false;
local ruleWanted;
local ruleRecords = {};
local ruleTime;

--- Each group's orders as each rule predicts them; the reverse of each is checked too. In GHI
--- nothing is ever hidden, so Show order is creation order there. JKL's two are written already
--- reversed, the way the first three came out.
local GROUPS = {
    { letters = "ABC", predictions = { creation = "ABC", script = "ACB", show = "BAC" } },
    { letters = "DEF", predictions = { creation = "DEF", show = "EFD", script = "FDE" } },
    { letters = "GHI", predictions = { creation = "GHI", hook = "IGH" } },
    { letters = "JKL", predictions = { ["Show on a shown frame moves it"] = "JLK",
        ["Show on a shown frame moves nothing"] = "LKJ" } },
};

local function RuleReport()
    DebindDevDB = DebindDevDB or {};
    local saved = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        records = ruleRecords,
        groups = {},
    };
    DebindDevDB.updateOrderRule = saved;

    print(TAG .. format("%d frames", #ruleRecords));
    for _, group in ipairs(GROUPS) do
        local counts = {};
        for _, seq in ipairs(ruleRecords) do
            local only = seq:gsub("[^" .. group.letters .. "]", "");
            counts[only] = (counts[only] or 0) + 1;
        end
        saved.groups[group.letters] = counts;
        local parts = {};
        for order, count in pairs(counts) do
            local names = {};
            for rule, predicted in pairs(group.predictions) do
                if (order == predicted) then
                    names[#names + 1] = rule;
                elseif (order == predicted:reverse()) then
                    names[#names + 1] = rule .. " reversed";
                end
            end
            parts[#parts + 1] = format("%s x%d (%s)", order, count,
                #names > 0 and table.concat(names, ", ") or "no rule");
        end
        print(TAG .. group.letters .. ": " .. table.concat(parts, "; "));
    end

    local whole = {};
    for _, seq in ipairs(ruleRecords) do
        whole[seq] = (whole[seq] or 0) + 1;
    end
    local list = {};
    for seq, count in pairs(whole) do
        list[#list + 1] = { seq = seq, count = count };
    end
    sort(list, function(a, b) return a.count > b.count; end);
    local parts = {};
    for i = 1, math.min(#list, 3) do
        parts[i] = format("%s x%d", list[i].seq, list[i].count);
    end
    print(TAG .. "whole frame: " .. table.concat(parts, ", "));
    print(TAG .. "saved to DebindDevDB.updateOrderRule. /reload when done with it.");
    ruleRecords = {};
end

local function RuleMark(letter)
    if (not ruleWanted) then
        return;
    end
    local now = GetTime();
    if (now ~= ruleTime) then
        ruleTime = now;
        if (#ruleRecords >= ruleWanted) then
            ruleWanted = nil;
            RuleReport();
            return;
        end
        ruleRecords[#ruleRecords + 1] = "";
    end
    ruleRecords[#ruleRecords] = ruleRecords[#ruleRecords] .. letter;
end

local function BuildRuleFrames()
    local made = {};
    local function make(letter, shown)
        made[letter] = CreateFrame("Frame");
        if (not shown) then
            made[letter]:Hide();
        end
    end
    local function script(letter)
        made[letter]:SetScript("OnUpdate", function() RuleMark(letter); end);
    end
    local function hook(letter)
        made[letter]:HookScript("OnUpdate", function() RuleMark(letter); end);
    end
    local function show(letter)
        made[letter]:Show();
    end

    make("A"); make("B"); make("C");
    script("A"); script("C"); script("B");
    show("B"); show("A"); show("C");

    make("D"); make("E"); make("F");
    show("E"); show("F"); show("D");
    script("F"); script("D"); script("E");

    make("G", true); make("H", true); make("I", true);
    hook("I"); hook("G"); hook("H");

    make("J", true); make("K", true); make("L", true);
    script("J"); script("K"); script("L");
    show("J");

    SecureStateDriverManager:HookScript("OnUpdate", function() RuleMark("M"); end);
    ruleBuilt = true;
end

SLASH_DEBUO1 = "/debuo";
SlashCmdList["DEBUO"] = function(msg)
    if (ruleWanted) then
        print(TAG .. "already running");
        return;
    end
    if (not ruleBuilt) then
        if (InCombatLockdown()) then
            print(TAG .. "out of combat to start: it hooks the manager");
            return;
        end
        BuildRuleFrames();
    end
    ruleWanted = math.max(1, math.floor(tonumber(strtrim(msg or "")) or RULE_FRAMES));
    ruleTime = nil;
    print(TAG .. format("watching %d frames", ruleWanted));
end

local HS_FRAMES = 60;
local HS_ACT = 20;
local hsRunning = false;
local hsRecords = {};
local hsTime;
local hsMade = {};

--- What a group's three letters come out as when the hidden one moved to the front, and when not.
local HS_GROUPS = {
    { letters = "STU", name = "same frame, the walk passes it hidden", moved = "TSU", stayed = "STU" },
    { letters = "VWX", name = "across a frame, the walk never sees it hidden", moved = "WVX", stayed = "VWX" },
};

local function HSReport()
    DebindDevDB = DebindDevDB or {};
    DebindDevDB.hideShow = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        act = HS_ACT,
        records = hsRecords,
    };
    for _, group in ipairs(HS_GROUPS) do
        local before, after = {}, {};
        local around = {};
        for n, seq in ipairs(hsRecords) do
            local only = seq:gsub("[^" .. group.letters .. "]", "");
            if (n < HS_ACT) then
                before[only] = (before[only] or 0) + 1;
            elseif (n > HS_ACT + 1) then
                after[only] = (after[only] or 0) + 1;
            else
                around[#around + 1] = format("%d:%s", n, only);
            end
        end
        local function Tally(t)
            local parts = {};
            for order, count in pairs(t) do
                local verdict = (order == group.moved and "moved") or (order == group.stayed and "stayed") or "?";
                parts[#parts + 1] = format("%s x%d (%s)", order, count, verdict);
            end
            return table.concat(parts, ", ");
        end
        print(TAG .. format("%s, %s", group.letters, group.name));
        print(TAG .. format("  before: %s | %s | after: %s", Tally(before), table.concat(around, " "),
            Tally(after)));
    end
    print(TAG .. "saved to DebindDevDB.hideShow.");
    for _, frame in pairs(hsMade) do
        frame:SetScript("OnUpdate", nil);
    end
    hsMade = {};
end

--- The frame number this OnUpdate runs in, the record for it opened by the first mark of a frame.
--- Nil once the run is over.
local function HSMark(letter)
    if (not hsRunning) then
        return nil;
    end
    local now = GetTime();
    if (now ~= hsTime) then
        hsTime = now;
        if (#hsRecords >= HS_FRAMES) then
            hsRunning = false;
            HSReport();
            return nil;
        end
        hsRecords[#hsRecords + 1] = "";
    end
    local n = #hsRecords;
    hsRecords[n] = hsRecords[n] .. letter;
    return n;
end

local function BuildHideShow()
    local f = {};
    -- The last to run is set first: a frame that becomes updatable goes to the front.
    for _, letter in ipairs({ "U", "T", "S", "X", "W", "V" }) do
        f[letter] = CreateFrame("Frame");
        hsMade[letter] = f[letter];
    end
    f.U:SetScript("OnUpdate", function()
        if (HSMark("U") == HS_ACT) then
            f.T:Show();
        end
    end);
    f.T:SetScript("OnUpdate", function() HSMark("T"); end);
    f.S:SetScript("OnUpdate", function()
        if (HSMark("S") == HS_ACT) then
            f.T:Hide();
        end
    end);
    f.X:SetScript("OnUpdate", function()
        if (HSMark("X") == HS_ACT) then
            f.W:Hide();
        end
    end);
    f.W:SetScript("OnUpdate", function() HSMark("W"); end);
    f.V:SetScript("OnUpdate", function()
        if (HSMark("V") == HS_ACT + 1) then
            f.W:Show();
        end
    end);
end

SLASH_DEBHS1 = "/debhs";
SlashCmdList["DEBHS"] = function()
    if (hsRunning) then
        print(TAG .. "already running");
        return;
    end
    hsRecords = {};
    hsTime = nil;
    hsRunning = true;
    BuildHideShow();
    print(TAG .. format("watching %d frames, acting on frame %d", HS_FRAMES, HS_ACT));
end
