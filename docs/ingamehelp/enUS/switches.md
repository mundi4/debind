<!--
**Why this page exists.** The tab shows what each switch is right now and lets it be turned over, and
nothing on it says what a switch is for. A reader who has not already put one on an action has no way
in.

**The order is make, use, work, and only then what it starts as.** The last two answer a reader who
already has one running, so they cannot stand in front of the two that get them there.

**The automatic kind is one paragraph at the end** (`CUSTOM_STATE_MODE_MACRO_CONDITIONAL`). It is the
one shape of switch a key cannot press, and a reader who never sets it never meets it.

**It opens on what sends a reader there** (2026-09-20, owner): the condition menu holding nothing for
what they want. Nothing on screen says that is what this is for, and without it the paragraph reads
as a second way to do what the menu already does.

**In combat is named on the key rather than on the switch**, because that is where the difference is:
the tab refuses during a fight (`SWITCH_TOGGLE_IN_COMBAT`) and a key does not.

**"Flips" is the word the menu already uses** (`TYPE_SETSTATE_DESC`), so the third choice is named
here the way the reader meets it there.

**The row's button carries both labels** (`SWITCH_TURN_ON`, `SWITCH_TURN_OFF`), named by what the
next click does, and one click flips the Switch either way.

**Switch is a capitalised name here, and lower case everywhere else on screen** (2026-09-22, owner:
it is not a common noun). This page was brought over first; the strings that still write it lower
case are listed in `.zzz/ingame-help.md`.

**Overrides are named by their values, not by an axis.** Class, specialization and character are what
the dropdown offers, and "layer" is the code's word for the shape they make.

**No worked macro** (2026-09-22, owner). The trinket line that stood here was `/use` under a switch
and nothing else, which is a condition asked on a key pressed to use that trinket; it only means
something beside a second line, and a second line costs a spell name that ties this page to one
class. The syntax is already shown where switches go into a macro, and the paragraph above carries
the case in words. Somebody who writes macros does not need the line, and somebody who does not
would not be got there by it.
-->

# What are Switches for?

A Switch is a value of your own, either on or off. Put it on an action as a condition and that action runs only while the Switch is on, leaving the key to the next action while it is off, or to nothing at all. Make one with *New Switch* on the *Switches* tab, or with *Switches* in an action's right-click menu, which makes it and puts it on that action in one step.

A Switch is read as a condition in two places: *Switches* in an action's right-click menu, where you pick on or off, and a Custom Macro, where you write **[$fishing]** for on and **[no$fishing]** for off.

To change one with a key, add a *Switch* action to that key from the *Special* tab of *Add an Action*, then pick in its menu which Switch it changes and whether the press turns that Switch on, turns it off, or flips it. A key does this in combat as well. The button on the Switch's own row, labelled *Turn On* or *Turn Off* by what a click will do, flips it, but not in combat.

*Starts as* on the *Switches* tab sets the value a Switch has after you log in and after you change specialization: *On*, *Off*, or *As you left it*. *Set it for* above it picks what that answer covers: the whole account, one class, one specialization or one character. The narrowest one that fits the character you are on is the one being read, and that one is blue in the list. Set it for one character and only that character starts with the Switch off, while the same action on the same key is untouched everywhere else.

Everything you pick in the condition menu has to be true at once, and some things have no row there at all. *Set automatically* answers both: it takes a macro conditional, and the Switch is on exactly while that is true. **[pet:Felhunter][pet:Voidwalker]** is on while either of those two is out. One set this way cannot be flipped by hand or by a key.