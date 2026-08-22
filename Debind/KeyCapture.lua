local _, DebindPrivate = ...;

local LLL              = DebindPrivate.L;
local DebindUI         = DebindPrivate.DebindUI;

--- Asking for one key, for one action or one key group, once.
---
--- The addon's other way of taking a key is a **mode**: the toggle over the list stays on, whatever
--- is under the cursor gets what you press, and a session's worth of changes is cancelled in one
--- go (`SetBindingMode` in `DebindUI.lua`). That shape is for hanging ten keys in a row. This one
--- is for the opposite case - a reader who wants the key for *this* set and nothing else. There is
--- no aiming, so there is nothing to say about pointing: the dialog shows what it is asking about
--- and takes the next key.
---
--- **The chrome is the export/import dialogs'** (`DebindDialogTemplate`), because the reader meets
--- all of them in the same window and a fourth shape to learn buys nothing.
---
--- Top to bottom: what to press, where the mouse counts, the key the set is on today, and then the
--- actions. The key sits over the set rather than on each row because a key group *is* the actions
--- sharing one key - a column of it would print one string as many times as the group is long.

--------------------------------------------------------------------------------
-- Measurements
--
-- Only the dialog's width is in the XML. Its height is worked out per open, because the group it is
-- asking about decides how many rows there are. `DebindBringFrame` is the other dialog that does
-- this.
--
-- **What is written here is spacing, and nothing else.** Every height in the sum is asked for rather
-- than assumed: a line of text is however tall that string came out in this locale
-- (`GetStringHeight`), the button strip is however tall the button is, and the chrome around
-- `ContentArea` is the gap between the frame and it. That last one is the whole reason `ContentArea`
-- exists - `DebindDialogTemplate` made it so no dialog would restate 40 / -40 / -40 / 25, and a
-- constant here adding them back up would be that restatement with a different name on it.
--------------------------------------------------------------------------------

--- How many rows are drawn before a count takes over.
---
--- **A key group has no ceiling this addon can name**, so the dialog cannot simply grow with it.
--- Eight is past every set in ordinary use, and what goes over says so in a line of its own rather
--- than being dropped without a word.
---
--- **A scrolling list is not the alternative here.** A scroll region takes the mouse and the wheel,
--- and the wheel is a key this dialog has to be able to read - a list you could scroll would be a
--- list that eats `MOUSEWHEELUP`.
local MAX_ROWS         = 8;

local ROW_PITCH        = 24;
local ICON_SIZE        = 20;

--- Between one section and the next: the instruction, the key they are on, the list, the buttons.
---
--- **One value for all of them.** The four are peers, and a gap that differs by pair is read as the
--- narrower two belonging together. What is deliberately *not* this is the step from the caption to
--- the rows under it - those are one section, and the rows sit close because they belong to the line
--- above them.
local GAP              = 16;

--- How far the list sits inside the caption over it, so the rows read as belonging to that line
--- rather than as the next thing after it.
local ROW_INDENT       = 12;

--- The step from that caption to the first row. **Smaller than `GAP` on purpose** - the two are one
--- section, and a step as wide as the ones between sections would cut the caption off from the list
--- it captions.
local CAPTION_GAP      = 8;


--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

--- Whether there is a key a reader could press.
---
--- **A number is not one.** A set that arrived in a string sits on a synthetic key until the reader
--- decides its real one (`NextSyntheticKey`), and that number stands *where* a key would without
--- being a key - which is the whole reason it is a number and a real key is always a string.
---
--- [Unbind Key] reads it, and so does the key each row draws when the rows disagree. Lit over a set
--- with a synthetic key the button would stand over nothing to unbind: the set is already off every
--- key, and taking that number away would only break it into loose actions.
---
--- **Up here because `LayoutRow` reads it.** It sat below with the rest of the reading and the rows
--- had no use for it until they started drawing keys of their own; a local named before it is
--- defined is `nil` at the call, and nothing says so at run time.
local function HasRealKey(action)
    return type(action.key) == "string";
end

