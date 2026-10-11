local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local STORAGE_PANEL_ID = Dev.STORAGE_PANEL_ID

-----------------------------------------------------------
-- Test Cases: The storage tab counts what actually leaves
--
-- **This is the one the headless specs cannot reach.** They check the payload, and separately the
-- panel's list is built by code that never runs outside the game. What can go wrong is the two
-- disagreeing - the panel says "12 selected" and nine leave - and neither half is wrong on its
-- own, so only asking both at once finds it.
--
-- Nothing here reads a field to decide what it expects: the string is decoded the way any receiver
-- would decode it, and the count in it is set against the count the window drew.
-----------------------------------------------------------

--- The payload inside an exported string, undone by the door a pasted string goes through.
local function DecodeExportedString(str)
    local payload, why = DebindPrivate.Store.DecodeExportString(str)
    if not payload then
        return nil, tostring(why)
    end
    return payload
end

--- Every action in a payload, whatever layer it sits under. The nesting is the address, so this is
--- the walk a reader makes (`building-export-import.md`).
local function PayloadActions(payload)
    local out = {}
    for _, classes in pairs(payload.layers or {}) do
        for _, specTbl in pairs(classes) do
            for _, list in pairs(specTbl) do
                for _, action in ipairs(list) do
                    out[#out + 1] = action
                end
            end
        end
    end
    return out
end

--- **Three numbers, and they have to agree.** What the preview counts, what the string carries, and
--- what adding it back would put in the profile. The tick set feeds all three (`FilterPayload`,
--- `PlanArrival`), so a filter read in one place and not another is silent everywhere else: the
--- window says 12, the string carries 9, and nobody sees the difference until somebody else opens
--- it (section 12 of `building-export-import.md`).
RegisterTest("Storage: the preview, the string and the add all count the same", {
    description = "What the preview counts, what the string carries and what Add places are one number, and the badge is left out",
    run = function()
        local NAME = "Export counts"

        -- Two the tester owns and one still quarantined. A key with both on it is the sharpest
        -- case: the group goes out half, which is right, and a filter that worked per key rather
        -- than per action would send three or one.
        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F5", combat = true })
        InsertAction({ type = Constants.SPELL, value = 589, key = "CTRL-ALT-F5" })
        local badged = InsertAction({ type = Constants.SPELL, value = 6603, key = "CTRL-ALT-F6" })
        badged.arrivalID = 99
        ApplyBindings()

        -- **The panel is fetched, not opened.** `ResolvePanel` is what the tab calls to bring
        -- `DebindStorage` in, and stopping there is enough: nothing below needs a frame on screen.
        --
        -- The run's own layer has an id past every real one (`GetTestLayer`), and that used to be a
        -- reason not to build the list at all. It is not one any more: the preview names a layer by
        -- the **payload's address** rather than by that id, and `BuildExportPayload` files a layer
        -- with no character flag and no spec under the class block -- an address every client has.
        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end

        -- **The entry is real and it stays until teardown.** Making one is the only way into the
        -- list, and a row the runner leaves behind is a row the tester finds later - so it goes,
        -- along with the panel's own view state, which `OnHide` would normally clear and cannot on
        -- a panel that was never shown.
        --
        -- The copy dialog goes too: it takes keyboard focus when it opens, which is what it is for,
        -- and it must not hold it over whatever runs next.
        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            DebindCopyFrame.Output.EditBox:ClearFocus()
            DebindCopyFrame:Hide()
            panel:SelectEntry(nil)
            DebindPrivate.Store.DeleteEntry(entry.id)
        end)

        -- What `OnShow` does: pick the row, which builds the preview and ticks all of it.
        panel:SelectEntry(entry)

        -- What the window says, counted twice the way the window counts it: the [select all] total
        -- walks every listed action, and each header prints its own layer's length.
        local listed = panel:EnumerateListedActions()
        local headerTotal = 0
        for _, layer in ipairs(panel.previewLayers or {}) do
            headerTotal = headerTotal + #layer.actions
        end
        if headerTotal ~= #listed then
            return Fail(NAME, format("headings total %d, whole list %d", headerTotal, #listed))
        end

        for _, action in ipairs(listed) do
            if action == badged then
                return Fail(NAME, "an isolated action is in the list")
            end
        end

        -- And what leaves. `OnCopyClicked` is the button, and the box it fills is the one the
        -- reader copies out of. **The dialog keeps no copy of the string beside that box**, so the
        -- box is the only place to read it from (`ShowText`).
        panel:OnCopyClicked()
        local payload, why = DecodeExportedString(DebindCopyFrame.Output.EditBox:GetText())
        if not payload then
            return Fail(NAME, format("could not read the string: %s", why))
        end

        local sent = PayloadActions(payload)
        if #sent ~= #listed then
            return Fail(NAME, format("the window said %d and it sent %d", #listed, #sent))
        end
        for _, action in ipairs(sent) do
            if action.value == badged.value then
                return Fail(NAME, "an isolated action was carried into the string")
            end
        end

        -- **The third number.** Adding puts the same set into the profile and gets there through
        -- `PlanArrival` rather than through the string, so this is what catches a tick set one of the
        -- two reads and the other does not. Planned rather than placed: the count is what is being
        -- asked, and placing would leave the run's layer holding a second copy of everything.
        --
        -- **The entry's own payload, not the one decoded above.** A tick is the action table
        -- itself, so a payload built by decoding holds a second set of tables that nothing has
        -- ticked, and planning against it places nothing. `OnAddClicked` reaches `PlanArrival`
        -- through `CommitEntry`, which opens the entry the same way the preview did
        -- (`GetEntryPayload`).
        local stored = DebindPrivate.Store.GetEntryPayload(entry)
        if not stored then
            return Fail(NAME, "could not open the entry payload")
        end

        local planned, skipped = DebindPrivate.Store.PlanArrival(stored, { selection = panel.selected })
        if #planned ~= #listed then
            return Fail(NAME, format("the window said %d and it places %d", #listed, #planned))
        end
        if skipped ~= 0 then
            return Fail(NAME, format("%d came back with nowhere to go, those are addresses this board made", skipped))
        end

        return Pass(NAME, format("%d = %d = %d, and the badge did not go out", #listed, #sent, #planned))
    end,
})

--- **The two verbs grey out, they do not leave** (2026-08-23, the owner). A control that disappears
--- takes with it the answer to "what can I do here", and the screen where nothing is picked is
--- exactly where the reader is asking. The heading check is the other way round - it heads a list,
--- so with no list under it there is nothing for it to head.
---
--- **Nothing raises when an `IsEnabled` goes the wrong way** and no static check reads frame state,
--- so the three can only be held together from in here. One of them going missing altogether raises
--- for a different reason: `parentKey` is what these are found by, and a renamed one answers nil.
RegisterTest("Storage: the verbs grey out when nothing is picked", {
    description = "With no entry picked the two buttons grey out rather than disappear",
    run = function()
        local NAME = "Storage verbs"

        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F7" })

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end

        local verbs = {
            { button = panel.Preview.AddButton,  name = "[Add to My Setup]" },
            { button = panel.Preview.CopyButton, name = "[Create Share Code]" },
        }
        for _, verb in ipairs(verbs) do
            if not verb.button then
                return Fail(NAME, format("no %s button, check the parentKey in the XML", verb.name))
            end
        end

        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            panel:SelectEntry(nil)
            DebindPrivate.Store.DeleteEntry(entry.id)
        end)

        -- **The lit state is checked first.** Without it, the pass below is explained just as well
        -- by "both were dark to begin with".
        panel:SelectEntry(entry)
        if #panel:EnumerateListedActions() == 0 then
            return Fail(NAME, "the premise is gone: the entry just made holds no action at all")
        end
        if not panel.Preview.SelectAllCheck:IsShown() then
            return Fail(NAME, "picked an entry that has actions and there is no [select all]")
        end
        for _, verb in ipairs(verbs) do
            if not verb.button:IsEnabled() then
                return Fail(NAME, format("picked a fully ticked entry and %s is grey", verb.name))
            end
        end

        panel:SelectEntry(nil)
        if panel.Preview.SelectAllCheck:IsShown() then
            return Fail(NAME, "nothing is picked and [select all] is standing")
        end
        for _, verb in ipairs(verbs) do
            if not verb.button:IsShown() then
                return Fail(NAME, format("%s disappeared, it should have gone grey", verb.name))
            end
            if verb.button:IsEnabled() then
                return Fail(NAME, format("nothing is picked and %s can still be pressed", verb.name))
            end
        end

        return Pass(NAME, "both light up when something is picked, and go grey in place when nothing is")
    end,
})

--- **The client is the only thing that can read a `CL02:` code.** Headless has no deflate and no
--- JSON, so `clique_spec.lua` stands the three calls in with known answers; this makes the code the
--- way Clique 5.0.14's `GetExportString` does, with the client's own `C_EncodingUtil`, and asks
--- whether what comes back out is the binding list that went in (`importing-clique-profiles.md` §1).
RegisterTest("Clique CL02 code", {
    description = "A share code made the way Clique makes one comes in as a Clique payload",
    run = function()
        local NAME = "Clique CL02 code"

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not DebindPrivate.Store then
            return Fail(NAME, "could not load the storage, check the tab number or LoadAddOn")
        end
        if not C_EncodingUtil then
            return Fail(NAME, "this client has no C_EncodingUtil")
        end

        local bindings = {
            { type = "spell", spell = "Rejuvenation", key = "SHIFT-BUTTON1",
                sets = { default = true, spec3 = true } },
            { type = "item", item = "13", key = "ALT-F", sets = { global = true } },
        }
        local code = "CL02:" .. C_EncodingUtil.EncodeHex(C_EncodingUtil.CompressString(
            C_EncodingUtil.SerializeJSON(bindings)))

        local entry, reason = DebindPrivate.Store.ImportEntry(code)
        if not entry then
            return Fail(NAME, format("the code was refused: %s", tostring(reason)))
        end
        AddTeardown(function() DebindPrivate.Store.DeleteEntry(entry.id) end)

        local actions = PayloadActions(entry.payload)
        if #actions ~= 2 then
            return Fail(NAME, format("%d actions came out of 2 bindings", #actions))
        end
        local spell, slot = actions[1], actions[2]
        if spell.type ~= Constants.SPELL or spell.value ~= "Rejuvenation" or spell.key ~= "SHIFT-BUTTON1" then
            return Fail(NAME, format("the spell came out as %s / %s / %s",
                tostring(spell.type), tostring(spell.value), tostring(spell.key)))
        end
        if not (spell.untranslated and spell.untranslated.spec3 == true) then
            return Fail(NAME, "the specialization number did not survive the JSON")
        end
        if slot.type ~= Constants.USESLOT or slot.value ~= 13 then
            return Fail(NAME, format("the trinket came out as %s / %s", tostring(slot.type), tostring(slot.value)))
        end
        return Pass(NAME, "the client reads it back into the bindings that went in")
    end,
})

--- **`DEB2:` is packed by the client**, and headless stands a library in for it (`export_spec.lua`).
--- The probes measured the client's CBOR on hand-built tables; this puts a payload through the
--- addon's own `EncodeExportPayload` and `DecodeExportString`, so the calls and the enum names they
--- pass are the ones that ship. The cell keys are the part that can go wrong in silence: a spec
--- number or the guid coming back as another type puts every action somewhere else.
RegisterTest("Storage: a DEB2 string keeps its cells", {
    description = "A string packed by the client comes back with its spec numbers, its guid cell and who it is, and a numbered cell nobody names at its number",
    run = function()
        local NAME = "DEB2 cells"

        local Store = DebindPrivate.Store
        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not Store then
            return Fail(NAME, "could not load the storage, check the tab number or LoadAddOn")
        end

        local guid, class = UnitGUID("player"), Constants.PLAYER_CLASS
        local function Spell(value)
            return { { type = Constants.SPELL, value = value, key = "CTRL-ALT-F7", seq = 1 } }
        end
        local payload = {
            v = Store.PAYLOAD_VERSION, dbver = Constants.DB_VERSION,
            layers = {
                account = { GENERAL = { [0] = Spell(1) }, [class] = { [0] = Spell(2), [2] = Spell(3) } },
                [guid] = { [class] = { [0] = Spell(4), [5] = Spell(5) } },
            },
            characters = { [guid] = { name = DebindPrivate.GetUnitFullName("player"), class = class } },
        }

        local back, why = Store.DecodeExportString(Store.EncodeExportPayload(payload))
        if not back then
            return Fail(NAME, format("the string did not come back: %s", tostring(why)))
        end
        local account, mine = back.layers.account, back.layers[guid]
        if not (account and account.GENERAL and account.GENERAL[0]) then
            return Fail(NAME, "the general cell is not at [0] any more")
        end
        if not (account[class] and account[class][2] and account[class][2][1].value == 3) then
            return Fail(NAME, "the class spec 2 cell is not at the number 2 any more")
        end
        if not (mine and mine[class] and mine[class][5] and mine[class][5][1].value == 5) then
            return Fail(NAME, "the guid cell or its spec 5 did not come back")
        end
        if not (back.characters and back.characters[guid] and back.characters[guid].name == DebindPrivate.GetUnitFullName("player")) then
            return Fail(NAME, "who the cell is did not come back")
        end

        -- A v2 string's character layer is stored under "1" (`RaiseV2`), and a row holding one can
        -- go back out. A numeric string key is the one CBOR could hand back as a number.
        local numbered = {
            v = Store.PAYLOAD_VERSION, dbver = Constants.DB_VERSION,
            layers = { ["1"] = { [class] = { [5] = Spell(5) } } },
        }
        local back1 = Store.DecodeExportString(Store.EncodeExportPayload(numbered))
        if not back1 then
            return Fail(NAME, "the string with a numbered cell did not come back")
        end
        if not (back1.layers["1"] and back1.layers["1"][class] and back1.layers["1"][class][5]) then
            return Fail(NAME, "the numbered cell is not at \"1\"")
        end

        return Pass(NAME, "every cell came back at its own key, and the numbered one at \"1\"")
    end,
})

--- **The second door to the same outcome asks the same question** (2026-08-23, the owner). [Add and
--- Accept] used to reach down into the plan and leave the badge off, which put the arrivals live on
--- the sender's keys with nothing asked - and on a key the reader already uses, that is a merge
--- they never chose. It lands badged now and runs the approval, so the prompt [Accept all] raises
--- stands here too.
---
--- **Until the prompt is answered the arrivals are pending**, which is what makes its [Cancel] a
--- whole answer: nothing is half done, the actions are in and waiting like any other arrival.
---
--- `StaticPopup_Show` is the game's, so nothing outside it can see this.
RegisterTest("Storage: adding and accepting asks about a key I am using", {
    description = "[Add and Accept] raises the bulk approval confirmation for a key that clashes",
    run = function()
        local NAME = "Storage add and accept"
        local KEY = "CTRL-ALT-F4"

        AddTeardown(function() StaticPopup_Hide("DEBIND_APPROVE_ALL_OCCUPIED") end)

        -- One of mine already stands on that key. The payload is lifted from the profile, so it
        -- comes back carrying the same key.
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        ApplyBindings()

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end

        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            panel:SelectEntry(nil)
            DebindPrivate.Store.DeleteEntry(entry.id)
        end)

        panel:SelectEntry(entry)
        local listed = panel:EnumerateListedActions()
        if #listed == 0 then
            return Fail(NAME, "the premise is gone: the entry holds no action at all")
        end

        -- The press, then the button in the dialog it opens (`DebindAddFrame`).
        AddTeardown(function() DebindAddFrame:CloseDialog() end)
        panel:OnAddClicked()
        if not DebindAddFrame:IsShown() then
            return Fail(NAME, "[Add to My Bindings] did not open the add dialog")
        end
        DebindAddFrame.AcceptedButton:Click()

        local dialog = StaticPopup_FindVisible("DEBIND_APPROVE_ALL_OCCUPIED")
        if not dialog then
            return Fail(NAME, "it came in on a key I use and nothing was asked")
        end

        -- **What the window is holding is what gets read.** `CollectArrivedActions` cannot see it:
        -- the payload cannot carry the address of a layer this board made (`ImportAddress`), so the
        -- arrivals settle into the **real** class layer, and the kit swaps the three enumerators out
        -- and does not show that one. In the game they are the same thing, and here this list is
        -- where it is.
        local pending = dialog.data and dialog.data.arrivals or {}
        if #pending == 0 then
            return Fail(NAME, "the confirmation stood holding nothing")
        end

        -- **They are pending for as long as the question stands.** With the badge already off, the
        -- window would be asking about something that has already happened.
        for _, action in ipairs(pending) do
            if action.arrivalID == nil then
                return Fail(NAME, "the confirmation is up and something has already lost its badge")
            end
            if action.key ~= KEY then
                return Fail(NAME, format("the arrival lost the key it was sent on: %s", tostring(action.key)))
            end
        end

        return Pass(NAME, format("the confirmation stood and %d are pending", #pending))
    end,
})

--- **Leaving the tab is not the same as picking a different entry** (2026-08-23, the owner). What is
--- ticked and which layers are open are the reader's answers, and `OnShow` used to throw both away
--- and start the entry over - so a glance at Overview undid however many clicks they had spent
--- setting up what to bring.
---
--- **What makes keeping them safe is that the tables do not move.** A tick is keyed by the action
--- table itself, and both walks that open a stored payload write into the tables rather than
--- replacing them (`GetEntryPayload`, `MigrateLayer`). Nothing headless can see that, because what
--- is being asked is what two frame scripts do in sequence.
RegisterTest("Storage: a tab change keeps what is ticked and what is open", {
    description = "Leaving the tab and coming back keeps what is ticked and what is open",
    run = function()
        local NAME = "Storage view state"

        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F8" })
        InsertAction({ type = Constants.SPELL, value = 589, key = "CTRL-ALT-F9" })

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end

        -- **The window is stood up first.** The panel's `OnShow` registers on the window's callback
        -- bus, that bus is made by `DebindFrameMixin:OnLoad`, and what calls that is the window's
        -- first `OnShow`. Called without standing it up, `DebindFrame.Event` is nil.
        DebindFrame:Show()

        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            panel:SelectEntry(nil)
            panel:OnHide()
            DebindPrivate.Store.DeleteEntry(entry.id)
            DebindFrame:CloseWindow()
        end)

        panel:OnShow()
        panel:SelectEntry(entry)

        local listed = panel:EnumerateListedActions()
        local layer = (panel.previewLayers or {})[1]
        if #listed < 2 or not layer then
            return Fail(NAME, format("the premise is gone: %d action(s), layer %s",
                #listed, tostring(layer and layer.key)))
        end

        -- Straight after picking, everything is ticked. This turns over one of each of the things a
        -- reader would touch. **Which way a layer starts is not assumed**: whatever it was, the
        -- tab change has to keep the other way.
        local untickedAction = listed[1]
        local collapsedAfterToggle = not panel:IsLayerCollapsed(layer.key)
        panel:ToggleAction(untickedAction)
        panel:ToggleLayerCollapsed(layer.key)
        if panel.selected[untickedAction] or panel:IsLayerCollapsed(layer.key) ~= collapsedAfterToggle then
            return Fail(NAME, "the premise is gone: what was touched did not turn over on the spot")
        end

        -- Leaves the tab and comes back. These two are what run when the window swaps panels.
        panel:OnHide()
        panel:OnShow()

        if panel:GetSelectedEntry() ~= entry then
            return Fail(NAME, "the picked entry changed while we were away")
        end
        if panel.selected[untickedAction] then
            return Fail(NAME, "a tick that was cleared is back on")
        end
        if panel:IsLayerCollapsed(layer.key) ~= collapsedAfterToggle then
            return Fail(NAME, "a layer that was opened or collapsed went back")
        end

        -- It also checks that the rest stayed as they were. On the two above alone, "everything went
        -- off" passes too.
        local stillTicked = 0
        for _, action in ipairs(panel:EnumerateListedActions()) do
            if panel.selected[action] then
                stillTicked = stillTicked + 1
            end
        end
        if stillTicked ~= #listed - 1 then
            return Fail(NAME, format("%d ticks should be left and there are %d", #listed - 1, stillTicked))
        end

        return Pass(NAME, format("%d ticks and the toggled layer survived the tab change", stillTicked))
    end,
})

--- **The preview is grouped by whose cells they are** (`reshaping-stored-layers.md` 6-2). Adding
--- takes one character and the reader picks it by ticking, so two characters of this class have to
--- stand under two headers. Grouped by where the press would put them, they merged into one.
RegisterTest("Storage: two characters of this class stand under two owners", {
    description = "An entry with the account and two characters of this class shows three owner headers",
    run = function()
        local NAME = "Storage owners"
        local class = Constants.PLAYER_CLASS
        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end
        DebindFrame:Show()

        local store = DebindPrivate.Store
        local entry = store.StorePayload({
            v = store.PAYLOAD_VERSION, dbver = Constants.DB_VERSION,
            layers = {
                account = { GENERAL = { [0] = { { type = Constants.SPELL, value = 585, key = "CTRL-ALT-F8" } } } },
                ["Player-9-DEBTESTA"] = { [class] = { [0] = { { type = Constants.SPELL, value = 589 } } } },
                ["Player-9-DEBTESTB"] = { [class] = { [0] = { { type = Constants.SPELL, value = 17 } } } },
            },
            characters = {
                ["Player-9-DEBTESTA"] = { name = "Debtesta", class = class },
                ["Player-9-DEBTESTB"] = { name = "Debtestb", class = class },
            },
        }, "Debtest owners")
        if not entry then
            return Fail(NAME, "the payload was not stored")
        end
        AddTeardown(function()
            panel:SelectEntry(nil)
            store.DeleteEntry(entry.id)
            DebindFrame:CloseWindow()
        end)

        panel:SelectEntry(entry)
        local owners = panel.previewOwners or {}
        if #owners ~= 3 then
            return Fail(NAME, format("%d owner headers, not 3", #owners))
        end
        for _, owner in ipairs(owners) do
            if #owner.actions ~= 1 then
                return Fail(NAME, format("%s holds %d actions, not 1", owner.label, #owner.actions))
            end
        end
        return Pass(NAME, "the account and each character stand on their own")
    end,
})

--- **The key view stands a key's actions in firing order** (`grouping-the-storage-preview-by-key.md`
--- 2절): the narrower layer first, the way Overview's left column does. Name order would put the
--- general layer's action first here.
RegisterTest("Storage: the key view orders a key by layer", {
    description = "One key in the general layer and a character layer: the character's action stands first",
    run = function()
        local NAME = "Storage key view"
        local class = Constants.PLAYER_CLASS
        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end
        DebindFrame:Show()

        local store = DebindPrivate.Store
        local KEY = "CTRL-ALT-F8"
        local general = { type = Constants.MACROTEXT, value = "/say a", name = "AAA debtest", key = KEY, seq = 1 }
        local mine = { type = Constants.MACROTEXT, value = "/say z", name = "ZZZ debtest", key = KEY, seq = 1 }
        local entry = store.StorePayload({
            v = store.PAYLOAD_VERSION, dbver = Constants.DB_VERSION,
            layers = {
                account = { GENERAL = { [0] = { general } } },
                ["Player-9-DEBTESTA"] = { [class] = { [0] = { mine } } },
            },
        }, "Debtest key view")
        if not entry then
            return Fail(NAME, "the payload was not stored")
        end
        AddTeardown(function()
            panel:SelectEntry(nil)
            store.DeleteEntry(entry.id)
            DebindFrame:CloseWindow()
        end)

        panel:SelectEntry(entry)
        local groups = panel:PreviewKeys()
        if #groups ~= 1 or groups[1].key ~= KEY then
            return Fail(NAME, format("%d key groups, the first on %s", #groups, tostring(groups[1] and groups[1].key)))
        end
        local actions = groups[1].actions
        if #actions ~= 2 then
            return Fail(NAME, format("the key holds %d actions, not 2", #actions))
        end
        if actions[1].value ~= mine.value then
            return Fail(NAME, "the general layer's action stands before the character's")
        end
        return Pass(NAME, "the character's action stands first")
    end,
})
