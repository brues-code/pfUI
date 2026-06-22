- Hard dependency on [ClassicAPI](https://github.com/brues-code/ClassicAPI) — modern `C_*` namespaces and engine polyfills (focus, nameplates, GUIDs).
- TBC/Wrath/expansion plumbing removed; vanilla 1.12 + Turtle WoW only.
- Nameplate overhaul — GUID-keyed caches, per-tick allocation cuts, name-collision filtering, configurable name text position.
- Unit auras rebuilt on `C_UnitAuras` — replaces the old tooltip-scraping aura tracker with structured engine data, so buff/debuff durations, stack counts, and source attribution are accurate without polling.
- Equipment manager — new backport of Blizzard's gear-set UI, integrated into the character pane. Save, swap, and edit sets without a third-party addon.
- Bag sorting — new built-in feature (previously pfUI only deferred to third-party sorters).
- `/focus` and `/clearfocus` moved to ClassicAPI; `/focusname` retained in pfUI.
- questitem refactored onto `C_QuestLog`.
- `updatenotify` isolated to its own `pfUI-brues` addon-message prefix so we don't share traffic with upstream pfUI installs.

See full commit history at https://github.com/brues-code/pfUI/commits/master for details.