--- One row: icon and name, the way every list in this addon draws an action.
---
--- **Regions on the dialog, not frames.** Anything that takes the mouse would swallow the click this
--- dialog is open to read, and there is nothing to click here anyway - the list is what is being
--- asked about, not a set of choices.
local function CreateRow(dialog)
    local row = {};

    row.Icon = dialog:CreateTexture(nil, "ARTWORK");
    row.Icon:SetSize(ICON_SIZE, ICON_SIZE);

    row.Name = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    row.Name:SetJustifyH("LEFT");
    row.Name:SetMaxLines(1);

    --- The key this one action is on. **Only drawn where the rows disagree** - see `LayoutRow`.
    ---
    --- Its own span rather than a point on the icon, because a `RIGHT` point sets both axes and the
    --- right edge here belongs to the dialog while the line belongs to the icon. Given the icon's
    --- height and told to centre in it, the two agree without a third number.
    row.Key = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    row.Key:SetJustifyH("RIGHT");
    row.Key:SetJustifyV("MIDDLE");
    row.Key:SetHeight(ICON_SIZE);
    row.Key:SetMaxLines(1);

    return row;
end

--- Puts one row at `y` and fills it in. The name hangs off the icon by a single `LEFT` point, so it
--- sits on that line without a second number to keep in step with the first.
---
--- **`showKey` is on exactly when the line above cannot name one key** (`CurrentKeyText` reading
--- "More than one"). With the set all on one key that line has already said it, and a column
--- repeating it beside every row is the same answer read twice - which is the rule the overview's
--- folded heading keeps for its summary. Which key each row is on is only worth a column when they
--- are not the same, and then it is the whole of what the reader came to find out.
local function LayoutRow(dialog, row, action, y, showKey)
    local name, icon = DebindUI.NameAndIconForAction(action);

    row.Icon:ClearAllPoints();
    row.Icon:SetPoint("TOPLEFT", dialog.ContentArea, "TOPLEFT", ROW_INDENT, y);
    DebindUI.SetActionIcon(row.Icon, icon);

    row.Name:ClearAllPoints();
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0);
    row.Name:SetText(name or "");

    if (showKey) then
        row.Key:ClearAllPoints();
        row.Key:SetPoint("TOPRIGHT", dialog.ContentArea, "TOPRIGHT", 0, y);

        -- **Greyed where there is none**, the same rule the line above keeps: a key is white, the
        -- absence of one is grey, and a reader scanning this column is looking for which rows have
        -- nothing yet as much as for which key the others are on.
        if (HasRealKey(action)) then
            row.Key:SetText(DebindPrivate.GetKeyDisplayText(action.key));
            row.Key:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
        else
            -- A row that came in names the key it came in on, the same as the line above and the
            -- heading it was opened from. Grey all the same: neither of these is a key it has.
            if (type(action.imported) == "string") then
                row.Key:SetText(DebindPrivate.GetKeyDisplayText(action.key, action.imported));
            else
                row.Key:SetText(LLL["OVERVIEW_NO_KEY"]);
            end
            row.Key:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
        end
        row.Key:Show();

        -- 이름은 키 앞에서 멈춘다. 안 그러면 긴 이름이 키 위로 지나간다.
        row.Name:SetPoint("RIGHT", row.Key, "LEFT", -6, 0);
    else
        row.Key:Hide();
        row.Name:SetPoint("RIGHT", dialog.ContentArea, "RIGHT", 0, 0);
    end

    row.Icon:Show();
    row.Name:Show();
end

local function HideRow(row)
    row.Icon:Hide();
    row.Name:Hide();
    row.Key:Hide();
end


--------------------------------------------------------------------------------
-- What is being asked about
--------------------------------------------------------------------------------

--- Is there anything here for [Unbind Key] to take off.
---
--- **Any of them, not the first.** This window takes any 1..n actions, and only some of those are a
--- key group -- a group shares one key by definition, but a selection somebody made by hand shares
--- nothing. Reading `actions[1]` answered for the rest, which is true of a group and a lie about a
--- selection.
local function AnyRealKey(actions)
    for i = 1, #actions do
        if (HasRealKey(actions[i])) then
            return true;
        end
    end
    return false;
end

--- The menus that offer [Unbind] on a selection ask the same question this dialog's button does, and
--- have to get the same answer: a menu item lit over a set on a synthetic key would be offering to
--- take off something that is not a key.
DebindPrivate.AnyRealKey = AnyRealKey;

