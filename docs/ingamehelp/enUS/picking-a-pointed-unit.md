<!--
**The case that surprises**: a picked Unit Frame or Mouseover is an ordinary picked unit, so with nothing pointed at the action still takes its turn and the press dies there. The way out is a condition on that unit (`devdocs/which-action-a-key-runs.md` §5).

**"Only while you point at nothing" is not offered here.** With the target on that unit, a doesn't-exist condition lets the action run exactly when it has nowhere to go.
-->

# What if the target is Unit Frame or Mouseover?

The action goes only to that unit. While you point at nothing there is no such unit, and the press does nothing, the way an action aimed at your focus does with no focus set.

To hand the press to the next action instead, give the action *When the unit exists* on that unit under *Units*.
