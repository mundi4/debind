local _, DebindPrivate = ...;

--- A help page body, cut into the blocks `DebindMessageFrameMixin:SetMessage` lays out one
--- FontString each.
---
--- **The structure lives in the locale string rather than in a list of keys.** A page split across
--- keys renumbers them all when a paragraph goes in, and a locale missing one of them puts an
--- English paragraph in the middle of a translated page; one key per page falls back whole.
---
--- A line starting `# ` is a heading, `> ` a note, `1. ` or `- ` an item, each two leading spaces
--- one level of nesting. A blank line ends a block; any other line joins the block before it with a
--- space.
--- Escapes (`|cn`, `|A`, `|H`) are left for the FontString. A body with no line breaks at all is
--- one paragraph, so a page written with `|n` still reads as it did.
function DebindPrivate.ParseHelpText(text)
    local blocks = {};
    local current;

    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        local indent, rest = line:match("^( *)(.-)%s*$");
        local heading = rest:match("^#%s+(.*)$");
        local note = rest:match("^>%s+(.*)$");
        local marker, itemText = rest:match("^(%d+%.)%s+(.*)$");
        if (not marker) then
            marker, itemText = rest:match("^(%-)%s+(.*)$");
        end

        if (rest == "") then
            current = nil;
        elseif (heading) then
            blocks[#blocks + 1] = { kind = "heading", text = heading };
            current = nil;
        elseif (note) then
            current = { kind = "note", text = note };
            blocks[#blocks + 1] = current;
        elseif (marker) then
            current = { kind = "item", marker = marker, level = math.floor(#indent / 2), text = itemText };
            blocks[#blocks + 1] = current;
        elseif (current) then
            current.text = current.text .. " " .. rest;
        else
            current = { kind = "paragraph", text = rest };
            blocks[#blocks + 1] = current;
        end
    end

    return blocks;
end
