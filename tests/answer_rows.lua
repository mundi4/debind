-- The 27 actions of `devdocs/legacy/rewriting-evaluate-issues.md` §4, in the shape a profile stores them.
--
-- **One table for two specs.** `issue_spec` reads the issue columns and `keymap_spec` the record
-- counts, and a row spelled out twice is a row that can drift into two different actions.
--
-- Each row's `action()` returns a fresh table: the binding caches are keyed by the action, so a
-- table handed to one case must not carry what the last one derived.

return function(Constants)
    local HELP = { reaction = Constants.REACTION_HELP };
    local HARM = { reaction = Constants.REACTION_HARM };

    local function copy(value)
        if (type(value) ~= "table") then
            return value;
        end
        local out = {};
        for k, v in pairs(value) do
            out[k] = copy(v);
        end
        return out;
    end

    --- **Every row says what its Hover Cast is**, because off is the default and the rows are read
    --- by two specs: a row left blank would be one nobody can tell from a row meant to be off.
    local HOVER = { hoverCast = "cast" };
    local HOVER_OFF = {};
    local ALL_OFF = {
        normalCast = false,
        selfCastKey = "skip",
        focusCastKey = "skip",
    };
    local CAST_KEYS_OFF = { selfCast = false, focusCast = false };

    --- `units` and `groups` go under `conditions`; `options` is the settings tab. A row that says
    --- nothing about Casting gets Hover Cast on, which is the shape most of these rows were written
    --- against.
    local function row(n, label, fields)
        fields.n, fields.label = n, label;
        fields.casting = fields.casting or HOVER;
        fields.action = function()
            local conditions;
            if (fields.units or fields.groups) then
                conditions = { units = copy(fields.units), groups = fields.groups };
            end
            return {
                type = Constants.SPELL, value = 585, key = fields.key or "F1", seq = 1,
                unit = fields.unit, casting = copy(fields.casting), conditions = conditions,
            };
        end
        return fields;
    end

    return {
        row(1, "\"@\" reaction 0", { units = { ["@"] = { reaction = 0 } } }),
        row(2, "\"@\" [friendly], target [hostile]", { units = { ["@"] = HELP, target = HARM } }),
        row(3, "2 with both cast keys off in the settings tab",
            { units = { ["@"] = HELP, target = HARM }, options = CAST_KEYS_OFF }),
        row(4, "target focus, \"@\" [friendly], focus [hostile]",
            { unit = "focus", units = { ["@"] = HELP, focus = HARM } }),
        row(5, "target row reaction 0", { units = { target = { reaction = 0 } } }),
        row(6, "target unitframe, \"@\" [there], unitframe [none]",
            { unit = "unitframe", units = { ["@"] = {}, unitframe = false } }),
        row(7, "target unitframe, unitframe reaction 0",
            { unit = "unitframe", units = { unitframe = { reaction = 0 } } }),
        row(8, "tank [there], solo only", { units = { tank = {} }, groups = Constants.GROUP_NONE }),
        row(9, "target tank, \"@\" [there], solo only",
            { unit = "tank", units = { ["@"] = {} }, groups = Constants.GROUP_NONE }),
        row(10, "Hover Cast off, unitframe [hostile]",
            { casting = HOVER_OFF, units = { unitframe = HARM } }),
        row(11, "BUTTON3, \"@\" [friendly], unitframe [hostile]",
            { key = "BUTTON3", units = { ["@"] = HELP, unitframe = HARM } }),
        row(12, "BUTTON1, \"@\" [friendly], unitframe [hostile]",
            { key = "BUTTON1", units = { ["@"] = HELP, unitframe = HARM } }),
        row(13, "\"@\" [friendly], player [hostile]", { units = { ["@"] = HELP, player = HARM } }),
        row(14, "\"@\" [friendly], target, player, focus, unitframe all [hostile]",
            { units = { ["@"] = HELP, target = HARM, player = HARM, focus = HARM, unitframe = HARM } }),
        row(15, "\"@\" [none]", { units = { ["@"] = false } }),
        row(16, "BUTTON3, target unitframe, \"@\" [there]",
            { key = "BUTTON3", unit = "unitframe", units = { ["@"] = {} } }),
        row(17, "all four off", { casting = ALL_OFF }),
        row(18, "17 with \"@\" reaction 0", { casting = ALL_OFF, units = { ["@"] = { reaction = 0 } } }),
        row(19, "Hover Cast off, both cast keys off, unitframe [hostile]",
            { casting = HOVER_OFF, options = CAST_KEYS_OFF, units = { unitframe = HARM } }),
        -- The bare click answers `"cast"` whatever is stored, so [when there is none] on that unit
        -- is the one way to leave it with nothing (`HoverCastChoiceOf`).
        row(20, "BUTTON1, unitframe [none]",
            { key = "BUTTON1", casting = HOVER_OFF, units = { unitframe = false } }),
        row(21, "Normal Cast off, \"@\" [friendly], target [hostile]",
            { casting = { normalCast = false, hoverCast = "cast" },
                units = { ["@"] = HELP, target = HARM } }),
        row(22, "focus group 0, target [there]", { units = { focus = { group = 0 }, target = {} } }),
        row(23, "unitframe role 0", { units = { unitframe = { role = 0 } } }),
        row(24, "unitframe role tank, solo only",
            { units = { unitframe = { role = Constants.ROLE_TANK } }, groups = Constants.GROUP_NONE }),
        -- A scalar this build does not know (`UnitConditionForBinding`).
        row(25, "target row unreadable", { units = { target = "unreadable" } }),
        row(26, "target row role 0", { units = { target = { role = 0 } } }),
        row(27, "\"@\" [none], target, player, focus [there]",
            { units = { ["@"] = false, target = {}, player = {}, focus = {} } }),
    };
end
