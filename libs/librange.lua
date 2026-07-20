-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ librange ]]--
-- A thin wrapper over ClassicAPI's UnitInRange: a fixed 40y healing-range
-- check computed C-side from unit positions, valid for any unit. There is
-- no cache or scan loop -- the check is cheap enough to run per query,
-- which also sidesteps the staleness a cached scan hit on zone changes and
-- roster re-indexing.
--
--  librange:UnitInSpellRange(unit)
--    Returns `1` if the unit is within range, `nil` otherwise.

if pfUI.api.librange then return end

local librange = {}

function librange:UnitInSpellRange(unit)
  -- _G-qualified: bare `UnitInRange` resolves to pfUI.api.UnitInRange inside
  -- the pfUI environment (which calls us), so this must reach ClassicAPI's
  -- global directly or it recurses.
  local inRange, checked = _G.UnitInRange(unit)
  -- position miss (e.g. a unit outside the client's sync range): we can't
  -- tell, so default to in-range -- matches the old cache's nil behavior.
  if not checked then return 1 end
  return inRange and 1 or nil
end

-- add librange to pfUI API
pfUI.api.librange = librange
