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

**Overrides are named by their values, not by an axis.** Class, specialization and character are what
the rows offer, and "layer" is the code's word for the shape they make.
-->

# What a switch is for

A switch is an on and off value you name yourself. Put it on an action as a condition and that action runs only while the switch is on, leaving the key to another action while it is off, or to nothing at all. Make one with *New Switch* on the *Switches* tab, or with *Switches* in an action's right-click menu, which puts it on that action as it makes it.

Two places take one: *Switches* in an action's menu, where you pick on or off, and a Custom Macro, where you write **[$fishing]** for on and **[no$fishing]** for off.

Work one with a key: put *Switch* on it from the *Special* tab of *Add an Action*, then pick in its menu which switch the key works and whether the press turns that switch on, off or over. A key does it in combat, which is where a switch earns its place. Clicking one on the *Switches* tab turns it over as well, out of combat.

Each switch says what it comes up as when you log in and when you change specialization: *Starts on*, *Starts off*, or *As you left it*. Right-click it on the *Switches* tab to pick that, and to set it differently for one class, one specialization or one character under *Override*. The narrowest one that fits is what counts, and it gets a row under the switch so you can read it off the list.

When the condition menu has nothing for what you want, a switch can work itself out. *Set Automatically* takes a macro conditional such as **[@tank,exists]**, and the switch is on exactly while that is true. One set this way cannot be turned over by hand or by a key.
