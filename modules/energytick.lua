-- One server clock drives every power: Player::RegenerateAll fires every
-- REGEN_TIME_FULL (2s), re-arms with `+=`, and is never reset by casting. The
-- five-second rule (SetLastManaUse on any mana-costing cast) changes what a tick
-- pays, never when it lands; mp5 and the player's MOD_MANA_REGEN_INTERRUPT share
-- still come in. That share can't be computed here -- item sources are equip
-- auras absent from the buff list and m_modManaRegenInterrupt is never sent --
-- so the spark shows it instead: dim through the window until a tick lands.
--
-- The sweep free-runs on that clock and phase-locks to observed gains. A gain
-- mid-sweep (Illumination, Judgement of Wisdom, potions, a Mana Spring totem on
-- its own phase) is not the tick and never moves it.

local FIVE_SECOND_RULE = 5

-- gains farther than this from the predicted boundary are not the tick
local TICK_TOLERANCE = .25

-- arrival jitter; a tick inside this band confirms the sweep rather than
-- re-anchoring it, or the spark hitches at every wrap
local TICK_JITTER = .08

-- Player::RegenerateAll:
--   mod = GetTotalAuraModifier(SPELL_AURA_MOD_ENERGY_REGEN_TIME)
--   if mod > 0 then mod = mod * agility / 10 end
--   m_regenTimer += max(1, REGEN_TIME_FULL - mod)          -- milliseconds
local REGEN_TIME_FULL = 2
local ENERGY_REGEN_TIME_AURA = 217 -- SPELL_AURA_MOD_ENERGY_REGEN_TIME

-- fixed magnitude is basePoints + baseDice (stored 11 -> 12); a die above 1 is
-- a roll the client can't know, so it counts as nothing rather than a guess
local amountCache = {}
local function auraAmount(spellID)
  local amount = amountCache[spellID]
  if amount then return amount end
  amount = 0
  local effects = C_Spell.GetSpellEffectInfo(spellID) -- nil for an id with no record
  if effects then
    for i = 1, 3 do
      local fx = effects[i]
      if fx.auraName == ENERGY_REGEN_TIME_AURA and fx.dieSides <= 1 then
        amount = fx.basePoints + fx.baseDice
        break
      end
    end
  end
  amountCache[spellID] = amount
  return amount
end

-- A passive is in effect exactly while known (current rank only, never in the
-- buff list); anything castable or cast on us counts only while it is up.
local function getEnergyRegenTimeMod()
  local sum = 0
  for _, spellID in ipairs(C_SpellBook.GetPlayerSpellsByAura(ENERGY_REGEN_TIME_AURA)) do
    if C_Spell.IsSpellPassive(spellID) then
      sum = sum + auraAmount(spellID)
    end
  end
  for i = 1, 32 do
    local spellID = select(10, C_UnitAuras.UnitAura("player", i, "HELPFUL"))
    if not spellID then break end
    sum = sum + auraAmount(spellID)
  end
  return sum
end

-- cleared on SPELLS_CHANGED (passives) and PLAYER_AURAS_CHANGED (buffs), and
-- recomputed by the next tick that asks. Agility stays live: it's one call.
local energyRegenTimeMod

local function getAdjustedTickTimer()
  if not energyRegenTimeMod then
    energyRegenTimeMod = getEnergyRegenTimeMod()
  end
  if energyRegenTimeMod == 0 then return REGEN_TIME_FULL end

  -- ms on the server, seconds here; the 1ms floor is the server's and this is a divisor
  local reduction = energyRegenTimeMod * UnitStat("player", 2) / 10000
  return math.max(0.001, REGEN_TIME_FULL - reduction)
end

