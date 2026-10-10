local _, DebindPrivate = ...;
local Constants               = DebindPrivate.Constants;

local format, tostring                   = format, tostring;
local wipe, ipairs                       = wipe, ipairs;

local Rebuild                 = DebindPrivate.Rebuild;
local sortedKeys              = Rebuild.sortedKeys;
local appendLine              = Rebuild.appendLine;

--- `EmitCastChords`'s scratch for `sortedKeys`. Two, because the walks nest: one key's chords are
--- sorted inside the walk over the bound keys.
local _sortedA           = {};
local _sortedB           = {};

--- The order the client drops modifiers in when a chord has no binding of its own
--- (`handing-the-rest-of-a-key-to-the-game.md` §6-2, measured), which is also the order a binding
--- string spells them in (`Constants.MODIFIER_ORDER`).
local CHORD_MODIFIERS = Constants.MODIFIER_ORDER;
local SplitChord = DebindPrivate.SplitKeyModifiers;
local JoinChord = DebindPrivate.JoinKeyModifiers;

local _chordMods = {};

--- `key` with `mod` added, or nil when it already holds it.
local function AddModifier(key, mod)
    local base = SplitChord(key, _chordMods);
    if (_chordMods[mod]) then
        return nil;
    end
    _chordMods[mod] = true;
    return JoinChord(_chordMods, base);
end

--- The bare key of ours a chord is bound to, false for somebody else's, nil for none. `ours` is the
--- set of bare keys bound this rebuild.
---
--- **The game's side is the saved set and every override in force but ours.** A bar or
--- click-casting addon routes its keys through overrides with nothing saved behind them, and a press
--- of such a chord went to it before the chords were bound. This runs after the rebuild has taken
--- our own overrides off (`ClearPreviousBindings`), so what is left there is someone else's.
local function DirectLanding(chord, ours)
    if (ours[chord]) then
        return chord;
    end
    if (GetBindingAction(chord, true) ~= "") then
        return false;
    end
    return nil;
end

--- `LandingOf`'s scratch, one pair per depth it recurses to.
local _landingMods, _landingDropped = {}, {};

