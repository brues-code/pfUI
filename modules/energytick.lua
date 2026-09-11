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

  -- inside the module body on purpose: C is on pfUI.env, not _G
  local function getBarWidth()
    return C.unitframes.player.pwidth ~= "-1" and C.unitframes.player.pwidth or C.unitframes.player.width
  end

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

  local energytick = CreateFrame("Frame", nil, pfUI.uf.player.power.bar)
  energytick:SetAllPoints(pfUI.uf.player.power.bar)
  energytick:RegisterEvent("PLAYER_ENTERING_WORLD")
  energytick:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
  energytick:RegisterUnitEvent("UNIT_ENERGY", "player")
  energytick:RegisterUnitEvent("UNIT_MANA", "player")
  energytick:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  energytick:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  energytick:RegisterEvent("SPELLS_CHANGED")
  energytick:RegisterEvent("PLAYER_AURAS_CHANGED")

  energytick:SetScript("OnEvent", function()
    if UnitPowerType("player") == Enum.PowerType.Mana and C.unitframes.player.manatick == "1" then
      this.mode = "MANA"
      this:Show()
    elseif UnitPowerType("player") == Enum.PowerType.Energy and C.unitframes.player.energy == "1" then
      this.mode = "ENERGY"
      this:Show()
    else
      this:Hide()
    end

    if event == "SPELLS_CHANGED" or event == "PLAYER_AURAS_CHANGED" then
      energyRegenTimeMod = nil
      return
    end

    if event == "PLAYER_ENTERING_WORLD" then
      this.lastPower = UnitPower("player")
    end

    -- the rule arms on the cast (Spell::TakePower: mana powerType, cost > 0),
    -- not on a mana drop -- Mana Burn lowers mana without arming it
    if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
      local cost = C_Spell.GetSpellPowerCost(arg3)
      cost = cost and cost[1]
      if cost and cost.type == Enum.PowerType.Mana and cost.cost > 0 then
        this.fsrSpell, this.fsrEnd = arg3, GetTime() + FIVE_SECOND_RULE
        this.fsrGain = nil
      end
      return
    end

    -- Unit::Update won't expire the rule while the spending spell still channels
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" and arg1 == "player" then
      if this.fsrSpell and this.fsrSpell == arg3 then
        this.fsrEnd, this.fsrGain = GetTime() + FIVE_SECOND_RULE, nil
      end
      return
    end

    if (event == "UNIT_MANA" or event == "UNIT_ENERGY") and arg1 == "player" then
      local power = UnitPower("player")
      local diff = this.lastPower and (power - this.lastPower) or 0
      this.lastPower = power

      -- only a gain can be the tick; a spend never touches the phase
      if diff > 0 and lockTick(this) then
        -- a tick inside the window proves regen continues through it
        if this.fsrEnd and this.fsrEnd > GetTime() then
          this.fsrGain = true
        end
      end

      -- phase is kept while hidden; OnUpdate catches up by whole periods
      if this.mode == "MANA" and power >= UnitPowerMax("player") then
        this:Hide()
      end
    end
  end)

  energytick:SetScript("OnUpdate", function()
    -- Throttle for performance
    if (this.tick or 0) > GetTime() then
      return
    end
    this.tick = GetTime() + 0.020  -- ~50 FPS

    -- five-second rule drains to nothing
    local remaining = this.fsrEnd and (this.fsrEnd - GetTime()) or 0
    if this.mode == "MANA" and remaining > 0 then
      this.fsrbar:SetWidth(getBarWidth() * remaining / FIVE_SECOND_RULE)
      this.fsrbar:Show()
    else
      this.fsrSpell, this.fsrEnd, this.fsrGain = nil, nil, nil
      this.fsrbar:Hide()
    end

    if not this.start then
      this.spark:SetAlpha(0)
      return
    end

    if this.mode == "MANA" and UnitPower("player") >= UnitPowerMax("player") then
      this.spark:SetAlpha(0)
      return
    end

    this.current = GetTime() - this.start

    -- roll over by whole periods, not from now: restarting bakes frame
    -- overshoot into the phase as drift the lock then has to chase
    if this.current > this.max then
      this.start = this.start + this.max * math.floor(this.current / this.max)
      this.max = getAdjustedTickTimer()
      this.current = GetTime() - this.start
    end

    -- dim while the rule is up and nothing has ticked inside it yet
    this.spark:SetAlpha((remaining > 0 and not this.fsrGain) and .4 or 1)

    if not C.unitframes.player.pheight then
      return
    end

    local pos = getBarWidth() * (this.current / this.max)
    this.spark:SetPoint("LEFT", pos - ((C.unitframes.player.pheight + 5) / 2), 0)
  end)

  energytick.fsrbar = energytick:CreateTexture(nil, "ARTWORK")
  energytick.fsrbar:SetTexture(1, 1, 1, .15)
  energytick.fsrbar:SetPoint("TOPLEFT", 0, 0)
  energytick.fsrbar:SetPoint("BOTTOMLEFT", 0, 0)
  energytick.fsrbar:Hide()

  energytick.spark = energytick:CreateTexture(nil, "OVERLAY")
  energytick.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  energytick.spark:SetHeight(C.unitframes.player.pheight + 15)
  energytick.spark:SetWidth(C.unitframes.player.pheight + 5)
  energytick.spark:SetBlendMode("ADD")

  local hookUpdateConfig = pfUI.uf.player.UpdateConfig
  function pfUI.uf.player.UpdateConfig()
    energytick.spark:SetHeight(C.unitframes.player.pheight + 15)
    energytick.spark:SetWidth(C.unitframes.player.pheight + 5)
    hookUpdateConfig(pfUI.uf.player)
  end
end)
