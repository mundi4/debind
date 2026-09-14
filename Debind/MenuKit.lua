local _, DebindPrivate = ...;
local LLL              = DebindPrivate.L;

--- The parts every dropdown in this addon is built from.
---
--- **Nothing here knows what a Debind action is.** A menu family makes a registry, hands it the
--- three things that are its own (how to read a value, how to ask for an issue, how to turn one
--- into a sentence), and declares its rows as named nodes. The action menu is one such family
--- (`DropDownMenus.lua`); the Switches tab is meant to be the second (`SwitchesUI.lua`).
---
--- `ctx` is the family's own table, made once per opened menu and handed to every callback in the
--- tree. This file only passes it through, because there is no field yet that every family must
--- carry. The day one is agreed on, reading it here is fine.
local MenuKit = {};
DebindPrivate.MenuKit = MenuKit;

--- A checkbox that flips a value between truthy and nil rather than picking one of several. Put in
--- the `value` slot where a real value would go.
MenuKit.TOGGLE = {};

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------

--- A menu item's tooltip: its own label as the title, one instruction line under it.
---
--- Shared out because the Switches tab builds a menu of its own with the same items in it
--- (`SwitchesUI.lua`), and two copies of this would be two answers to "what does a menu item's
--- tooltip look like" in one window.
---
--- `lockReason` is optional and is **a function, asked as the tooltip is drawn**. A locked control
--- has to say what is locking it, and what that is moves while the menu is open: picking a target
--- two rows up locks or frees the box below without the description being rebuilt. A string caught
--- here would be the answer from whenever the menu was assembled.
function MenuKit.SetInstructionTooltip(description, text, lockReason)
    description:SetTooltip(function(tooltip, elementDescription)
        GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
        GameTooltip_AddInstructionLine(tooltip, text);
        local reason = lockReason and lockReason();
        if (reason) then
            GameTooltip_AddBlankLineToTooltip(tooltip);
            GameTooltip_AddDisabledLine(tooltip, reason);
        end
    end);
end

function MenuKit.SetErrorTooltip(description, text)
    description:SetTooltip(function(tooltip, elementDescription)
        GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
        GameTooltip_AddErrorLine(tooltip, text);
    end);
end

--------------------------------------------------------------------------------
-- New feature marks
--------------------------------------------------------------------------------

--- Marks a menu label as newly arrived. **The same atlas the list already uses** (`DebindUI.xml`'s
--- `NewDot`, the one on an arrived action). The game's own new-feature label
--- (`MenuTemplates.AttachNewFeatureFrame`) is a frame with text over a texture and cannot be put
--- inside a menu row's own string.
function MenuKit.NewFeatureLabel(text)
    return format("%s %s", text, CreateAtlasMarkup("plunderstorm-new-dot-lg", 25, 25));
end

--- Puts the dot on a row that is already built.
---
--- **The string a row draws is not its `text` field.** Every template catches a copy in its own
--- initializer (`MenuTemplates.CreateTitle`, `MenuVariants.CreateCheckbox`), so writing the field
--- afterwards changes nothing on screen. Ours runs after theirs and re-fits what they left in
--- `fontString`, which is where all of them park it.
local function MarkRowNew(description)
    if (description.debindNewFeature) then
        return;
    end
    description.debindNewFeature = true;

    description:AddInitializer(function(frame)
        frame.fontString:SetTextToFit(MenuKit.NewFeatureLabel(frame.fontString:GetText()));
    end);
end

--------------------------------------------------------------------------------
-- Counts on a split selection
--------------------------------------------------------------------------------

--- Puts `count()` after a row's label while it answers a number, and nothing while it answers nil.
---
--- **Asked when the row is drawn**, which is again after every press that refreshes the menu, so the
--- number follows the values rather than the moment the menu was built. Drawn over what the template
--- left in `fontString`, for the reason `MarkRowNew` gives.
function MenuKit.AppendCount(description, count)
    description:AddInitializer(function(frame)
        local n = count();
        if (n) then
            frame.fontString:SetTextToFit(format("%s %s", frame.fontString:GetText(), format(LLL["MENU_MIXED_COUNT"], n)));
        end
    end);
    return description;
