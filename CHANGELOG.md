# Initial release

First tagged release of the brues fork of pfUI. Highlights since upstream:

- Hard dependency on [ClassicAPI](https://github.com/brues-code/ClassicAPI) — modern `C_*` namespaces, SuperWoW APIs, and engine polyfills (focus, nameplates, GUIDs).
- TBC/Wrath/expansion plumbing removed; vanilla 1.12 + Turtle WoW only.
- Nameplate overhaul — GUID-keyed caches, per-tick allocation cuts, name-collision filtering, configurable name text position.
- Equipment manager rewrite with mouse-wheel scrolling, GLOBAL_MOUSE_DOWN popovers, and unbounded set count.
- `/focus` and `/clearfocus` moved to ClassicAPI; `/focusname` retained in pfUI.
- libbagsort extracted into its own library; questitem refactored onto `C_QuestLog`.
- `updatenotify` isolated to its own `pfUI-brues` addon-message prefix so we don't share traffic with upstream pfUI installs.

See full commit history at https://github.com/brues-code/pfUI/commits/master for details.