pfUI:RegisterModule("energytick", function()
  if not pfUI.uf or not pfUI.uf.player then
    return
  end

  local rawborder, default_border = GetBorderSize("unitframes")
  local cbtexture = pfUI.media[C.appearance.castbar.texture]

  -- style is read once: switching it in the GUI needs a /reload, same as the
  -- other structural (not cosmetic) toggles in this file
  local fsrOverlay = C.unitframes.player.fsrstyle == "1"

  -- was this gain the regen tick? if so, re-anchor the sweep on it
  local function lockTick(frame)
    local now, period = GetTime(), getAdjustedTickTimer()

    if frame.start then
      -- signed distance to the nearest predicted boundary
      local err = mod(now - frame.start, period)
      if err > period / 2 then err = err - period end

      if math.abs(err) <= TICK_TOLERANCE then
        -- correct only what lies beyond normal jitter
        if err > TICK_JITTER then
          frame.start = frame.start + (err - TICK_JITTER)
        elseif err < -TICK_JITTER then
          frame.start = frame.start + (err + TICK_JITTER)
        end
        frame.max, frame.rejected = period, nil
        return true
      end

      -- two rejected gains one period apart are the real clock: relock to it
      local periodic = frame.rejected and math.abs(now - frame.rejected - period) <= TICK_TOLERANCE
      if not periodic then
        frame.rejected = now
        return false
      end
    end

    frame.start, frame.max, frame.rejected = now, period, nil
    return true
  end

  -- the bar sweeps its fill over one tick period from a duration object; the
  -- fill is invisible and carries the spark on its edge
  local energytick = CreateFrame("StatusBar", nil, pfUI.uf.player.power.bar)
  energytick:SetAllPoints(pfUI.uf.player.power.bar)
  energytick:SetColorFill(1, 1, 1, 0)
  energytick.sweep = C_DurationUtil.CreateDuration()
  energytick:SetTimerDuration(energytick.sweep, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
  energytick:RegisterEvent("PLAYER_ENTERING_WORLD")
  energytick:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
  energytick:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
  energytick:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  energytick:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  energytick:RegisterEvent("SPELLS_CHANGED")
  energytick:RegisterEvent("PLAYER_AURAS_CHANGED")

  -- the spark hides until a tick is seen, and dims while the rule is up and
  -- nothing has ticked inside it yet
  local function UpdateRule()
    local fsrUp = energytick.mode == "MANA" and energytick.fsr:IsActive()
    energytick.fsrbar:SetShown(fsrUp and energytick:IsShown() and C.unitframes.player.showfsr == "1")
    energytick.spark:SetAlpha(not energytick.start and 0 or (fsrUp and not energytick.fsrGain) and .4 or 1)
  end

  -- the window closed without being re-armed
  local function RuleEnd()
    energytick.fsrSpell, energytick.fsrGain = nil, nil
    energytick.fsr:Reset()
    UpdateRule()
  end

  local function ArmRule()
    energytick.fsr:SetTimeFromStart(GetTime(), FIVE_SECOND_RULE)
    if energytick.ruletimer then energytick.ruletimer:Cancel() end
    energytick.ruletimer = C_Timer.NewTimer(FIVE_SECOND_RULE, RuleEnd)
  end

  -- sweeps the period that holds now and wakes at its end. Rolls over by
  -- whole periods, not from now: restarting bakes timer overshoot into the
  -- phase as drift the lock then has to chase. Runs only while shown; a
  -- hidden bar keeps its phase and catches up as it shows.
  local Sweep
  local function Wrap() Sweep() end
  function Sweep()
    if energytick.wrap then energytick.wrap:Cancel() end
    if not energytick.start or not energytick:IsShown() then return end

    local now = GetTime()
    while now - energytick.start >= energytick.max do
      energytick.start = energytick.start + energytick.max * math.floor((now - energytick.start) / energytick.max)
      energytick.max = getAdjustedTickTimer()
    end

    energytick.sweep:SetTimeFromStart(energytick.start, energytick.max)
    energytick.wrap = C_Timer.NewTimer(energytick.start + energytick.max - now, Wrap)
  end

  energytick:SetScript("OnEvent", function()
    if UnitPowerType("player") == Enum.PowerType.Mana and C.unitframes.player.manatick == "1" then
      this.mode = "MANA"
    elseif UnitPowerType("player") == Enum.PowerType.Energy and C.unitframes.player.energy == "1" then
      this.mode = "ENERGY"
    else
      this.mode = nil
    end

    -- mana regen stops showing at full mana
    this:SetShown(this.mode and not (this.mode == "MANA" and UnitPower("player") >= UnitPowerMax("player")))

    if event == "SPELLS_CHANGED" or event == "PLAYER_AURAS_CHANGED" then
      energyRegenTimeMod = nil
    end

    -- a shift swaps the power the gains are measured on
    if event == "PLAYER_ENTERING_WORLD" or event == "UNIT_DISPLAYPOWER" then
      this.lastPower = UnitPower("player")
    end

    -- the rule arms on the cast (Spell::TakePower: mana powerType, cost > 0),
    -- not on a mana drop -- Mana Burn lowers mana without arming it
    if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
      local cost = C_Spell.GetSpellPowerCost(arg3)
      cost = cost and cost[1]
      if cost and cost.type == Enum.PowerType.Mana and cost.cost > 0 then
        this.fsrSpell, this.fsrGain = arg3, nil
        ArmRule()
      end
    end

    -- Unit::Update won't expire the rule while the spending spell still channels
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" and arg1 == "player" then
      if this.fsrSpell and this.fsrSpell == arg3 then
        this.fsrGain = nil
        ArmRule()
      end
    end

    -- only the shown power: a cat druid's mana regen is not an energy gain
    if event == "UNIT_POWER_UPDATE" and arg2 == this.mode then
      local power = UnitPower("player")
      local diff = this.lastPower and (power - this.lastPower) or 0
      this.lastPower = power

      -- only a gain can be the tick; a spend never touches the phase
      if diff > 0 and lockTick(this) then
        -- a tick inside the window proves regen continues through it
        if this.fsr:IsActive() then
          this.fsrGain = true
        end
        Sweep()
      end
    end

    UpdateRule()
  end)

  energytick.fsr = C_DurationUtil.CreateDuration()

  if fsrOverlay then
    -- classic style: a translucent shade on top of the power bar's own fill,
    -- under the spark
    energytick.fsrbar = CreateFrame("StatusBar", nil, pfUI.uf.player.power.bar)
    energytick.fsrbar:SetAllPoints(energytick)
    energytick.fsrbar:SetColorFill(1, 1, 1, .15)
    energytick:SetFrameLevel(energytick.fsrbar:GetFrameLevel() + 1)
  else
    -- a real bar below the power bar, not an overlay on top of it -- the same
    -- treatment nameplate castbars get relative to the health bar, so the
    -- window can't be mistaken for missing mana
    energytick.fsrbar = CreateFrame("StatusBar", nil, pfUI.uf.player)
    energytick.fsrbar:SetStatusBarTexture(cbtexture)
    energytick.fsrbar:SetPoint("TOPLEFT", pfUI.uf.player.power.bar, "BOTTOMLEFT", 0, -default_border * 2)
    energytick.fsrbar:SetPoint("TOPRIGHT", pfUI.uf.player.power.bar, "BOTTOMRIGHT", 0, -default_border * 2)
    energytick.fsrbar:SetHeight(tonumber(C.unitframes.player.fsrheight) or 4)
    energytick.fsrbar:SetStatusBarColor(GetStringColor(C.appearance.castbar.fsrcolor))
    CreateBackdrop(energytick.fsrbar, default_border)
    CreateBackdropShadow(energytick.fsrbar)
  end
  energytick.fsrbar:SetTimerDuration(energytick.fsr, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
  energytick.fsrbar:Hide()

  -- the bar isn't parented to energytick, so it follows it by hand
  energytick:SetScript("OnShow", function()
    Sweep()
    UpdateRule()
  end)

  energytick:SetScript("OnHide", function()
    Sweep()
    this.fsrbar:Hide()
  end)

  energytick.spark = energytick:CreateTexture(nil, "OVERLAY")
  energytick.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  energytick.spark:SetHeight(C.unitframes.player.pheight + 15)
  energytick.spark:SetWidth(C.unitframes.player.pheight + 5)
  energytick.spark:SetBlendMode("ADD")
  energytick.spark:SetPoint("CENTER", energytick:GetStatusBarTexture(), "RIGHT")
  energytick.spark:SetAlpha(0)

  local hookUpdateConfig = pfUI.uf.player.UpdateConfig
  function pfUI.uf.player.UpdateConfig()
    energytick.spark:SetHeight(C.unitframes.player.pheight + 15)
    energytick.spark:SetWidth(C.unitframes.player.pheight + 5)
    if not fsrOverlay then
      energytick.fsrbar:SetHeight(tonumber(C.unitframes.player.fsrheight) or 4)
      energytick.fsrbar:SetStatusBarColor(GetStringColor(C.appearance.castbar.fsrcolor))
    end
    hookUpdateConfig(pfUI.uf.player)
  end
end)
