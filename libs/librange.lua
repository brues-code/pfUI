-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ librange ]]--
-- A pfUI library that detects and caches distance to units.
--
--  librange:UnitInSpellRange(unit)
--    Returns `1` if the unit is within range, `nil` otherwise.
--
-- Requires SuperWoW's UnitPosition for the friendly scan path. Target
-- range still works via IsActionInRange (vanilla-native) for any class
-- with a known 40y healing spell on the action bar.

if pfUI.api.librange then return end

local _, class = UnitClass("player")
local librange = CreateFrame("Frame", "pfRangecheck", UIParent)

-- 40y spells per class. Only consulted to find an action-bar slot for the
-- IsActionInRange target-range path; the party/raid scan uses UnitPosition.
local spells = {
  ["PALADIN"] = {
    "Interface\\Icons\\Spell_Holy_FlashHeal",
    "Interface\\Icons\\Spell_Holy_HolyBolt",
  },
  ["PRIEST"] = {
    "Interface\\Icons\\Spell_Holy_FlashHeal",
    "Interface\\Icons\\Spell_Holy_LesserHeal",
    "Interface\\Icons\\Spell_Holy_Heal",
    "Interface\\Icons\\Spell_Holy_GreaterHeal",
    "Interface\\Icons\\Spell_Holy_Renew",
  },
  ["DRUID"] = {
    "Interface\\Icons\\Spell_Nature_HealingTouch",
    "Interface\\Icons\\Spell_Nature_ResistNature",
    "Interface\\Icons\\Spell_Nature_Rejuvenation",
  },
  ["SHAMAN"] = {
    "Interface\\Icons\\Spell_Nature_MagicImmunity",
    "Interface\\Icons\\Spell_Nature_HealingWaveLesser",
    "Interface\\Icons\\Spell_Nature_HealingWaveGreater",
  },
}

-- friendly units the scan loop iterates
local units = {}
table.insert(units, "pet")
for i=1,4 do table.insert(units, "party" .. i) end
for i=1,4 do table.insert(units, "partypet" .. i) end
for i=1,40 do table.insert(units, "raid" .. i) end
for i=1,40 do table.insert(units, "raidpet" .. i) end
local numunits = table.getn(units)

local unitcache = {}
local unitdata = {}
local librange_isLoggingOut = false
librange.id = 1

librange:Hide()
librange:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
librange:RegisterEvent("PLAYER_ENTERING_WORLD")
librange:RegisterEvent("PLAYER_LOGOUT")
librange:RegisterEvent("PLAYER_LEAVING_WORLD")
librange:SetScript("OnEvent", function()
  if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
    librange_isLoggingOut = true
    this:SetScript("OnUpdate", nil)
    this:Hide()
    return
  end

  if pfUI_config.unitframes.rangecheck == "0" then
    this:Hide()
    return
  end

  this.interval = tonumber(C.unitframes.rangechecki)/numunits

  if event == "ACTIONBAR_SLOT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    librange.slot = this:GetRangeSlot()
    if UnitPosition then this:Show() end
  end
end)

librange:SetScript("OnUpdate", function()
  if librange_isLoggingOut then return end

  if (this.tick or 1) > GetTime() then return end
  this.tick = GetTime() + this.interval

  while not this:NeedRangeScan(units[this.id]) and this.id <= numunits do
    this.id = this.id + 1
  end

  if this.id <= numunits then
    local unit = units[this.id]
    if not UnitIsUnit("target", unit) then
      local x1, y1, z1 = UnitPosition("player")
      local x2, y2, z2 = UnitPosition(unit)
      if x1 and x2 then
        local distance = ((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2)^.5
        unitdata[unit] = distance < 45 and 1 or 0
      end
    end
    this.id = this.id + 1
  else
    this.id = 1
  end
end)

function librange:NeedRangeScan(unit)
  if not UnitExists(unit) then return nil end
  if not UnitIsVisible(unit) then return nil end
  if CheckInteractDistance(unit, 4) then return nil end
  return true
end

function librange:GetRealUnit(unit)
  if unitdata[unit] then return unit end

  if unitcache[unit] and UnitIsUnit(unitcache[unit], unit) then
    return unitcache[unit]
  end

  for id, realunit in pairs(units) do
    if UnitIsUnit(realunit, unit) then
      unitcache[unit] = realunit
      return realunit
    end
  end

  return unit
end

function librange:GetRangeSlot()
  if not spells[class] then return nil end
  for i=1,120 do
    -- Resolve the slot to a spellID for both spell and macro actions; the old
    -- `not GetActionText` macro-filter missed macros that cast a 40y heal but
    -- displayed a non-spell icon. C_Spell.GetSpellTexture(spellID) gives the
    -- spell's *intrinsic* icon, which is what we match against.
    local kind, id = GetActionInfo(i)
    local spellID
    if kind == "spell" then
      spellID = id
    elseif kind == "macro" then
      local _, _, sid = GetMacroSpell(id)
      spellID = sid
    end
    if spellID then
      local texture = C_Spell.GetSpellTexture(spellID)
      if texture then
        for _, check in pairs(spells[class]) do
          if check == texture then return i end
        end
      end
    end
  end
  return nil
end

function librange:UnitInSpellRange(unit)
  if UnitIsUnit("target", unit) then
    if not librange.slot then return nil end
    return IsActionInRange(librange.slot) == 1 and 1 or nil
  end

  local unit = librange:GetRealUnit(unit)

  if unitdata[unit] and unitdata[unit] == 1 then
    return 1
  elseif not unitdata[unit] then
    return 1
  else
    return nil
  end
end

-- add librange to pfUI API
pfUI.api.librange = librange