--- **Where a press of `chord` lands with nothing but the bare keys we bind and the game's side**,
--- which is where every press landed before the chords were bound. The client takes the chord's own
--- binding, and failing that drops one modifier at a time, ALT, then CTRL, then SHIFT (measured,
--- §6-2). Dropping two is only ever asked of a chord we made from a key with both cast modifiers,
--- and both single drops are asked first there, so the order past one drop is the order of the
--- first.
local function LandingOf(chord, ours, depth)
    local direct = DirectLanding(chord, ours);
    if (direct ~= nil) then
        return direct;
    end

    depth = depth or 1;
    local mods = _landingMods[depth] or {};
    local dropped = _landingDropped[depth] or {};
    _landingMods[depth], _landingDropped[depth] = mods, dropped;
    wipe(dropped);
    local base = SplitChord(chord, mods);
    for _, mod in ipairs(CHORD_MODIFIERS) do
        if (mods[mod]) then
            mods[mod] = nil;
            dropped[#dropped + 1] = JoinChord(mods, base);
            mods[mod] = true;
        end
    end
    for _, smaller in ipairs(dropped) do
        local landing = DirectLanding(smaller, ours);
        if (landing ~= nil) then
            return landing;
        end
    end
    for _, smaller in ipairs(dropped) do
        local landing = LandingOf(smaller, ours, depth + 1);
        if (landing ~= nil) then
            return landing;
        end
    end
    return nil;
end

--- Every chord this rebuild weighed for a self or focus tier, and whether one of them was left
--- because somebody else holds it. What the override hooks ask (`Events.lua`): a call on anything
--- else cannot move a chord of ours.
local _chordCandidates = {};
local _chordsYielded = false;

function DebindPrivate.IsCastChordCandidate(key)
    return _chordCandidates[key] == true;
end

function DebindPrivate.CastChordsYielded()
    return _chordsYielded;
end

--- **The chords a bound key takes for its self and focus tiers**, as `chord -> tier`
--- (`picking-the-cast-tier-like-an-action-button.md` §3).
---
--- **Only for a tier with a twin** (`hasSelf`, `hasFocus`). A chord left unbound is the client's:
--- it lands on whatever else holds it, or falls to the key, whose press then reads the cast keys
--- itself (`EVAL_SNIPPET`). So the self and both-held chords go with a self twin, and the focus one
--- with a focus twin. With both cast keys on one modifier that one chord is self's where the key
--- has a self twin and focus's otherwise, or a key no action uses the Self Cast Key on could never
--- reach its focus twins.
---
--- Taken exactly where a press used to fall to the key: on a chord that, with only the bare keys
--- bound, lands on this key. A chord that lands elsewhere -- the game's own binding, another of our
--- keys, a chord of one -- went there before and still does.
---
--- **Every chord made is a candidate, bound or not**: one left to fall is on the way another one
--- falls, and an override put on it moves where that one lands.
local _castChords3, _castTiers3 = {}, {};

local function CastChordsOf(key, ours, selfMod, focusMod, hasSelf, hasFocus, out)
    wipe(out);
    local SELF, FOCUS = Constants.CASTMOD_SELF, Constants.CASTMOD_FOCUS;
    local selfChord = selfMod and AddModifier(key, selfMod);
    local chords, tiers = _castChords3, _castTiers3;
    chords[1], tiers[1] = selfChord, hasSelf and SELF or nil;
    chords[2], tiers[2] = focusMod and AddModifier(key, focusMod), hasFocus and FOCUS or nil;
    chords[3], tiers[3] = selfChord and focusMod and AddModifier(selfChord, focusMod), hasSelf and SELF or nil;
    if (selfMod and selfMod == focusMod) then
        tiers[1] = tiers[1] or tiers[2];
        chords[2] = nil;
    end
    for i = 1, 3 do
        local chord, tier = chords[i], tiers[i];
        if (chord) then
            _chordCandidates[chord] = true;
            if (tier) then
                local landing = LandingOf(chord, ours);
                if (landing == false) then
                    _chordsYielded = true;
                elseif (landing == key) then
                    out[chord] = tier;
                end
            end
        end
    end
    return out;
end

--- The game's modifier for a cast key, or nil where the reader turned ours off or the game has
--- none. `SetModifiedClick` takes any string, so only the three the options offer count.
local function CastModifier(enabled, action)
    if (not enabled) then
        return nil;
    end
    local mod = GetModifiedClick(action);
    if (mod == "ALT" or mod == "CTRL" or mod == "SHIFT") then
        return mod;
    end
    return nil;
end

--- The modifiers of the Self Cast Key and the Focus Cast Key a press reads, each nil where it is
--- off (`CastModifier`).
function DebindPrivate.CastKeyModifiers()
    return CastModifier(DebindPrivate.SelfCastEnabled(), "SELFCAST"),
        CastModifier(DebindPrivate.FocusCastEnabled(), "FOCUSCAST");
end

local _boundBare = {};
local _castChords = {};
local _tierItems = {};
local _hasSelfTwin, _hasFocusTwin = {}, {};

--- Empties the bare keys `NoteBareKey` fills, before the key walk that binds them.
local function BeginCastChords()
    wipe(_boundBare);
    wipe(_hasSelfTwin);
    wipe(_hasFocusTwin);
end

--- A bare key the key walk bound, and whether it has a self or a focus twin.
local function NoteBareKey(key, hasSelfTwin, hasFocusTwin)
    _boundBare[key] = true;
    _hasSelfTwin[key] = hasSelfTwin;
    _hasFocusTwin[key] = hasFocusTwin;
end

--- **A chord goes on at priority false, so it lies under another addon's override at true.** A
--- click-casting addon binds keys from the restricted side while the cursor is over a unit frame,
--- which neither the hooks nor `DirectLanding` see. Priority decides between two owners on one key
--- whatever order they were set in (`handing-the-rest-of-a-key-to-the-game.md` §6, measured), so
--- one at true wins however often the loop puts the chord back.
---
--- **It is the same for every chord, and the chord's row still carries it.** The loop and a key
--- coming back write the chord with what the row says, so the value is decided here and nowhere
--- else (`picking-the-cast-tier-like-an-action-button.md` §3). Only a chord's row has a `base`
--- either, but `base` says which key a chord goes over with; reading the priority off it would
--- decide the value again, on the restricted side, from a field that means something else.
local CHORD_PRIORITY = false;

--- Binds the chords of every bare key `NoteBareKey` was told of. `chordEntries` is the key walk's
--- per tier entries of each judged key, and a chord of one gets its tier's item in `judgmentItems`.
local function EmitCastChords(selfMod, focusMod, judgmentItems, chordEntries)
    wipe(_chordCandidates);
    _chordsYielded = false;
    if (selfMod or focusMod) then
        for _, key in ipairs(sortedKeys(_boundBare, _sortedA)) do
            CastChordsOf(key, _boundBare, selfMod, focusMod, _hasSelfTwin[key], _hasFocusTwin[key], _castChords);
            local first = true;
            local selfNamed, focusNamed = false, false;
            -- Two chords can land on one tier, and its item is the same for both.
            wipe(_tierItems);
            for _, chord in ipairs(sortedKeys(_castChords, _sortedB)) do
                local tier = _castChords[chord];
                local button = format("%s%s#%d", Constants.CLICKTIME_BUTTON_PREFIX, key, tier);
                if (first) then
                    first = false;
                    appendLine("bindings=ClickTimeKeys[%q]", Constants.CLICKTIME_BUTTON_PREFIX .. key);
                end
                -- One name per tier, though two chords can land on it (CTRL and ALT-CTRL both mean
                -- self where self is on CTRL).
                local named;
                if (tier == Constants.CASTMOD_SELF) then
                    named = selfNamed;
                else
                    named = focusNamed;
                end
                if (not named) then
                    appendLine("ClickTimeKeys[%q]=bindings", button);
                    appendLine("ClickTimeTiers[%q]=%d", button, tier);
                    if (tier == Constants.CASTMOD_SELF) then
                        selfNamed = true;
                    else
                        focusNamed = true;
                    end
                end
                appendLine("self:SetBindingClick(%s,%q,DefaultClickFrameName,%q)", tostring(CHORD_PRIORITY),
                    chord, button);
                appendLine("c=newtable() c.clickButton=%q c.base=%q c.priority=%s BoundKeys[%q]=c",
                    button, key, tostring(CHORD_PRIORITY), chord);
                if (chordEntries[key]) then
                    -- `false` keeps a tier with no item for a second chord on it.
                    local item = _tierItems[tier];
                    if (item == nil) then
                        item = DebindPrivate.Judgment.ItemFor(chordEntries[key][tier], key) or false;
                        _tierItems[tier] = item;
                    end
                    if (item) then
                        judgmentItems[chord] = item;
                    end
                end
            end
        end
    end
end

Rebuild.AddModifier     = AddModifier;
Rebuild.BeginCastChords = BeginCastChords;
Rebuild.NoteBareKey     = NoteBareKey;
Rebuild.EmitCastChords  = EmitCastChords;
