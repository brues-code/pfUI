-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libdebuff ]]--
-- Aura readers over ClassicAPI's C_UnitAuras, which already resolves each
-- aura's caster (sourceGUID) and expiration for non-player units:
--   GetBestAuraCast       - live HoT timers for libpredict
--   UnitDebuff/OwnDebuff  - libdebuff's legacy multi-return signature, still
--                           read by third-party addons (e.g. SuperCleveRoidMacros)

-- return instantly when another libdebuff is already active
if pfUI.api.libdebuff then return end

local libdebuff = {}

-- ============================================================================
-- API: GetBestAuraCast (for libpredict HoT tracking)
-- ============================================================================

-- Report the active aura for spellName on `guid`, read straight from
-- C_UnitAuras. expirationTime is the true, caster-modified remaining time, so
-- no cast-event bookkeeping is needed -- and a unit only ever holds one instance
-- of a given spell, so this is inherently the "best" one.
-- Returns (startTime, duration, timeleft, rank, casterGuid) or nil.
function libdebuff:GetBestAuraCast(guid, spellName)
  if not guid or not spellName then return nil end

  local aura = C_UnitAuras.GetAuraDataBySpellName(guid, spellName)
  if not aura or not aura.expirationTime or aura.expirationTime == 0 then return nil end

  local timeleft = aura.expirationTime - GetTime()
  if timeleft <= 0 then return nil end

  local duration = (aura.duration and aura.duration > 0) and aura.duration or timeleft
  local startTime = aura.expirationTime - duration
  local rank = aura.spellId and tonumber((string.gsub(C_Spell.GetSpellSubtext(aura.spellId) or "", RANK, ""))) or nil

  return startTime, duration, timeleft, rank, aura.sourceGUID
end

-- ============================================================================
-- API: UnitDebuff / UnitOwnDebuff (C_UnitAuras adapters)
-- ============================================================================
-- Remap C_UnitAuras' AuraData onto libdebuff's legacy tuple:
--   effect, rank, texture, stacks, dtype, duration, timeleft, caster

local function AuraToLegacy(aura)
  if not aura then return nil end

  local duration = aura.duration or 0
  local timeleft = -1
  -- Only report a timer for genuinely timed auras. ClassicAPI can leave a
  -- stale expirationTime on permanent (duration 0) auras, so gate on duration.
  if duration > 0 and aura.expirationTime and aura.expirationTime > 0 then
    timeleft = aura.expirationTime - GetTime()
    if timeleft < 0 then timeleft = 0 end
  end

  -- Aura spellId is the specific cast rank, so its subtext is the active rank.
  local rank
  local subtext = aura.spellId and C_Spell.GetSpellSubtext(aura.spellId)
  if subtext and subtext ~= "" then
    rank = tonumber((string.gsub(subtext, "Rank ", "")))
  end

  local dtype = aura.dispelName
  if dtype == "" then dtype = nil end

  local caster = aura.isFromPlayerOrPlayerPet and "player" or "other"

  return aura.name, rank, aura.icon, aura.applications or 0, dtype, duration, timeleft, caster
end

-- id is a 1-based harmful-aura index, matching C_UnitAuras / Blizzard's
-- compacted debuff slots.
function libdebuff:UnitDebuff(unit, id)
  return AuraToLegacy(C_UnitAuras.GetAuraDataByIndex(unit, id, "HARMFUL"))
end

-- Player-cast harmful auras only, via the PLAYER filter -- no manual
-- caster-GUID bookkeeping needed.
function libdebuff:UnitOwnDebuff(unit, id)
  return AuraToLegacy(C_UnitAuras.GetAuraDataByIndex(unit, id, "HARMFUL|PLAYER"))
end

-- add libdebuff to pfUI API
pfUI.api.libdebuff = libdebuff
