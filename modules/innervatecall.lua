-- Innervate Callout Module
-- Announces Innervate casts via raid/party/battleground chat
-- Listens to COMBAT_LOG_EVENT_UNFILTERED - zero polling, pure event-driven

pfUI:RegisterModule("innervatecall", function ()
  -- Only load for druids
  if UnitClassBase("player") ~= "DRUID" then return end

  local INNERVATE_SPELLID = 29166
  local GCD_DURATION = 1.5

  -- Determine chat channel based on group context
  local function GetAnnounceChannel()
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" then
      return "BATTLEGROUND"
    end

    if IsInRaid() then
      return "RAID"
    end

    if IsInGroup() then
      return "PARTY"
    end

    return nil
  end

  -- Set on our cast, cleared once the "ready" timer is scheduled
  local pending = false

  -- Schedule the "ready" announcement once Innervate's own cooldown is in
  -- the spell history. Until then GetSpellCooldown reports only the GCD,
  -- which has no isOnGCD flag here, so tell them apart by duration.
  local function ScheduleReady()
    local cd = C_Spell.GetSpellCooldown(INNERVATE_SPELLID)
    if not cd or cd.duration <= GCD_DURATION then return end

    pending = false
    C_Timer.After(cd.startTime + cd.duration - GetTime(), function()
      local ch = GetAnnounceChannel()
      if ch then
        SendChatMessage(T[">> Innervate is ready <<"], ch)
      end
    end)
  end

  pfUI.events:RegisterFrameEventAndCallback("SPELL_UPDATE_COOLDOWN", function()
    if pending then ScheduleReady() end
  end)

  pfUI.events:RegisterFrameEventAndCallback("COMBAT_LOG_EVENT_UNFILTERED", function()
    -- Innervate is instant, so it logs SPELL_CAST_SUCCESS with its target
    local _, subevent, _, sourceGUID, _, _, _, _, destName, _, _, spellId = CombatLogGetCurrentEventInfo()
    if subevent ~= "SPELL_CAST_SUCCESS" or spellId ~= INNERVATE_SPELLID then return end

    -- Only announce our own casts
    if not IsPlayerGuid(sourceGUID) then return end

    -- Determine channel
    local channel = GetAnnounceChannel()
    if not channel then return end -- solo, no announcement

    SendChatMessage(format(T[">> Innervate cast on %s <<"], destName or T["Unknown"]), channel)

    pending = true
    ScheduleReady()
  end)
end)
