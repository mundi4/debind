local ADDON_NAME, DebindPrivate = ...;
local L                       = DebindPrivate.L;
local Constants               = DebindPrivate.Constants;

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
    switches = "COUNT_SWITCHES",
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

--- Somebody else's text made safe to draw: at most `maxChars` characters, and every `|` doubled.
--- **A `|` is the client's markup** (`|c` colour, `|H` link, `|T` texture, `|n` line break), and
--- text from a string somebody else wrote could recolour a row, fake a link or stretch the list.
--- Doubled, it draws as itself. A pasted entry's name and description go through it, and so does
--- what a broken action was (`NameAndIconForAction`).
---
--- One line unless `multiline`: a name sits on a row, and a description is typed in a box that
--- takes line breaks. Every other control character is a space either way.
---
--- Cut before it is escaped, so the cut cannot split a doubled `|` and leave a live one. Nil for
--- anything that is not a string or is empty once trimmed.
function DebindPrivate.PlainText(text, maxChars, multiline)
    if (type(text) ~= "string") then
        return nil;
    end
    if (multiline) then
        text = text:gsub("\r\n?", "\n"):gsub("[^%S\n]+", " "):gsub("[%c]", function(c)
            return c == "\n" and c or " ";
        end);
        text = strtrim(text);
    else
        text = strtrim((text:gsub("[%c]+", " ")));
    end
    if (text == "") then
        return nil;
    end

    local count, cut = 0, nil;
    for start in text:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1;
        if (count > maxChars) then
            cut = start;
            break;
        end
    end
    if (cut) then
        text = strtrim(text:sub(1, cut - 1)) .. "...";
    end

    return (text:gsub("|", "||"));
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