--- The key these are on now, for the line that says so.
---
--- Three answers, because a set of several can be in a state one action cannot: **they are not all
--- on the same key.** There is no key to name there, and naming the first one would be picking a
--- winner out of a list the reader can see disagrees.
---
--- With no key at all it is the client's `NOT_BOUND`, held by `OVERVIEW_NO_KEY`. Read under the
--- other screen's key on purpose: one fact gets one word, and a second key holding the same global
--- is how two screens end up saying it differently.
---
--- **A set still waiting says the key it came in on instead**, which is what the overview's heading
--- calls it. The reader gets here from that heading, and the two lines naming one set differently
--- would read as two different sets.
local function CurrentKeyText(actions)
    local key, shared = DebindPrivate.SharedKeyOf(actions);
    if (not shared) then
        return LLL["KEY_CAPTURE_CURRENT_KEY_MIXED"];
    end

    if (type(key) == "number") then
        local from = DebindPrivate.ArrivalKeyOf(actions);
        if (from) then
            return DebindPrivate.GetKeyDisplayText(key, from);
        end
    end
    if (type(key) ~= "string") then
        return LLL["OVERVIEW_NO_KEY"];
    end
    return DebindPrivate.GetKeyDisplayText(key);
end

--- Hung on the two buttons so the wheel does not roll past them into the capture below.
---
--- Clicks need no such thing - a frame with the mouse enabled swallows every button whether or not
--- it asked for it, so the buttons already shield themselves. The wheel is the exception: it goes to
--- the topmost frame that enabled **the wheel**, and the buttons do not, so without this a scroll
--- over [Cancel] binds the wheel. An empty handler to stop a fall-through is the game's own move
--- (`CustomBindingButtonMixin:OnMouseWheel`).
local function SwallowWheel() end


--------------------------------------------------------------------------------
-- The dialog
--------------------------------------------------------------------------------

DebindKeyCaptureFrameMixin = {};

function DebindKeyCaptureFrameMixin:OnLoad()
    -- **Before `InitDialog`, which reads it** and hangs the drag on the left mouse button for every
    -- dialog that can be moved. Here that button is a binding, and a drag ends in a release on this
    -- frame - dragging the dialog out of the way would bind the button that dragged it.
    -- `KeyCapture.xml` says why this is a line of Lua and not an attribute on the frame.
    self:SetMovable(false);
    self:InitDialog(LLL["KEY_CAPTURE_TITLE"]);

    self.Description:SetText(LLL["KEY_CAPTURE_DESC"]);
    self.CurrentKeyLabel:SetText(LLL["KEY_CAPTURE_CURRENT_KEY"]);
    self.TargetsLabel:SetText(LLL["KEY_CAPTURE_TARGETS"]);

    --- The rows, made once. `MAX_ROWS` is the ceiling, so this is all of them there will ever be.
    self.rows = {};
    for i = 1, MAX_ROWS do
        self.rows[i] = CreateRow(self);
        HideRow(self.rows[i]);
    end

    --- What the list does not draw. Grey, because it is not one of the rows - it is a count of the
    --- ones that are not on screen. They are getting the key just the same.
    self.MoreText = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
    self.MoreText:SetJustifyH("LEFT");
    self.MoreText:Hide();

    self.CancelButton:SetScript("OnClick", function() self:Hide(); end);
    self.UnbindButton:SetScript("OnClick", function() self:Commit(nil); end);

    for _, button in ipairs({ self.CancelButton, self.UnbindButton }) do
        button:EnableMouseWheel(true);
        button:SetScript("OnMouseWheel", SwallowWheel);
    end
end

