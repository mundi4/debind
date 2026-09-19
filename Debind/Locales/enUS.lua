local _, addon = ...;
addon.L = setmetatable({}, { __index = function(_, key) return key end });
local L = addon.L;

-- 색은 **클라이언트 색 이름**으로 쓴다(`|cnRED_FONT_COLOR:`). 날 hex는 애드온 고유색인
-- _MESSAGE_PREFIX 하나뿐이다 - 그것만 우리 것이고 나머지는 게임의 것이라, 게임이 색을
-- 바꾸면 같이 바뀌어야 맞다. 한때 같은 뜻에 hex와 색 이름이 섞여서, 빨강 하나가
-- 문자열마다 다른 빨강이었다.
L["_MESSAGE_PREFIX"] = "|cff3b9de3[Debind]|r "
L["ADDON_NAME"] = "Debind"
-- 여럿을 고른 채로 연 우클릭 메뉴의 제목. 이름을 나열하지 않는 이유는 DELETE_CONFIRM_MESSAGE_MULTIPLE
-- 쪽 주석에 있다. 아래 카운트와 낱말을 맞춘다 - 한 화면에서 같은 것을 두 가지로 부르지 않는다.
L["BULK_MENU_TITLE"] = "%d selected"
-- 목록 위 스트립. 고른 것이 둘 이상일 때만 뜬다 - 하나일 때는 행 강조가 이미 말했다.
L["BULK_SELECTED_COUNT"] = "%1$d selected (%2$d in this layer)"
-- 조건 툴팁에서 조건 이름(CONDITION_BONUSBAR / CONDITION_GROUP) **바로 아래** 붙는 줄이다.
-- 둘 다 "No option is selected."였는데, 그러면 같은 툴팁에 두 번 떠도 어느 쪽 이야기인지
-- 줄만 봐서는 모른다. FORMS/HOVER처럼 무엇이 안 골렸는지를 말한다.
-- The toggle in the portrait row. With it on, pointing at a row and pressing a key is the whole
-- act. The reasoning is in the `BindModePortrait` comment in DebindUI.xml.
--
-- **It names the mode, not the act** ("Set Keys" before). What the toggle turns on outlives the
-- press, and a verb on a control that stays lit reads as a one-shot.
--
-- The client owns this concept for the action bars - `QUICK_KEYBIND_MODE`, "Quick Keybind Mode" -
-- and we deliberately do not take that string: ours is a different mode in a different window, and
-- borrowing the name would promise the game's. "Bind Mode" is still the client's own compound
-- (`QUICK_KEYBIND_MODE_BUTTON` reads "Quick Bind Mode"), so no word here is invented.
--
-- The second one is what the toggle says while the mode is on, and it is a tooltip title now that
-- the button carries an icon instead of a label. It stays a verb: at that point the only thing left
-- to say about the button is what pressing it now does.
L["BIND_MODE"] = "Bind Mode"
L["BIND_MODE_STOP"] = "Done"
-- **This used to be the client global `ESCAPE_TO_UNBIND`, and that was the wrong sentence in this
-- position.** The client hangs it off the very button being hovered (`QuickKeybindTooltip`), where
-- "this action" points at something. Ours is nailed to a standing overlay in the left column, so
-- "this" has nothing to point at. Worse, the reader most likely to be reading it is pointing at
-- nothing, which is the one state where Escape does not unbind anything at all.
--
-- So it names the condition instead of pointing, and it carries **both** of Escape's meanings. The
-- second one cannot be taken back, and [Cancel] is the only other place that says it exists.
--
-- **Two lines, because it is one key with two meanings and the reader has to pick theirs.** Run
-- together, the second half reads as a footnote to the first; broken at `|n` the two stand as a
-- pair, opening on the thing that tells them apart. `README.md` carries the same two facts as a
-- two-item list.
--
-- The cost, taken knowingly: the client global came out in the reader's own language for free, and
-- every locale now has to translate this. Korean and Russian read this English line until they do.
L["BIND_MODE_UNBIND_HINT"] = "If you are pointing at an action, Escape clears its key.|nIf you are pointing at nothing, Escape puts back every key you changed and leaves."
L["BIND_MODE_CANCEL"] = "Cancel"
L["BIND_MODE_OVERLAY"] = "Point at an action on the right and press the key you want."
L["BIND_MODE_DESC"] = "Turns on a mode where whatever you press becomes the key for the action under your cursor. Selecting and the right-click menu pause while it is on."
L["BINDING_ERROR_BONUSBARS_NONE_SELECTED"] = "No action bar is selected."
L["BINDING_ERROR_CONDITIONS_NEVER"] = "The conditions are impossible to meet."
-- **One state, two sentences, because the reader is looking at two different things.** Neither side
-- is wrong on its own: the reader wrote one ordinary condition, and what it cannot meet is the key.
-- "The conditions are impossible" would send them looking for a second condition that is not there.
--
-- **Beside the key, the condition is not "this".** The reader is looking at the key, so the sentence
-- says what the key can do and that something on the action rules it out.
L["BINDING_ERROR_KEY_RULED_OUT"] = "This key runs only when you click a unit frame, and a condition on this action rules that click out."
-- **Beside the condition, it is named as the reader set it.** `%s` is the mode they picked on that
-- unit row, so a rename carries into the sentence; the row they are looking at says which unit.
L["BINDING_ERROR_CONDITION_NEVER_ON_KEY"] = "%s never holds on this key: a left or right click with no modifier runs only when you click a unit frame."
L["BINDING_ERROR_FORMS_NONE_SELECTED"] = "No shapeshift form is selected."
L["BINDING_ERROR_GROUPS_NONE_SELECTED"] = "No group type is selected."
-- One axis each, named by the axis. The frame type one said "reaction or frame type" while it was
-- raised for frame types alone, and a reaction left empty said the conditions contradict.
L["BINDING_ERROR_HOVER_NONE_SELECTED"] = "No frame type is selected."
L["BINDING_ERROR_REACTIONS_NONE_SELECTED"] = "No reaction is selected."
L["BINDING_ERROR_ROLES_NONE_SELECTED"] = "No role is selected."
-- The same empty role beside frame types other than party and raid frames. A role is only measured
-- on those, so the action still runs over the rest, and this says which frames it loses.
L["BINDING_ERROR_ROLES_NONE_ON_GROUP_FRAMES"] = "No role is selected, so it does not run on party or raid frames."
L["BINDING_ERROR_UNITGROUPS_NONE_SELECTED"] = "No group option is selected."
-- **It names the way out that is not turning a press back on.** The reader may have meant to stop
-- this action, and the mark has to be closable by saying so rather than by choosing a value they do
-- not want. The second sentence is what tells turning off from deleting.
L["BINDING_ERROR_NOTHING_RUNS"] = "Every press is turned off, so this action never runs. Turn it off if you don't want to use it. A turned-off action keeps everything you set on it and hands its key back to the game."
-- The reader cannot fix the spell's name, so the sentence says what to do instead: pick another
-- row, or drop the condition. Neither half of the reason (macro conditionals, commas) is
-- something the window has ever spoken about.
L["BINDING_ERROR_KNOWN_NAME_UNPARSABLE"] = "This spell's name cannot be used in this condition. Pick another spell, or turn the condition off."
L["BINDING_ERROR_SPECS_NONE_SELECTED"] = "No specialization is selected."
-- The fourth of the *_NONE_SELECTED family, and the only one that is not about a condition: the
-- action itself has not been told which switch it works. Kept apart from the line below on
-- purpose. "You have not picked one" and "the one you picked is gone" send the reader to two
-- different places, and the second names a switch while this one has none to name.
L["BINDING_ERROR_SWITCH_NONE_SELECTED"] = "No switch is picked. Until one is, this binding does not fire at all."
-- **Escape by name, because Escape is what is refused** (`IsKeyInvalidForAction`). It used to name
-- Toggle Game Menu and follow that binding, which meant it could print about a key the reader had
-- moved somewhere we could not follow. "Escape" is the client's own word for the key
-- (`KEY_ESCAPE`).
--
-- **Nothing is highlighted.** The whole line is already drawn red as an error, and one white word
-- inside it reads as a second thing being said rather than as emphasis. The other errors highlight
-- a value they were handed (`%s`); there is no value here, only the one key this is about.
L["BINDING_ERROR_NOT_SUPPORTED_GAMEMENU_KEY"] = "The Escape key cannot be used."
-- %s is the name the action carries: written into a macro body, or picked as what an on/off/toggle
-- action sets. **This line and the macro one below are the only errors that take an argument** --
-- every other BINDING_ERROR_* is about a condition, and which condition is already visible in the
-- box it belongs to. Neither of these two has a box, so without the name there is nothing on
-- screen saying what to fix.
L["BINDING_ERROR_UNDEFINED_STATE"] = "There is no switch named |cnHIGHLIGHT_FONT_COLOR:%s|r."
-- The second line that takes an argument, for the reason above: a macro name also lives inside the
-- action rather than in a condition control.
L["BINDING_ERROR_MISSING_MACRO"] = "There is no macro named |cnHIGHLIGHT_FONT_COLOR:%s|r on this account or character."
-- On a saved [Use WoW's Own Binding] or binding command row. The row's own name already says what it
-- was, so this says what a press does now and why, then the two ways out. It says "the game's own
-- keybinding" because the command was one.
--
-- **It says nothing about the key**, and neither may anything written here later. This action is one
-- of several the key can hold and it may carry conditions of its own, so whether the key is taken,
-- and whether the actions under it run, are answered by the whole key and never by this row.
--
-- **The macro is offered "where it can be done" and not flatly.** Not every binding command has a
-- slash command, and `CanConvertToMacroText` takes neither of these two types, so the reader makes
-- the Custom Macro themselves rather than converting this row.
L["BINDING_ERROR_TYPE_RETIRED"] = "Debind no longer passes keys to the game's own keybindings, so this action does nothing when it takes a press. Delete it, or where a slash command can do the same thing, replace it with a Custom Macro."
-- The only MINOR code, so this states what happened and stops there. The key itself still fires,
-- and leaving an outranked action in place is a choice the reader is allowed to make.
--
-- Two things it must not say. The coverage can come from several earlier actions at once
-- (`CheckUnreachableBindings` hands the whole set to `isCovered`), so sending the reader off to
-- look at one action points at something that may not exist. And this action may carry no
-- conditions at all, so any wording resting on the situations it was set up for is false for the
-- plainest case there is, two condition-less actions on one key.
--
-- "No matter what" is what the sentence turns on. Every action but the first is preceded by others,
-- which is what this line said before, and it was true of the healthy rows just as much.
L["BINDING_ERROR_UNREACHABLE"] = "This action never runs. No matter what, another action on this key gets there first."
L["BINDING_TITLE"] = "%2$s (%1$s)"
L["BLIZZARD_UNIT_FRAMES_ARENA"] = "Arena Frames"
L["BLIZZARD_UNIT_FRAMES_BOSS"] = "Boss Frames"
L["BLIZZARD_UNIT_FRAMES_PARTY"] = "Party Frames"
L["BLIZZARD_UNIT_FRAMES_PET"] = "Pet Frame"
L["BLIZZARD_UNIT_FRAMES_PLAYER"] = "Player Frame"
L["BLIZZARD_UNIT_FRAMES_RAID"] = "Raid Frames"
L["BLIZZARD_UNIT_FRAMES_TARGET"] = "Target and Focus"
-- **It names a subject and not an action.** What is under it is every unit frame decision the
-- addon has, and not only the taking away.
L["UNIT_FRAME_SUPPORT"] = "Unit Frame Support"
-- **Not the client's `HELP_LABEL`.** That one is the game menu's entry into customer support, so the
-- same word would point somewhere else.
L["HELP_TOPICS"] = "Help"
--- The second line of the (i) tooltip, under the topic's own title.
---
--- **Not the client's `CLICK_FOR_MORE_INFO`** ("Click for more information"). That line stands under
--- something the reader has already been shown, and here there is nothing above it but the title -
--- a question, with the answer still behind the click. "More" would be counting from nothing.
L["HELP_TIP_OPEN"] = "Click to read this help topic"
-- The two groups under `UNIT_FRAME_SUPPORT`.
--
-- **Not `Blizzard's`.** A possessive wants a noun behind it, and `Blizzard's Frames` reads as the
-- frames belonging to a company rather than as the ones the game ships.
L["FRAME_BLACKLIST_BLIZZARD"] = "Blizzard Frames"
L["FRAME_BLACKLIST_ADDONS"] = "Addon Frames"
-- **A name, because the rows above it are names.** It stands under `Grid2` and `VuhDo`, so it takes
-- the same shape they do; `Addons Not Listed Above` reads as a description in that column and
-- breaks the run.
L["LEAVE_OTHER_ADDON_FRAMES"] = "Any Other Addon"
L["CANNOT_OPEN_WITH_GAME_MENU"] = "Close the game menu first."
L["COMPARTMENT_TOOLTIP_LEFT_CLICK"] = "Click to open Debind. The bindings overview is the left column."
-- The client's own two words for the flight styles: `MOUNT_JOURNAL_FILTER_FLYING` and
-- `MOUNT_JOURNAL_FILTER_DRAGONRIDING` (which reads "Skyriding" today). Both say what the **area**
-- allows, not what the reader is doing, so the values below say "Where" rather than "While".
L["CONDITION_ADVFLYABLE_NO"] = "Where skyriding is not allowed"
L["CONDITION_ADVFLYABLE_YES"] = "Where skyriding is allowed"
L["CONDITION_ADVFLYABLE"] = "Skyriding Allowed"
L["CONDITION_ACTIONBARS"] = "Action Bars"
L["CONDITION_BONUSBAR"] = "Stance Bar"
L["CONDITION_COMBAT_NO"] = "While not in combat"
L["CONDITION_COMBAT_YES"] = "While in combat"
L["CONDITION_COMBAT"] = "Combat"
L["CONDITION_CUSTOM_STATES"] = "Switches"
L["CONDITION_CUSTOM_STATE_NO"] = "When the switch is off"
L["CONDITION_CUSTOM_STATE_YES"] = "When the switch is on"
L["CONDITION_EXTRABAR_NO"] = "When the Extra Action Button is not present"
L["CONDITION_EXTRABAR_YES"] = "When the Extra Action Button is present"
L["CONDITION_EXTRABAR"] = "Extra Action Button"
L["CONDITION_FLYABLE_NO"] = "Where flying is not allowed"
L["CONDITION_FLYABLE_YES"] = "Where flying is allowed"
L["CONDITION_FLYABLE"] = "Flying Allowed"
-- **The pair of `CONDITION_FLYABLE`, and the words have to keep them apart.** That one is about
-- the place and this one is about the reader, so it says "While" where the other says "Where".
L["CONDITION_FLYING_NO"] = "While not airborne"
L["CONDITION_FLYING_YES"] = "While airborne"
L["CONDITION_FLYING"] = "Airborne"
L["CONDITION_FORM_N"] = "Form %d"
L["CONDITION_FRAMETYPES"] = "Frame Type"
-- **두 반쪽을 다 말해야 한다.** 이 줄은 개체창 유닛 아래에도, Resolved Unit 아래에도 선다.
-- 앞 문장이 "어느 개체창이냐"를, 뒤 문장이 "이 개체가 그 개체창의 개체냐"를 답한다. 뒤를
-- 빼면 대상을 따로 고른 액션에서 상자를 켠 사람이 아무 일도 안 일어나는 것을 보게 된다.
L["CONDITION_FRAMETYPES_DESC"] = "Only the frame you are pointing at has a kind. When this unit is not the one on that frame, this does not hold the action back."
L["CONDITION_GROUP"] = "Group";
-- The negative is "Not Indoors" and deliberately not "Outdoors". The condition reads `IsIndoors()`
-- alone, so its false half is everything that is not indoors, which is a wider thing than the
-- client's Outdoors. Calling it Outdoors would be a claim the measurement does not make.
L["CONDITION_INDOORS_NO"] = "While not indoors"
L["CONDITION_INDOORS_YES"] = "While indoors"
L["CONDITION_INDOORS"] = "Indoors"
-- **The rows under it are spell names**, so the row names what is picked rather than describing a
-- state. The client has no noun for this (`Already Known`, `This spell is already known` are all
-- sentences), so the two words are ours.
L["CONDITION_KNOWN"] = "Known Spell"
L["CONDITION_KNOWN_YES"] = "While you know the spell"
-- The row names the spell it asks about, and the rows are a list to pick one from. A talent that
-- replaces a spell is its own row, which is the whole point of naming them.
L["CONDITION_KNOWN_VALUE"] = "While you know %s"
-- **The client's own word for the thing** (`TALENTS`), and the branches under it are named by the
-- client too: the class, the specialization, each hero tree and `PVP_TALENTS`. The reader has one
-- name for each of those already and a second one would put two names on one thing.
L["CONDITION_TALENT"] = "Talents"
-- The rows under each branch are talent names, so these two say what picking one does. A talent
-- the character has bought is *taken*, which is the word the client's own failure messages use.
L["CONDITION_TALENT_TAKEN"] = "While it is taken"
L["CONDITION_TALENT_NOT_TAKEN"] = "While it is not taken"
-- The same two, where the tooltip names the talents instead of standing under one.
-- The branch holding what other specializations carry. **It opens on what is stored, not on their
-- trees**: the menu offers the specialization being played, so these rows can be read and cleared
-- but nothing new can be put on them.
-- The client's own words for the thing (`HERO_TALENTS_LOCKED_1`), in the case a menu row is
-- written in rather than the banner's caps.
L["CONDITION_TALENT_HERO"] = "Hero Talents: %s"
-- **The heading over the one thing this menu can do about them.** It lists the specialization
-- being played, so talents set on another one have no rows here; the button under this is how they
-- come off without switching specialization.
--
-- **Classes are named too, and not for completeness.** A shared string carries the sender's own
-- specialization ids, so an imported action arrives holding a class this character will never
-- play, and switching specialization can never reach it.
L["CONDITION_TALENT_OTHER_SPECS"] = "Set on other classes and specializations"
L["CONDITION_TALENT_CLEAR_OTHERS"] = "Remove all"
-- **What the button does not touch is the half worth saying.** It reads as though it clears the
-- talent condition, and the rows above it are the ones the reader has been clicking.
L["CONDITION_TALENT_CLEAR_OTHERS_DESC"] = "Removes the talents set on every other class and specialization. What you set on the specialization you are playing stays."
-- The same block with nothing in it. **A line and not an empty space**: the reader came here to
-- find out whether anything is set elsewhere, and silence does not answer that.
L["CONDITION_TALENT_NO_OTHERS"] = "None"
-- **Two things a reader cannot see on the rows.** The condition is kept per specialization and
-- this menu writes the one being played, so the rows say nothing about the others; and both hero
-- trees are offered, while the game runs one of them at a time.
L["CONDITION_TALENT_DESC"] = "Only what you set here, on the specialization you are playing, is shown. Both hero talent trees are offered, and a talent in the one you have not chosen counts as not taken."
L["CONDITION_TALENT_VALUE_TAKEN"] = "While %s is taken"
L["CONDITION_TALENT_VALUE_NOT_TAKEN"] = "While %s is not taken"
-- The submenu that holds the four conditions too small to hold a row of the main list each. It
-- names no rule of its own, so it stays the plain word rather than trying to describe what is
-- inside it.
L["CONDITION_MISC"] = "Miscellaneous"
-- Not the client's `MOUNTS`. That word names the collection, and a menu titled with it reads as
-- a choice of which mount to summon; what this asks is whether the reader is on one.
L["CONDITION_MOUNTED_NO"] = "While not mounted"
L["CONDITION_MOUNTED_YES"] = "While mounted"
L["CONDITION_MOUNTED"] = "Mounted"
L["CONDITION_PETBATTLE_NO"] = "While not in a pet battle"
L["CONDITION_PETBATTLE_YES"] = "While in a pet battle"
L["CONDITION_PETBATTLE"] = "Pet Battle"
L["CONDITION_REACTIONS"] = "Reactions"
-- 게임의 낱말 그대로다: ROLE / TANK / HEALER / DAMAGER, 그리고 알 수 없을 때가 UNKNOWN.
-- 우리가 붙인 이름이 하나도 없어야 하는 자리다.
L["CONDITION_ROLE"] = "Role"
L["CONDITION_ROLE_DESC"] = "Only party and raid frames can tell you a role. Over any other frame, and when this unit is not the one on the frame you are pointing at, this does not hold the action back."
L["ROLE_TANK"] = "Tank"
L["ROLE_HEALER"] = "Healer"
L["ROLE_DAMAGER"] = "Damage"
-- **The client's own `NO_ROLE`**, and the fourth role rather than a failure to read one. It was
-- "Unknown", which says something about us: the addon always has the answer once the three headers
-- are up, so there is no unit it looked at and could not tell. What it names is a unit nobody has
-- assigned a role to. A frame that cannot be asked at all is a separate thing and never reaches
-- this value (`CONDITION_ROLE_DESC`).
L["ROLE_NONE"] = "No Role"
L["CONDITION_SHAPESHIFT"] = "Shapeshift"
L["CONDITION_SHAPESHIFT_DESC"] = "The name beside each number is what that number means for this character's class. On another class the same number is a different form, and a number with no name is one this class does not have."
-- The client's own word for the flight style (`ACCESSIBILITY_ADV_FLY_LABEL`,
-- `MOUNT_JOURNAL_FILTER_DRAGONRIDING`). Dragonriding is what it used to be called and is not what
-- a player reads today.
L["CONDITION_SKYRIDING_NO"] = "While not skyriding"
L["CONDITION_SKYRIDING_YES"] = "While skyriding"
L["CONDITION_SKYRIDING"] = "Skyriding"
-- **The number is the label and the name is a hint on it.** An action can be moved to a tab
-- several classes share, so every class is on the list and not only the one being played. Both
-- halves are the client's own words (`CLASS`, `SPECIALIZATION`).
--
-- **Singular, because the row names the one thing it opens** rather than counting what is behind
-- it. `CONDITION_SPECS` below is the plural, and it heads a list.
--
-- One specialization of each class has no name, so `NO_SPECIALIZATION` fills that row instead. It
-- is the specialization a character has before choosing one.
L["CONDITION_SPEC"] = "Class/Specialization"
-- The tooltip lists several at once, where the menu row names the one thing it opens. The client
-- heads its own list the same way (`CLUB_FINDER_SPECIALIZATIONS`).
L["CONDITION_SPECS"] = "Specializations"
L["CONDITION_SPEC_DESC"] = "Pick the specializations this fires in. Every class is listed because an action in the Account tab runs on characters of another one."
L["CONDITION_SPECIALBAR_DESC"] = "Active while something has replaced your main action bar -- a vehicle, a possession, and the like."
L["CONDITION_SPECIALBAR_NO"] = "While your action bar is not replaced"
L["CONDITION_SPECIALBAR_YES"] = "While your action bar is replaced"
L["CONDITION_SPECIALBAR"] = "Replaced Action Bar"
L["CONDITION_STEALTH_NO"] = "While not stealthed"
L["CONDITION_STEALTH_YES"] = "While stealthed"
L["CONDITION_STEALTH"] = "Stealth"
L["CONDITION_UNIT_DOES_NOT_EXIST"] = "When the unit doesn't exist"
L["CONDITION_UNIT_EXISTS"] = "When the unit exists"
L["CONDITION_LIFE"] = "Alive or Dead"
L["CONDITION_UNIT_GROUP"] = "Group"
L["CONDITION_UNITS"] = "Units"
L["CONFIRM_CURRENT_CHANGE_FIRST"] = "Confirm current change first."
L["CONVERT_TO_MACRO_TEXT"] = "Convert to a Custom Macro"
L["COPY_TO"] = "Copy to..."
-- 이동·복사 목록에서 지금 그 액션이 사는 탭. %s는 다른 줄과 **똑같은** 탭 이름이고, 뒤에
-- 붙는 표시만 그 줄을 가른다 - 이름을 갈아치우면 목록에서 그 탭의 자리를 잃는다.
L["CURRENT_TAB_SUFFIX"] = "%s |cnLIGHTGRAY_FONT_COLOR:(current)|r"
-- **`@@`가 여기서 안 된다는 것은 이 줄이 유일하게 말하는 자리다.** 식은 누름마다 한 번, 어느 액션이
-- 이기는지 정해지기 전에 계산돼서 겨누는 유닛이 없다(`implementing-focus-and-self-cast.md` §4). 상자는
-- 게임 조건문을 그대로 받고 어떤 문법도 안 보므로, 적어 넣어도 막히지 않고 조용히 안 맞는다.
L["CUSTOM_STATE_EDIT_VALUE_DESC"] = "Enter macro conditional expression.\n(Example: |cnHIGHLIGHT_FONT_COLOR:[@tank,exists,combat]|r)\n|cnHIGHLIGHT_FONT_COLOR:@@|r is not read here."
L["CUSTOM_STATE_EDIT_VALUE"] = "Enter macro conditional expression."
L["CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC"] = "This option lets the addon determine the value of the switch based on macro conditional expressions (Example: |cnHIGHLIGHT_FONT_COLOR:[@healer,exists]|r)."
L["CUSTOM_STATE_MODE_MACRO_CONDITIONAL"] = "Set Automatically"
L["CUSTOM_STATE_OFF"] = "Off"
L["CUSTOM_STATE_ON"] = "On"
-- What a switch is, said once. The Switches tab's own tooltip prints it (PANELS in DebindUI.lua)
-- and so does the condition menu's switch group, which is handed this key explicitly
-- (CreateSwitchConditionMenu in DropDownMenus.lua). A twin key, CONDITION_CUSTOM_STATES_DESC, used
-- to hold a paragraph that did not differ from this one by a single character, which meant
-- translating the same text twice in every locale.
--
-- It said "the tooltip of the SwitchesPortrait button" until 3c took that button off the window.
L["CUSTOM_STATES_DESC"] = "These are ON/OFF switches that can be used as special conditions or macro conditional expressions in |cnLIGHTBLUE_FONT_COLOR:Custom Macros|r (Example: |cnHIGHLIGHT_FONT_COLOR:[$state1]|r). You can turn these switches on or off at any time, or you can set them as macro conditionals themselves."
L["CUSTOM_STATES"] = "Switches"
L["CUSTOM_TARGET_FAILED"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - |cnRED_FONT_COLOR:Failed to set from '%2$s'|r"
L["CUSTOM_TARGET_INVALIDATED"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnRED_FONT_COLOR:Cleared|r - it was held by group slot, not by name, and the group changed. Set it again."
L["CUSTOM_TARGET_SET_VOLATILE"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - Set to %2$s - held by group slot rather than by name, because the group changed during this fight. Set it again after combat and it will follow them."
-- The three lines a Set Custom Target press can fail with. `UnitWatch.lua` says which is which.
--
-- **None of them names a unit token.** `hover` and `mouseover` are values the addon writes for
-- itself; the reader chose neither and has never seen either.
--
-- **Two of them are one cause split by combat**, because the limit is not the same one. In combat
-- the answer is bounded by which frames Debind is wired to; out of combat any frame resolves, and
-- what is left is a unit with no token to point at it again.
L["CUSTOM_TARGET_FRAME_NOT_OURS_IN_COMBAT"] = "|cnHIGHLIGHT_FONT_COLOR:Another addon|r|cnRED_FONT_COLOR: drives this unit frame, so a custom target cannot be set on it in combat|r"
L["CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT"] = "|cnRED_FONT_COLOR:In combat a custom target can only be set over the Player, Pet, Party/Raid, Boss and Arena unit frames|r"
L["CUSTOM_TARGET_UNSUPPORTED_UNIT"] = "|cnRED_FONT_COLOR:A custom target can only hold yourself, your pet, someone in your party or raid, an encounter boss, or an arena opponent|r"
L["DEFAULT"] = "Default"
L["DELETE_CONFIRM_MESSAGE"] = "Are you sure you want to delete |cnHIGHLIGHT_FONT_COLOR:%s|r?"
-- 여럿을 한꺼번에 지울 때. **이름 대신 개수로 묻는다** - 열몇 개를 나열하면 팝업이 화면을
-- 덮고, 몇 개만 적으면 나머지를 숨긴 채로 묻는 꼴이 된다.
L["DELETE_CONFIRM_MESSAGE_MULTIPLE"] = "Are you sure you want to delete |cnHIGHLIGHT_FONT_COLOR:%d|r actions?"
L["DELETE"] = "Delete"
-- 클라이언트가 이미 모든 언어로 갖고 있는 말이다. 여기서 한 번 받아두면 로케일 파일이
-- 없는 언어도 제 나라 말로 나온다.
--
-- 단축키 버튼과 행 툴팁이 **같이** 쓴다. 한때 행 툴팁만 따로 L["NOT_BOUND"]를 들고
-- 있었는데, 그러면 로케일이 손으로 옮긴 말과 클라이언트의 말이 같은 창 안에서 갈릴 수
-- 있었다 - 같은 뜻은 한 군데서만 나와야 한다.
L["OVERVIEW_NO_KEY"] = NOT_BOUND
-- What a menu title says after the one thing it names: how many more are in it. The key group menu
-- names the first action, and the action menu over several layers names the broadest one.
-- **Not a total** - the one being named is not counted again, so a key with two actions reads
-- "Charge +1".
--
-- A sign and a number and nothing else, because it sits beside a name, and anything wordier takes
-- characters from that name.
L["OVERVIEW_KEY_HEADER_MORE"] = "+%d"
-- 이 열은 접히지 않으므로 빈 자리가 늘 보인다. "비었다"가 아니라 **무엇을 하면 채워지는지**를
-- 말한다 - 오른쪽 목록의 빈 문장들과 같은 규칙이다.
L["OVERVIEW_EMPTY"] = "No key is bound yet. Give an action a key on the right and it turns up here."
L["DISABLE"] = "Disable"
L["DISABLE_ALL"] = "Disable All"
L["EDIT_MACRO"] = "Edit this Custom Macro"
L["ERROR_MESSAGE_CANNOT_SET_CUSTOM_TARGET_IN_COMBAT"] = "Cannot set a custom target by command while in combat."
L["EXCLUDE_PLAYER_DESC"] = "An action aimed at Tank, Healer, Main Tank or Main Assist goes to whoever in your group holds it, and a ticked one never resolves to you. These targets stand only while exactly one member holds them, so excluding yourself is how a tank aims at the other tank."
L["EXCLUDE_PLAYER"] = "Exclude self"
L["FRAMETYPE_ARENA"] = "Arena Frames"
L["FRAMETYPE_BOSS"] = "Boss Frames"
L["FRAMETYPE_GROUP"] = "Party/Raid Frames"
L["FRAMETYPE_PET"] = "Pet Frame"
L["FRAMETYPE_PLAYER"] = "Player Frame"
L["FRAMETYPE_TARGET"] = "Target And Focus"
L["FRAMETYPE_UNKNOWN"] = "Others"
L["GENERAL"] = "General"
-- 목록 위의 체크박스. 묶어도 줄 순서는 이름순이라는 것과, 진짜 발동 순서는 어디서
-- 보는지를 툴팁이 대신 말한다 - 그걸 말할 자리가 여기밖에 없다(InitializeButtons 참고).
-- 축은 비교자와 **같은 수, 같은 차례**로 적는다(Ordering.lua의 CompareActionOrder).
-- 한때 hover가 빠져 있었는데, 그건 중요도 바로 다음에 오는 축이고 이 애드온에서 제일
-- 자주 순서를 가르는 것이기도 하다. 어디서 보는지는 **화면에 있는 그대로** 적는다 -
-- 한때 "Key & Order 탭"이었고 그 탭이 없어졌다. 없는 것을 부르면 찾다가 못 찾는다.
L["GROUP_NONE"] = "When not in a group";
L["GROUP_PARTY"] = "When in a party";
L["GROUP_RAID"] = "When in a raid";
-- The last line on a spec tab that is not the one being played. The line above it states the
-- layer's precedence in the present tense, which is not true while the layer is out of play; this
-- says when it starts being true.
--
-- **No verb for entering the spec.** "Switch to it" and the like read equally well as "click this
-- tab" -- which is what the reader's cursor is on and what they are about to do -- and that
-- reading is false, since clicking does not make the layer apply. A state ("when you're in this
-- spec") cannot be read the second way.
L["INACTIVE_SPEC_DESC"] = "Keys you put here start working when you're in this spec."
L["INACTIVE_SPEC_LABEL"] = "%s (Inactive)"
-- **Named for what it does to the action, beside Delete, which is the other way to stop one.** What
-- turning off keeps is said in the help instead (`HELP_STOPPING_AN_ACTION_BODY`): a checkbox already
-- promises the way back, and the tooltip's one job is the key, which several actions can share.
L["ACTION_DISABLED"] = "Turn this action off"
L["ACTION_DISABLED_DESC"] = "The action stops running. The key goes to the next action on it, and when every action on it is off, back to whatever WoW has bound to it."
L["KEY"] = "Key"
--- The dialog that asks for one key, for one action or one set of them (`KeyCapture.lua`).
---
--- **The title is the instruction**, which is what the other three dialogs in this window do -
--- "Bring in - %s", "Paste a Debind string", `EXPORT_COPY_TITLE`. Each of them names the act the
--- reader came to perform. `KEY_BINDING` stood here first and was the odd one out: the client's word
--- for the settings *category*, a noun where the neighbours are all verbs, saying nothing about what
--- pressing something now would do.
---
--- **And it does not name the target**, because the dialog shows it - the actions about to get the
--- key are listed under this line with their icons, the way every other list in the addon draws an
--- action. Saying "for Wrath +2" in a sentence was the version that had to stand in for showing
--- them.
L["KEY_CAPTURE_TITLE"] = "Assign a key"
--- **The middle clause is the one that earns its place.** That mouse buttons and the wheel are keys
--- here is where this addon parts company with the game's own keybinding panel, which will not take
--- them - so a reader who knows that panel does not try, and nothing else on screen says otherwise.
---
--- The last clause is the rule that cannot be guessed at all: those are read where they land, and
--- landing anywhere else does whatever it always does. The keyboard has no such condition and the
--- line does not raise one - saying it works anywhere only made the reader wonder why it was worth
--- mentioning.
L["KEY_CAPTURE_DESC"] = "Press any key to assign it - mouse buttons and the wheel included, but those only count over this window."
--- The key the set is on today, said once over the whole list. **A label, not a sentence**, because
--- what follows it is the value - which is also what [Unbind key] is talking about, so the button
--- being lit or dead has something on screen to point at.
L["KEY_CAPTURE_CURRENT_KEY"] = "Current key:"
--- What the line above says when the actions being asked about are **not all on the same key**. It
--- is the state a hand-made selection can be in and a key group never is, so it arrived with this
--- window being opened on more than a key group.
---
--- **Not the first one's key.** The rows are listed right underneath, so naming one of several keys
--- is the window contradicting itself in the space of two lines.
---
--- Deliberately not a count. "3 keys" invites the reader to work out which three, and the answer to
--- that is the list below - what this line has to say is only that there is no single answer.
L["KEY_CAPTURE_CURRENT_KEY_MIXED"] = "More than one"
--- The caption over the list. **It reads for one action and for twelve** - a set on one key is the
--- ordinary case here, so "this action" would be wrong more often than not.
L["KEY_CAPTURE_TARGETS"] = "Applies to these actions:"
--- Only when the set is longer than the dialog will draw. **The cap is what this is for**: a key
--- group has no ceiling the addon can name, and a dialog that grows with it walks off the screen.
--- Everything counted here is still getting the key - the line says what is not being drawn, not
--- what is being left out.
L["KEY_CAPTURE_MORE"] = "...and %d more"
--- A row's right-click item. **Same three words as the heading's** (`KEY_HEADER_SET_KEY`), because
--- the act is the same one and the same dialog opens; what differs is how much of the column it
--- reaches, and that is said by where the reader clicked and by the tooltip below. Two keys and not
--- one, so the two tooltips can never be made to share a sentence they only half fit.
L["ACTION_SET_KEY"] = "Assign a key"
-- The same item on a row that arrived and has not been accepted. **Giving one a key accepts it**
-- (`DebindFrameMixin:SetActionKey`), which the reader had no way of knowing before pressing.
--
-- **The three words stay, and a clause goes after them** (2026-08-23, 소유자). They are the act's
-- name at every scope it is offered at, so replacing them here would make this look like a
-- different operation; what is added is the half that is true only on this row.
--
-- **`&`, and it is doing a different job from the client's** (2026-08-23, 소유자). The client keeps
-- the ampersand for pairs of nouns ("Dungeons & Raids") and spells the word out on a button that
-- does two things ("Save and Exit"). In a menu the two halves have to be told apart at a glance
-- from the item above, which is the first half on its own - the ampersand is the mark that reads as
-- a join before the words are read at all.
L["ACTION_SET_KEY_ACCEPT"] = "Assign a key & Accept"
--- **The one thing this has to say is what happens to the rest.** A key's actions are told apart by
--- conditions, on purpose - so a row walking off to its own key produces no error, no warning and
--- nothing on screen that looks wrong. The reader finds out later, when two keys each do half of
--- what one key used to do.
---
--- **It is not written as a mistake**, because it is not one: giving one condition its own shortcut
--- is a thing people mean to do. It is written as what happens, and the reader decides.
---
--- **It does not describe the dialog.** The opening line used to say "the key you press", which is
--- wrong twice over - the answer can be a mouse button or the wheel, and it can be [Unbind key],
--- which presses nothing and still takes this action out of the set. How the key is given is the
--- dialog's own line to say (`KEY_CAPTURE_DESC`); this one says who it is given to.
---
--- **One string for two lists, and the conditional is what makes that possible.** It is read from
--- the overview's rows, where the set is drawn under one heading, and from the bin's, where the list
--- is one layer in name order and nothing says a key can carry several actions at all. "If this
--- action is part of a set on one key" carries its own premise, so it introduces the fact for the
--- reader who cannot see it and merely points at it for the reader who can.
---
--- Three earlier wordings assumed the overview and read as a non-sequitur in the bin: "the ones it
--- is listed with" (names the wrong rows there), "only this one moves" (nothing moves there), and
--- opening on "this action alone", which answers a question that list gives nobody a reason to ask.
---
--- It is also right that the clause is conditional rather than flat. Most actions are alone on their
--- key, and announcing what happens to "the others" every time describes a situation the reader is
--- usually not in.
---
--- "Group" is not available for any of it: in this window that word is the party/raid kind
--- (`CONDITION_GROUP`).
L["ACTION_SET_KEY_DESC"] = "Sets the key for this action.|n|nIf this action is part of a set sharing one key, only this action changes - the rest keep the key they are on. Both keys still work; they just stop working as one."
-- The same item on a row that arrived, where the line above is **false**: "both keys still work" is
-- what happens between two sets of the reader's own, and the set this one is leaving is pending - so
-- its key does nothing at all.
--
-- **And the warning does not come back in another form** (2026-08-23, 소유자). It is there above
-- because a set of the reader's own comes apart with nothing to show for it until both halves fire.
-- What is left behind here is drawn in the arrival's blue and is still sitting on screen, so the
-- reader is told by the list rather than by a sentence.
L["ACTION_SET_KEY_ACCEPT_DESC"] = "Sets the key for this action and takes it: it starts working on that key."
--- Asked when the key that was pressed is already carrying something.
---
--- **The count is what this dialog is for.** The walk behind it reaches every layer this character
--- has, so some of what is being counted can be off screen right now - another specialization's, or
--- hidden by the "only what came in" switch. Saying the number before the choice is how that is paid
--- for, the same way "Accept all %d" pays for reaching past the screen.
---
--- **It used to say "counting every specialization of this character", which drew the line in the
--- wrong place.** Those eleven layers are not all this character's: two of them belong to the class
--- and one to the account (`EnumerateAllProfileLayers`), so an action counted here can be one that is
--- on that key for every character the reader has. Naming specializations made the sentence sound
--- like the reach stopped at this character, and the answer beside it takes the key away from
--- whatever is counted - which is where that mattered. It now says what the number is: everything
--- that key does here. Who else that touches is `KEY_GROUP_CONFLICT_SHARED`'s line, and only when
--- there is somebody.
---
--- Numbered placeholders because two of them are strings; the rule is in
--- `writing-user-facing-text.md`.
L["KEY_GROUP_CONFLICT"] = "|cnHIGHLIGHT_FONT_COLOR:%2$s|r already has |cnHIGHLIGHT_FONT_COLOR:%3$d|r actions on it - everything that key does on this character, whichever specialization they belong to.|n|nWhat should happen to them when |cnHIGHLIGHT_FONT_COLOR:%1$s|r moves there?"
--- Added under the question when any of the ones being counted lives in a shared scope.
---
--- **Only then, because most of the time it is not true**, and a dialog that warns about other
--- characters every time teaches the reader to stop reading it. The test is the layer's own
--- `isCharacterSpecific`, the same one the importance menu asks before it warns
--- (`IMPORTANCE_SHARED_WARNING`).
---
--- **It does not name the button.** Spelling out what [Overwrite] says leaves this sentence pointing
--- at something that is not there the day that word changes, and a line here has already died that
--- way. "Taking the key from them" is the same act named by what it does.
L["KEY_GROUP_CONFLICT_SHARED"] = "Some of them are your other characters' as well - they are on that key there too, and taking the key from them takes it everywhere."
--- **Not a compromise, and not a warning.** Several actions on one key, told apart by conditions, is
--- what this addon is for - so the answer that puts the two sets on one key needs no caveat.
---
--- **It said "Keep both", and before that "Merge", and it is back to `Merge` because the objection
--- that killed it stopped being true.** That objection was that nothing is combined -- the two sets
--- simply both sat on the key with their conditions telling them apart, because what arrived was
--- parked on a key of its own. It is not parked anywhere now: accepting moves it onto `(key, nil)`,
--- the reader's own group, and `RenumberKeyGroup` ranks the two as **one** group, 1..n
--- (`building-export-import.md` 12절). Combining is exactly what happens.
---
--- The other half of that objection was that the client does not use the word. That test answers
--- "is there a word here to reuse", and it was being read as "would a reader know this one" -- which
--- it does not answer at all. Somebody who plays this game has merged a save, a profile and an addon
--- config, and `Merge` costs them nothing to read (2026-08-23, owner).
---
--- **And it says what `Keep both` could not.** "Both" names the outcome and leaves the mechanism to
--- the tooltip; the mechanism is the part the reader has to picture, because from here on the two
--- move as one and the order between them is a thing they own.
L["KEY_GROUP_CONFLICT_KEEP"] = "Merge"
--- On the button, because **the two answers to this question are the two most expensive things in
--- the window** and a word each is not enough for either. One of them takes bindings off keys.
---
--- What this one adds is the part nobody expects: **the order becomes a decision**. A key runs down
--- its list and fires the first action whose conditions match, so two sets landing on one key means
--- the ranking now decides between them - and nobody chose that ranking, it fell out of the two sets
--- having been written at different times.
---
--- That both sides are kept is the label's line and is not repeated here, the same trim "the key you
--- press" got. **Where the order is changed is not named either**: spelling out a tab or a menu is a
--- sentence pointing at something that can be renamed out from under it.
L["KEY_GROUP_CONFLICT_KEEP_DESC"] = "Pressing the key then runs down the list until something matches, so which one goes off depends on the order they land in - and that order is yours to change."
--- **The client's own verb for this, and the reader met it a moment ago** - the game calls taking a
--- key off "unbind" (`UNBIND`), it is what the button on the key capture dialog says, and it names
--- exactly what happens to these: they lose the key and nothing else.
---
--- It said "Overwrite" for a while, which is not a client word either (the one place the game names
--- that idea, `TUTORIAL_PERKS_PROGRAM_OVERWRITE_FROZEN_ITEM`, reads "Replace") and which overstates
--- what happens - it sounds like a delete, and nothing is deleted.
---
--- **This pair was rejected once and is back on purpose.** The objection was that the two buttons
--- answer different questions - this one says what happens to the occupants, its partner describes
--- what the key ends up holding - and that is still true. It was accepted because the pair that
--- replaced it had the same fault ("Merge" is an end state too) while spending two words the client
--- does not use, and because the wording that would have fixed the axis reads as [Cancel] beside a
--- button that unbinds. The mismatch is the cheaper fault; `building-export-import.md` has the line.
L["KEY_GROUP_CONFLICT_UNBIND"] = "Unbind them"
--- Two things the label cannot say: **how far it reaches** and **what it does not do.**
---
--- The reach, because the count above is every layer this character has and some of those rows are
--- not on screen - another specialization's, or filtered out. The reader is answering about things
--- they cannot see, which is the same debt the prompt's number is paying.
---
--- And **what it cannot put back.** Nothing is deleted, and each of them can be given a key again --
--- but they stop being one set, and which ones belonged together is not written down anywhere. The
--- half-sentence this used to be read as "you can undo this", which is false for the part that
--- matters. Saying it here rather than in the label keeps the button one act long.
L["KEY_GROUP_CONFLICT_UNBIND_DESC"] = "All of them, not just the ones you can see - the count above is every layer this character has. Nothing is deleted: each one ends up with no key at the bottom of the list, where you can give it one again. They stop being one set, though, and nothing records which ones went together."
--- The heading's item. **The words are `ACTION_SET_KEY`'s** - the act is the same and the same
--- dialog opens - and how much of the column it reaches is left to the tooltip.
---
--- **The scope is not in the label, and the reason is width.** "Everything under this" was tried
--- here and the menu came out wider than the bar it hangs off: a context menu takes the width of its
--- longest line, and this menu has two lines and no third to hide behind. What pays for the short
--- label is **the position and the title above it** - the reader right-clicked the set's own bar,
--- and the title names that set by what is in it.
---
--- **The act is named the way the window it opens names itself** (`KEY_CAPTURE_TITLE`). The press
--- lands in that dialog, so a reader who takes the item and a reader who reads the title are being
--- told the same thing. Separate keys on purpose - if that dialog is ever renamed, whether this
--- follows is a decision, not a rename that happens to it.
--- The heading's tooltip, and the only line in it. **It exists because the gesture it names is the
--- one thing on this bar that nothing points at**, and since the row menu stopped offering the set's
--- own items there is no other way in to them.
---
--- **Folding is not mentioned, and that is the rule rather than an omission.** Not knowing it costs
--- the reader nothing: the column opens expanded, so a fold they never discover leaves every action
--- and every operation reachable. Not knowing the right-click costs them the whole menu. The bar's
--- end cap is Blizzard's own collapse art besides, so the visible half teaches itself.
---
--- "under this heading" rather than "on this key", because a set can be sitting on no key at all and
--- the heading still stands over it - and because that is the phrase the item's own tooltip uses
--- (`KEY_HEADER_SET_KEY_DESC`). One set, one way of naming it per screen.
L["KEY_HEADER_TOOLTIP_INSTRUCTION"] = "Right-click for what can be done to everything under this heading."
--- What the greyed key name in the column means, said once for the whole group. **The outcome and
--- not the cause**: a group is grey because every action in it is turned off, because they all
--- belong to a specialization you are not in, or because it is the key that opens the game menu,
--- and the causes can be mixed in one group. Each row says its own (`LINE_TOOLTIP_NOT_RUNNING_DISABLED`,
--- `LINE_TOOLTIP_SPEC_INACTIVE`) and the mark says the game menu one. All three do the same thing
--- to the key, which is what this sentence is about.
---
--- **A group that is only broken is not grey and does not get this line.** The key is still ours
--- and does not go anywhere; that nothing comes out of it is the mark's to say.
---
--- **"whatever WoW has bound to it" is the phrase the switch that causes this already uses**
--- (`ACTION_DISABLED_DESC`). One thing, one wording per screen.
L["KEY_HEADER_TOOLTIP_KEY_LEFT_TO_GAME"] = "Nothing here is running, so this key is left to whatever WoW has bound to it."
--- The same slot for an arrival group. **"reaches no key until you accept it" is
--- `LINE_TOOLTIP_IMPORTED`'s own wording**, for the same reason.
---
--- It is said instead of the line above and never beside it: an arrival sitting on a key the reader
--- already uses reaches no key while that key is very much still theirs, and a sentence about where
--- the key goes would be answering about somebody else's group.
L["KEY_HEADER_TOOLTIP_NOT_ACCEPTED"] = "Nothing here has been accepted yet, so it reaches no key."
L["KEY_HEADER_SET_KEY"] = "Assign a key"
--- The heading's import items.
---
--- **A heading stands over rows nobody picked**, and what is waiting under it can be five scattered
--- through twelve that are already the reader's - so the item has to say what it is about to gather.
--- Where the reader chose the target by hand the count is theirs already and the plain label reads
--- better, which is why the row and bulk menus keep `APPROVE_IMPORT` / `REJECT_IMPORT`.
---
--- **It names the state and does not point.** "Accept these 5" was written first and contradicts
--- itself over a heading with twelve rows under it: "these" claims the rows, the number is a
--- fraction of them, and the label cannot say which fraction. "Still waiting" is the subset itself,
--- and it is the phrase this screen already uses for it (`APPROVE_ALL_IMPORT_DESC`).
---
--- **Not the strip's "Accept all %d".** That one reaches the whole profile, and "all" is exactly the
--- word that would make this promise more than it does: these take what is drawn under this one
--- heading and nothing else.
---
--- **A singular of its own**, because "the 1 still waiting" is not English and falling back to the
--- bare `APPROVE_IMPORT` would put the pointing problem back - over twelve rows, a label with no
--- count in it reads as all of them.
L["KEY_HEADER_APPROVE"] = "Accept the %d still waiting"
L["KEY_HEADER_APPROVE_ONE"] = "Accept the one still waiting"
L["KEY_HEADER_REJECT"] = "Reject the %d still waiting"
L["KEY_HEADER_REJECT_ONE"] = "Reject the one still waiting"
--- The other end of the axis, over the same set. **The words are `UNBIND`'s**, for the reason the
--- item above shares its words with the row's: the act is the same, only the reach differs, and the
--- reach is the tooltip's to carry.
---
--- **The scope is not "this group".** `Group` is this window's word for a party or a raid
--- (`CONDITION_GROUP`, `UNITGROUP_NONE`), and a set sharing one key is not a thing the profile keeps
--- either (`building-export-import.md` 12절). "under this heading" is what the item above
--- says and is what this screen has to name it by.
---
--- **The set coming apart is not said here.** `UNBIND_SCATTERS_CONFIRM` stands in front of the press
--- with the number it actually found, and a tooltip written once cannot name that number.
L["KEY_HEADER_UNBIND"] = "Unbind key"
L["KEY_HEADER_UNBIND_DESC"] = "Takes the key off every action under this heading, in one go. That includes any in specializations you are not in."
--- **This is where the label's missing half went, so the first line has to carry it**: one key, the
--- whole set, at once.
---
--- **The tail is the part the reader cannot check** (2026-08-23, 소유자). It read "folded or not, and
--- however many of them there are", which answers a hazard nobody has: a folded heading is still
--- that heading, and the count is not a danger. What is actually out of sight is that the set is
--- collected from every layer this character has, so a specialization they are not in changes too.
---
--- No warning about the set coming apart, which is the row tooltip's job. From here there is no one
--- row on offer - the heading cannot pick one out - so the sentence would be describing something
--- this menu cannot do.
---
--- **That it accepts what is waiting is the arrival's line, not this one.** Deciding a key is that
--- decision and the badge comes off with it (`SetKeyForActions`), but **this item is on every
--- heading** - saying it here teaches a vocabulary to everyone who has never taken a string from
--- anybody. The heading that arrived has a string of its own, and a label that says it out loud.
---
--- It said "the key you press" too, and that is wrong here for the reasons it was wrong there: the
--- answer can be a mouse button or the wheel, and [Unbind key] presses nothing and still settles
--- the whole set. How the key arrives is `KEY_CAPTURE_DESC`'s line.
L["KEY_HEADER_SET_KEY_DESC"] = "Sets one key for every action under this heading, in one go - including any in specializations you are not in."
-- The same item over a heading that arrived. **Nothing is left behind here**, which is the one way
-- it differs from the row's: the press takes the whole set, so there is no half still pending to
-- warn about. The reach is still what the label cannot say.
L["KEY_HEADER_SET_KEY_ACCEPT_DESC"] = "Sets one key for every action under this heading and takes them all, in one go - including any in specializations you are not in."
L["LIFE_ALIVE"] = "Alive"
L["LIFE_DEAD"] = "Dead"
L["UNITGROUP_NONE"] = "Not in my group"
L["UNITGROUP_PARTY"] = "In my party"
L["UNITGROUP_RAID"] = "In my raid"
L["LINE_TOOLTIP_CONDITION_LABEL"] = "%s:"
-- Under the issue mark's title, which is the grade in words (`ORDER_FLAG_ISSUE*`). **The title says
-- what the grade is called and this says what it costs the reader**, which is the thing a name
-- alone cannot carry. It says the action does not work rather than that it is ignored: a saved
-- retired type is red and still holds its place on the key, doing nothing there.
L["MARK_TOOLTIP_ISSUE_DESC"] = "This action does not work until the problem is fixed."
-- The conditional mark's tooltip. **It says a condition exists and never which one** -- the row's
-- own tooltip draws every condition with its value, and repeating one of them here would put the
-- same setting on screen twice with nothing saying which is the whole list.
L["MARK_TOOLTIP_CONDITIONAL"] = "Runs only while the conditions set on it hold."
-- The other grade. **The action runs**, so what this has to say is that one part of it does not,
-- said as the action still running, because a reader who arrived at a red-looking mark needs to know
-- first that nothing is dead.
L["MARK_TOOLTIP_ISSUE_DESC_WARNING"] = "This action still runs, but one thing it was told to do does not."
-- Sits directly under the key line, because the key is what it qualifies: that line says which key
-- it has, this one says that key does nothing yet.
--
-- **It is the only thing in the tooltip that says so.** The title used to carry the badge as a
-- colour and no longer does, so if this sentence goes the tooltip stops mentioning it at all.
--
-- No source and no date, though the action carries the key it arrived on. Reading either of those means
-- reading `DebindStorage`'s saved variables, and that addon is load-on-demand - a tooltip that says
-- where a string came from only after some other window has been opened is worse than one that
-- never claims to.
L["LINE_TOOLTIP_IMPORTED"] = "Came in from a string. It reaches no key until you accept it."
-- 한때 "and set its key"가 붙어 있었다. 그 시절에는 행을 고르면 왼쪽 열이 그 액션의 상세
-- 패널이 되고 거기서 키를 걸었다. 지금 왼쪽 열은 키보드 사영이라 보여주기만 하고, 키는
-- 목록 위의 [키 지정] 모드에서 건다 - 좌클릭은 고르는 것이 전부다.
--
-- 그 모드를 여기서 가리키지 않는 이유는, 가리키려면 버튼 글자(BIND_MODE)를 이 문장에
-- 복사해 넣어야 하고 그러면 버튼 이름을 바꾸는 날 이 줄이 없는 버튼을 가리키게 되기
-- 때문이다. 방금 죽은 문장이 정확히 그렇게 죽었다.
--
-- 수식어는 **한 줄로 붙여 둔다.** 따로 세우면 안내 줄이 셋이 되는데, 저것은 이 줄이 말한
-- 좌클릭의 뒷말이지 다른 조작이 아니다. 좌클릭 줄이 짧아져서 자리도 났다.
--
-- **이 줄이 다중 선택을 알리는 유일한 자리다.** 한때 같은 말을 하는 도움말 풍선
-- (TIP_MULTI_SELECT)이 통 아래에 떴는데, 이 줄이 그 말을 하게 된 뒤로는 묻지도 않은 사람을
-- 한 번 붙잡는 값이 남지 않아 풍선 쪽을 지웠다. 그러니 이 문장에서 수식어를 덜어내면
-- CTRL/SHIFT-클릭을 알리는 곳이 UI에 하나도 없어진다.
L["LINE_TOOLTIP_INSTRUCTION_MESSAGE1"] = "Left click to select this action. Hold CTRL or SHIFT while clicking to select more than one."
-- 지정 모드 중에 이 행을 가리키면 위아래 두 줄 대신 이것만 뜬다(`DebindLineMixin:OnEnter`).
-- **BIND_MODE_OVERLAY와 다른 말이어야 한다.** 저쪽은 "오른쪽에서 행동을 가리키라"고 하는데,
-- 이 줄을 읽는 사람은 이미 가리키는 중이라 그 문장이 할 일이 없다. 남은 물음은 하나다.
L["LINE_TOOLTIP_INSTRUCTION_BIND"] = "Press any key or mouse button to give it to this action."
L["LINE_TOOLTIP_INSTRUCTION_MESSAGE2"] = "Right click for more options."
-- The value the line above pushes aside, where the reader chose no target of their own. It names
-- the rule and not an outcome: the game answers this with the current target for one action and
-- with the player for another under auto self cast, and naming one makes the other a lie.
L["LINE_TOOLTIP_TARGET_NORMAL"] = "Where it normally goes"
-- Under the numbers, the way the unreachable line sits under the key: the action is set up right
-- and this says only that the world is not the one it asked for.
L["LINE_TOOLTIP_SPEC_INACTIVE"] = "You are on a different specialization, so it does not run."
-- **The two lines the talent condition needs beyond naming talents.** A talent set on another
-- class or specialization does nothing here and has no row in the menu, so without these the
-- action reads as carrying less than it does.
--
-- **Each is a sentence about the action**, not a value: written as a value under the talent lines,
-- it read as that talent being taken over there (2026-09-19, owner).
L["LINE_TOOLTIP_TALENT_ALSO_OTHERS"] = "Other classes and specializations have talents of their own set."
L["LINE_TOOLTIP_TALENT_ONLY_OTHERS"] = "Talents are set on other classes and specializations only, so none of them apply here."
-- Under the Cast Options lines, the way the line above sits under the specialization numbers. **Not
-- an issue**: the reader asked for this, so it says why the action does not run and nothing asks
-- them to change it.
L["LINE_TOOLTIP_NOT_RUNNING_DISABLED"] = "This action is turned off."
-- What fits named, and the rest left unnamed. **"and others" rather than "and 3 more"**: what the
-- line names is specializations of this character's class and whole classes otherwise, so a number
-- after it would be counting two different things at once. The client says it the same way where
-- it has its own label baked in (`BOSS_INFO_STRING_MANY`, "Boss: %s and others").
L["LINE_TOOLTIP_SPEC_OVERFLOW"] = "%s and others"
L["LOGIN_MESSAGE"] = "Run the /deb slash command to open the UI."
-- %d는 MACRO_NAME_CHAR_LIMIT다. 한때 32가 글자로 박혀 있었는데, 호출부는 그때도 한계값을
-- 넘기고 있었다(DebindUI.lua의 OpenForAction) - 받을 자리가 없어서 조용히 버려졌을 뿐이다.
-- 세로 탭(사이드탭) 툴팁의 설명 줄. 다섯 레이어에 하나씩이고, 세 마디로 고정한다:
-- **누가 쓰는가**, **무엇보다 우선하는가**, 그리고 **언제 그 말이 안 맞는가.**
--
-- 셋째 마디를 빼면 **거짓말이 된다.** 레이어는 실행 순서의 네 번째 축이라(IMPORTANCE_DESC:
-- 중요도 → 마우스 올림 → 조건 → 탭 → 순서), 조건이 붙은 공유/일반 액션은 조건 없는
-- 공유/야성 액션보다 먼저 실행된다. 중요도를 건드렸으면 더 그렇다. 툴팁은 일부러 불러서
-- 읽는 글이라 이 길이가 부담이 아니고, 탭마다 반복돼도 한 번에 하나만 보인다.
--
-- **마우스 올림은 절에 안 적는다.** 그것도 탭을 이기는 축이 맞지만, 그 액션을 만든 사람은
-- 자기가 만든 줄 알고 있다 - 조건과 중요도처럼 나중에 잊고 부딪히는 것이 아니다. 넷을 다
-- 적으면 절이 문장보다 길어진다. 전부 알고 싶은 사람은 IMPORTANCE_DESC가 다섯 축을 순서대로
-- 적어 둔다.
--
-- 지는 쪽은 **레이어 이름 전체**로 부른다("Account / Druid"). 툴팁 제목이 그 형식이라 참조도
-- 같아야 화면에서 찾을 수 있다 - 근거는 GetSideTabDescription 주석에.
--
-- 영어는 README의 Layers 표 오른쪽 열과 **같은 말**로 적는다. 표를 읽고 온 사람과 툴팁만
-- 보는 사람이 같은 문장을 읽어야 둘이 같은 것이라는 걸 안다.
L["LAYER_DESC_SHARED_GENERAL"] = "Every character on the account."
-- %s 둘은 차례로 직업명(UnitClass), 지는 레이어의 이름.
L["LAYER_DESC_SHARED_CLASS"] = "Every %1$s you own. A key here beats the same key in %2$s, unless conditions or Importance say otherwise."
-- %s 셋은 차례로 직업명, 전문화명, 지는 레이어의 이름.
L["LAYER_DESC_SHARED_SPEC"] = "Every %1$s you own, while %2$s. A key here beats the same key in %3$s, unless conditions or Importance say otherwise."
-- 여기만 지는 쪽이 레이어 하나가 아니라 공유 셋 전부라, 아래 탭 이름을 그대로 쓴다.
L["LAYER_DESC_CHARACTER_GENERAL"] = "This character. A key here beats the same key everywhere in Account, unless conditions or Importance say otherwise."
-- **This is the narrowest layer, so it beats every other one** -- not the one directly below it.
-- Naming a single loser here was wrong, and naming all four would be a list nobody reads, so it
-- says "everywhere else", the same move `LAYER_DESC_CHARACTER_GENERAL` makes with "in Account".
--
-- That leaves English with no argument at all: the tooltip title already reads "Oreo / Balance",
-- so "this spec" has something to point at. Korean still needs the spec name and takes it as the
-- only `%s`. The two locales therefore disagree on format specifiers, which check-locales knows
-- about through EXTRA_SPECS_OK.
L["LAYER_DESC_CHARACTER_SPEC"] = "This character, in this spec. A key here beats the same key everywhere else, unless conditions or Importance say otherwise."
-- 남의 문자열에서 온 레이어의 캐릭터 자리. 이름이 없어서() 낱말로 대신한다.
L["LAYER_SHORT_CHARACTER"] = "Character"
L["MACRO_POPUP_TEXT"] = "Enter Macro Name (Max %d Characters):"
-- 둘째 %d는 MACRO_CHAR_LIMIT다. 위와 같은 이유로 1000이 박혀 있었다.
L["MACROFRAME_CHAR_LIMIT"] = "%1$d/%2$d Characters Used"
-- The tooltip on the same button when it reads REVERT, which happens only on an action the
-- conversion menu item just made. The label alone would be read as "undo my typing", and this
-- button is bigger than that: the action goes back to what it was and the body goes with it. The
-- second sentence is the one that has to be there, since nothing on screen shows that cost.
L["MACROFRAME_REVERT_DESC"] = "Puts this action back to what it was before it became a Custom Macro. Anything typed here is lost."
L["MOVE_TO"] = "Move to..."
-- Tooltip on the greyed-out row for the layer the action is already in. One action and several get
-- the same sentence, so it names no subject.
L["MOVE_TO_CURRENT_LAYER_BLOCKED"] = "Already on this layer."
L["NO_ACTIONS_IN_THIS_LAYER"] = "There are no actions in this layer. You can add a new action by dragging a spell, a macro, an item, or a mount here."
-- 검색 결과가 없을 때. 위와 갈라 쓴다 - 저쪽은 "끌어다 놓으세요"라고 시키는데, 검색에 안
-- 맞아서 빈 것뿐이면 할 일이 그게 아니다.
L["NO_SEARCH_RESULTS"] = "Nothing here matches your search."
L["NO_SHAPESHIFT"] = "No Shapeshift"
L["NO_SPECIALIZATION"] = "None chosen"

--- The main window's title bar, and **only while the fight is on**. Being on screen is what says
--- "in combat", so the sentence does not say it again -- unlike the line above, which is a standing
--- rule shown whatever the state.
L["CHANGES_APPLY_AFTER_COMBAT"] = "Changes take effect when combat ends."
-- What the overview's reason column says instead of an ordering sentence when the row has something
-- wrong with it. **Two words for the whole set of problems, one per grade** -- red for a row that is
-- waiting on the reader, grey for one that is merely outranked.
--
-- There was a short line per `BINDING_ISSUE_*` code here once ("No group selected", "Unknown state
-- name") and they were dropped, which is worth knowing because the reasoning ran the other way at
-- the time. This column is scanned, not read: its own subject is which row beat the one below it,
-- and a problem pitched several levels finer made one slot talk at two resolutions. **The detail was
-- not lost, it was gathered** -- `BINDING_ERROR_*` says it in full, under the very condition it is
-- about, on the surface the reader opens on purpose.
L["ORDER_FLAG_ISSUE"] = "Needs fixing"
-- The other half of the line above, for the grade where the key works and one thing it was told to
-- do does not. **The two share their first word on purpose**: this column is scanned rather than
-- read, and a pair that differs in one place can be told apart with one of them on screen. Before,
-- both grades printed the line above and only the colour parted them, which needs both at once and
-- reaches a colour-blind reader not at all.
L["ORDER_FLAG_ISSUE_WARNING"] = "Needs checking"
L["ORDER_FLAG_UNREACHABLE"] = "Never runs"
-- **The row stands where it would stand if that specialization were the active one**, so this line
-- is the only thing on screen telling it apart from what is running right now. Which one it is comes
-- from the row tooltip, which names the layer; this slot is a few words wide and what has to fit in
-- it is that the row is not in play.
--
-- **The client's word, not ours.** A specialization is made current with `TALENT_SPEC_ACTIVATE`
-- ("Activate"), so the state is active / inactive - and `FACTION_INACTIVE` is where the other half
-- of the pair is already spelled. "Other specialization" was ours and said the wrong thing besides:
-- it reads as "some specialization elsewhere" when what matters is that this one is switched off.
L["ORDER_FLAG_OFFSPEC"] = "Inactive specialization"
-- **No specialization is named, on purpose.** Some classes have no such spell in any of their
-- specializations (a Restoration shaman and the external), and naming one would promise a
-- specialization that does not exist.
--
-- The tooltip is where the reader learns which spell is missing: `LINE_TOOLTIP_SPEC_SPELL_NONE`
-- already stands at the top of it.
L["ORDER_FLAG_NO_SPELL"] = "No spell"
-- %s는 그 액션이 사는 레이어의 라벨(ORDER_LAYER_LABEL)이다.
L["ORDER_LAYER_LABEL"] = "%1$s / %2$s"
L["ORDER_GOTO_ACTION"] = "Go to it in %s"
-- 우클릭 줄은 오른쪽 목록의 것을 그대로 쓴다(LINE_TOOLTIP_INSTRUCTION_MESSAGE2). 두 목록 다
-- 그 액션의 메뉴가 열리므로 여기만 다른 말을 쓸 이유가 없다.
L["ORDER_LINE_TOOLTIP_INSTRUCTION_GOTO"] = "Left click to go to this action. Hold CTRL or SHIFT while clicking to select more than one."
L["OTHER_OPTIONS"] = "Other Options"
L["PET"] = "Pet"
L["IMPORTANCE_DESC"] = "The same key can be assigned to more than one action. When you press it, Debind tries them in order and runs the first one whose conditions are met. Only one of them ever runs.|n|nImportance is compared first, so it beats everything below it. Between actions that are equally important, the order is decided by:|n|n1. Conditions. An action with conditions is tried before one without.|n2. Tab. The more specific tab is tried first, from this character and specialization down to Account.|n3. Order. When everything above is equal, the action you bound to the key first is tried first. That is also the only step you can move an action within."
-- 끝의 이유절에 **주어를 세웠다.** 원래는 "their own bindings are not loaded this session"이라
-- 누가 안 불러왔는지가 없었는데, 3.1 전까지는 읽을 갈래가 하나뿐이라 그래도 됐다 - 캐릭터
-- 전용 지정이 진짜 캐릭터별 SavedVariables(`DebounceVarsPerChar`)에 있어서, 그 캐릭터로
-- 접속하지 않은 세션에는 **디스크에서 올라오지도 않았다.**
--
-- 3.1이 그걸 계정 파일 하나로 접었다(`DebindVars.characters[guid]`). 이제 부캐 지정도 로그인
-- 때 통째로 메모리에 올라오고 세션 내내 거기 있다 - `CleanUpDB`도 지금 guid 한 칸만 만진다.
-- 안 하는 것은 그걸 `LayerArray`로 짓는 일뿐이다(`Profile.lua`의 `InitDB`).
--
-- 그래서 주어 없는 원문이 **"우리가 안 읽었다"로 읽으면 참, "파일에서 안 올라왔다"로 읽으면
-- 거짓**이 됐다. 문장이 스스로 어느 쪽인지 못 정한다. 하필 이 줄은 계정 전체를 바꾼다는
-- 경고에 붙어서 "숨기는 게 아니라 여기 없는 것"이라는 안심을 맡고 있는데, 계정 파일 하나에
-- 부캐 지정이 다 들어 있는 것을 나중에 본 사람에게 그 안심은 얼버무린 것이 된다.
--
-- 낱말은 그대로 "load"를 쓴다. 갈라진 것은 낱말이 아니라 빠진 주어였다.
L["IMPORTANCE_SHARED_WARNING"] = "This action lives in the Account tab, so its importance does too: it changes the order this action is tried on EVERY key it is bound to, on EVERY character of this account. What happens on your other characters cannot be shown here -- Debind only loads the bindings of the character you are on."
L["OVERVIEW"] = "Overview"
-- 이름표에 매달린 툴팁. 열 이름이 한 낱말이라 이 열의 규칙을 말할 자리가 여기밖에 없다.
--
-- **"the keyboard you are playing with"라고 쓰지 말 것.** 설계 메모의 말버릇이지 플레이어의
-- 말이 아니다 - 저쪽에게 keyboard는 책상 위의 물건이라, 이 창이 그걸 보여준다는 소리가 된다.
--
-- **"여기 있는 것은 지금 누르면 실제로 일어날 일"이 두 번 무너졌다.** 처음은 격리였다 - 꺼진
-- 채로 들어온 것이 목록에 있고 키도 있는데 눌러도 아무 일이 없다. 두 번째가 오프스펙이다.
-- 그래서 그 약속은 이제 문장에 없고, 대신 **자리가 무엇을 뜻하는지**를 말한다: 다른 전문화의
-- 행동은 그 전문화였다면 섰을 자리에 서고, 지금 안 돈다는 것은 옆 칸이 말한다. 약속을 지킬 수
-- 없게 됐을 때 문장을 안 고치면 읽는 사람은 그것을 고장으로 읽는다.
L["OVERVIEW_DESC"] = "Everything in this character's bindings, grouped by the key it is on. Within a key, they are listed in the order Debind tries them.|n|nActions on an inactive specialization are listed too, in the place they would take if that specialization were active. The line beside them says so, and they reach no key until you activate it. Opening another tab on the right does not change what is listed here.|n|nActions with no key are gathered at the end: what came in from a string keeps the set it arrived in, and everything else is one pile in name order. Anything still waiting to be accepted is listed as well, and reaches no key until you say so."
-- The two balloons on Overview's help plate, one per column.
--
-- **Not `OVERVIEW_DESC` split in two.** That one hangs off the tab and answers "what is this tab",
-- so it has to cover the whole of it: off spec actions, what came in from a string, where the
-- keyless ones went. These two answer a different question, asked with the plate already up and
-- both columns lit: which of the two am I looking at, and what do I do to it. A reader who is
-- looking at the plate can see the lists; what they cannot see is that one side is the sum and the
-- other is where you put things.
--
-- **The left one may not promise that this is what pressing the key does**, for the two reasons the
-- `OVERVIEW_DESC` comment above records: an action that came in switched off, and one on another
-- specialization. Both are listed, both hold a key, and neither fires. It said so for a while.
--
-- Each one says the other side's name, because the pair is one sentence about cause and effect: you
-- drop on the right and it appears on the left. That is the reason the window is two columns at all
-- (`DebindUI.xml`, `LayerPanel`), and the plate is the only place it is ever said.
L["OVERVIEW_HELP_RESULT"] = "Every key this character has, and everything on it. Actions from all the layers arrive here together, grouped by the key they are on, in the order Debind tries them.|n|nNothing is put in from this side. It is what the layers on the right add up to."
L["OVERVIEW_HELP_LAYER"] = "One layer at a time, and what is in it. The tabs underneath and the ones down the side of the window pick which layer.|n|nDrag a spell, a macro, an item or a mount in here to add it, and it shows up on the left."
-- 결과 목록에서 한 행이 **바로 아래 행을 이긴 이유**. 순서를 가르는 축은 넷인데 비교자가
-- 위에서부터 훑으므로 처음 갈린 하나가 곧 답이다 - 그래서 다섯 중 언제나 하나만 나온다.
-- 칸 끝에 붙는 회색 한 줄이라 짧아야 한다. 주어는 그 행 자신이다.
-- 순서 이동 버튼. 3.0에서 그대로 돌아온 문자열이다 - 규칙이 안 바뀌었으므로 말도 안 바꾼다.
-- ORDER_BLOCKED_*는 `ComputeOrderSwap`이 돌려주는 사유 코드와 이름이 맞물려 있다.
-- The button that stands in the arrows' place on a row that came in. **Its being there is the row's
-- way of saying it has not been accepted**, which is why no label says that as well.
--
-- **Not the client's `ACCEPT`**, even though the word matches and taking a client global is usually
-- the right move. That one is for invitations and quests; the rule here is different, and borrowing
-- it would put a third word (수락) beside the two this feature already uses on the same screen -
-- "Accept as mine" in the menu, "Accept all %d" in the strip. One thing, one name per screen.
L["ORDER_ACCEPT"] = "Accept"
-- **The one thing the label cannot say** (2026-08-23, 소유자): the press is the moment the key goes
-- live. It also said "take this one as yours", which is the label again in other words, and that the
-- rest of the arrival stays pending - a thing nobody reads the item as doing, since the menu was
-- opened over one row and its title names that row.
L["ORDER_ACCEPT_DESC"] = "This one starts working on the key it came in on."
-- **The same press on something that arrived with no key** (2026-08-23, 소유자). The line above is
-- false there and false in the way that costs most: it names an outcome the reader then goes looking
-- for. Nothing about the screen changes on this press except that the row stops being pending, so
-- the sentence has to be the part that is still missing.
--
-- The item under it does both halves in one press (`ACTION_SET_KEY_ACCEPT`), which is what a reader
-- who wanted this working wants instead.
L["ORDER_ACCEPT_NO_KEY_DESC"] = "This one came in with no key. Accepting takes it, but it does nothing until you give it one."
L["ORDER_MOVE_UP"] = "Run Sooner"
L["ORDER_MOVE_UP_DESC"] = "Move this action one place earlier on this key."
L["ORDER_MOVE_DOWN"] = "Run Later"
L["ORDER_MOVE_DOWN_DESC"] = "Move this action one place later on this key."
L["ORDER_BLOCKED_ALREADY_FIRST"] = "This action already runs first on this key."
L["ORDER_BLOCKED_ALREADY_LAST"] = "This action already runs last on this key."
-- 아래 넷은 위의 ALREADY_* 둘과 **틀이 다르다.** 저 둘은 그 자체로 막는 이유이고 주어도
-- 제 안에 있다("This action already runs first"). 이 넷은 **두 액션 사이의 관계**라, 한때
-- "They have different importance."처럼 관계만 적어놨었다 - 그런데 이 툴팁은 죽은 버튼 하나에
-- 딸려 뜨고 두 번째 액션을 꺼낸 적이 없다. they가 누구인지 화면 어디에도 없었다.
--
-- 그래서 셋을 한 문장에 담는다: **막혔다는 것**(제목과 설명은 일어날 일을 말하는데 그 일은
-- 안 일어난다), **누구와 누구인지**, 그리고 **무엇이 순서를 정하고 있는지**. 마지막이 이
-- 자리의 값어치다 - UpdateMoveButtons 주석대로 규칙을 가르치는 몇 안 되는 자리다.
--
-- **방향을 안 짚는다.** 위/아래 버튼이 이 문자열을 같이 쓰므로, 위아래를 적으면 방향마다
-- 문자열을 따로 둬야 하고 늘어난 만큼 로케일이 갈라진다. 어느 쪽인지는 누른 화살표가 말한다.
--
-- **뒷절은 규칙이지 비교 절차가 아니다.** 넷 다 "...is compared before the order on this key"로
-- 끝났었는데, 사다리가 있다는 것 자체가 읽는 사람에게 없는 개념이라 그 문장은 물음에 답을
-- 안 하고 우리가 무엇을 먼저 비교하는지만 말했다. 사다리 전체는 IMPORTANCE_DESC가 다섯
-- 단계로 가르치고 같은 화면에서 닿는다.
--
-- **어느 것도 절대화하지 않는다.** IMPORTANCE 아래 셋은 전부 위에 다른 축이 있어서 "always"가
-- 거짓이 된다. 제 축의 규칙만 말하고 멈춘다.
L["ORDER_BLOCKED_CONDITIONAL"] = "This action cannot move past the one next to it -- only one of the two has conditions, and an action with conditions is tried before one without."
-- **layer이고 scope가 아니다.** README가 "Layers, not profiles"로 가르치고 CurseForge 설명도
-- layered bindings라 읽는 사람이 이미 만난 말이다. scope는 덮는다는 뜻을 안 나르고, tab은
-- 누르는 컨트롤 이름이라 Import 탭·Storage 탭과 자리를 다툰다.
--
-- narrower는 README의 "The narrowest layer holding that key wins"에서 온 낱말이다.
L["ORDER_BLOCKED_LAYER"] = "This action cannot move past the one next to it -- they are in different layers, and the narrower layer is tried first."
-- Importance는 메뉴 이름이라 대문자다(L["IMPORTANCE"]). 뒤는 "the higher one"으로 받는다 -
-- **더 중요하다고는 안 한다.** 그건 사용자가 고른 값이지 우리가 매길 것이 아니다.
L["ORDER_BLOCKED_IMPORTANCE"] = "This action cannot move past the one next to it -- they have different Importance, and the higher one is tried first."
-- **Not the shape the rest of this family uses**, and it should not be: the others say why this
-- action cannot pass the one beside it, and this one is not in the running at all. What came in a
-- string reaches no key until it is accepted, so there is no order for it to have a place in.
-- The second sentence is the one `LINE_TOOLTIP_IMPORTED` already says, because it is the same fact
-- and a reader who has met it once should not have to learn it twice.
L["ORDER_BLOCKED_IMPORTED"] = "This action is not in the key's order yet. It came in from a string, and it reaches no key until you accept it."
-- **Not held, just nothing to contend for.** The four above cannot pass because one step
-- splits them, and changing that step lets them; these two are never on one list together, so
-- an order between them settles nothing. That is the grey branch, with no red
-- (BLOCKED_WITH_NOTHING_TO_DO in DebindUI.lua).
--
-- **run이 아니라 active를 쓴다.** 한 키에 걸린 것은 원래 하나만 도니, 안 같이 돈다고 하면
-- 이 짝만의 특징인 것처럼 읽히고 다른 짝은 같이 도는 것이 된다. 같은 행의 사유 칸이 이미
-- ORDER_FLAG_OFFSPEC("Inactive specialization")이라 낱말도 그쪽에 맞춘다.
L["ORDER_BLOCKED_SPEC"] = "This action and the one next to it are never active at the same time, so their order settles nothing."
L["IMPORTANCE"] = "Importance"
L["IMPORTANCE1"] = "Very High"
L["IMPORTANCE2"] = "High"
-- 순서 목록의 모든 행이 이 낱말을 쓰므로 짧아야 한다. 다섯 중 가운데라 메뉴에서도
-- 기본값이라는 게 자리로 읽힌다 - "(Default)"를 뒤에 달던 것을 뗐다.
L["IMPORTANCE3"] = "Normal"
L["IMPORTANCE4"] = "Low"
L["IMPORTANCE5"] = "Very Low"
L["REACTION_ALL"] = "All"
L["REACTION_HARM"] = "Enemy"
L["REACTION_HELP"] = "Friendly"
L["REACTION_OTHER"] = "Others"
-- 순서 목록의 행 툴팁에서 쓰는 이름표. 값은 ORDER_LAYER_LABEL이다.
L["SCOPE"] = "Scope"
L["SHARED_BINDINGS"] = "Account"
L["CONDITIONS"] = "Conditions"
L["SPECIAL_UNIT_SET_MESSAGE"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - Set to %2$s"
L["SPECIAL_UNIT_UNSET_MESSAGE_TOO_MANY"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnDISABLED_FONT_COLOR:Cleared (More than one unit detected)|r"
L["SPECIAL_UNIT_UNSET_MESSAGE"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnDISABLED_FONT_COLOR:Cleared|r"
-- **Names what you are excluded from, because nothing else in the section can** (2026-09-12,
-- owner). The rows are four bare target names, and nothing on screen says `Tank` there is
-- something an action is aimed at.
L["SPECIAL_UNITS"] = "Exclude Self from Role Targets"
-- Title over the right-click menu's list. The list itself is tab names, so this line is what
-- says which question they answer. Shaped like the move and copy menus' "Move to... / Copy to..."
-- on purpose: three menus showing the same list should not each name it differently.
L["SPELL_PICKER_ADD_TO"] = "Add to..."
L["SPELL_PICKER_EMPTY"] = "Nothing here."
L["SPELL_PICKER_GROUP_ACCOUNT_MACROS"] = "Account Macros"
L["SPELL_PICKER_GROUP_CHARACTER_MACROS"] = "Character Macros"
-- The two groups of the Items tab. The first names what the key follows -- the slot, not the item
-- in it today -- because that is the whole difference between the two groups.
--
-- The second is the client's own word for the bags taken together (`INVENTORY_TOOLTIP`, which
-- Korean answers with the same string as `BACKPACK_TOOLTIP`). It was "Carried", coined here for
-- the contrast with wearing something, which is the coinage this file exists to prevent.
L["SPELL_PICKER_GROUP_INVENTORY"] = "Inventory"
L["SPELL_PICKER_GROUP_EQUIPPED"] = "Use Equipped Item"
-- **종류를 이름에 넣는다.** 탈것과 장난감이 한 탭에 살아서, 둘 다 "Favorites"를 달면 같은
-- 머리글이 한 목록에 두 번 서고 두 번째가 첫 번째의 이어짐으로 읽힌다.
L["SPELL_PICKER_GROUP_FAVORITE_MOUNTS"] = "Favorite Mounts"
L["SPELL_PICKER_GROUP_FAVORITE_TOYS"] = "Favorite Toys"
L["SPELL_PICKER_GROUP_MOUNTS"] = "Mounts"
L["SPELL_PICKER_GROUP_OTHERS"] = "Everything Else"
L["SPELL_PICKER_GROUP_TOYS"] = "Toys"
-- 행 툴팁의 안내 줄 둘(이 줄과 SPELL_PICKER_RIGHT_CLICK_TO_ADD). **왼쪽/오른쪽을 부르는 말은
-- 왼쪽 목록 행 툴팁의 것을 그대로 쓴다**("Left click to ..." / "Right click ..." -
-- LINE_TOOLTIP_INSTRUCTION_MESSAGE1/2). 같은 애드온의 두 목록이 같은 조작을 다르게 부르면
-- 다른 조작으로 읽힌다.
--
-- **하이픈은 안 쓴다.** 클라이언트 표기가 두 낱말이다 - GlobalStrings에 "Right Click to Open"
-- 꼴은 있어도 "Left-Click"/"Right-Click"은 한 줄도 없다(wago.tools GlobalStrings 조회).
--
-- %s는 지금 열려 있는 탭의 이름(GetLayerLabel)이다. "현재 탭"이라고만 적지 않는 이유: 창 둘이
-- 나란히 서 있고 탭은 저쪽 창에만 있어서, 이 창의 툴팁이 "현재"라고 말하면 어느 창의 현재인지를
-- 읽는 사람이 눈으로 찾아야 한다. 이름을 적으면 커서가 있는 자리에서 답이 끝난다.
L["SPELL_PICKER_LEFT_CLICK_TO_ADD"] = "Left click to add it to |cnHIGHLIGHT_FONT_COLOR:%s|r."
L["SPELL_PICKER_MENU_DESC"] ="Browse what you already have -- spells, macros, mounts, toys, and the game's own binding commands. The window stays open, and each click adds to whichever tab you have open."
L["SPELL_PICKER_NEW_MACROTEXT"] = "New Custom Macro"
L["SPELL_PICKER_NO_MATCH"] = "Nothing matches your search."
L["SPELL_PICKER_ONLY_FAVORITES"] = "Favorites only"
-- SPELL_PICKER_LEFT_CLICK_TO_ADD의 짝. 오른쪽 클릭이 있다는 것을 말하는 자리가 화면에
-- 여기뿐이다 - 행은 있으나 없으나 같은 모양이다.
L["SPELL_PICKER_RIGHT_CLICK_TO_ADD"] = "Right click to add it to another layer."
-- 바꾸기 중의 안내 줄. 한 줄뿐이라 SPELL_PICKER_RIGHT_CLICK_TO_ADD의 짝이 없다 - 넣을 탭을
-- 고를 일이 없어서 오른쪽 클릭도 할 일이 없다.
L["SPELL_PICKER_LEFT_CLICK_TO_REPLACE"] = "Left click to replace with it."
-- SPELL_PICKER_TITLE과 같은 창의 제목이다. 이 창이 지금 무엇을 하는 중인지를 말하는 자리가
-- 제목 말고는 없어서, 두 모드가 같은 제목을 달면 클릭이 무엇을 할지 알 수 없다.
L["SPELL_PICKER_REPLACE_TITLE"] = "Replace an Action"
-- Same thing the overview's `ORDER_FLAG_OFFSPEC` names, so it has to be the same word: two names
-- for one thing in one window is how a reader ends up thinking there are two things.
L["SPELL_PICKER_SHOW_OFFSPEC"] = "Inactive specializations"
-- The client calls the window that holds mounts, toys, pets and heirlooms Collections
-- (`COLLECTIONS_MICRO_BUTTON_SPEC_TUTORIAL` names those four). Only two of them can carry a
-- key, so the tab takes the word rather than the client's full "Warband Collections".
L["SPELL_PICKER_TAB_COLLECTIBLE"] = "Collections"
L["SPELL_PICKER_TAB_COMMAND"] = "Commands"
L["SPELL_PICKER_TAB_ITEM"] = "Items"
L["SPELL_PICKER_TAB_MACRO"] = "Macros"
L["SPELL_PICKER_TAB_SPECIAL"] = "Special"
L["SPELL_PICKER_TAB_SPELL"] = "Spells"
-- 창 제목이자 그 창을 여는 [+] 버튼의 툴팁 제목이다(DebindUI.xml의 AddPortrait).
-- 버튼 쪽은 "Add..."라는 따로 놀던 낱말을 쓰고 있었는데, 눌러서 열리는 창이 다른 이름을
-- 달고 있으면 같은 것인지 알 수가 없다.
L["SPELL_PICKER_TITLE"] = "Add an Action"
L["STATE_CHANGED_MESSAGE_OFF"] = "|cnRED_FONT_COLOR:OFF|r"
L["STATE_CHANGED_MESSAGE_ON"] = "|cnGREEN_FONT_COLOR:ON|r"
L["STATE_CHANGED_MESSAGE"] = "|cnLIGHTBLUE_FONT_COLOR:%1$s|r is now %2$s."
-- **Blizzard's own name for the machinery, kept.** "Condition Update Interval" was tried and reads
-- as the interval every condition the reader wrote is worked out on, which is not what this is
-- (2026-09-12, owner). It is even less that now: a condition is worked out at the press, and what
-- waits on this timer is the game noticing that something replaced the action bar. The tooltip
-- says so rather than leaving a reader to change it and see nothing.
L["STATE_DRIVER_UPDATE_THROTTLE"] = "State Driver Update Interval"
L["STATE_DRIVER_UPDATE_THROTTLE_DESC"] = "The time interval between Blizzard's state driver updates. Your keys work their conditions out the moment you press them, so this does not change how quickly one answers; what waits for it is the game noticing that a vehicle or a pet battle has taken your action bar. The lower the value, the more frequently the state driver updates (|cnHIGHLIGHT_FONT_COLOR:0|r means no interval at all).|n|nDon't worry. This value is not permanently saved and will reset to the default value if you disable the addon.|n|nBlizzard's default value is |cnHIGHLIGHT_FONT_COLOR:0.2|r seconds."
L["STATE_DRIVER_UPDATE_THROTTLE_WARNING"] = "Changing this value may cause performance issues."
-- The Switches tab. Everything below is read on that tab and nowhere else.
--
-- **The four answers.** A switch is either worked out from a macro conditional or pressed by hand,
-- and a pressed one still has to say what it is when the session starts. Those are one question to
-- a reader, so the four are worded as four answers to it rather than as a mode plus a setting --
-- the last of them is `CUSTOM_STATE_MODE_MACRO_CONDITIONAL`, which keeps its old key name from
-- the settings menu on the portrait that 3c took off the window.
--
-- **The label says the ordinary thing and the tooltip carries the rest.** This read "comes up on"
-- for a while, picked so that no one moment was named: the answer is applied at login and on every
-- specialization change too. That was a code lesson wearing a screen label. `initialValue` was
-- renamed for naming one moment because a field that is incomplete is a field that is wrong, and
-- the same is not true of a word somebody reads.
--
-- **A reader only asks what it starts as.** Resetting on a specialization change is ours: a value
-- that is going to be thrown away is a value not worth keeping, so we throw it away at the moment
-- it stops applying. That is a reason to write the code that way, not a reason to make the label
-- vague enough to cover it. The tooltips below say both moments in one sentence, which is where
-- somebody who wants that goes.
L["SWITCH_ANSWER_ON"] = "Starts on"
L["SWITCH_ANSWER_ON_DESC"] = "Turns on when you log in and when you change specialization. You can still turn it off by hand in between."
L["SWITCH_ANSWER_OFF"] = "Starts off"
L["SWITCH_ANSWER_OFF_DESC"] = "Turns off when you log in and when you change specialization. You can still turn it on by hand in between."
L["SWITCH_ANSWER_REMEMBER"] = "As you left it"
L["SWITCH_ANSWER_REMEMBER_DESC"] = "Starts on if you left it on. Every character remembers its own answer."
-- **The second sentence is the whole reason the tooltip exists.** A reader who ticks this and
-- then watches a switch the addon works out move in silence has no way to tell the option from a
-- fault, so which switches it covers is said here rather than left to be discovered.
L["SWITCH_MESSAGES"] = "Switch change messages"
L["SWITCH_MESSAGES_DESC"] = "Prints a line when a switch changes. Only switches you turn on and off yourself print one, never the ones the addon works out from a macro conditional."
-- The section where Debind hands a key it holds back to the game for as long as something else
-- needs it.
--
-- **The three rows are named after the situation, not after what happens to the key.** What happens
-- is the same on all three and the heading already says it, so a row repeating it would leave the
-- reader comparing three sentences to find the one word that differs.
--
-- The first row is `CONDITION_SPECIALBAR`, the name this state already has in the condition list.
-- A second name for it would put two words on one thing in front of a reader who cannot know they
-- are the same.
-- The balloon on the gear, the first time this window is opened. **It names what is behind the
-- gear rather than saying "settings are here"**: the gear already says that much, and what the
-- reader cannot see is that the things under it are ones they have to set before Debind behaves
-- the way they expect. Three of the four sections are named in the reader's own words, from the
-- headings they will find there.
L["SETTINGS_TIP"] = "Cast Options, Unit Frame Support and Keys Given Back are set here."
L["GIVE_BACK_KEYS"] = "Keys Given Back"
L["GIVE_BACK_REPLACED_BAR_DESC"] = "While a vehicle, a possession or the like has replaced your action bar, the keys bound to that bar's action buttons go back to the game. Your own actions on those keys come back when the bar does."
L["GIVE_BACK_ONLY_WITH_ACTION"] = "Filled buttons only"
L["GIVE_BACK_ONLY_WITH_ACTION_DESC"] = "A key goes back only where the replaced bar actually has an action. Empty buttons keep doing what you bound them to."
-- **The client's own name for the thing** (`MAP_LEGEND_PETBATTLE`), so every language gets it for
-- free. Assigned here only; translating it again could disagree with the game inside one window.
L["GIVE_BACK_PET_BATTLE"] = MAP_LEGEND_PETBATTLE
L["GIVE_BACK_PET_BATTLE_DESC"] = "During a pet battle, the keys bound to action buttons 1 to 5 go back to the game. There is no other way to reach a pet battle ability from a key."
-- **Not taken from the client**, which has no bare name for it: every string it has is a sentence
-- around one (`Exit House Editor`).
L["GIVE_BACK_HOUSE_EDITOR"] = "House Editor"
L["GIVE_BACK_HOUSE_EDITOR_DESC"] = "The House Editor claims some keys for itself while it is open. Ticked, Debind steps aside on the keys it claims and keeps every other one."
-- **There is no "only the first key" row, and there cannot be one** (2026-09-18, measured). The
-- client does not keep the two slots of a command in the order the keybinding screen showed: bind
-- a key in the first slot, reload, bind another in the second, reload, and the first slot is now
-- the second key. "The first key" would name a different key from one login to the next, which is
-- not something a checkbox can promise.
-- The rows under a switch: one per override, and the account-wide answer last.
--
-- **"Override" is the client's own word**, and 덮어쓰기 in Korean: `TRANSMOG_ARTIFACT_OPTIONS_HEADER`
-- is "Legion Artifact Override" / "군단 유물 덮어쓰기", `TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_ARTIFACT`
-- is "Ignore Override" / "덮어쓰기 무시".
--
-- ⚠ **Not "tab", which is what this said first.** IMPORTANCE_DESC calls a layer a tab, and it is right
-- to: that line compares two actions by *where they were put*. This list answers *when does this
-- apply*, the Switches tab has no side tabs to point at, and an override does not live in the tab it
-- names -- copying a tab copies actions and leaves the override behind (§4-7-1). Naming the tab
-- would promise the opposite.
--
-- **The axis has no name here, only its values**: a class, a specialization, a character. That is
-- the `reaction` move in `writing-user-facing-text.md`, and it is what keeps the sentence
-- out of the window's furniture.
--
-- ⚠ **The two lines below are what stops the rows reading as an order.** Stacked rows mean "the
-- next one runs when this one does not match" everywhere else in this window; here exactly one is
-- in use and the rest do nothing at all. The tick says which, and these say what the tick means.
L["SWITCH_OVERRIDE"] = "Override"
L["SWITCH_OVERRIDE_DESC"] = "Say what this switch comes up as for one class, one specialization or one character. Wherever you set none, the account-wide answer wins."
L["SWITCH_OVERRIDE_REMOVE"] = "Remove this override"
-- **Which one wins, not which one differs.** These rows are not a same-or-different reading of the
-- one above them: exactly one of them decides what the switch comes up as and the rest decide
-- nothing, so what a row has to say is that it won or that it lost. "Different" names the gap
-- between two rows, which is neither.
--
-- **"Wins" is this addon's own word for it** and the README teaches it in the same breath as the
-- layers: "The narrowest row that fits wins."
L["SWITCH_LAYER_WINNING"] = "This one wins here, so it is what the switch comes up as."
-- **Two ways to lose, and the row shows neither.** An override loses either because it is for a
-- character or specialization that is not the one in play, or because a narrower one beat it.
L["SWITCH_LAYER_LOSING"] = "This one does not win here. Either it is not for this character and specialization, or a narrower override beats it."
L["SWITCH_LAYER_MENU_INSTRUCTION"] = "Right-click to change this answer or take it away."
-- The row's own tooltip. **The three distances are the point of it**: a switch belongs to the
-- account while the list belongs to the character reading it, and one total cannot separate a
-- switch three characters depend on from one that does nothing here any more.
--
-- Written as label-and-number rather than as sentences. Three sentences saying almost the same
-- thing is a paragraph to read; three labels is a column to compare, which is what the reader is
-- actually doing with them.
L["SWITCH_USED_BY_HEADER"] = "Actions using it:"
L["SWITCH_USED_ACCOUNT"] = "Across the account"
L["SWITCH_USED_CHARACTER"] = "This character"
-- **"Right now" is a specialization, not a session.** This one counts what the current
-- specialization reads, so it drops when the reader changes specialization and the two above do
-- not. That is the whole reason it is a third line.
L["SWITCH_USED_LIVE"] = "Active right now"
L["SWITCH_MENU_INSTRUCTION"] = "Right-click for settings, renaming and deleting."
L["SWITCH_TURN_ON"] = "Turn On"
L["SWITCH_TURN_OFF"] = "Turn Off"
L["SWITCH_NOT_TRACKED"] = "Not tracked"
L["SWITCH_NOT_TRACKED_WHY"] = "No action reads it."
L["SWITCH_TOGGLE_INSTRUCTION"] = "Click to turn it on or off."
L["SWITCH_TOGGLE_IN_COMBAT"] = "Not from here during combat. A key set up to work the switch does it any time."
L["SWITCH_TOGGLE_IS_AUTOMATIC"] = "This one is worked out from its macro conditional, so pressing it would not hold."
L["SWITCH_RENAME"] = "Rename"
-- **The rule is spelled out because the box refuses on it.** A reader who types a space and is told
-- no learns the rule one refusal at a time; a reader who is told first types a name that takes.
L["SWITCH_RENAME_PROMPT"] = "What should this switch be called?\nLetters, numbers and |cnHIGHLIGHT_FONT_COLOR:_|r. The |cnHIGHLIGHT_FONT_COLOR:$|r in front is added for you."
L["SWITCH_RENAME_ERROR_GONE"] = "That switch is not here any more."
-- Making one. **Three places open this box**: the button under the Switches list, the condition
-- menu, and an on/off/toggle action's own menu. All three exist because a reader finds out they
-- want a switch while they are setting up the thing that needs it, not while looking at a list of
-- switches.
-- **Title case, as `SPELL_PICKER_NEW_MACROTEXT` is.** What follows "New" is the name of the kind of
-- thing the press makes, and the two rows say one thing between them wherever a reader meets both.
L["SWITCH_CREATE"] = "New Switch..."
L["SWITCH_CREATE_BUTTON"] = "New Switch"
-- **The tooltip carries the button's whole meaning now**, the [+] having no label of its own, so the
-- title above is what the button would have said and this is what the press does. It says the box
-- comes up because a name is the one thing making a switch needs and nothing on screen asks for it
-- yet. A reader expecting a row to appear presses once and gets a dialog instead.
L["SWITCH_CREATE_BUTTON_INSTRUCTION"] = "Click and it asks what to call it."
L["SWITCH_CREATE_DESC"] = "Makes a switch and puts it on this action straight away."
L["SWITCH_CREATE_PROMPT"] = "What should the new switch be called?\nLetters, numbers and |cnHIGHLIGHT_FONT_COLOR:_|r. The |cnHIGHLIGHT_FONT_COLOR:$|r in front is added for you."
-- **The two refusals a typed name gets, and they are about the name rather than about which box
-- it was typed into.** Renaming and creating both hand them back (`RenameSwitch`, `CreateSwitch`),
-- which is why they are not called SWITCH_RENAME_ERROR_* any more.
L["SWITCH_NAME_ERROR_INVALID"] = "A switch name can hold only letters, numbers and |cnHIGHLIGHT_FONT_COLOR:_|r."
L["SWITCH_NAME_ERROR_TAKEN"] = "There is already a switch by that name."
-- The [Set Switch] menu on an on/off/toggle action: which switch the key works, and what it does
-- to it. **The verbs are worded as what the key does, not as what the switch is.** "On" beside a
-- list of switches reads as the switch's own value, which is the one thing this menu cannot set.
L["SWITCH_ACTION_TITLE"] = "Pressing the key"
L["SWITCH_ACTION_ON"] = "Turns it on"
L["SWITCH_ACTION_OFF"] = "Turns it off"
L["SWITCH_ACTION_TOGGLE"] = "Turns it over"
-- **Deleting says how much it reaches, because the list cannot.** The definition is the account's
-- and the list shows what this character can see, so the number is the only place a reader learns
-- that deleting here takes conditions off actions on their other characters.
--
-- It says the actions keep the name rather than that they lose it: they do, they turn red, and
-- that red is how they get found again.
L["SWITCH_DELETE_CONFIRM"] = "Delete |cnHIGHLIGHT_FONT_COLOR:%1$s|r?\n|cnHIGHLIGHT_FONT_COLOR:%2$d|r actions across the account name it. They keep the name and go red until you fix them."
-- **A second line only when there is one to say.** Appended to the sentence above rather than
-- written into it, so the ordinary case -- a switch that is the same everywhere -- is not made to
-- read a sentence about overrides it does not have.
--
-- It says "this list does not show" for the same reason the line above counts the whole account:
-- the list draws what one character reaches, so a druid's overrides go without ever having been
-- on screen.
L["SWITCH_DELETE_CONFIRM_OVERRIDES"] = "|cnHIGHLIGHT_FONT_COLOR:%d|r overrides go with it, including ones on your other characters that this list does not show."
-- **It quoted the button for as long as the button had a label**, and it does not any more: the way
-- in is the [+] in the corner. A sentence that spells out a picture has the reader hunting for a
-- control against a description instead of seeing it, and the [+] is the only control on this tab.
--
-- So it goes back to the one job an empty-list line has, **saying what fills it**. The second line
-- is what a row will be: the switch, and under it the places its answer differs.
L["SWITCHES_EMPTY"] = "No switches yet.|n|nOne you make stands here, with every place you have set it differently under it."
-- The two headings the list is split under. **The second says what `SWITCH_NOT_TRACKED` says on a
-- row**, because they are the same fact about the same switch, and two wordings for it in one
-- panel leave the reader unable to see that.
L["SWITCHES_GROUP_TRACKED"] = "Tracked"
L["SWITCHES_GROUP_UNTRACKED"] = "Not tracked"
-- 아래 탭 둘의 툴팁 설명 줄. 사이드탭 쪽(LAYER_DESC_*)과 같은 마디로 적되, 여기는
-- 사이드탭 셋을 통째로 덮는 자리라 전문화까지 내려가지 않는다. 중요도에 붙는 단서도
-- 같다 - 같은 주장이면 같은 데서 틀린다.
L["TAB_DESC_SHARED"] = "Every character on the account."
L["TAB_DESC_CHARACTER"] = "This character only. A key here beats the same key in Account, unless conditions or Importance say otherwise."
-- The instruction line on the `Target` row (`MenuKit`'s `<label>_DESC` rule).
--
-- **The second sentence is the surprising half.** A picked target is taken out of every
-- redirection, the two keys included: a key still held from the key pressed just before reads as
-- held, and would send the action somewhere the reader never chose (2026-09-15, owner). The client's
-- own names are used so they can be matched against the game's settings panel, where they sit
-- together; Hover Cast is this addon's own and sits in its settings.
--
-- **`Disable` is named because it is the way back**, it is the row directly above in this same
-- menu, and its own label carries no hint that it is the one that hands the decision to the game.
L["TARGET_UNIT_DESC"] ="The action is used on that unit without targeting it, even over a unit frame.|n|nWhile a target is picked here, nothing moves it: not the Self Cast Key or the Focus Cast Key, not Hover Cast, not Mouseover Cast or Auto Self Cast. Disable hands the decision back to the game."
-- Carried by every entry in the `Target` menu except `Disable`, appended to whatever that entry
-- says for itself (`ActionMenuItems.lua`). The parent row says it too (`TARGET_UNIT_DESC`); this
-- one exists because a reader can land on a single entry without passing the parent.
--
-- **Every redirection is named**, the client's with the client's own labels so the sentence can be
-- matched against the game's settings panel. Auto Self Cast is named although no key is held for it:
-- it fires with no key at all, so leaving it out would read as "that one still applies".
L["TARGET_UNIT_FIXED"] = "While this is picked, the action goes here: neither the Self Cast Key nor the Focus Cast Key moves it, and Hover Cast, Mouseover Cast and Auto Self Cast are left out. Disable hands the decision back to the game."
L["TARGET_UNIT"] = "Target"
-- The group an issue about the presses an action answers points at, the row that opens the menu
-- holding them, and the settings section holding the account-wide values those rows fall back on.
L["CASTING"] = "Cast Options"
-- **The row names the presses, not the values under it.** Four submenus each answering "and on this
-- press?" is what the reader is about to read, and a row that tried to say what each of them does
-- would be the menu written out on one line.
L["CASTING_DESC"] = "Which presses this action stands on, and where it goes on each of them."
-- The three rows inside a cast key's menu. **Each says what happens while the key is held**, which
-- is the question the reader opened the row with (`which-action-a-key-runs.md` §6).
--
-- **The two keys are named by the client's own labels** (`AUTO_SELF_CAST_KEY_TEXT`,
-- `FOCUS_CAST_KEY_TEXT`, the dropdowns in its settings), so the sentences here name the key the
-- same way the row above them does.
L["CASTING_SELF_CAST_KEY_DESC"] = "What this action does while the Self Cast Key is held."
L["CASTING_FOCUS_CAST_KEY_DESC"] = "What this action does while the Focus Cast Key is held."
L["CASTING_SELF_CAST"] = "Cast on yourself"
L["CASTING_SELF_CAST_DESC"] = "Holding the Self Cast Key sends this action to you."
L["CASTING_FOCUS_CAST"] = "Cast on your focus"
L["CASTING_FOCUS_CAST_DESC"] = "Holding the Focus Cast Key sends this action to your focus."
-- **One label for the middle value of all three rows**, because it is one answer: the action takes
-- its turn on that press and the press does not move it. The sentence under it is written per row,
-- since what is being turned down differs.
L["CASTING_AS_USUAL"] = "Cast as usual"
L["CASTING_SELF_USUAL_DESC"] = "Holding the Self Cast Key does not send this action to you. It goes where it would with no key held, and keeps its place among the actions on the key."
L["CASTING_FOCUS_USUAL_DESC"] = "Holding the Focus Cast Key does not send this action to your focus. It goes where it would with no key held, and keeps its place among the actions on the key."
L["CASTING_HOVER_USUAL_DESC"] = "Pointing at a unit does not send this action to it. It goes where it would with nothing pointed at, and keeps its place among the actions on the key."
-- **One word for the same value on all three rows.** Turned off, the action makes no binding for
-- that press; what that leaves behind differs by row, and each row's own sentence says it.
L["CASTING_OFF"] = "Off"
L["CASTING_SKIP_DESC"] = "The action sits this press out, and the next action on the key takes it."
-- **Off does not take the action off the pointed press**, and the sentence has to say so, because
-- the two rows above it do exactly that. With no twin the action waits in the last tier, so a
-- pointed press still reaches it once every action that answers one has been tried.
L["CASTING_HOVER_OFF_DESC"] = "Pointing at a unit does nothing for this action. It runs on a plain press, behind any action on the key that does run on a pointed press."
L["CASTING_HOVER_CAST_DESC"] = "What this action does while you point at a unit with no key held, and which units count as pointed at."
-- **The key decides, so the row says so and stops.** Nothing stored here reaches a bare click, and a
-- reader who came to change it is owed the reason rather than a row that does nothing.
L["CASTING_HOVER_BARE_CLICK"] = "A left or right click with no modifier only runs on a unit frame, so this action always casts on the unit you click."
-- **It says where the answer comes from and then says what the answer is.** The mode lives in one
-- place for the whole account, and a row that only pointed at it would send the reader off to read
-- one word.
L["CASTING_HOVER_ACCOUNT"] = "Use the mode in Debind's settings"
L["CASTING_HOVER_ACCOUNT_DESC"] = "Whatever Hover Cast is set to in Debind's settings, which is %s right now."
L["CASTING_POINTED_CAST"] = "Cast on the unit you point at"
L["CASTING_POINTED_CAST_DESC"] = "Pointing at a unit sends this action to it."
-- **The fourth press has no key and no unit to name it by**, so it is named as the plain one: the
-- key pressed with nothing held and nothing pointed at. Ticked is what every action did before any
-- of these values existed.
--
-- **What is left once it is unticked is not listed here.** It used to end "and this action is only
-- reached by a held key or by pointing at a unit", which was true while every action answered a
-- pointed press; with Hover Cast off by default that half names a way in the reader does not have.
-- The three rows above each say what they answer, so the reader has the list already.
L["CASTING_NORMAL"] = "Normal Cast"
L["CASTING_NORMAL_DESC"] = "The action runs on a press with nothing held and nothing pointed at. Unticked, that press goes to the next action on the key."
L["CAST_KEY_OFF_ACCOUNT_WIDE"] = "This key is turned off for every Debind key, in Debind's settings. What is set here is kept and does nothing until it is turned back on."
-- **One sentence for two positions, because it is one fact** (`ActionMenuItems.lua`): a picked
-- target is never moved by any of these presses. On the first row of each it says the label is not
-- literal here; on [Cast as usual] it is why the row stands locked, since with a target picked the
-- two say the same thing.
L["CAST_KEY_TARGET_PICKED"] = "This action has a target of its own, and it goes there on this press as well."
-- **Named apart from `TARGET_UNIT`.** That one is the target the reader picks; this row is what the
-- pick turns into at the press, once a held key or Hover Cast has had its say, and that is you or
-- your focus as often as a target. The two sit in one menu tree, where "Target" twice would read as
-- one thing (`implementing-focus-and-self-cast.md` §3-6).
L["RESOLVED_TARGET"] = "Resolved Unit"
-- **Formatted, not written out.** The first and last are this addon's own labels (`TARGET_UNIT`,
-- `CASTING_AS_USUAL`) and the middle two the client's (`AUTO_SELF_CAST_KEY_TEXT`,
-- `FOCUS_CAST_KEY_TEXT`, the two modifier dropdowns in its settings), so a rename on either side
-- carries into the sentence (`ActionMenuNodes.lua`).
--
-- **A held key comes before the pointed unit**, and the order of the sentence says so: the pointed
-- unit is only reached with no key held.
--
-- **Cast as usual is named because it lands on the current target too.** A held key or a pointed
-- unit set to it sends the action where it would go with nothing held or pointed at, and the
-- conditions follow it there (`which-action-a-key-runs.md` S3). Without it the sentence
-- promises you or your focus on a press that goes neither way.
--
-- **"Sits the press out", not "does not go out".** A condition that fails hands the press to the
-- next action on the key; the old wording read as the press ending there. The words are
-- `CASTING_SKIP_DESC`'s, since it is the same outcome.
--
-- **Auto Self Cast is named** because it is what a reader expects to rescue a friendly spell on the
-- current target (2026-09-13, owner), and when the conditions fail it never gets the chance.
L["RESOLVED_TARGET_DESC"] = "The unit this action is used on once the key is pressed: the one picked under %1$s. With none picked, it is you while the %2$s is held, your focus while the %3$s is held, the unit you point at while %5$s is on for this action and you point at one, and your current target on any other press or on one set to %4$s.|n|nWhen the conditions set here do not hold for that unit, this action sits the press out and the next action on the key takes it. On your current target, that also means Auto Self Cast does not get a turn."
L["TYPE_BLOCK"] = "Nothing"
L["TYPE_BLOCK_DESC"] = "The press does nothing. It takes the key for itself, so no action under it on the same key runs either.|n|nPut conditions on it to stop the actions under it in those cases only."
L["TYPE_COMMAND"] = "Binding Command"
L["TYPE_FLYOUT"] = "Flyout"
L["TYPE_FOCUS"] = "Set Focus Target"
-- **Numbers the two slots the client calls by one name.** `TRINKET0SLOT` and `TRINKET1SLOT` are
-- both "Trinket" and the two finger slots are both "Finger"; the character sheet tells them apart
-- by where they sit, and a list has nothing to tell them apart with.
L["USESLOT_NUMBERED"] = "%s %d"
L["TYPE_USESLOT"] = "Equipment Slot"
-- Says what the key follows, because that is what a reader is choosing between here: this row and
-- the item itself sitting in the Carried group below it.
L["TYPE_USESLOT_DESC"] = "Uses whatever you are wearing in this slot."
L["TYPE_ITEM"] = "Item"
L["TYPE_MACRO"] = "Macro"
L["TYPE_MACROTEXT_DESC"] = "Creates a macro that lives in this addon and leaves WoW's macro slots free. It can aim at special units and read your switches, which a macro in WoW's own list cannot.|n|nExample: |cnHIGHLIGHT_FONT_COLOR:/cast [@tank,exists] Rejuvenation|r"
L["TYPE_MACROTEXT"] = "Custom Macro"
L["TYPE_MOUNT"] = "Mount"
L["TYPE_PETACTION"] = "Pet Command"
L["TYPE_SETCUSTOM_DESC"] = "Pins the unit whose frame you are hovering over as this custom target. A custom target holds a unit the way focus does: aim at it with |cnHIGHLIGHT_FONT_COLOR:@custom1|r or |cnHIGHLIGHT_FONT_COLOR:@custom2|r in a custom macro, or hand it to any action as its target.|n|nWorks over Player, Pet, Party/Raid, Boss and Arena unit frames."
L["TYPE_SETCUSTOM"] = "Set Custom Target"
L["TYPE_SETCUSTOM1"] = "Set Custom Target 1"
L["TYPE_SETCUSTOM2"] = "Set Custom Target 2"
L["TYPE_SETSTATE_DESC"] = "Turns a switch on or off. A switch is an on/off value of your own that other actions take as a condition, so one key does one thing while it is on and another while it is off.|n|nRight-click it once it is in to pick which switch it works, and whether the key turns that switch on, turns it off, or flips it.|n|nIt flips |cnHIGHLIGHT_FONT_COLOR:in combat|r too."
L["TYPE_SETSTATE_ANY"] = "a Switch"
L["TYPE_SETSTATE_OFF"] = "Turn Off %s"
L["TYPE_SETSTATE_ON"] = "Turn On %s"
L["TYPE_SETSTATE_TOGGLE"] = "Toggle %s"
L["TYPE_SETSTATE"] = "Switch"
L["TYPE_SPELL"] = "Spell"
L["TYPE_TARGET"] = "Set Target"
L["TYPE_TOGGLEMENU"] = "Open Unit Popup Menu"
L["TYPE_SPEC_RESOLVED_HEADER"] = "Class and Specialization"
-- The second half of all three descriptions below. They say one thing between them: the action
-- carries no condition, so it matches everywhere and the key is spent even where there is nothing
-- to cast.
--
-- **It asks what you have, not which specialization you are in.** The spell comes out of the
-- specialization table without anyone checking whether it has been learned
-- (`SpecSpells.SpellForType`), so a specialization that has one on paper is the same case while
-- the spell is still unlearned, and a sentence naming the specialization would miss it.
--
-- **It names `CONDITION_KNOWN` in words.** Renaming that row leaves this sentence pointing at
-- something that is not on screen, which is the cost; without the name the reader is told a
-- condition exists and not which one, and the sentence stops being actionable.
L["TYPE_SPEC_RESOLVED_NONE_DESC"] = "The key is still taken when you have none, and the press does nothing. To have the key only when you have one, turn on the Known Spell condition."
L["TYPE_DISPEL"] = "Dispel"
L["TYPE_DISPEL_DESC"] = "Casts your specialization's friendly dispel, whichever it is right now."
L["TYPE_EXTERNAL"] = "External"
L["TYPE_EXTERNAL_DESC"] = "Casts your specialization's damage reduction or absorb for another player, such as Pain Suppression, Ironbark or Blessing of Sacrifice."
L["TYPE_RAIDBUFF"] = "Raid Buff"
L["TYPE_RAIDBUFF_DESC"] = "Casts your class's raid-wide buff, such as Power Word: Fortitude or Arcane Intellect."
-- The addon's own name, since the client has none for it: the game has no notion of a unit frame an
-- addon happens to know about. A header that spelled the feature out instead of naming it was the
-- worse of the two (2026-09-12, owner), so the row below repeats the name rather than dropping it.
-- **Everything true of both reaches is here, and what each reach covers is on its own entry**
-- (2026-09-12, owner). The row between them carries nothing: it was a third tooltip saying a third
-- piece of one explanation.
--
-- **The friendly-or-harmful sentence is the whole reason this feature stops where it does.**
-- Nothing in the client answers that question in a way a key could act on, so the unit goes out as
-- it is and a wrong one is silent: the spell lands on the current target, or on you, or nowhere.
-- The two boxes are labelled with the client's own `AUTO_SELF_CAST_KEY_TEXT` and
-- `FOCUS_CAST_KEY_TEXT`. **Unticked says where the action goes, not that the game takes over**: the
-- game's own handling stays off for a Debind key either way (`Debind.lua`).
L["SELF_CAST_KEY_DESC"] = "Holding the Self Cast Key sends an action with no target of its own to you. An action with a target picked keeps going there.|n|nUnticked, Debind ignores that key, and the action goes where it would with no key held."
L["FOCUS_CAST_KEY_DESC"] = "Holding the Focus Cast Key sends an action with no target of its own to your focus. An action with a target picked keeps going there.|n|nUnticked, Debind ignores that key, and the action goes where it would with no key held."
-- Under the two above, with the key the game has now (`SettingsTab.lua`). **None gets no sentence of
-- its own** (2026-09-14, owner): the value and the line under it already say where to set one.
-- "Current" in the client's own `CURRENT_PET` shape.
L["CURRENT_SELF_CAST_KEY"] = "Current Self Cast Key: %s"
L["CURRENT_FOCUS_CAST_KEY"] = "Current Focus Cast Key: %s"
L["CAST_KEY_CHANGE_IN_GAME_OPTIONS"] = "You can change it in the game's Options, under Combat."
L["POINTED_UNIT_CAST"] = "Hover Cast"
-- **What this row sets, and nothing else.** The feature itself is a page now
-- (`docs/ingamehelp/enUS/hover-cast.md`), reached by the link under the row: the explanation is
-- longer than a tooltip holds, and a reader who already knows what Hover Cast is comes here to pick
-- a mode.
L["POINTED_UNIT_CAST_DESC"] = "Which units count as pointed at.|n|nTurning Hover Cast on is done on each action, in its right-click menu, and an action can use a mode of its own there as well."
-- **Entry names are Title Case**, which is what the client's own lists use
-- (`SELF_CAST_AUTO_AND_KEY_PRESS`, `SETTING_EMPOWERED_SPELL_INPUT_HOLD_OPTION`).
--
-- `UNITFRAME_LABEL` is the client's word for the frames. **No "only" on it**: a dropdown says that
-- already, and the word would have to come off again the day a third entry lands between the two.
L["POINTED_UNIT_CAST_FRAMES"] = "Unit Frames"
L["POINTED_UNIT_CAST_FRAMES_DESC"] = "The unit of the unit frame under your cursor. Away from a unit frame nothing is pointed at."
-- **The client's own word, because it is the client's own reach.** `ENABLE_MOUSEOVER_CAST` is
-- what the game calls the thing in its settings, and a Debind key is the one place it cannot do it
-- (`HELP_TARGETING_BODY`). A second name for one behaviour would leave the reader with two.
L["POINTED_UNIT_CAST_MOUSEOVER"] = "Mouseover"
L["POINTED_UNIT_CAST_MOUSEOVER_DESC"] = "A unit frame, a nameplate, or the unit itself in the world. This covers the unit frames as well."
L["LINE_TOOLTIP_SPEC_SPELL"] = "Casts on this character"
L["LINE_TOOLTIP_SPEC_SPELL_NONE"] = "Nothing. This specialization has no such spell"
L["TYPE_UNUSED"] = "Use WoW's Own Binding"
L["TYPE_WORLDMARKER"] = "World Marker"
L["TYPE_ACTIONBUTTON"] = "Action Button"
L["UNABLE_TO_REGISTER_UNIT_FRAME_IN_COMBAT"] = "Unable to register some unit frames due to being in combat. They will be registered when combat is over."
L["UNBIND"] = "Unbind key"
--- Asked before a key comes off two or more actions that share one.
---
--- **The whole point of the sentence is the last clause.** Taking a key off deletes nothing and the
--- reader can give each action a key again, so the obvious reading of "unbind" is that it can be
--- undone. What it actually costs is the grouping, and no field anywhere remembers it -- so if they
--- do not remember which ones went together, there is no way back to it.
---
--- **The count is what the box is for.** A single action is never asked about: there is no set there
--- to lose. What the reader is being told is the size of what comes apart.
---
--- "Separate actions" and not "lose their key", because losing the key is the part they asked for.
L["UNBIND_SCATTERS_CONFIRM"] = "%d actions share a key here. Taking it off leaves them as separate actions with no key, and nothing records that they went together - if you do not remember, you cannot put them back."
--- **The verb, not [Okay].** The reader is agreeing to the thing the sentence just described rather
--- than acknowledging that they read it, and the client's own destructive prompts name the act.
L["UNBIND_SCATTERS_CONFIRM_YES"] = "Unbind and separate"
L["UNIT_CUSTOM1"] = "Custom Target 1"
L["UNIT_CUSTOM2"] = "Custom Target 2"
L["UNIT_DISABLE"] = "Disable"
L["UNIT_FOCUS"] = "Focus"
L["UNIT_HEALER"] = "Healer"
L["UNIT_HOVER_DESC"] = "The unit on the frame you are hovering over"
L["UNIT_HOVER"] = "Unit Frame"
L["UNIT_MAINASSIST"] = "Main Assist"
L["UNIT_MAINTANK"] = "Main Tank"
L["UNIT_MOUSEOVER"] = "Mouseover"
-- **Only what is true of this entry alone.** Auto Self Cast used to be named here; every entry in
-- the menu now carries `TARGET_UNIT_FIXED`, which says it for all four, and saying it twice on one
-- tooltip reads as two different facts.
L["UNIT_NONE_DESC"] = "Turns the cursor into the targeting cursor even when you already have a target, and you pick where it lands."
L["UNIT_NONE"] = "Always Ask"
L["UNIT_PET"] = "Pet"
L["UNIT_PLAYER"] = "Player"
-- 하나보다 많으면 풀린다(SPECIAL_UNIT_UNSET_MESSAGE_TOO_MANY). 예전 문장은 "only one
-- that role must exist"라 문장이 깨져 있었고, 하나만 있어야 한다는 것도 안 읽혔다.
L["UNIT_ROLE_DESC"] = "Tank, Healer, Main Tank and Main Assist only work while exactly one member of your party or raid holds that role."
L["UNIT_TANK"] = "Tank"
L["UNIT_TARGET"] = "Target"
-- **`nil` is one of the three and not a missing answer.** The game only asks this question of
-- keybinds (`ACTION_BUTTON_USE_KEY_DOWN`), so the entry names the game rather than the key
-- setting, and the settings tab shows in brackets which of the other two that setting comes to.
-- **A noun, like every other row label in the settings list** (2026-09-13, owner). The row sits under
-- the unit frame section, so "click" needs no subject.
L["UNITFRAME_CLICK_EDGE"] = "Click Timing"
L["UNITFRAME_CLICK_EDGE_DESC"] = "When a click on a unit frame casts: as the mouse button goes down, or as it comes back up."
L["UNITFRAME_CLICK_EDGE_DOWN"] = "Pressed"
-- Title Case like every other entry in a dropdown the client draws
-- (`SELF_CAST_AUTO_AND_KEY_PRESS`, `INTERACT_ICONS_DEFAULT`), which the one-word entries around it
-- could not show on their own.
L["UNITFRAME_CLICK_EDGE_GAME"] = "Game Setting"
L["UNITFRAME_CLICK_EDGE_UP"] = "Released"
L["UNNAMED_ACTION"] = "(Unnamed)"
-- Printed once a session, when another addon keeps taking a unit frame back the moment Debind
-- takes it. Debind gives that frame up; the addon that wanted it keeps working there.
--
-- **What the reader can act on is the second half.** They cannot see who is doing it and there is
-- nothing to switch, so the useful sentence is which of their keys will not work and where. "Some
-- of your unit frames" rather than a name, because the frame that lost is not one they can point
-- at either.
--
-- **One chat line**, like everything else this addon says there.
L["WARNING_MESSAGE_UNIT_FRAME_CONTESTED"] = "Another addon keeps claiming some of your unit frames, so Debind's keys do not work on them."
-- **The addon has stood down from settings written by a newer version of itself**, and will not
-- read or write one byte of them (`Profile.lua`). It goes out at login, and again every time
-- somebody tries to open the window, and it keeps going out on every login until the reader does
-- something about it, because the state it describes does not go away on its own.
--
-- **One chat line, like every other thing this addon says here.** It was three, one per thing to
-- say, and three lines land as three prefixes and three timestamps in the same frame as loot and
-- quest text. Wrapping costs nothing; a second entry costs the reader a second look.
--
-- **The symptom opens it, not the cause.** What the reader is looking at is a character whose keys
-- have all stopped, and what they are looking for is why that happened. The reassurance came first
-- until this was read on a screen, and there it had nothing to attach to yet.
--
-- **"Put the newer version back", not "update".** Rolling an addon back is something people do on
-- purpose, and telling somebody to undo what they just deliberately did reads as not having
-- understood them. This sentence is true either way.
--
-- **No version number in it.** The one this build could name is its own, and the number the reader
-- needs is the one they came from, which nothing here knows.
L["NEWER_PROFILE_MESSAGE"] = "None of your keys work: what Debind saved is from a newer version and this one cannot read it. Nothing was changed, so put that version back and it all returns. Or type |cnHIGHLIGHT_FONT_COLOR:/deb reset|r to wipe it and start over."
-- The first of the two steps. It says what goes and that it is final, and **ends on the token**, so
-- the thing to be typed is the last thing read and sits directly above the typing. Nothing to count
-- and nothing to remember (`Profile.lua`).
--
-- **"on every character of this account" is not decoration.** One file holds the whole account, so
-- somebody typing this on an alt they barely play is about to delete their main's keys too.
--
-- The token itself is never translated: every command this addon has is English already.
L["NEWER_PROFILE_RESET_PROMPT"] = "This wipes everything Debind saved, on every character of this account, and cannot be undone. To go ahead, type: |cnHIGHLIGHT_FONT_COLOR:/deb reset confirm|r"
-- 창을 덮는 판. **"왜 이 화면을 보고 있나"를 먼저 답한다** - 사용자는 자기가 무언가를
-- 껐다는 사실과 이 화면을 연결하지 못한다. 그다음이 "그게 뭔데"이고, 마지막이 부탁이다.
-- 순서를 뒤집으면(부탁부터) 이유는 안 읽히고 [필요 없음]만 눌린다.
L["MIGRATION_DIALOG_HEADER"] = "Debind"
L["MIGRATION_DIALOG_TITLE"] = "Your settings are still here - Debind just cannot reach them."
L["MIGRATION_DIALOG_BODY"] = "In case you missed it: this addon was called |cnHIGHLIGHT_FONT_COLOR:Debounce|r until version 3.0. Same addon, same settings. Version 3.1 renames the folder as well, and that is where WoW keeps your settings file - so the companion addon |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r is now the only thing that can read the old one. Right now it is switched off.|n|n|cnGREEN_FONT_COLOR:Turning it on is the right answer in every case.|r It is barely an addon - no code, nothing that runs, nothing to slow down. Debind opens it once per character to read the old file, and once every character has been through it is never loaded again. All it costs you is one line in your addon list.|n|nUntil you answer, Debind will not open. Closing this window asks again next time you log in."
L["MIGRATION_DIALOG_ENABLE"] = "Turn it on and reload"
-- 거절 둘의 **범위를 글자가 진다.** 되돌릴 버튼이 없으므로 어디까지 걸리는지 읽고 누르게 한다.
-- 캐릭터 단위가 따로 있는 이유는 애드온 활성 상태가 캐릭터별이기 때문이다(XML의 근거).
L["MIGRATION_DIALOG_DECLINE_CHARACTER"] = "Start fresh on this character"
L["MIGRATION_DIALOG_DECLINE_ACCOUNT"] = "Start fresh on every character"
-- 툴팁이 버는 것은 **버튼 글자에 못 넣는 것**이다 - 되돌릴 수 없다는 사실, 옛 파일이 남는다는
-- 사실, 아직 로그인하지 않은 캐릭터까지 걸린다는 사실. 글자를 다시 풀어 쓰는 툴팁은 없느니만
-- 못하다. 셋 다 다는 이유는 하나만 비면 그 버튼에 마우스를 올린 사람이 "툴팁 없는 창"으로
-- 판단하고 나머지도 안 보기 때문이다.
-- 계정 몫이 이미 넘어온 뒤에 이 캐릭터만 남은 경우. **공유 바인딩은 지금 멀쩡히 동작 중이고**
-- 그 사람은 그걸 보면서 이 창을 읽는다. "네 설정을 못 읽는다"고 뭉뚱그리면 눈앞의 사실과
-- 어긋나서, 창이 무엇을 말하는지가 아니라 창을 믿을지가 문제가 된다.
-- 폴더가 아예 없는 경우. **켜기 버튼이 할 수 있는 게 없어서 숨긴다** - `EnableAddOn`은 없는
-- 애드온에 아무 일도 안 하고, 리로드하면 같은 창으로 돌아온다. 그러면 남는 선택지가 되돌릴 수
-- 없는 둘뿐이므로, 다시 받는 길을 먼저 알려주고 창을 닫아도 된다고 말해준다.
L["MIGRATION_DIALOG_TITLE_MISSING"] = "The addon that holds your old settings is not installed."
L["MIGRATION_DIALOG_BODY_MISSING"] = "|cnHIGHLIGHT_FONT_COLOR:Debind Migration|r ships with Debind and holds the settings saved by 3.0 and earlier. It is not in your AddOns folder, so it was either removed or the install did not finish.|n|nDownloading Debind again puts it back, and your old settings are still on disk in the meantime - nothing has been lost.|n|nYou can close this window and reinstall. It will ask again next time you log in.|n|nOnly answer below if you would rather start over without those settings."
L["MIGRATION_DIALOG_TITLE_CHARACTER_ONLY"] ="This character's own bindings have not come across yet."
L["MIGRATION_DIALOG_BODY_CHARACTER_ONLY"] = "Your account bindings are already here - they moved when you logged in on another character, which is why most of your keys work.|n|nWhat is still missing is anything you set up for |cnHIGHLIGHT_FONT_COLOR:this character alone|r: its own layers and its custom targets. Those live in a separate file, and the companion addon |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r is the only thing that can read it. Right now it is switched off.|n|n|cnGREEN_FONT_COLOR:Turning it on is still the right answer.|r If it turns out you never made character-specific bindings here, nothing happens and you are done. If you did, you get them back. Either way it stops asking.|n|nUntil you answer, Debind will not open. Closing this window asks again next time you log in."
L["MIGRATION_DIALOG_ENABLE_TOOLTIP"] ="Enables |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r for every character and reloads your interface.|n|nThis character's settings are back as soon as the reload finishes. Your other characters keep theirs until you next log in on them - each one brings its own across on its own first login, whenever that is. Nothing else to do."
L["MIGRATION_DIALOG_DECLINE_CHARACTER_TOOLTIP"] = "This character starts with no bindings, and is never asked again.|n|nOther characters are unaffected - they will still be offered their settings.|n|n|cnRED_FONT_COLOR:This cannot be undone from inside the addon.|r Your old file is left untouched on disk either way."
L["MIGRATION_DIALOG_DECLINE_ACCOUNT_TOOLTIP"] = "Debind stops offering old settings to |cnHIGHLIGHT_FONT_COLOR:every character on this account|r, including ones you have not logged in on and ones you make later.|n|n|cnRED_FONT_COLOR:This cannot be undone from inside the addon.|r Your old file is left untouched on disk either way."
L["WARNING_MESSAGE_LEGACY_ADDON_STILL_INSTALLED"] = "An older full copy of this addon is still installed and is setting keybinds alongside Debind, so the two are fighting over your keys. Reinstalling or updating Debind replaces that folder with the small |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r companion. Do not just delete the folder - characters you have not logged in on since updating still have their settings in it."

-- The sharing window. The tooltips are long because both choices it offers - what to send, and
-- whether the keys ride along - leave for somewhere you cannot reach: a string handed to someone
-- else is not recallable. A tooltip is read on purpose, so length is not the cost it looks like.
--
-- These live here rather than in `DebindStorage` because they are eleven strings against that
-- addon's reason for existing, and a second locale tree would need its own parity check.
-- The window's own tabs (`PANELS` in `DebindUI.lua`). The label is one word, so the tooltip is
-- where the tab says what it opens - and Import and Export both open something that leaves for
-- somewhere you cannot reach, so the same "read it on purpose" rule as above applies.
--
-- The two panels themselves live in `DebindStorage`, which is load-on-demand and may not be there.
-- **One failure, so one message.** That addon cannot load and then not have built its panel, so
-- "loaded but empty" is not a second case to describe - if it ever happened the install would be
-- broken, and the second line below is already the fix for that.
--
-- **It says what failed and what to do, not where our code lives.** Which addon holds which panel
-- is our filing, not the reader's problem; what they can act on is the switch in the AddOns list
-- and, failing that, installing again. No `%s` either, unlike the chat line further down - the
-- reason string the client hands back is for the log, not the middle of a window.
-- Taking the badge off imported actions. **The verb is about the reader, not the action** -
-- nothing is being changed or repaired, they are saying they will have it.
--
-- **It is the moment a key starts working.** What arrives keeps the key it was sent on and the badge
-- is the only thing holding it back, so this press puts it live. It used to be the opposite - what
-- arrived sat on a number the build skipped - and the sentence that said so went with the number
-- (`building-export-import.md` 12절).
--
-- **"As mine" came off** (2026-08-23, 소유자). It marked the answer while there was nothing else in
-- the menu it could be confused with; the item beside it now is the same verb with a key picked
-- first, and the two read as a pair only if the plain one is plain. `ORDER_ACCEPT` on the row is
-- the same word for the same press, which is what one thing having one name means.
L["APPROVE_IMPORT"] = "Accept"
-- The row above the two columns, which is the only thing on that row while anything is waiting.
--
-- **It names the state, and the two answers to it are in the menu it opens.** Two buttons stood
-- here - [Accept all %d] and [Reject all %d] - and a label per answer meant the row could not be
-- one control. Naming the state instead is what folds them: a reader who has not decided yet is
-- told what there is to decide about, and both verbs are one press away.
--
-- **"Pending" is the client's word for exactly this** - something that arrived and is waiting on
-- the reader to say yes or no (`COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER` = "Pending Invites
-- (%d)", `CLUB_FINDER_PENDING_REQUESTS`). It is a third name for the state on this screen, after
-- the filter tick's "Not Accepted Yet" and the menu items' "still waiting", and it earns that by
-- being the only one of the three that has to stand **alone**: the other two sit inside a sentence
-- or a verb that supplies what is being waited on, and a button on an empty row has neither.
--
-- **"Action" is the reader's word for the thing being counted.** `|4` is the client's own plural
-- form, resolved when the string is drawn rather than by `format`.
--
-- **It breaks off** (2026-08-23, 소유자). The press opens a menu rather than doing anything, and a
-- label that names a state on a button that acts is the one shape a reader cannot tell apart from a
-- label that names a state on a button that asks. The tab's own [Add to My Setup...] breaks off for
-- the same reason.
L["IMPORT_PENDING"] = "%d Pending |4Action:Actions;..."
-- **Two facts, and the reader needs both before opening the menu.** What the state means - none of
-- this is doing anything - and how far the count reaches, which is the one thing they cannot see
-- from here (the same reason `APPROVE_ALL_IMPORT_DESC` has to say "wherever it went").
--
-- **It does not repeat the number**; the title is the button's own text and already carries it.
L["IMPORT_PENDING_DESC"] = "These came in from a string and do nothing until you accept them - no key of yours behaves any differently while they wait. The count is everything still waiting anywhere in your bindings, including specializations you are not in."
-- **Both mouse buttons, so neither is named.** Saying "left-click" would make the right one look
-- like something else; saying both would spend a line on a distinction that does not exist here.
L["IMPORT_PENDING_INSTRUCTION"] = "Click for what can be done to all of it."
-- Accepting everything at once, which is the ordinary way out.
--
-- **The number is not here, and there is still no confirmation box.** It used to be - this was a
-- button on the row above the columns and read "Accept all %d", with that number standing in for
-- the box, since the one useful thing such a box could have said is how much is about to start
-- working. What carries it now is the button this menu opens off, which reads `IMPORT_PENDING` and
-- is on screen the whole time the menu is: the count is one widget away rather than gone, and it is
-- the same count because both come from `CollectArrivedActions`.
--
-- **"all" is the whole of the scope, and it means the profile.** The heading menu's items name the
-- subset they gather instead (`KEY_HEADER_APPROVE`) precisely because "all" would overpromise
-- there; here it does not.
L["APPROVE_ALL_IMPORT"] = "Accept all"
-- **It has to say "wherever it went"**, because the count includes actions on specializations you
-- are not in, and those are on no list the reader can see from here.
--
-- **And it has to say that these go live.** They arrive on the keys the sender had them on and the
-- badge is the only thing holding them back, so taking the badge off is the moment they start
-- working. It used to say the opposite, truthfully: what arrived sat on a number the build skipped,
-- so accepting could not reach a key. That number is gone
-- (`building-export-import.md` 12절) and the sentence went with it.
L["APPROVE_ALL_IMPORT_DESC"] = "Accepts everything that is still waiting, wherever it went, including other specializations. They start working on the keys they came in on. If any of those is a key you already use, you will be asked what to do about it first."
-- Asked once for the whole batch, when accepting would take keys the reader is using.
--
-- **Two doors reach it and the sentence has to be true from both** (2026-08-23, 소유자). [Accept
-- all] takes every badge in the profile, so it opened "%d actions are waiting" - which the storage
-- tab's [Add and Accept] makes false twice over: nothing was waiting, since that press is what put
-- them there, and the count is what that press placed rather than the backlog. What both have in
-- common is the moment: some keys are about to change hands.
--
-- **Two numbers, and they count different things.** The first is how many actions start working,
-- which is what the reader pressed for. The second is how many of their own are standing on the
-- contested keys, which is what the answer decides the fate of.
--
-- **Both count actions** (2026-08-23, 소유자). The second one counted key groups, on the grounds
-- that a group is the unit at risk - taking a key off four actions leaves four loose ones and no
-- record that they went together (`KEY_GROUP_CONFLICT_UNBIND_DESC`). A group is not a thing the
-- reader has ever been shown a count of, though, and two numbers in one sentence counting two
-- different units is a sentence nobody can read at speed.
--
-- **And a hedge went with it.** It read "some of them came in on keys you already use", which is a
-- vague quantity standing in front of an exact one. There was nothing for the vagueness to cover
-- once both numbers count the same thing.
--
-- **The question asks who gets the key, not what happens to one side.** It read "What should happen
-- to yours?" while the answers were two, and stayed there when a third was added - at which point
-- [Merge] was not an answer to the question above it. Every one of the three names a winner, so the
-- question has to be the one they all answer.
L["APPROVE_ALL_OCCUPIED"] = "|cnHIGHLIGHT_FONT_COLOR:%1$d|r actions are about to take the keys they came in on, and |cnHIGHLIGHT_FONT_COLOR:%2$d|r of yours are on those keys already.|n|nWho gets those keys?"
-- **The answer that changes nothing of what is already there**, and first because that is where
-- Enter lands.
--
-- **`Existing` and not `Mine`.** The pair with `Incoming` is exact - the two words name the two
-- sides and neither claims anything about them. `Mine` claims one thing that is not always true:
-- what came in can be the reader's own backup (`Create` makes a payload out of this profile), and
-- then both sides are theirs and the label says otherwise. That is the same fault `Theirs` was
-- turned down for on the other button.
L["APPROVE_ALL_KEEP_EXISTING"] = "Keep Existing"
-- What the label cannot say: **the incoming ones still arrive.** This answer is about the key, not
-- about whether to take them - the reader already pressed accept - so what steps aside is the key
-- and they land unbound. That is the state everything used to arrive in before an arrival kept the
-- key it was sent on (`building-export-import.md` 12절).
--
-- **And that it is only the contested keys.** Anything that came in on a key nobody was using takes
-- that key whichever of the three is pressed.
L["APPROVE_ALL_KEEP_EXISTING_DESC"] = "Only on the keys you are already using. What came in on those ends up with no key at the bottom of the list, where you can give it one. Anything that came in on a free key takes that key either way."
-- The other exclusive answer. **`Take` rather than `Overwrite`** - nothing is deleted and your
-- actions only lose the key, so a word that says "destroyed" would have to be walked back by its own
-- tooltip. It also puts both labels on one axis: each of the three names what ends up on the key,
-- and the reader reads the set instead of each label.
L["APPROVE_ALL_TAKE_INCOMING"] = "Take Incoming"
-- The other answer, and the design note always had the two side by side. **The same set as
-- [Accept all], opposite verb** - two items standing together must not quietly mean different
-- amounts.
--
-- **The pair is accept/reject, and it must not be crossed with keep/discard.** Both are pairs the
-- reader already owns, so borrowing one word from each leaves them looking for the missing halves.
--
-- **Not keep/discard, because "keep" would say the thing is already running** - it asks whether to
-- let something continue, and the one fact quarantine exists to establish is that none of this is
-- doing anything yet. The button would contradict the badge. ("Reject" not naming the removal is
-- the smaller cost, and the prompt below spends one clause on it.)
L["REJECT_ALL_IMPORT"] = "Reject all"
L["REJECT_ALL_IMPORT_DESC"] = "Removes everything that is still waiting, wherever it went. The string it came from stays in the Import tab, so you can bring it in again."
-- **Why [Move to] and [Copy to] are dead on the multi-selection menu.** Neither names the act, since
-- one string stands on both - and a sentence naming it would have to be two, saying the same thing
-- about the same rows.
--
-- **Two of them, because the way out differs.** With some of the picked rows still waiting, the
-- selection is what to change; with all of them waiting there is nothing to take out of it, so what
-- is left to do is accept, and that item is two rows further down the same menu.
--
-- Neither says why moving is refused. The reason is that what arrived is ordered the way its sender
-- ordered it, which is a sentence about machinery the reader has no reason to hold - and the answer
-- to "why not" is the same in both cases anyway: it has not been accepted yet.
-- The third scope [Assign a key] is offered at, after a row (`ACTION_SET_KEY_DESC`) and a heading
-- (`KEY_HEADER_SET_KEY_DESC`). **The label is the same three words in all three**, since the act is
-- one act and the same window opens; the scope is what the three tooltips are for.
--
-- **The second half is the row's warning, and it is needed more here than there.** A selection can
-- hold part of a key group, so the rows left behind are ones the reader chose not to pick rather
-- than ones they never saw - and a key coming apart shows nothing at all until both halves fire.
L["BULK_SET_KEY_DESC"] = "Sets one key for everything you picked, in one go.|n|nRows sharing a key with something you did not pick are left on it. Both keys still work; they just stop working as one."
L["BULK_BLOCKED_ALL_IMPORTED"] = "None of what you picked has been accepted yet. That has to come first."
L["BULK_BLOCKED_SOME_IMPORTED"] = "Some of what you picked has not been accepted yet. Take those rows out of the selection."
-- A single row's [Move to] and [Copy to] on something not accepted yet. `BULK_BLOCKED_ALL_IMPORTED`
-- speaks of "what you picked", and a row somebody right-clicked is not a pick.
L["MOVE_BLOCKED_IMPORTED"] = "This has not been accepted yet. That has to come first."
-- **Why an item is dead on the menu over several rows**: it belongs to one action at a time
-- (importance, the known condition, the two macro items). The way out is the selection, so that is
-- what the sentence says; why each of those cannot go on many is not the reader's question here.
L["MENU_BLOCKED_ONLY_ONE"] = "This can only be changed on one action at a time. Pick just one."
-- Dead because some of the picked rows cannot carry this at all, as a macro takes no target. The way
-- out is the one `BULK_BLOCKED_SOME_IMPORTED` gives, and in the same words.
L["MENU_BLOCKED_SOME_CANNOT"] = "Some of what you picked cannot have this. Take those rows out of the selection."
-- After a row's label on the menu over several rows, **only where the picked rows disagree**: how
-- many of them hold this. The title above already says how many were picked, so the number reads
-- against it without a word.
L["MENU_MIXED_COUNT"] = "(%d)"
-- The single one, from a row's right-click menu.
L["REJECT_IMPORT"] = "Reject"
-- **The second sentence is the whole reason this has a tooltip**, and it is the one [Reject all]
-- ends on: what makes the item pressable is that the arrival is still in the drawer. Only the first
-- half had to be rewritten, because this one is aimed at a single row.
--
-- Its opposite number is `ORDER_ACCEPT_DESC`, which the menu borrows from the row's accept button.
-- There was nothing to borrow for this half - no row carries a reject button.
L["REJECT_IMPORT_DESC"] = "Removes this one. The string it came from stays in the Import tab, so you can bring it in again."
-- **The second sentence is what makes this pressable.** Without it this reads as the destructive
-- half of the pair, when it is in fact the reversible one - accepting is what cannot be undone.
L["REJECT_IMPORT_CONFIRM"] = "Reject |cnHIGHLIGHT_FONT_COLOR:%d|r actions that came in and have not been accepted?|n|nThey are removed, but the string they came from stays in the Import tab, so you can bring it in again."
--- The one-shot in the options menu. **A sweep of what the reader already has**, not of what is
--- arriving - two payloads made by the same person share their account layer, and bringing both in
--- leaves that layer holding the same action twice.
---
--- "Duplicate" and not "identical": the client uses neither on a button, and between the two only
--- one says the second copy is redundant rather than merely alike.
L["REMOVE_DUPLICATES"] = "Remove Duplicate Actions"
--- Three things the label has no room for, and each of them changes what the reader expects.
---
--- **Which two count as the same one**: everything about the action including the key, so two on
--- different keys are two bindings and stay.
--- **How far it looks**: inside one layer only. The same action on the general layer and on a
--- specialization layer is the stack this addon is for, not a mistake.
--- **What it keeps**: the one that fires first, so nothing about what a key does moves.
L["REMOVE_DUPLICATES_DESC"] = "Looks for actions that are exactly the same - same key and all - sitting in the same layer, and removes the extra copies. The one that fires first stays. The same action on two different layers is left alone: that is how a specialization overrides the general list."
--- Pressed on a profile with nothing to find. **A line rather than a box** - there is nothing to
--- confirm and nothing to look at, and a dialog saying "no" is a dialog to dismiss.
-- **말줄임표는 창이 뜬다는 뜻이 아니라 더 물어본다는 뜻이다.** 이 줄은 무엇으로 바꿀지를
-- 골라야 끝나므로 옆의 MOVE_TO / COPY_TO와 같은 꼴이다. EDIT_MACRO와 CONVERT_TO_MACRO_TEXT는
-- 창이 뜨지만 더 묻는 것이 없어서 안 단다.
L["REPLACE_ACTION"] = "Replace..."
--- 무엇을 고른 **뒤에** 서는 확인 창이라, 머리줄이 바꿀 것의 이름을 댈 수 있다. 고르기 전에는
--- 못 하던 것이고, 이 창이 언제나 설 수 있는 이유이기도 하다.
L["REPLACE_CONFIRM_ONE"] = "Replace this action with |cnHIGHLIGHT_FONT_COLOR:%s|r?"
L["REPLACE_CONFIRM_MANY"] = "Replace |cnHIGHLIGHT_FONT_COLOR:%d|r actions with |cnHIGHLIGHT_FONT_COLOR:%s|r?"
--- 목록에 들어가는 이름은 메뉴가 쓰는 것 그대로다(`TARGET_UNIT`, `CONDITION_KNOWN`). 읽는
--- 사람이 거기서 정해둔 것이라, 낱말이 다르면 무엇을 잃는지 찾아야 한다.
---
--- **"conditions"라고 못 적는다.** 대상은 조건이 아니다. 둘을 덮는 낱말이라야 한다.
L["REPLACE_CONFIRM_LOSES"] = "The following settings are removed:"
--- **목록 밖에 따로 선다.** 설정이 아니라 액션의 몸통이고, 다시 치는 것 말고는 돌아올 길이
--- 없는 유일한 것이라 무게가 다르다.
L["REPLACE_CONFIRM_MACROTEXT"] = "A Custom Macro's body is not kept."
L["REMOVE_DUPLICATES_NONE"] = "No duplicate actions to remove."
--- **The count is the whole question.** Naming them would be the same name repeated, which is what
--- a duplicate is.
---
--- **And it says nothing is lost**, which is what makes one press over rows the reader has not
--- looked at offerable at all: every one of these has a twin staying behind.
L["REMOVE_DUPLICATES_CONFIRM"] = "Remove |cnHIGHLIGHT_FONT_COLOR:%d|r duplicate actions?|n|nEach one is an exact copy of another in the same layer, and the copy that fires first is staying. Nothing your keys do will change."
-- **The filter dropdown, one tick per value.** Two axes, and each is written out value by value
-- rather than as one switch that hides a side, so that every tick means the same thing: show this
-- too. A switch called "off-spec" would mean the opposite of its neighbours - ticking it would add
-- rows where ticking the others removes them.
--
-- The client's own shape, from the collection windows: [Collected] / [Not Collected] side by side,
-- all ticked to begin with, and untick everything on one axis and the list is honestly empty.
--
-- **Title Case, because that is what the client's filter items use** - [Collected] / [Not Collected]
-- / [Usable Items] in the collection windows, and `NOT_BOUND` below is one of those strings.
--
-- **Layers, not specializations.** The layers do not match specializations one to one: General,
-- the class and the character apply in every one, and each specialization has two of its own. A
-- row on a live layer whose own condition leaves this specialization out stays on the active side
-- (2026-09-15, owner). "Specialization" here filed it with the other specializations' layers, and
-- the reader took it for something that comes back by itself.
--
-- Both plural: several layers are active at once.
L["FILTER_ACTIVE_LAYER"] = "Active Layers"
L["FILTER_INACTIVE_LAYER"] = "Inactive Layers"
-- The key axis. **Three values, and none of them overlaps another**: an action either presses on a
-- key, or is waiting to be accepted, or is neither.
--
-- **The word carries "key" with it.** The client's `NOT_BOUND` was tried here and taken back out:
-- there it stands beside a `Key:` label that supplies the subject, and alone in a list "Bound"
-- reads as soulbound first. `OVERVIEW_EMPTY` already says it the way that closes - "No key is
-- bound yet".
--
-- **Not "assigned", though the addon says that too.** [Assigned Target] has that word in this same
-- window, and one word naming two things on one screen is how a reader ends up thinking there is
-- a connection.
--
-- "No Key Bound" is narrower than it sounds: what is waiting to be accepted has no key either, and
-- the line below carries that. The three standing together is what makes it read - a reader picking
-- among three does not take one of them for the whole.
L["FILTER_KEYED"] = "Key Bound"
L["FILTER_UNKEYED"] = "No Key Bound"
-- **"Accepted" is the word the rest of the import uses** (`APPROVE_IMPORT`, `LINE_TOOLTIP_IMPORTED`),
-- so this is not a new idea for the reader - it is the same state named where it can be filtered on.
L["FILTER_PENDING"] = "Not Accepted Yet"
-- Empty right-hand list because a filter took everything out. **Different from the search one**:
-- that reader knows what they typed, and this one has to open the dropdown to see which value is
-- switched off.
L["NO_ACTIONS_MATCH_FILTERS"] = "Nothing in this tab matches the filters. The dropdown above the left column has what is switched off."
-- Empty left-hand column for the same reason. Different from the one above: that list is one tab,
-- this one is the whole keyboard.
L["OVERVIEW_EMPTY_FILTERED"] = "Nothing matches the filters. The dropdown above this column has what is switched off."
-- Everything picked turned out to have nowhere to go - the same two causes as
-- `IMPORT_COMMITTED_SKIPPED`, with nothing left over to report a count against.
L["IMPORT_NOTHING_PLACED"] = "Nothing came in - none of what you picked has anywhere to go here."
-- **Said out loud because the screen barely moves.** What just arrived is bound to nothing, so a
-- press that did a lot looks like a press that did nothing.
--
-- **It used to end "look for the glowing icons", and nothing glows.** The badge is a colour on the
-- name and a dot on the icon, and even when that was closer to true it was the wrong thing to send
-- somebody hunting for - the actions are scattered by name and by key, which is why the strip
-- exists. So the line points at where the strip stands rather than describing any art.
--
-- It says the position, not the words on the controls: renaming either of them must not turn this
-- sentence into a pointer at something that is not there.
-- The other way in. **Both halves are said** because a string can hold either kind: what the sender
-- had on a key is on that key now, and what they had not bound yet cannot be, so it lands the same
-- way everything else does.
L["IMPORT_COMMITTED_KEYED"] = "Brought in %d actions on the keys they came with. Anything that arrived without one is unbound until you give it a key."
L["IMPORT_COMMITTED"] = "Brought in %d actions. They are pending until you accept them - a row for doing that is now at the top of the window."
-- **Two things reach this and neither is the reader's doing**, so it names both rather than picking
-- one: a specialization this character's class does not have, and a layer a newer Debind invented.
-- It used to say only the second, and the first is the one that actually turns up.
L["IMPORT_COMMITTED_SKIPPED"] = "%d of them had nowhere to go here and were left out - a specialization this character does not have, or a layer this version does not know."
-- The right-click menu on an action in the preview. **Taking things out is the only edit an entry
-- has**, so these two are the whole menu.
--
-- "This action" rather than the action's name: the row is under the cursor and the menu is over
-- it, so naming it again would be the menu reading the screen back.
L["STORAGE_DELETE_ACTION"] = "Delete this action"
-- The other item. %d is what is ticked, which starts as everything in the entry - so the number is
-- usually large and is usually not a number the reader chose.
L["STORAGE_DELETE_SELECTED"] = "Delete %d selected"
-- Which is why two or more ask. One does not: a menu is already enough hands not to reach by
-- accident, and the second look is for the count rather than for the act.
L["STORAGE_DELETE_SELECTED_CONFIRM"] = "Take %1$d actions out of this? They do not come back - you would have to make it again."
-- The door that makes a row out of what this character has right now, beside the one that makes a
-- row out of a code somebody sent.
--
-- **The thing has a name now, and the name is the code's** (2026-08-23, 소유자). 12절 spent a while
-- looking for a word for what sits in this list and settled on not naming it, on the grounds that
-- the client's own names are each already something else and the free ones are free because nobody
-- uses them. That is overturned: the reader is told the word rather than kept away from it, and the
-- tooltip below is where they are told (`0-DECISION-LOG.md`).
--
-- **`Save` was here for one commit and did not hold.** It reads as the button that keeps a settings
-- screen, which is a thing this window has none of.
--
-- **No object and no range on it.** What this takes is everything the character has, including the
-- specializations they are not playing, so any range it named would be too narrow - and what it
-- makes is the row that appears right above it.
L["STORAGE_CREATE"] = "New Payload"
-- What the word means, on the button that makes one. **A tooltip is read by someone who stopped to
-- ask**, so it has the room to teach a word the list itself only uses.
--
-- **The two lines have two subjects and that is why they are two lines** (2026-08-23, 소유자). This
-- one is about the thing: what a payload is, and what having one is good for. The instruction line
-- under it is about the press. Written as one paragraph they came out as three sentences the reader
-- has to sort by subject as they go.
--
-- It says the two directions rather than the contents: a payload is worth having because it goes
-- somewhere, and both places it goes are one press away on this screen.
L["STORAGE_CREATE_TOOLTIP"] = "A payload is a saved set of actions, kept outside your bindings. Add one to your bindings later, or send it to somebody as a share code."
-- The press, in the line the client keeps for what a click does.
L["STORAGE_CREATE_INSTRUCTION"] = "Click to make one out of everything this character has right now."
-- **Not "Import", which the client owns and spends on something else.** Every one of those buttons
-- takes a code and makes it yours in one press. This one takes a code and puts a row in a list, and
-- nothing the reader has is any different afterwards, so the word would promise the half of the
-- client's gesture that only happens later and on another button (2026-08-22, 소유자).
--
-- Says "Share Code" because `STORAGE_COPY` does, and the two are the same code going opposite ways.
--
-- **It keeps "Paste", where the other one names what it makes.** The two doors are not the same
-- shape: one takes what the reader already has and the other wants something out of their
-- clipboard, and the verb is the part of that they have to know before pressing.
L["STORAGE_PASTE"] = "Paste Share Code"
-- **The button lost its label to an icon, so the verb has to be said again here.** "Paste" was the
-- half of the old label the reader had to know before pressing, and a picture cannot carry it.
--
-- It names the clipboard because that is where the code has to already be: the box that opens has
-- nowhere to get one from, and a reader who presses this without a code in hand has opened a dialog
-- for nothing.
L["STORAGE_PASTE_INSTRUCTION"] = "Click with a share code on your clipboard and it opens the box to paste it into."
-- `HOUSING_BLUEPRINT_COLLECTION_COPY`, on the button doing exactly this job: a saved thing turned
-- into text to hand to somebody.
--
-- **"String" is our word, not the client's, and this key is the first to stop using it.**
-- Measured 2026-08-17: every place the game shows one of these to a player it calls it a **code**
-- - `LOADOUT_ERROR_BAD_STRING` reads "Invalid loadout code",
-- `COOLDOWN_VIEWER_SETTINGS_ERROR_ENTER_IMPORT_STRING_AND_NAME` reads "a valid import code",
-- `HOUSING_BLUEPRINT_IMPORT_SHARECODE_LABEL` reads "Enter Import Code:" - and keeps "string" to
-- its own key names, which is the same line this file is supposed to draw. koKR says 코드
-- throughout.
--
-- **The rest are not renamed, and that is still a finding rather than a decision.** It is a dozen
-- keys across two files and one track's whole vocabulary; ruRU carries none of them, so the cost
-- when it is done is enUS and koKR only.
-- **"With Their Keys" came off** (2026-08-23, 소유자). It named the whole of what the answer decided
-- while an arrival was parked on a number of ours; since the badge became the only thing holding
-- one back, an arrival carries the sender's key from the moment it lands and accepting is what lets
-- that key fire. The clause said what `Accept` already says.
L["STORAGE_ADD_ACCEPTED"] = "Add and Accept"
-- **The second sentence is the same one the other door to that prompt uses**
-- (`APPROVE_ALL_IMPORT_DESC`). One question asked from two places is announced the same way, or the
-- reader meets a prompt one of them never mentioned.
--
-- **No warning that accepting cannot be undone.** True of accepting wherever it is pressed rather
-- than of this item, and a warning on the ordinary choice is what turns a decision into a hazard.
L["STORAGE_ADD_ACCEPTED_DESC"] = "They start working straight away, on the keys they came in on. If any of those is a key you use, you are asked what to do about it first."
-- **What the label leaves out is that nothing of the reader's moves**, which is the reason to pick
-- this item at all: "pending" says they are waiting and says nothing about what happens to the keys
-- already in use.
--
-- It named the row in Overview where a pending arrival is accepted. That is one of three places
-- accepting is offered - the row's own button and its menu are the others - so the sentence was
-- wrong about the only part it added, and the count is on screen the moment the reader gets there.
L["STORAGE_ADD_QUARANTINED_DESC"] = "They go into your bindings doing nothing, and none of your keys change until you accept them."
-- The other item on that menu, and the one the reader wants nine times out of ten.
--
-- **No switch on this tab** (2026-08-23, 소유자). It read "Switched Off Until I Accept Them", which
-- drags a word this addon has a whole tab of into a screen that has nothing to do with one - and
-- promises a thing that flips both ways, where accepting an arrival is a door that only opens one
-- way (`ApproveArrivedActions` is the only writer, and nothing puts the badge back).
--
-- `Pending` is what the overview's button and filter already call this state (`IMPORT_PENDING`).
L["STORAGE_ADD_QUARANTINED"] = "Add as Pending"
L["STORAGE_COPY"] = "Create Share Code"
-- **The destination, because `Add` on its own points at the list.** This said the client's `ADD`,
-- and in the client that word sits on buttons that put a row in a list: add a friend, add to the
-- ignore list. Two buttons under the list on the left already do that here, so a reader looking at
-- a list and a button beside it read the third one as another of those.
--
-- **Not "keys" and not "this character".** Neither is true. Nothing new turns up under a key while
-- an arrival is still pending, and where an action lands is what its own address says, which can be
-- a place every character shares.
--
-- **Not "My Actions"** (2026-08-23, 소유자). The other end of the same press is a payload, which is
-- a set of actions (`STORAGE_CREATE_TOOLTIP`); naming both ends "actions" makes the sentence say a
-- thing goes into itself. What it goes into is the lot of what the reader has.
--
-- **"My Bindings", after a spell as "My Setup"** (2026-08-23, 소유자). Bindings was turned down on
-- the grounds that some actions have no key, and that reading is wrong: the client's own Key
-- Bindings screen lists a command that is not bound, so **unbound is a state inside bindings rather
-- than outside them**. A word is cut for being wrong about the thing, not for being awkward in a
-- corner of it (`writing-user-facing-text.md`) - and following the corner left `Setup`,
-- which is a word of ours that says less. This one is the client's, it is what this window edits,
-- and the item's own tooltip was already saying it.
--
-- **It breaks off, because the press asks rather than acts** (2026-08-23, 소유자). The two ways the
-- actions can land are the reader's to pick, so the menu finishes the sentence the label starts.
L["STORAGE_ADD"] = "Add to My Bindings..."
-- **The date has to say which date it is.** The row shows it bare, where it is one of two lines
-- and the reader is scanning rather than reading; the tooltip is where somebody stops to ask, and
-- an unlabelled number there answers "made", "pasted" and "today" equally well.
--
-- Which word applies is which way the entry got here, and the character name is what says so: only
-- an entry made on this account carries one.
L["STORAGE_ENTRY_MADE"] = "Created %s"
L["STORAGE_ENTRY_RECEIVED"] = "Received %s"
-- The tab. **A place, not the thing kept in it** - the client has no empty word for one of these
-- (Blueprint, Layout and Loadout are each already something else) and naming a place needs none.
--
-- The client's own word for a tab holding what you own and have not put anywhere yet is
-- `HOUSE_EDITOR_CATALOG_STORAGE_TAB`, the housing catalog's. **Three locales come off that one
-- string**, which is what settled it against counting the word on its own - "보관함" is 65 lines
-- in koKR and almost none of them are this in enUS.
--
-- It is also the AddOns list name of the addon that keeps the payloads, and that was known and
-- taken: the two never stand on one screen (12절 of `building-export-import.md`).
L["STORAGE_TITLE"] = "Storage"
-- The header over actions this version has no layer for: a specialization number past the end of
-- the class they came from, which only a hand-edited string carries. **They are drawn rather than
-- dropped**, so what the preview counts is what the string holds - and adding them puts them
-- nowhere, which is the number said separately after a press.
L["STORAGE_PREVIEW_ELSEWHERE"] = "Nowhere to put these"
-- The right column's resting state: nothing picked. **It said "pick something"** because the thing
-- in the list had no name to call it by, which is what a screen that will not name its object is
-- reduced to. It has one now (`STORAGE_CREATE`), so the sentence says which thing to pick.
L["STORAGE_NOTHING_PICKED"] = "Pick a payload on the left to see what is in it."
L["STORAGE_MENU_DESC"] = "Where payloads are kept: ones you save from this character, and ones you paste in from somebody else.|n|nAdding one puts its actions in as pending, so none of your keys change until you accept them."

-- The drawer. **It is a place things pile up in, not a wizard**, so the empty state says what fills
-- it rather than what to do next - there is no next step until something is in there.
--
-- **The instruction came out when the button moved** and stays out for a second reason now. It stood
-- in the far bottom corner and this sentence was the only thing pointing at it; the two ways in are
-- portraits in the tab's corner since then, and a sentence pointing at one of those would have to
-- spell out a picture to say which. What is left is the half a visible button cannot say: that
-- anything landing here stays.
L["IMPORT_DRAWER_EMPTY"] = "Nothing here yet.|n|nA string you paste will sit here until you decide what to do with it, and it is kept afterwards - so you can come back and finish later."
L["IMPORT_PASTE_TITLE"] = "Paste a Debind string"
-- The two halves of the game's own import dialog, which this one is shaped after: a caption over
-- the box, and the instruction **inside** it. The caption names what the box holds; the
-- instruction says what to do and then gets out of the way the moment anything is typed. Blizzard
-- runs them as "Import Text" over "Paste loadout code here" - the caption deliberately does not
-- repeat the instruction, and the instruction deliberately does not repeat the title.
L["IMPORT_PASTE_INPUT_LABEL"] = "Text to import"
L["IMPORT_PASTE_INSTRUCTIONS"] = "Paste the Debind string here"
-- **A name, not a sender.** It asked "Who it came from", which presumes something the game cannot
-- do: no string is sent anywhere. One is copied off a page, out of a chat window, out of your own
-- notes - and the reader pasting their own backup had nothing to put there, which is the case a
-- name is worth most in. The client asks beside its own paste box and asks for a name
-- (HUD_CLASS_TALENTS_IMPORT_DIALOG_NAME_LABEL, "New Loadout Name").
--
-- No noun in front of it: the dialog title says what is being named.
L["IMPORT_PASTE_NAME"] = "Name (optional)"
-- **The client's own, taken whole.** Its loadout import dialog is this dialog - a box to paste
-- into, an optional name beside it, one button to finish - and that button is this global. So the
-- word is the game's in every locale and stays the game's if it ever changes it; enUS assigns it
-- and no other locale file carries the key.
--
-- It read "Add to drawer", which named a place nothing on screen is called and made the press
-- sound like filing rather than importing. The tab is Import and this is the button that does it.
L["IMPORT_PASTE_ACCEPT"] = HUD_CLASS_TALENTS_IMPORT_LOADOUT_ACCEPT_BUTTON
-- Two things about an entry, side by side. The row's second line puts the date in front of the
-- counts and the delete prompt puts the sender in front of the date, so what fills the two is the
-- caller's. **Two of the same conversion, so they are numbered** - a locale that wants them the
-- other way round can swap them, and unnumbered the swap would silently print them in the wrong
-- order.
L["IMPORT_ENTRY_LINE"] = "%1$s  %2$s"
L["IMPORT_ENTRY_COUNTS"] = "%1$d keys, %2$d actions"
-- The free text typed at paste time, on the row's tooltip. **The only human writing about an
-- entry**, and optional - so it is a line that may not be there rather than the name the entry is
-- known by. The class it came from is in that name already (`IMPORT_ENTRY_LINE`), which is why the
-- line that used to say it here is gone.
-- **The first line is the title**: this popup has no title bar, so it is what the reader reads
-- first and it has to name what goes.
--
-- **It said "from the drawer".** Nothing on this screen is called a drawer - the tab says Import
-- and the list has no name - so the phrase asked the reader to remove something from a place they
-- have never been shown. What it is being removed from is this list, and the popup is standing on
-- top of it.
L["IMPORT_DELETE_CONFIRM"] = "Remove |cnHIGHLIGHT_FONT_COLOR:%s|r?|n|nThis is the only copy. Anything you already added to your bindings stays where it is."
-- **Four, where the decoder reports eight.** Each of its reasons is a different step, but a reader
-- has three things they might do about one - look again at what they pasted, update, ask for it
-- again - and a sentence per step would spread those three over eight that all end the same way.
-- The mapping is `REASON_TEXT` in `StorageUI.lua`.
L["IMPORT_FAILED_NOT_OURS"] = "That is not a Debind string."
L["IMPORT_FAILED_TOO_NEW"] = "That string was made by a newer version of Debind. Update and try again."
-- The same refusal pointing the other way, and it must not borrow the sentence above: updating is
-- what the reader already did. There is nothing for them to do here, so this says so rather than
-- asking - and it says where the string can still be used, because it can.
L["IMPORT_FAILED_TOO_OLD"] = "That string was made by a version of Debind too old for this one to read.|n|nNothing you can do here changes that. The string still works in the version it came from."
L["IMPORT_FAILED_DAMAGED"] = "That string is a Debind string but could not be read. It was most likely copied only part of the way - ask for it again and copy the whole thing."
L["IMPORT_FAILED_LIBS_MISSING"] = "Debind Storage could not load the libraries it reads strings with. Downloading Debind again puts them back."
-- **What is missing is what this tab reads, not the tab.** Import and Export are Debind's own
-- panels now; `Debind Storage` is the load-on-demand part that keeps the strings, and without it
-- there is nothing for either to show. Switching it off in the AddOns list is the one way here.
L["PANEL_ADDON_MISSING"] = "This tab reads what |cnHIGHLIGHT_FONT_COLOR:Debind Storage|r keeps, and it could not be loaded.|n|nIf you switched it off, switch it back on in the AddOns list. If it is not in that list at all, install Debind again - Debind Storage comes with it."
-- **One box does both jobs**, so the label says what is true and not what a click would do. It
-- read "Select all" while checked, at the moment a click would put everything down.
--
-- **Both numbers, because one on its own reads as the total.** "Select all (8)" says there are
-- eight here, which is the opposite of what it meant on an entry of 24 with 8 picked.
L["EXPORT_SELECTED_COUNT"] = "%1$d of %2$d selected"
L["EXPORT_EMPTY"] = "There is nothing here to export yet."
L["EXPORT_LAYER_HEADER"] = "%1$s (%2$d/%3$d)"
L["EXPORT_LAYER_COUNT"] = "%d actions"
L["EXPORT_FAILED_LIBS_MISSING"] = "The libraries that build the string are missing, which means the install did not finish. Downloading Debind again brings them back."
L["EXPORT_COPY_TITLE"] = "Copy this string (Ctrl-C)"
