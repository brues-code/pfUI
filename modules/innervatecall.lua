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
        SendChatMessage(">> Innervate is ready <<", ch)
      end
    end)
  end

  local frame = CreateFrame("Frame")
  frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  frame:SetScript("OnEvent", function()
    if event == "SPELL_UPDATE_COOLDOWN" then
      if pending then ScheduleReady() end
      return
    end

    -- Innervate is instant, so it logs SPELL_CAST_SUCCESS with its target
    -- arg2=subevent, arg4=sourceGUID, arg9=destName, arg12=spellId
    if arg2 ~= "SPELL_CAST_SUCCESS" or arg12 ~= INNERVATE_SPELLID then return end

    -- Only announce our own casts
    if not IsPlayerGuid(arg4) then return end
    local destName = arg9

    -- Determine channel
    local channel = GetAnnounceChannel()
    if not channel then return end -- solo, no announcement

    SendChatMessage(">> Innervate cast on " .. (destName or "Unknown") .. " <<", channel)

    pending = true
    ScheduleReady()
  end)
end)
