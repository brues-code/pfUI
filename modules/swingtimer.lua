pfUI:RegisterModule("swingtimer", function ()
  local rawborder, border = GetBorderSize()

  -- SPELL_QUEUE_EVENT codes (EVENTS.md)
  local ON_SWING_QUEUED       = 0
  local ON_SWING_QUEUE_POPPED = 1

  -- seconds a melee bar stays full after its swing is due, to bridge the gap
  -- until PLAYER_SWING arrives; it then hides unless auto attack goes on
  local GRACE = 0.15

  -- the last half second of a hunter's ranged swing, when moving cancels the shot
  local DEADZONE = 0.5

  -- Consolidate state into a table to avoid Lua 5.0 upvalue limit (32 max)
  local S = {
    mhSpeed = 0, ohSpeed = 0, raSpeed = 0,
    autoAttackActive = false,
    inCombat = false,
    hsQueued = false, cleaveQueued = false, maulQueued = false,
    hsSeenCurrent = false, cleaveSeenCurrent = false, maulSeenCurrent = false,
    isWarrior = false,
    isDruid = false,
    cachedHSSlots = {}, cachedCleaveSlots = {}, cachedMaulSlots = {},
    useSpellQueueEvent = false,
    onSwingCache = {},
    outOfRange = {},  -- by Enum.PlayerSwingType
  }

  local MAINHAND = Enum.PlayerSwingType.MainHand
  local OFFHAND  = Enum.PlayerSwingType.OffHand
  local RANGED   = Enum.PlayerSwingType.Ranged

  -- On-next-swing spells replace the next auto-attack swing.
  -- Covers Raptor Strike, Maul, Mongoose Bite, Holy Strike, etc. automatically.
  local function IsOnSwingSpell(spellId)
    if S.onSwingCache[spellId] ~= nil then return S.onSwingCache[spellId] end
    local result = C_Spell.IsNextMeleeSpell(spellId)
    S.onSwingCache[spellId] = result
    return result
  end

  -- HS / Cleave / Maul are detected dynamically via IsOnSwingSpell (the
  -- SPELL_ATTR_ON_NEXT_SWING bit) + name comparison against the rank-1
  -- canonical names cached below — no per-rank ID maintenance.

  -- Read config
  local sw_width     = tonumber(C.unitframes.swingtimerwidth) or 200
  local sw_height    = tonumber(C.unitframes.swingtimerheight) or 12
  local sw_texture   = C.unitframes.swingtimertexture or "Interface\\AddOns\\pfUI\\img\\bar"
  local sw_showtext  = C.unitframes.swingtimertext ~= "0"
  local sw_showlabel = C.unitframes.swingtimerlabel ~= "0"
  local sw_showoh    = C.unitframes.swingtimeroffhand ~= "0"
  local sw_showranged = C.unitframes.swingtimerranged ~= "0"
  local sw_fontsize  = tonumber(C.unitframes.swingtimerfontsize) or 12
  local sw_hsqueue   = C.unitframes.swingtimerhsqueue ~= "0"
  local sw_showspeed = C.unitframes.swingtimerattackspeed == "1"

  local function ParseColor(str, dr, dg, db, da)
    if not str or str == "" then return dr, dg, db, da end
    local _, _, r, g, b, a = string.find(str, "([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+)")
    if r then
      return tonumber(r) or dr, tonumber(g) or dg, tonumber(b) or db, tonumber(a) or da
    end
    return dr, dg, db, da
  end

  local mhR, mhG, mhB, mhA = ParseColor(C.unitframes.swingtimermhcolor, 0.8, 0.3, 0.3, 1)
  local ohR, ohG, ohB, ohA = ParseColor(C.unitframes.swingtimerohcolor, 0.3, 0.8, 0.3, 1)
  local raR, raG, raB, raA = ParseColor(C.unitframes.swingtimerrangedcolor, 0.3, 0.6, 1.0, 1)
  local rwR, rwG, rwB, rwA = ParseColor(C.unitframes.swingtimerrangedwarncolor, 0.9, 0.0, 0.0, 1)
  local orR, orG, orB = ParseColor(C.unitframes.swingtimeroutrangecolor, 0.5, 0.5, 0.5, 1)
  local isHunter = UnitClassBase("player") == "HUNTER"

  -- the countdown text, cut down to tenths
  local countdown = C_StringUtil.CreateNumericRuleFormatter()
  countdown:AddBreakpoint({ threshold = 0, step = 0.1, rounding = Enum.NumericRuleFormatRounding.Down, format = "%.1f" })

  -- the container keeps the public API
  pfUI.swingtimer = CreateFrame("Frame", "pfSwingTimer", UIParent)
  pfUI.swingtimer:Hide()

  -- A bar fills by itself from `swing`, the time span of the whole swing, and
  -- its text binding counts it down. The marker and its glows ride the edge
  -- of the fill. `shown` is whether the config lets the bar show at all.
  local function CreateSwingBar(name, label, shown)
    local bar = CreateFrame("StatusBar", name, UIParent)
    bar:SetWidth(sw_width)
    bar:SetHeight(sw_height)
    bar:SetStatusBarTexture(sw_texture)
    bar:Hide()
    bar.shown = shown

    bar.swing = C_DurationUtil.CreateDuration()
    bar:SetTimerDuration(bar.swing, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)

    bar.text = bar:CreateFontString("Status", "DIALOG", "GameFontNormal")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
    bar.text:SetTextColor(1, 1, 1, 1)
    bar.text:SetShown(sw_showtext)

    bar.timer = C_DurationUtil.CreateDurationTextBinding()
    bar.timer:SetFontString(bar.text)
    bar.timer:SetDuration(bar.swing)
    bar.timer:SetFormatter(countdown)

    bar.label = bar:CreateFontString("Status", "DIALOG", "GameFontNormal")
    bar.label:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    bar.label:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
    bar.label:SetTextColor(0.8, 0.8, 0.8, 1)
    bar.label:SetText(sw_showlabel and label or "")

    bar.speed = bar:CreateFontString("Status", "DIALOG", "GameFontNormal")
    bar.speed:SetPoint("LEFT", bar, "RIGHT", 4, 0)
    bar.speed:SetFont(pfUI.font_default, sw_fontsize, "OUTLINE")
    bar.speed:SetTextColor(0.8, 0.8, 0.8, 1)
    bar.speed:SetShown(sw_showspeed)

    CreateBackdrop(bar)

    bar.edge = CreateFrame("Frame", nil, bar)
    bar.edge:SetAllPoints(bar)
    bar.edge:Hide()

    bar.marker = bar.edge:CreateTexture(nil, "OVERLAY")
    bar.marker:SetColorTexture(1, 1, 1, 1.0)
    bar.marker:SetWidth(2)
    bar.marker:SetHeight(sw_height)
    bar.marker:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")

    -- Left glow: fades from transparent to white (right edge = marker)
    bar.markerGlowL = bar.edge:CreateTexture(nil, "OVERLAY")
    bar.markerGlowL:SetColorTexture(1, 1, 1, 1)
    bar.markerGlowL:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 0, 1, 1, 1, 0.35)
    bar.markerGlowL:SetWidth(10)
    bar.markerGlowL:SetHeight(sw_height)
    bar.markerGlowL:SetPoint("RIGHT", bar.marker, "LEFT", 0, 0)

    -- Right glow: fades from white to transparent (left edge = marker)
    bar.markerGlowR = bar.edge:CreateTexture(nil, "OVERLAY")
    bar.markerGlowR:SetColorTexture(1, 1, 1, 1)
    bar.markerGlowR:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 0.35, 1, 1, 1, 0)
    bar.markerGlowR:SetWidth(10)
    bar.markerGlowR:SetHeight(sw_height)
    bar.markerGlowR:SetPoint("LEFT", bar.marker, "RIGHT", 0, 0)

    CreateBackdropShadow(bar)
    return bar
  end

  local mainhand = CreateSwingBar("pfSwingTimerMainhand", "MH", true)
  mainhand:SetPoint("BOTTOM", UIParent, "CENTER", -189, 103)
  mainhand.showmarker = true

  local offhand = CreateSwingBar("pfSwingTimerOffhand", "OH", sw_showoh)
  offhand:SetPoint("TOP", mainhand, "BOTTOM", 0, -4)
  offhand.showmarker = true

  -- Hunters fill from the center: the bar drains toward the middle during
  -- the reload, then the auto shot deadzone grows back out in the warn color.
  -- Each phase is a time span of its own on `phase`.
  local ranged = CreateSwingBar("pfSwingTimerRanged", "Ra", sw_showranged)
  ranged:SetPoint("BOTTOM", UIParent, "CENTER", -189, 83)
  ranged:SetFillStyle(isHunter and "CENTER" or "STANDARD")
  ranged.showmarker = not isHunter
  if isHunter then
    ranged.phase = C_DurationUtil.CreateDuration()
    ranged.timer:SetDuration(ranged.phase)
  end

  pfUI.swingtimer.mainhand = mainhand
  pfUI.swingtimer.offhand = offhand
  pfUI.swingtimer.ranged = ranged

  UpdateMovable(mainhand)
  UpdateMovable(ranged)

  -- OH weapon detection: slot 17 (off hand) accepts one-hand (13) and off-hand
  -- weapons (22); main-hand-only (21) can never sit there.
  local OH_WEAPON_TYPES = { [13]=true, [22]=true }
  local function HasOffhandWeapon()
    local invType = C_Item.GetItemInventoryType({ equipmentSlotIndex = INVSLOT_OFFHAND })
    return OH_WEAPON_TYPES[invType] == true
  end

  local function UpdateWeaponSpeeds()
    local ms, os = UnitAttackSpeed("player")
    S.mhSpeed = (ms and ms > 0) and ms or S.mhSpeed
    S.ohSpeed = (HasOffhandWeapon() and os and os > 0) and os or 0
    local rs = UnitRangedDamage("player")
    S.raSpeed = (rs and rs > 0) and rs or 0
  end

  -- HS/Cleave/Maul helpers. Canonical rank-1 spellIDs resolve to the
  -- localized spell name once, so per-spell classification is rank- and
  -- locale-independent without per-rank ID hardcoding (every rank of
  -- Heroic Strike etc. returns the same name).
  local HS_NAME     = C_Spell.GetSpellName(78)    -- Heroic Strike (Rank 1)
  local CLEAVE_NAME = C_Spell.GetSpellName(845)   -- Cleave (Rank 1)
  local MAUL_NAME   = C_Spell.GetSpellName(6807)  -- Maul (Rank 1)

  -- Classify an on-next-swing spell as "hs" / "cleave" / "maul" / nil.
  -- IsOnSwingSpell gates the family (ATTR_ON_NEXT_SWING bit 0x04) so
  -- unrelated spells return nil cheaply.
  local function ClassifyOnSwingSpell(spellId)
    if not IsOnSwingSpell(spellId) then return nil end
    local name = C_Spell.GetSpellName(spellId)
    if name == HS_NAME then return "hs"
    elseif name == CLEAVE_NAME then return "cleave"
    elseif name == MAUL_NAME then return "maul"
    end
  end

  -- Set the queue flags from a ClassifyOnSwingSpell result. nil = no-op
  -- (preserves prior flag state when the queued spell isn't one we
  -- color-code, matching the legacy table-lookup behavior).
  local function SetQueuedKind(kind)
    if not kind then return end
    S.hsQueued     = (kind == "hs")
    S.cleaveQueued = (kind == "cleave")
    S.maulQueued   = (kind == "maul")
    S.hsSeenCurrent, S.cleaveSeenCurrent, S.maulSeenCurrent = false, false, false
  end

  local function RebuildQueueSlotCache()
    if not sw_hsqueue then return end
    S.cachedHSSlots     = {}
    S.cachedCleaveSlots = {}
    S.cachedMaulSlots   = {}
    if not (S.isWarrior or S.isDruid) then return end
    for slot = 1, 120 do
      local kind, id = GetActionInfo(slot)
      local name
      if kind == "spell" then
        name = C_Spell.GetSpellName(id)
      elseif kind == "macro" then
        name = GetMacroSpell(id)
      end
      if name == HS_NAME then
        table.insert(S.cachedHSSlots, slot)
      elseif name == CLEAVE_NAME then
        table.insert(S.cachedCleaveSlots, slot)
      elseif name == MAUL_NAME then
        table.insert(S.cachedMaulSlots, slot)
      end
    end
  end

  local function CheckQueuedAction(slotList)
    for i = 1, table.getn(slotList) do
      if IsCurrentAction(slotList[i]) then return true end
    end
    return false
  end

  -- Reconcile a stale event-driven queue flag against the client's current
  -- action. Not every de-queue emits a SPELL_QUEUE pop — pressing Esc or
  -- re-pressing to cancel an on-swing spell doesn't — so the flag alone stays
  -- set. IsCurrentAction, which the client clears on cancel, is the reconciling
  -- signal, but only after it has confirmed the ability as current at least once
  -- (`seen`): a nampower-initiated cast may never flip IsCurrentAction, and must
  -- keep its color until its own pop/resolve rather than be cleared early.
  -- Returns the updated (queued, seen).
  local function ReconcileQueued(queued, slots, seen)
    if not queued then return false, false end
    if CheckQueuedAction(slots) then return true, true end
    if seen then return false, false end  -- was current, now gone -> cancelled
    return true, false                    -- never confirmed current -> keep
  end

  local function IsHSOrCleaveQueued()
    if not sw_hsqueue or not S.isWarrior then return false, false end
    if S.useSpellQueueEvent then
      S.hsQueued, S.hsSeenCurrent =
        ReconcileQueued(S.hsQueued, S.cachedHSSlots, S.hsSeenCurrent)
      S.cleaveQueued, S.cleaveSeenCurrent =
        ReconcileQueued(S.cleaveQueued, S.cachedCleaveSlots, S.cleaveSeenCurrent)
      return S.hsQueued, S.cleaveQueued
    end
    return CheckQueuedAction(S.cachedHSSlots), CheckQueuedAction(S.cachedCleaveSlots)
  end

  -- The bar colors follow the queued on-next-swing ability, the range state
  -- and the hunter deadzone. Runs on the events that change any of them;
  -- ACTIONBAR_UPDATE_STATE covers the IsCurrentAction reconcile.
  local function UpdateColors()
    local r, g, b = mhR, mhG, mhB
    if sw_hsqueue then
      if S.isDruid and S.useSpellQueueEvent then
        S.maulQueued, S.maulSeenCurrent =
          ReconcileQueued(S.maulQueued, S.cachedMaulSlots, S.maulSeenCurrent)
      end
      if S.maulQueued and S.isDruid then
        r, g, b = 1.0, 0.55, 0.0 -- orange for druid maul queue
      elseif S.isWarrior then
        local hs, cl = IsHSOrCleaveQueued()
        if cl then
          r, g, b = 0.2, 0.9, 0.2
        elseif hs then
          r, g, b = 0.9, 0.9, 0.2
        end
      end
    end
    if S.outOfRange[MAINHAND] then r, g, b = orR, orG, orB end
    mainhand:SetStatusBarColor(r, g, b, mhA)

    if S.outOfRange[OFFHAND] then
      offhand:SetStatusBarColor(orR, orG, orB, ohA)
    else
      offhand:SetStatusBarColor(ohR, ohG, ohB, ohA)
    end

    local a
    if ranged.warn then
      r, g, b, a = rwR, rwG, rwB, rwA
    else
      r, g, b, a = raR, raG, raB, raA
    end
    if S.outOfRange[RANGED] then r, g, b = orR, orG, orB end
    ranged:SetStatusBarColor(r, g, b, a)
  end

  local function StopBar(bar)
    if bar.wake then bar.wake:Cancel() end
    bar.wake, bar.active, bar.graced = nil, nil, nil
    bar.timer:Disable()
    bar:Hide()
  end

  -- a melee bar that is due waits for the next swing; it hides after the
  -- grace unless auto attack goes on, or on the event that stops it later
  local function MeleeGrace(bar)
    bar.graced = true
    if not S.inCombat or not S.autoAttackActive then StopBar(bar) end
  end

  local function MeleeDue(bar)
    bar.edge:Hide()
    bar.wake = C_Timer.NewTimer(GRACE, function() MeleeGrace(bar) end)
  end

  local function RangedDue(bar)
    StopBar(bar)
  end

  -- the hunter's reload is over: the deadzone grows out in the warn color
  local function HunterDeadzone(bar)
    local finish = bar.swing:GetEndTime()
    bar.phase:SetTimeFromEnd(finish, DEADZONE)
    bar:SetTimerDuration(bar.phase, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
    bar.warn = true
    UpdateColors()
    bar.wake = C_Timer.NewTimer(finish - GetTime(), function() RangedDue(bar) end)
  end

  -- Restarts a bar from a PLAYER_SWING reset. `remaining` can be shorter than
  -- the weapon speed (parry haste, ranged wind-up), so the bar length stays
  -- the full swing and the fill starts part-way along.
  local function StartBar(bar, remaining, speed, due)
    if bar.wake then bar.wake:Cancel() end
    local now = GetTime()
    bar.swing:SetTimeFromEnd(now + remaining, math.max(speed, remaining))
    bar.active, bar.graced, bar.warn = true, nil, nil
    if speed > 0 then bar.speed:SetFormattedText("%.2f", speed) end

    if bar.phase then
      if remaining > DEADZONE then
        bar.phase:SetTimeFromEnd(now + remaining - DEADZONE, math.max(speed, remaining) - DEADZONE)
        bar:SetTimerDuration(bar.phase, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
        bar.wake = C_Timer.NewTimer(remaining - DEADZONE, function() HunterDeadzone(bar) end)
      else
        HunterDeadzone(bar)
      end
    else
      bar.wake = C_Timer.NewTimer(remaining, function() due(bar) end)
    end

    UpdateColors()
    if bar.shown then
      bar.edge:SetShown(bar.showmarker)
      if sw_showtext then bar.timer:Enable() end
      bar:Show()
    end
  end

  local function StartMH(remaining)
    UpdateWeaponSpeeds()
    StartBar(mainhand, remaining, S.mhSpeed, MeleeDue)
  end

  local function StartOH(remaining)
    UpdateWeaponSpeeds()
    -- The off-hand attack time stays set with a shield equipped
    if S.ohSpeed <= 0 then return end
    StartBar(offhand, remaining, S.ohSpeed, MeleeDue)
  end

  local function StartRanged(remaining)
    if not sw_showranged then return end
    UpdateWeaponSpeeds()
    if S.raSpeed <= 0 then return end
    StartBar(ranged, remaining, S.raSpeed, RangedDue)
  end

  -- melee bars waiting past their grace hide once auto attack stops
  local function StopWaitingBars()
    if mainhand.graced then StopBar(mainhand) end
    if offhand.graced then StopBar(offhand) end
  end

  local function ResetAll()
    StopBar(mainhand)
    StopBar(offhand)
    StopBar(ranged)
  end

  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_SWING")
  events:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")  -- ClassicAPI: per-slot, equipment-only
  events:RegisterEvent("PLAYER_REGEN_DISABLED")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  events:RegisterEvent("ACTIONBAR_UPDATE_STATE")
  events:RegisterEvent("PLAYER_DEAD")
  events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
  events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  events:RegisterEvent("SPELL_QUEUE_EVENT")
  events:RegisterEvent("START_AUTOATTACK")
  events:RegisterEvent("STOP_AUTOATTACK")

  events:SetScript("OnEvent", function()
    if event == "PLAYER_SWING" then
      -- ClassicAPI tracks the server's swing clock (white hits, on-next-swing
      -- abilities, swing-reset casts, parry haste, extra attacks, weapon
      -- swaps) and hands over the seconds left until the next swing.
      if arg2 == MAINHAND then
        StartMH(arg1)
      elseif arg2 == OFFHAND then
        StartOH(arg1)
      elseif arg2 == RANGED then
        StartRanged(arg1)
      end

    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
      -- arg1 = swingType, arg2 = isInRange, arg3 = checksRange; no check
      -- (no target, nothing to attack, no weapon) is not out of range
      S.outOfRange[arg1] = arg3 and not arg2
      UpdateColors()

    elseif event == "UNIT_SPELLCAST_SENT" then
      -- arg4 = spellID: an on-next-swing ability (HS / Cleave / Maul) queued
      local kind = ClassifyOnSwingSpell(arg4)
      if kind then
        S.useSpellQueueEvent = true
        SetQueuedKind(kind)
        UpdateColors()
      end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      -- arg3 = spellID: the on-next-swing ability resolved, which consumes
      -- the queue, so drop the queued color
      if IsOnSwingSpell(arg3) then
        S.hsQueued = false; S.cleaveQueued = false; S.maulQueued = false
        UpdateColors()
      end

    elseif event == "SPELL_QUEUE_EVENT" then
      local eventCode = arg1 or -1
      local spellId   = arg2 or 0
      if eventCode == ON_SWING_QUEUED then
        S.useSpellQueueEvent = true
        SetQueuedKind(ClassifyOnSwingSpell(spellId))
      elseif eventCode == ON_SWING_QUEUE_POPPED then
        S.hsQueued = false; S.cleaveQueued = false; S.maulQueued = false
      end
      UpdateColors()

    elseif event == "ACTIONBAR_UPDATE_STATE" then
      if sw_hsqueue then UpdateColors() end

    elseif event == "START_AUTOATTACK" then
      S.autoAttackActive = true

    elseif event == "STOP_AUTOATTACK" then
      S.autoAttackActive = false
      StopWaitingBars()

    elseif event == "PLAYER_ENTERING_WORLD" then
      local class = UnitClassBase("player")
      S.isWarrior  = (class == "WARRIOR")
      S.isDruid    = (class == "DRUID")
      UpdateWeaponSpeeds()
      RebuildQueueSlotCache()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
      -- arg1 = changed slot; only weapon slots (main/off/ranged) affect swing speed
      if not INVSLOTS_EQUIPABLE_IN_COMBAT[arg1] then return end
      UpdateWeaponSpeeds()
      if S.ohSpeed == 0 then StopBar(offhand) end
      if S.raSpeed == 0 then StopBar(ranged) end

    elseif event == "ACTIONBAR_SLOT_CHANGED" then
      RebuildQueueSlotCache()

    elseif event == "PLAYER_REGEN_DISABLED" then
      S.inCombat = true
      UpdateWeaponSpeeds()

    elseif event == "PLAYER_REGEN_ENABLED" then
      S.inCombat = false
      S.hsQueued     = false
      S.cleaveQueued = false
      S.maulQueued   = false
      UpdateColors()
      StopWaitingBars()

    elseif event == "PLAYER_DEAD" then
      ResetAll()
    end
  end)

  local function Remaining(bar)
    return bar.active and bar.swing:GetRemainingDuration() or 0
  end

  local function Progress(bar)
    return bar.active and bar.swing:GetElapsedPercent() or 0
  end

  -- -------------------------------------------------------------------------
  -- Public API for external addons (e.g. SCRM)
  -- Only available when the swingtimer module is loaded.
  -- Usage:
  --   if pfUI and pfUI.swingtimer and pfUI.swingtimer.api then
  --     local api = pfUI.swingtimer.api
  --     local mhTimer = api.GetMHTimer()
  --   end
  -- -------------------------------------------------------------------------
  pfUI.swingtimer.api = {
    -- Remaining time in seconds until next swing
    GetMHTimer        = function() return Remaining(mainhand) end,
    GetOHTimer        = function() return Remaining(offhand) end,
    GetRangedTimer    = function() return Remaining(ranged) end,

    -- Weapon speed (full swing duration in seconds)
    GetMHSpeed        = function() return S.mhSpeed end,
    GetOHSpeed        = function() return S.ohSpeed end,
    GetRangedSpeed    = function() return S.raSpeed end,

    -- Whether each timer is currently running
    IsMHActive        = function() return mainhand.active == true end,
    IsOHActive        = function() return offhand.active == true end,
    IsRangedActive    = function() return ranged.active == true end,

    -- Swing progress 0.0 (just reset) to 1.0 (about to swing)
    GetMHProgress     = function() return Progress(mainhand) end,
    GetOHProgress     = function() return Progress(offhand) end,
    GetRangedProgress = function() return Progress(ranged) end,

    -- Warrior HS/Cleave queue state
    IsHSQueued        = function() return S.hsQueued end,
    IsCleaveQueued    = function() return S.cleaveQueued end,
    IsMaulQueued      = function() return S.maulQueued end,
  }

  -- the range event fires only on a change, so read the state once
  local function EnableRangeCheck(swingType)
    C_SwingTimer.EnableRangeCheck(swingType, true)
    S.outOfRange[swingType] = C_SwingTimer.IsTargetWithinSwingRange(swingType) == false
  end
  EnableRangeCheck(MAINHAND)
  if sw_showoh then EnableRangeCheck(OFFHAND) end
  if sw_showranged then EnableRangeCheck(RANGED) end

  UpdateWeaponSpeeds()
  UpdateColors()
end)