end

--- The title that opens the menu this row leads to, **made here so the mark can reach it.**
---
--- A row cannot be asked what it is: the template it was made from is caught in a closure
--- (`MenuTemplates.CreateMenuElementDescription`), and the one thing that would have told a title
--- from a button, having no sound, cannot be asked either -- `GetSoundKit` calls what it holds
--- rather than answering nil. So the family's titles are made through here and the ones that open
--- a menu remember where they are.
local function RememberTitle(description, title)
    if (description.debindTitle == nil) then
        description.debindTitle = title;
    end
    return title;
end

--- The submenu's own name at the top of it.
---
--- `QueueTitle` would do the same and hand back nothing (`MenuUtil`'s wrapper drops it), and a
--- queued row cannot be found afterwards either: the queue is flushed into the submenu on the
--- first insert, which has not happened while the tree is still being built.
function MenuKit.QueueTitle(description, text)
    local title = MenuUtil.CreateTitle(text);
    description:AddQueuedDescription(title);
    return RememberTitle(description, title);
end

--- A title inside the menu, where the family builds its own rows.
function MenuKit.CreateTitle(description, text)
    local first = not description:HasElements();
    local title = description:CreateTitle(text);
    if (first) then
        RememberTitle(description, title);
    end
    return title;
end

--------------------------------------------------------------------------------
-- Value handlers
--------------------------------------------------------------------------------

--- Turns an accessor into the callback pairs the game's menu wants.
---
--- An accessor is four functions. `Targets(ctx)` is the list a menu aims at, `Get(target, key)` and
--- `Set(target, key, value)` read and write one of them, and `Commit(ctx)` runs once after a press
--- wrote anything and returns what the menu should do next. Everything a family does on the way in
--- and out of storage lives behind those: which table the key belongs to, what to prune after a
--- clear, what to rebuild once the values moved.
---
--- **A menu aims at a list because one menu edits a selection** (`devdocs/editing-many-actions-at-once.md`).
--- A single row is a list of one, and every rule below comes out as the plain single-value rule there.
---
--- - A radio or a box reads as picked only when **every** target holds it.
--- - A press decides **one** outcome from what is drawn and writes that to every target. Flipping
---   each target from its own value would leave a mixed selection mixed.
--- - A bit moves on every target and **each keeps its other bits**.
---
--- **`data` is the only thing the game hands a click callback back** (`MenuUtil.CreateRadio`), so
--- `ctx` rides in it. That is what lets the callbacks here be written once for every family, and
--- what keeps a shared current-target upvalue out of the menus that use them.
function MenuKit.MakeHandlers(accessor)
    local targets, get, set, commit = accessor.Targets, accessor.Get, accessor.Set, accessor.Commit;

    local function every(data, holds)
        local list = targets(data.ctx);
        if (#list == 0) then
            return false;
        end
        for i = 1, #list do
            if (not holds(get(list[i], data.key))) then
                return false;
            end
        end
        return true;
    end

    local function equals(data)
        if (data.value == MenuKit.TOGGLE) then
            return every(data, function(current)
                return current and true or false;
            end);
        end
        return every(data, function(current)
            return current == data.value;
        end);
    end

    --- **Writes nothing to a target already holding what was picked, and commits nothing when no
    --- target moved.** Clearing a key that was never set would otherwise make the table it lives in
    --- and then prune it away again.
    local function setValue(data)
        local value = data.value;
        local toggle = value == MenuKit.TOGGLE;
        if (toggle) then
            -- **The cleared box writes `false`, not nil.** Storing the off state rather than
            -- erasing the key is what the boxes coming this way have always done, and a family
            -- whose `Set` wants nil instead can fold `false` there.
            value = not equals(data);
        end
        local wrote = false;
        for _, target in ipairs(targets(data.ctx)) do
            local current = get(target, data.key);
            if (toggle) then
                current = current and true or false;
            end
            if (current ~= value) then
                set(target, data.key, value);
                wrote = true;
            end
        end
        if (wrote) then
            return commit(data.ctx);
        end
    end

    local function MaskOf(target, data)
        return get(target, data.key) or data.defaultValue or 0;
    end

    local function hasBit(data)
        local list = targets(data.ctx);
        if (#list == 0) then
            return false;
        end
        for i = 1, #list do
            if (bit.band(MaskOf(list[i], data), data.value) ~= data.value) then
                return false;
            end
        end
        return true;
    end

    local function toggleBit(data)
        local turnOn = not hasBit(data);
        local wrote = false;
        for _, target in ipairs(targets(data.ctx)) do
            local current = MaskOf(target, data);
            local mask = bit.bor(current, data.value);
            if (not turnOn) then
                mask = current - bit.band(current, data.value);
            end
            if (mask ~= current) then
                set(target, data.key, mask);
                wrote = true;
            end
        end
        if (wrote) then
            return commit(data.ctx);
        end
    end

    return { equals = equals, set = setValue, hasBit = hasBit, toggleBit = toggleBit };
end

--------------------------------------------------------------------------------
-- The rows a node draws
--------------------------------------------------------------------------------

local Appender = {};
Appender.__index = Appender;

function Appender:Title(text)
    return MenuKit.CreateTitle(self.description, text);
end

--- Hands a choice this kit drew to the family's `decorateChoice`, the same reading it was drawn with.
function Appender:Decorate(description, isSelected, data)
    if (self.decorateChoice) then
        self.decorateChoice(description, self.ctx, isSelected, data);
    end
    return description;
end

--- The row every axis opens with. It says `Disable`, which is this axis constraining nothing
--- rather than a third value to pick from.
function Appender:Disable(prefix, key)
    local text = rawget(LLL, prefix .. "_DISABLE") or LLL["DISABLE"];
    local data = { ctx = self.ctx, key = key, value = nil };
    return self:Decorate(self.description:CreateRadio(text, self.handlers.equals, self.handlers.set, data),
        self.handlers.equals, data);
end

function Appender:YesNo(prefix, key)
    local yesData = { ctx = self.ctx, key = key, value = true };
    local yes = self:Decorate(self.description:CreateRadio(rawget(LLL, prefix .. "_YES") or YES,
        self.handlers.equals, self.handlers.set, yesData), self.handlers.equals, yesData);
    local noData = { ctx = self.ctx, key = key, value = false };
    local no = self:Decorate(self.description:CreateRadio(rawget(LLL, prefix .. "_NO") or NO,
        self.handlers.equals, self.handlers.set, noData), self.handlers.equals, noData);
    return yes, no;
end

function Appender:DisableYesNo(prefix, key)
    local disable = self:Disable(prefix, key);
    local yes, no = self:YesNo(prefix, key);
    return disable, yes, no;
end

--- A checkbox that stores `value` while it is ticked and **clears the key** when it is not.
---
--- Not the same thing as `MenuKit.TOGGLE`, which keeps the off state as `false`. A key whose
--- presence changes what the thing it is on means has to leave nothing behind when it comes off,
--- or the cleared box goes on saying something.
function Appender:ClearingCheckbox(text, key, value)
    local handlers = self.handlers;
    local data = { ctx = self.ctx, key = key, value = value };
    return self:Decorate(self.description:CreateCheckbox(text, handlers.equals,
        function(pressed)
            if (handlers.equals(pressed)) then
                return handlers.set({ ctx = pressed.ctx, key = pressed.key, value = nil });
            end
            return handlers.set(pressed);
        end,
        data), handlers.equals, data);
end

--- One checkbox per item, each owning one bit of `key`.
---
--- An item may bring its own `isSelected`/`setSelected` where the bit rule does not hold, which is
--- how a box reading from somewhere else sits in the same block as the ones that do not.
function Appender:Checkboxes(key, items, callback, defaultValue)
    for _, item in ipairs(items) do
        local isSelected = item.isSelected or self.handlers.hasBit;
        local setSelected = item.setSelected or self.handlers.toggleBit;
        local data = { ctx = self.ctx, key = key, value = item.value, defaultValue = defaultValue };
        local description = self:Decorate(self.description:CreateCheckbox(item.text, isSelected, setSelected, data),
            isSelected, data);
        if (callback) then
            callback(description, item);
        end
    end
end

--------------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------------

local Registry = {};
Registry.__index = Registry;

--- `config` is what one family of menus answers for all of its nodes:
---
--- * `accessor` -- the default `Get`/`Set` pair. A node may name its own.
--- * `issueForKey(ctx, key)` -- optional. What is wrong with the value under `key`, or nil.
--- * `isActiveForKey(ctx, key)` -- optional. Whether that value is set to anything.
--- * `resolveIssue(issue)` -- returns the sentence and the colour for an issue. **The issue itself
---   is opaque here**: only the family knows whether it is a code, a sentence or something else.
function MenuKit.NewRegistry(config)
    local newFeatures = {};
    for _, tag in ipairs(config.newFeatures or {}) do
        newFeatures[tag] = true;
    end
    return setmetatable({
        nodes = {},
        handlers = {},
        newFeatures = newFeatures,
        --- The rows between the root and whatever is being built right now, outermost first.
        openRows = {},
        config = config,
    }, Registry);
end

--- A new-feature dot on the row `tag` names, **and on every row that has to be opened to reach
--- it**, while `tag` is in the family's `newFeatures`.
---
--- **The list is the whole of it.** A release takes the marks off by emptying that one list, and
--- what is marked is readable in a single place rather than spread over the rows that carry it.
--- A tag left in too long shows a dot that should be gone, which somebody sees; the other way
--- round -- a mark that quietly never appears -- is what putting the decision at each row costs.
---
--- **What is new is usually a block inside a submenu**, and a reader who is not told at the row
--- that opens it never goes in to find out. Which rows those are is what `openRows` answers, so
--- the door list is not written out beside the thing and cannot go stale when the tree moves --
--- the same reason `IssueOf` asks the tree instead of being told.
---
--- **The title at the top of the new thing's own menu is part of it and wears the mark; the ones
--- above are not.** A door's menu opens by repeating the door's name, and a dot there reads as
--- "everything in here is new" rather than "there is something new further in".
---
--- Call it once the row is built and once its own title stands, since both of those are what the
--- mark spreads to.
function Registry:MarkNew(tag, description)
    if (not self.newFeatures[tag]) then
        return description;
    end
    MarkRowNew(description);
    if (description.debindTitle) then
        MarkRowNew(description.debindTitle);
    end
    for i = 1, #self.openRows do
        MarkRowNew(self.openRows[i]);
    end
    return description;
end

function Registry:Define(name, node)
    assert(self.nodes[name] == nil, "menu node already defined: " .. name);
    node.name = name;
    self.nodes[name] = node;
    return node;
end

function Registry:Get(name)
    local node = self.nodes[name];
    assert(node, "no such menu node: " .. tostring(name));
    return node;
end

--- Made once per accessor rather than once per built row: a menu is rebuilt on every click that
--- returns `MenuResponse.Refresh`, and the pair holds nothing that changes between builds.
function Registry:HandlersFor(node)
    local accessor = node.accessor or self.config.accessor;
    local handlers = self.handlers[accessor];
    if (handlers == nil) then
        handlers = MenuKit.MakeHandlers(accessor);
        self.handlers[accessor] = handlers;
    end
    return handlers;
end

--- The first issue in this subtree, the node's own before its children's.
---
--- **A row that opens a submenu carries no value of its own**, so a problem two levels down used to
--- be invisible until the reader opened the right branch. The list of categories a parent had to
--- name was written out by hand beside it and went stale the day a child was added, which nothing
--- checks and only the screen shows. The tree already says who the children are, so it is asked
--- instead of told.
function Registry:IssueOf(node, ctx)
    local issue;
    if (node.issue) then
        issue = node.issue(ctx);
    elseif (node.key and self.config.issueForKey) then
        issue = self.config.issueForKey(ctx, node.key);
    end
    if (issue) then
        return issue;
    end
    local children = node.children;
    if (children) then
        for i = 1, #children do
            issue = self:IssueOf(self:Get(children[i]), ctx);
            if (issue) then
                return issue;
            end
        end
    end
end

function Registry:IsActive(node, ctx)
    if (node.isActive) then
        return node.isActive(ctx) and true or false;
    end
    if (node.key and self.config.isActiveForKey) then
        return self.config.isActiveForKey(ctx, node.key) and true or false;
    end
    return false;
end

--- Draws the node named `name` under `parentDescription` and returns its description.
function Registry:Build(parentDescription, name, ctx)
    return self:BuildNode(parentDescription, self:Get(name), ctx);
end

--- Draws a node that was never registered under a name.
---
--- **For the rows a menu only knows about once it is open**: one per unit condition the action
--- carries, one per switch that exists. A name would have to be invented for each and thrown away
--- with the menu, and nothing could refer to it, which is the whole of what a name buys.
---
--- Such a node's issue does not roll up on its own, because the tree has no children to walk. The
--- row that opens it answers for the branch itself, and that is a real answer rather than a gap:
--- both of these ask one question of the whole subtree.
---
--- `build` runs before `children`, so a node's own rows stand above the submenus it opens.
function Registry:BuildNode(parentDescription, node, ctx)
    -- **Not drawn at all, rather than drawn and disabled.** A greyed row says the reader could
    -- reach this if something changed; a node that says no here is one this thing can never carry,
    -- and there is nothing to tell them.
    if (node.shown and not node.shown(ctx)) then
        return nil;
    end

    local label = rawget(LLL, node.label) or node.label;

    -- **A leaf, not a submenu nobody can open.** `blocked` answers with the reason this ctx cannot
    -- have the node right now while some other one could, which is what a locked row says. The arrow
    -- a submenu carries would promise a step that is not there.
    local blockedReason = node.blocked and node.blocked(ctx);
    if (blockedReason) then
        local blockedDescription = parentDescription:CreateButton(label);
        blockedDescription:SetEnabled(false);
        MenuKit.SetErrorTooltip(blockedDescription, blockedReason);
        return blockedDescription;
    end

    local instruction = node.instruction;
    if (instruction == nil) then
        instruction = rawget(LLL, node.label .. "_DESC");
    else
        instruction = rawget(LLL, instruction) or instruction;
    end

    local description = parentDescription:CreateButton(label);
    local registry = self;
    description:AddInitializer(function(button, elementDescription)
        local color = HIGHLIGHT_FONT_COLOR;
        local err = registry:IssueOf(node, ctx);
        if (err) then
            -- **The grade picks the colour** (`resolveIssue`). Painting a problem this group holds
            -- nothing to fix about the same red as one it does sends the reader looking for a fix
            -- that is not in there. The sentence goes in the tooltip either way.
            local text, issueColor = registry.config.resolveIssue(err);
            err = text;
            color = issueColor or ERROR_COLOR;
        elseif (registry:IsActive(node, ctx)) then
            color = BLUE_FONT_COLOR;
        end

        button.fontString:SetTextColor(color:GetRGB());

        local mixed = registry.config.mixedCount and registry.config.mixedCount(node, ctx);
        if (mixed) then
            button.fontString:SetTextToFit(format("%s %s", button.fontString:GetText(),
                format(LLL["MENU_MIXED_COUNT"], mixed)));
        end

        elementDescription:SetTooltip(function(tooltip)
            local first = true;
            if (instruction) then
                GameTooltip_AddInstructionLine(tooltip, instruction);
                first = false;
            end
            if (err) then
                if (not first) then
                    GameTooltip_AddBlankLineToTooltip(tooltip);
                end
                GameTooltip_AddErrorLine(tooltip, err);
            end
        end);
    end);

    if (not node.skipTitle) then
        MenuKit.QueueTitle(description, MenuUtil.GetElementText(description));
    end

    local openRows = self.openRows;
    openRows[#openRows + 1] = description;

    if (node.build) then
        -- `kit` carries the description and the ctx as fields, so a node that needs the raw
        -- description for something the appenders do not cover reaches it without a third
        -- argument that most nodes would leave unread.
        node.build(setmetatable({
            description = description,
            ctx = ctx,
            handlers = self:HandlersFor(node),
            decorateChoice = self.config.decorateChoice,
        }, Appender), ctx);
    end

    local children = node.children;
    if (children) then
        for i = 1, #children do
            self:Build(description, children[i], ctx);
        end
    end

    openRows[#openRows] = nil;

    return description;
end