--- Puts the question up. `actions` is one action or a whole key group; `onCommit` is handed the key
--- that was pressed, or `nil` when the reader chose [Unbind Key]. Cancelling calls nothing.
---
--- **The actions are only read, never written.** What to do with the answer - which of them move,
--- what happens to whatever already sits on that key - is the caller's, and it is the half that
--- differs between one action and a set. It is also why this is a callback and not a return: giving
--- a key that is already carrying something raises a question of its own, and the answer to that one
--- arrives long after this dialog has closed.
function DebindKeyCaptureFrameMixin:Open(actions, onCommit)
    if (actions == nil or #actions == 0 or onCommit == nil) then
        return;
    end

    self.actions = actions;
    self.onCommit = onCommit;

    -- `y` is the top of whatever comes next, so where it ends up is what the stack took. Adding the
    -- pieces up a second time to get the height is how the two answers drift.
    local y = 0;

    -- The description wraps, so how tall it is depends on the locale and on nothing we can pick.
    -- Two horizontal points give it the width to wrap inside; `GetStringHeight` is then the answer
    -- for this string in this client rather than a guess about it.
    self.Description:ClearAllPoints();
    self.Description:SetPoint("TOPLEFT", self.ContentArea, "TOPLEFT", 0, y);
    self.Description:SetPoint("TOPRIGHT", self.ContentArea, "TOPRIGHT", 0, y);
    y = y - self.Description:GetStringHeight() - GAP;

    -- `CurrentKey` follows its label by an anchor in the XML, so only the label is placed. The taller
    -- of the two sets the line: the label and the value are different font objects, and which one
    -- wins is not ours to assume.
    --
    -- **Greyed where there is no key**, which is the rule the left column already keeps for the same
    -- state (`DebindKeyHeaderMixin:Init` greys both the unbound pile and a set still on a synthetic
    -- key). White is the reading; "Not Bound" is the absence of one, and a window that draws those
    -- alike makes the reader look twice at a line whose whole job is to be read once.
    local hasKey = AnyRealKey(actions);
    self.CurrentKeyLabel:ClearAllPoints();
    self.CurrentKeyLabel:SetPoint("TOPLEFT", self.ContentArea, "TOPLEFT", 0, y);
    self.CurrentKey:SetText(CurrentKeyText(actions));
    self.CurrentKey:SetTextColor((hasKey and HIGHLIGHT_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB());
    y = y - max(self.CurrentKeyLabel:GetStringHeight(), self.CurrentKey:GetStringHeight()) - GAP;

    self.TargetsLabel:ClearAllPoints();
    self.TargetsLabel:SetPoint("TOPLEFT", self.ContentArea, "TOPLEFT", 0, y);
    y = y - self.TargetsLabel:GetStringHeight() - CAPTION_GAP;

    -- 행마다 자기 키를 다는 것은 **위 줄이 하나로 못 부를 때뿐이다**(`LayoutRow`).
    local _, sharesOneKey = DebindPrivate.SharedKeyOf(actions);

    local drawn = min(#actions, MAX_ROWS);
    for i = 1, MAX_ROWS do
        if (i <= drawn) then
            LayoutRow(self, self.rows[i], actions[i], y, not sharesOneKey);
            y = y - ROW_PITCH;
        else
            HideRow(self.rows[i]);
        end
    end

    local overflow = #actions - drawn;
    self.MoreText:SetShown(overflow > 0);
    if (overflow > 0) then
        -- Lined up with the names, not with the icons: it stands in for rows, so it belongs to what
        -- those rows say rather than to the pictures they carry.
        self.MoreText:ClearAllPoints();
        self.MoreText:SetPoint("TOPLEFT", self.ContentArea, "TOPLEFT", ROW_INDENT + ICON_SIZE + 6, y);
        self.MoreText:SetText(format(LLL["KEY_CAPTURE_MORE"], overflow));
        y = y - ROW_PITCH;
    end

    -- **One real key anywhere in the set is enough to light it**, because that is exactly what the
    -- button acts on: it takes the key off whatever here has one, and the rest were never on one.
    -- It is dead where nothing does - a single action in the unbound pile, a set still waiting on a
    -- synthetic key, a selection where every row is keyless.
    --
    -- The same `hasKey` colours the line above, so the two still cannot disagree, but what they
    -- agree on is now "is there a real key in here" rather than "what key is this on". Those parted
    -- the day this window started taking selections: the line has three answers and the button has
    -- two, and the third answer ("More than one") is a lit one.
    self.UnbindButton:SetEnabled(hasKey);

    -- **The chrome is measured, not restated.** Whatever the frame is taller than `ContentArea` by
    -- is the template's four insets, so asking for the difference is asking the template - and the
    -- difference does not move when the height does, because `ContentArea` is anchored to the frame
    -- on all four sides.
    local insets = self:GetHeight() - self.ContentArea:GetHeight();
    self:SetHeight(-y + GAP + self.CancelButton:GetHeight() + insets);
    self:Show();
end

--- **Taken off the edit boxes before the first key arrives.** A focused `EditBox` reads the keyboard
--- ahead of everyone, so with the spell picker or the macro editor open behind this, the key meant
--- for the binding is typed into a box instead. The mode clears focus for the same reason and says
--- more about it (`SetBindingMode`).
function DebindKeyCaptureFrameMixin:OnShow()
    local focus = GetCurrentKeyBoardFocus();
    if (focus) then
        focus:ClearFocus();
    end

    self.pressed = nil;
end

function DebindKeyCaptureFrameMixin:OnHide()
    self.actions = nil;
    self.onCommit = nil;
    self.pressed = nil;
end

--- The one exit that carries an answer. `key` is a chord string, or `nil` for [Unbind Key].
---
--- **Down before the answer is handed over.** Giving a key can raise a question of its own - the key
--- may already be carrying something - and nothing should still be listening for keys over that.
function DebindKeyCaptureFrameMixin:Commit(key)
    local onCommit = self.onCommit;
    if (onCommit == nil) then
        return;
    end

    self:Hide();
    onCommit(key);
end

--- Every input that could be a key comes through here.
---
--- Modifiers on their own are not an answer - `SHIFT` is half a chord, and holding it is how the
--- other half is written. `CreateKeyChordStringUsingMetaKeyState` reads what is held **now**, which
--- is why it is asked at the instant the input arrives and not from anything stored.
function DebindKeyCaptureFrameMixin:Capture(input)
    if (input == nil or input == "UNKNOWN") then
        return;
    end

    local key = GetConvertedKeyOrButton(input);
    if (IsMetaKey(key)) then
        return;
    end

    self:Commit(DebindPrivate.CreateKeyChordStringUsingMetaKeyState(key));
end

--- **The keyboard is taken wherever the cursor is**, which is the half of this that cannot be a
--- mouse gesture: a key is pressed with the hand that is not on the mouse. The mouse is the other
--- way round and the description on the dialog says so.
---
--- Nothing here calls `SetPropagateKeyboardInput`. A frame with the keyboard enabled keeps what it
--- receives, which is exactly what is wanted - pressing `1` here must not also fire the first action
--- bar slot - and the call is taint in combat, so the branch that would have to guard it does not
--- exist either. The main window has to make the opposite arrangement and says why
--- (`DebindFrameMixin:OnKeyDown`).
---
--- **Escape is cancel, not the eraser.** In the mode it erases the row being pointed at, because in
--- a mode that never closes there is no other input left to mean "take this key away" - every
--- button, the wheel and Delete are all bindable. Here [Unbind Key] is on screen saying it, and
--- Escape is what it is in every other dialog.
function DebindKeyCaptureFrameMixin:OnKeyDown(key)
    if (key == "ESCAPE") then
        self:Hide();
        return;
    end
    self:Capture(key);
end

--- **A button counts on the way up, and only if this dialog saw it go down.**
---
--- The release edge is the mode's rule too, and there for a subtler reason (`SetBindingMode`). Here
--- it is the press that opened the dialog: the menu item that got the press is gone by the time the
--- finger lifts, and this dialog is what the release lands on. Answering it would bind the left
--- mouse button to whatever the reader had just asked a question about, without them touching
--- anything. Blizzard's own binding button carries a special case for the same half-click
--- (`cancelBindingModeOnRelease`); pairing the two edges covers every button instead of two.
function DebindKeyCaptureFrameMixin:OnMouseDown(button)
    self.pressed = self.pressed or {};
    self.pressed[button] = true;
end

function DebindKeyCaptureFrameMixin:OnMouseUp(button)
    if (not self.pressed or not self.pressed[button]) then
        return;
    end
    self.pressed[button] = nil;
    self:Capture(button);
end

--- The wheel has no press and release to pair, so it answers where it arrives.
function DebindKeyCaptureFrameMixin:OnMouseWheel(delta)
    self:Capture(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN");
end
