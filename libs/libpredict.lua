-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libpredict ]]--
-- A pfUI library that detects, receives and sends heal and resurrection predictions.
-- Healing predictions are done by caching the last known "normal" heal value of the
-- spell when last being used. Those chaches are cleared when new talents are detected.
-- The API provides function calls similar to later WoW expansions such as:
--   UnitGetIncomingHeals(unit)
--   UnitHasIncomingResurrection(unit)
--
-- The library is able to receive and send compatible messages to HealComm
-- including resurrections. It has an option to disable the sending of those
-- messages in case HealComm is already active.
--
-- Casts are read from ClassicAPI's UNIT_SPELLCAST_* events and heal amounts
-- from COMBAT_LOG_EVENT_UNFILTERED. GetHotDuration() reads live HoT timers
-- from C_UnitAuras (via libdebuff) and falls back to the HealComm-fed table.

-- return instantly when another libpredict is already active
if pfUI.api.libpredict then return end

local heals, ress, events, hots = {}, {}, {}, {}
local spell_queue = { "DUMMY", "DUMMYRank 9", "TARGET" }
local player = UnitName("player")
local cache, gear_string = {}, ""
local foreignCache = {}   -- [casterName][spellKey] = amount, in-memory cache for other healers
local rejuvDuration, renewDuration = 12, 15 --default durations
local ressGuidToName = {} -- [casterGuid] = casterName, for interrupted-cast cleanup
local healGuidToName = {} -- [casterGuid] = casterName, for interrupted-cast cleanup
local sentTargets = {}    -- [castGUID] = target name of an own cast, from UNIT_SPELLCAST_SENT
local castTargets = {}    -- [castGUID] = target name of a foreign cast, from UNIT_SPELLCAST_START
local ress_timers = {}    -- [target][sender] = expiry_timestamp (60s rez window)
local RESS_TIMEOUT = 60   -- Vanilla: rez offer expires after 60s

-- Localized spell names resolved once from canonical rank-1 spellIDs.
-- Every rank shares the same name, so per-rank comparisons elsewhere can
-- be done against these constants without per-locale or per-rank tables.
local PRAYER_OF_HEALING = C_Spell.GetSpellName(596)   -- Prayer of Healing (Rank 1)
local REJUVENATION      = C_Spell.GetSpellName(774)   -- Rejuvenation (Rank 1)
local RENEW             = C_Spell.GetSpellName(139)   -- Renew (Rank 1)
local REGROWTH          = C_Spell.GetSpellName(8936)  -- Regrowth (Rank 1)

local libpredict = CreateFrame("Frame")
libpredict:RegisterEvent("UNIT_HEALTH")
libpredict:RegisterEvent("CHAT_MSG_ADDON")
libpredict:RegisterEvent("PLAYER_TARGET_CHANGED")
libpredict:RegisterEvent("PLAYER_LOGOUT")

libpredict:SetScript("OnEvent", function()
  -- Handle shutdown to prevent crash 132
  if event == "PLAYER_LOGOUT" then
    this:UnregisterAllEvents()
    this:SetScript("OnEvent", nil)
    return
  end
  
  if event == "CHAT_MSG_ADDON" and (arg1 == "HealComm" or arg1 == "CTRA") then
    this:ParseChatMessage(arg4, arg2, arg1)
  elseif event == "UNIT_HEALTH" then
    local name = UnitName(arg1)
    if name and ress[name] and not UnitIsDeadOrGhost(arg1) then
      ress[name] = nil
    end
  end
end)

-- GUID->Name cache for dead players (UnitExists/UnitGUID return nil for corpses)
local guidNameCache = {}  -- [guid] = name

local function resolveNameFromGuid(guid)
  if not guid then return nil end
  if guidNameCache[guid] then return guidNameCache[guid] end
  -- UnitExists(guid) reverse lookup not reliable; cache is primary source
  return nil
end

-- Register with libdebuff hooks
local function cacheRaidNames()
  -- Cache all raid/party members while they are still reachable
  for i = 1, GetNumRaidMembers() do
    local unit = "raid" .. i
    local guid = UnitGUID(unit)
    local name = UnitName(unit)
    if guid and name then guidNameCache[guid] = name end
  end
  for i = 1, GetNumPartyMembers() do
    local unit = "party" .. i
    local guid = UnitGUID(unit)
    local name = UnitName(unit)
    if guid and name then guidNameCache[guid] = name end
  end
  -- player self
  local pguid = UnitGUID("player")
  if pguid then guidNameCache[pguid] = UnitName("player") end
end

local function isRezSpell(spellId)
  if not L["resurrections"] then return false end
  local spellName = C_Spell.GetSpellName(spellId)
  return spellName and L["resurrections"][spellName]
end

-- Build cache on world enter
libpredict:RegisterEvent("PLAYER_ENTERING_WORLD")
libpredict:RegisterEvent("RAID_ROSTER_UPDATE")
libpredict:RegisterEvent("PARTY_MEMBERS_CHANGED")
local origOnEvent = libpredict:GetScript("OnEvent")
libpredict:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" or event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
    cacheRaidNames()
  end
  if origOnEvent then origOnEvent() end
end)

-- Own cast-time spell started (heals + rez)
local function OnOwnCastStart(spellId, castGUID)
  local spellName = C_Spell.GetSpellName(spellId)
  if not spellName then return end

  -- SENT names the unit the cast went out at; self and no-target casts
  -- carry none, so fall back to what the cast hooks recorded
  local target = sentTargets[castGUID] or spell_queue[3]
  local _, _, _, startMs, endMs = C_Spell.CastingInfo()
  local castTime = startMs and endMs - startMs or 0

  libpredict.sender.castGUID = castGUID
  libpredict.sender.delayMs = 0
  libpredict.sender.current_cast = spellName
  libpredict.sender.current_cast_target = target

  if L["resurrections"][spellName] then
    if target then
      libpredict:Ress(player, target, UnitGUID("player"))
      libpredict.sender:SendHealCommMsg("Resurrection/" .. target .. "/start/")
      libpredict.sender:SendResCommMsg("RES " .. target)
      libpredict.sender.resurrecting = true
    end
    return
  end

  spell_queue[1] = spellName
  spell_queue[2] = spellName .. (C_Spell.GetSpellSubtext(spellId) or "")

  if spell_queue[1] == spellName and cache[spell_queue[2]] then
    local amount   = cache[spell_queue[2]][1]
    local casttime = castTime

    if spellName == REGROWTH then
      local fullSpell = spell_queue[2]
      local _, _, rankStr = fullSpell and string.find(fullSpell, "Rank (%d+)")
      local rankNum = rankStr and tonumber(rankStr) or nil
      if libpredict.sender.regrowth_timer then
        libpredict.sender.regrowth_target_next = target
        libpredict.sender.regrowth_rank_next = rankNum
      else
        libpredict.sender.regrowth_target = target
        libpredict.sender.regrowth_rank = rankNum
      end
    end

    if spellName == PRAYER_OF_HEALING then
      -- target is already correctly set from spell_queue[3]:
      -- selfcast (ALT) = player, otherwise = current target
      -- Use this to find the correct group to heal
      local pohTarget = target or player
      if IsInRaid() then
        -- Raid: find pohTarget's subgroup and heal only those members
        -- (Turtle WoW changed PoH to heal the target's group, not the caster's group)
        local targetGroup
        for i = 1, GetNumRaidMembers() do
          local name, _, subgroup = GetRaidRosterInfo(i)
          if name == pohTarget then targetGroup = subgroup break end
        end
        -- Fallback to caster's own group if target not in raid
        if not targetGroup then
          for i = 1, GetNumRaidMembers() do
            local name, _, subgroup = GetRaidRosterInfo(i)
            if name == player then targetGroup = subgroup break end
          end
        end
        if targetGroup then
          for i = 1, GetNumRaidMembers() do
            local name, _, subgroup = GetRaidRosterInfo(i)
            if subgroup == targetGroup then
              libpredict:Heal(player, name, amount, casttime)
              libpredict.sender:SendHealCommMsg("Heal/" .. name .. "/" .. amount .. "/" .. casttime .. "/")
              libpredict.sender.healing = true
            end
          end
        end
      else
        -- Party: heal all party members including self
        libpredict:Heal(player, player, amount, casttime)
        libpredict.sender:SendHealCommMsg("Heal/" .. player .. "/" .. amount .. "/" .. casttime .. "/")
        libpredict.sender.healing = true
        for i = 1, 4 do
          if CheckInteractDistance("party"..i, 4) then
            local pname = UnitName("party"..i)
            libpredict:Heal(player, pname, amount, casttime)
            libpredict.sender:SendHealCommMsg("Heal/" .. pname .. "/" .. amount .. "/" .. casttime .. "/")
            libpredict.sender.healing = true
          end
        end
      end
      return  -- skip the generic Heal call below
    end

    libpredict:Heal(player, target, amount, casttime)
    libpredict.sender:SendHealCommMsg("Heal/" .. (target or "") .. "/" .. amount .. "/" .. casttime .. "/")
    libpredict.sender.healing = true
  end
end

-- Own cast landed: HealStop, Regrowth timer, instant HoTs, own rez timer
local function OnOwnCastSucceeded(spellId, castGUID)
  local target = sentTargets[castGUID] or spell_queue[3]
  sentTargets[castGUID] = nil

  libpredict:HealStop(player)
  local spellName = C_Spell.GetSpellName(spellId)
  if spellName == REGROWTH then
    local now = pfUI.uf.now or GetTime()
    if libpredict.sender.regrowth_timer then
      libpredict.sender.regrowth_start_next = now
    else
      libpredict.sender.regrowth_start = now
    end
    libpredict.sender.regrowth_timer = now + 0.1
  end
  libpredict.sender.castGUID = nil
  libpredict.sender.current_cast = nil
  libpredict.sender.current_cast_target = nil

  if not target then return end

  -- Instant HoTs — classify by name (rank-independent) instead of a
  -- hardcoded per-rank ID table.
  local hotType
  if spellName == REJUVENATION then hotType = "Reju"
  elseif spellName == RENEW then hotType = "Renew"
  end
  if hotType then
    local duration = hotType == "Reju" and rejuvDuration or renewDuration
    local rank = 0
    local rankSub = C_Spell.GetSpellSubtext(spellId)
    if rankSub and rankSub ~= "" then
      rank = tonumber((string.gsub(rankSub, "Rank ", ""))) or 0
    end
    libpredict:Hot(player, target, hotType, duration, nil, "UNIT_SPELLCAST_SUCCEEDED", rank)
    libpredict.sender:SendHealCommMsg(hotType .. "/" .. target .. "/" .. duration .. "/" .. rank .. "/")
  end

  if isRezSpell(spellId) then
    libpredict:RessSetTimer(player, target)
  end
end

-- Foreign cast-time spell started (heals + rez)
local function OnOtherCastStart(unit, spellId, castGUID)
  local spellName = C_Spell.GetSpellName(spellId)
  if not spellName then return end

  local casterGuid = UnitGUID(unit)
  local casterName = resolveNameFromGuid(casterGuid)
  if not casterName then return end

  local targetName = UnitSpellTargetName(unit)
  if not targetName then return end
  castTargets[castGUID] = targetName

  -- Resurrection cast
  if L["resurrections"][spellName] then
    libpredict:Ress(casterName, targetName, casterGuid)
    return
  end

  -- Heal cast: look up cached amount from a previous cast by this healer
  local _, _, _, startMs, endMs = C_Spell.UnitCastingInfo(unit)
  if not startMs then return end
  local castTime = endMs - startMs

  local rankStr = C_Spell.GetSpellSubtext(spellId) or ""
  local spellKey = spellName .. (rankStr or "")

  local amount = foreignCache[casterName] and foreignCache[casterName][spellKey]
  if not amount then return end  -- no data yet, skip until we have a real value

  -- Prayer of Healing: heal entire subgroup of the target
  if spellName == PRAYER_OF_HEALING then
    if IsInRaid() then
      local targetGroup
      for i = 1, GetNumRaidMembers() do
        local rname, _, subgroup = GetRaidRosterInfo(i)
        if rname == targetName then targetGroup = subgroup break end
      end
      if not targetGroup then
        for i = 1, GetNumRaidMembers() do
          local rname, _, subgroup = GetRaidRosterInfo(i)
          if rname == casterName then targetGroup = subgroup break end
        end
      end
      if targetGroup then
        for i = 1, GetNumRaidMembers() do
          local rname, _, subgroup = GetRaidRosterInfo(i)
          if subgroup == targetGroup then
            libpredict:Heal(casterName, rname, amount, castTime, casterGuid)
          end
        end
      end
    else
      -- Party: heal self + all members
      libpredict:Heal(casterName, casterName, amount, castTime, casterGuid)
      for i = 1, 4 do
        local pname = UnitName("party" .. i)
        if pname then
          libpredict:Heal(casterName, pname, amount, castTime, casterGuid)
        end
      end
    end
    return
  end

  libpredict:Heal(casterName, targetName, amount, castTime, casterGuid)
end

-- Foreign cast landed: rez timer, or the predicted heal is fulfilled
local function OnOtherCastSucceeded(unit, spellId, castGUID)
  local casterGuid = UnitGUID(unit)
  local casterName = resolveNameFromGuid(casterGuid)
  if not casterName then return end

  if isRezSpell(spellId) then
    local targetName = castTargets[castGUID]
    if targetName then
      libpredict:RessSetTimer(casterName, targetName)
    end
    return
  end

  libpredict:HealStop(casterName)
end

-- Foreign cast interrupted: remove cancelled resses/heals
local function OnOtherCastInterrupted(unit)
  local casterGuid = UnitGUID(unit)
  if not casterGuid then return end
  local ressName = ressGuidToName[casterGuid]
  if ressName then
    libpredict:RessStop(ressName)
  end
  local healName = healGuidToName[casterGuid]
  if healName then libpredict:HealStop(healName) end
end

libpredict:SetScript("OnUpdate", function()
  -- throttle cleanup - no need to check every frame
  local now = pfUI.uf.now or GetTime()
  if (this.tick or 0) > now then return end
  this.tick = now + pfUI.throttle:Get("libpredict")  -- Default: Normal (10 FPS)

  -- update on timeout events
  for timestamp, targets in pairs(events) do
    if now >= timestamp then
      events[timestamp] = nil
    end
  end

  -- Rez timeout: remove offer after 60s if player doesn't accept
  for target, senders in pairs(ress_timers) do
    for sender, expiry in pairs(senders) do
      if now >= expiry then
        senders[sender] = nil
        if ress[target] then ress[target][sender] = nil end
      end
    end
  end
end)

function libpredict:ParseComm(sender, msg)
  local msgtype, target, heal, time, rank

  if msg == "HealStop" or msg == "Healstop" or msg == "GrpHealstop" then
    msgtype = "Stop"
    -- DEBUG: Log when HealStop received
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[libpredict RX]|r HealStop from " .. tostring(sender))
    end
  elseif msg == "Resurrection/stop/" then
    msgtype = "RessStop"
  elseif msg then
    local msgobj = {strsplit("/", msg)}

    if msgobj and msgobj[1] and msgobj[2] then
      -- legacy healcomm object
      if msgobj[1] == "GrpHealdelay" or msgobj[1] == "Healdelay" then
        msgtype, time = "Delay", msgobj[2]
      end

      if msgobj[1] and msgobj[1] == "Resurrection" and msgobj[2] then
        msgtype, target = "Ress", msgobj[2]
      end

      if msgobj[1] == "Heal" and msgobj[2] then
        msgtype, target, heal, time = "Heal", msgobj[2], msgobj[3], msgobj[4]
      end

      if msgobj[1] == "GrpHeal" and msgobj[2] then
        msgtype, target, heal, time = "Heal", {}, msgobj[2], msgobj[3]
        for i=4,8 do
          if msgobj[i] then table.insert(target, msgobj[i]) end
        end
      end

      if msgobj[1] == "Reju" or msgobj[1] == "Renew" or msgobj[1] == "Regr" then --hots
        msgtype, target, heal, time = "Hot", msgobj[2], msgobj[1], msgobj[3]
        -- NEW: Parse rank (optional, backwards compatible)
        -- Format: "Reju/Target/12/10/" where msgobj[3]=duration, msgobj[4]=rank
        -- "0" = unknown rank (for clients without rank extraction)
        local rankStr = msgobj[4]
        if rankStr and rankStr ~= "" and rankStr ~= "/" and rankStr ~= "0" then
          rank = tonumber(rankStr)
        end
      end
    elseif select then
      -- latest healcomm
      msgtype = tonumber(string.sub(msg, 1, 3))
      if not msgtype then return end

      -- Resolve sender's name to a group unit token so C_Spell can query
      -- the cast. Group rosters are tiny (44 slots max) so the walk is cheap
      -- relative to the cost of receiving a HealComm message.
      local function senderUnit()
        if UnitName("player") == sender then return "player" end
        for i = 1, GetNumPartyMembers() do
          if UnitName("party"..i) == sender then return "party"..i end
        end
        for i = 1, GetNumRaidMembers() do
          if UnitName("raid"..i) == sender then return "raid"..i end
        end
      end

      if msgtype == 0 then
        msgtype = "Heal"
        heal = tonumber(string.sub(msg, 4, 8))
        target = string.sub(msg,9, -1)

        local unit = senderUnit()
        if not unit then return end
        local _, _, _, startMs, endMs = C_Spell.UnitCastingInfo(unit)
        if not startMs or not endMs then return end
        time = (endMs - startMs) / 1000
      elseif msgtype == 1 then
        msgtype = "Stop"
      elseif msgtype == 2 then
        msgtype = "Heal"
        heal = tonumber(string.sub(msg,4, 8))
        target = {strsplit(":", string.sub(msg,9, -1))}
        local unit = senderUnit()
        if not unit then return end
        local _, _, _, startMs, endMs = C_Spell.UnitCastingInfo(unit)
        if not startMs or not endMs then return end
        time = (endMs - startMs) / 1000
      end
    end
  end

  return msgtype, target, heal, time, rank
end

-- Duplicate detection for HoT messages
local recentHots = {}
local DUPLICATE_WINDOW = 0.5  -- Ignoriere gleiche Nachricht innerhalb 0.5s

function libpredict:ParseChatMessage(sender, msg, comm)
  local msgtype, target, heal, time, rank

  if comm == "HealComm" then
    msgtype, target, heal, time, rank = libpredict:ParseComm(sender, msg)
  elseif comm == "CTRA" then
    local _, _, cmd, ctratarget = string.find(msg, "(%a+)%s?([^#]*)")
    if cmd and ctratarget and cmd == "RES" and ctratarget ~= "" and ctratarget ~= UNKNOWN then
      msgtype = "Ress"
      target = ctratarget
    end
  end

  if msgtype == "Stop" and sender then
    libpredict:HealStop(sender)
    return
  elseif ( msg == "RessStop" or msg == "RESNO" ) and sender then
    libpredict:RessStop(sender)
    return
  elseif msgtype == "Delay" and time then
    libpredict:HealDelay(sender, time)
  elseif msgtype == "Heal" and target and heal and time then
    if type(target) == "table" then
      for _, name in pairs(target) do
        libpredict:Heal(sender, name, heal, time)
      end
    else
      libpredict:Heal(sender, target, heal, time)
    end
  elseif msgtype == "Ress" then
    -- HealComm: only for other players (own resses tracked via UNIT_SPELLCAST_START)
    local playerName = UnitName("player")
    if sender ~= playerName then
      local senderGuid
      for i = 1, GetNumRaidMembers() do
        local unit = "raid" .. i
        if UnitName(unit) == sender then
          senderGuid = UnitGUID(unit)
          break
        end
      end
      if not senderGuid then
        for i = 1, GetNumPartyMembers() do
          local unit = "party" .. i
          if UnitName(unit) == sender then
            senderGuid = UnitGUID(unit)
            break
          end
        end
      end
      libpredict:Ress(sender, target, senderGuid)
    end
  elseif msgtype == "Hot" then
    -- Duplicate check: ignore same sender+target+spell within DUPLICATE_WINDOW
    local now = pfUI.uf.now or GetTime()
    local key = sender .. target .. heal
    if recentHots[key] and (now - recentHots[key]) < DUPLICATE_WINDOW then
      if libpredict.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DUPLICATE IGNORED]|r " .. key)
      end
      return
    end
    recentHots[key] = now
    
    -- Cleanup old entries (every 10s)
    if not libpredict.lastCleanup or (now - libpredict.lastCleanup) > 10 then
      for k, v in pairs(recentHots) do
        if (now - v) > DUPLICATE_WINDOW then
          recentHots[k] = nil
        end
      end
      libpredict.lastCleanup = now
    end
    
    -- For own HoTs: correct the startTime
    if sender == UnitName("player") then
      local existing = hots[target] and hots[target][heal]
      
      -- Do not overwrite if an active timer already exists
      if existing and (existing.start + existing.duration) > now then
        return
      end
      
      -- Compensate for HealComm delay
      local delay = (heal == "Regr") and 0.3 or 0
      local correctedStart = now - delay
      
      libpredict:Hot(sender, target, heal, time, correctedStart, "ParseComm-Self", rank)
      return
    end
    libpredict:Hot(sender, target, heal, time, nil, "ParseComm", rank)
  end
end

function libpredict:AddEvent(time, target)
  events[time] = events[time] or {}
  table.insert(events[time], target)
end

function libpredict:Heal(sender, target, amount, duration, senderGuid)
  if not sender or not target or not amount or not duration then
    return
  end

  local now = pfUI.uf.now or GetTime()
  local timeout = duration/1000 + now
  heals[target] = heals[target] or {}
  heals[target][sender] = { amount, timeout }
  if senderGuid then healGuidToName[senderGuid] = sender end
  libpredict:AddEvent(timeout, target)
end

-- Debug flag
libpredict.debug = false

function libpredict:Hot(sender, target, spell, duration, startTime, source, rank)
  hots[target] = hots[target] or {}
  hots[target][spell] = hots[target][spell] or {}

  -- Correct Regrowth duration (server returns 21, should be 20)
  if spell == "Regr" then
    duration = 20
  end
  
  -- Sicherstellen dass duration eine Zahl ist
  duration = tonumber(duration) or duration
  
  -- Rank protection: Don't overwrite higher rank HoT with lower rank
  local existing = hots[target][spell]
  if existing and existing.rank and rank then
    local existingRank = tonumber(existing.rank) or 0
    local newRank = tonumber(rank) or 0
    
    local now = pfUI.uf.now or GetTime()
    local existingTimeleft = (existing.start + existing.duration) - now
    
    -- If existing HoT is still active and has higher rank, don't overwrite
    if existingTimeleft > 0 and newRank > 0 and newRank < existingRank then
      if libpredict.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[Hot RANK BLOCK]|r %s Rank %d cannot overwrite Rank %d on %s", 
          spell, newRank, existingRank, target))
      end
      return -- Don't overwrite!
    end
  end

  local now = pfUI.uf.now or GetTime()
  hots[target][spell].duration = duration
  hots[target][spell].start = startTime or now
  hots[target][spell].rank = rank -- Store rank for protection
  
  -- Debug
  if libpredict.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[Hot]|r src=" .. (source or "?") .. 
      " | sender=" .. (sender or "nil") ..
      " | target=" .. (target or "nil") .. 
      " | spell=" .. (spell or "nil") ..
      " | dur=" .. tostring(duration) .. " (" .. type(duration) .. ")" ..
      " | rank=" .. tostring(rank or "?"))
  end

  -- update aura events of relevant unitframes
  if pfUI and pfUI.uf and pfUI.uf.frames then
    for _, frame in pairs(pfUI.uf.frames) do
      if frame.namecache == target then
        frame.update_aura = true
        if libpredict.debug then
          DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00-> Frame update triggered for " .. (frame:GetName() or "?") .. "|r")
        end
      end
    end
  end
end

function libpredict:HealStop(sender)
  for ttarget, t in pairs(heals) do
    for tsender in pairs(heals[ttarget]) do
      if sender == tsender then
        heals[ttarget][tsender] = nil
      end
    end
  end
  -- cleanup reverse lookup
  for guid, name in pairs(healGuidToName) do
    if name == sender then healGuidToName[guid] = nil end
  end
end

function libpredict:HealDelay(sender, delay)
  local delay = delay/1000
  for target, t in pairs(heals) do
    for tsender, amount in pairs(heals[target]) do
      if sender == tsender then
        amount[2] = amount[2] + delay
        libpredict:AddEvent(amount[2], target)
      end
    end
  end
end

function libpredict:Ress(sender, target, senderGuid)
  ress[target] = ress[target] or {}
  ress[target][sender] = true
  if senderGuid then ressGuidToName[senderGuid] = sender end
  -- no timer here - timer is only set once the cast actually completes
end

function libpredict:RessSetTimer(sender, target)
  ress_timers[target] = ress_timers[target] or {}
  local existing = ress_timers[target][sender]
  if not existing or GetTime() >= existing then
    ress_timers[target][sender] = GetTime() + RESS_TIMEOUT
  else
  end
end

function libpredict:RessStop(sender)
  local now = GetTime()
  for ttarget, t in pairs(ress) do
    for tsender in pairs(ress[ttarget]) do
      if sender == tsender then
        local expiry = ress_timers[ttarget] and ress_timers[ttarget][tsender]
        if not expiry or now >= expiry then
          ress[ttarget][tsender] = nil
          if ress_timers[ttarget] then ress_timers[ttarget][tsender] = nil end
        else
        end
      end
    end
  end
  for guid, name in pairs(ressGuidToName) do
    if name == sender then ressGuidToName[guid] = nil end
  end
end

function libpredict:UnitGetIncomingHeals(unit)
  if not unit then return 0 end
  local name = UnitName(unit)
  if not name then return 0 end
  if UnitIsDeadOrGhost(unit) then return 0 end

  local sumheal = 0
  if not heals[name] then
    return sumheal
  else
    local now = pfUI.uf.now or GetTime()
    for sender, amount in pairs(heals[name]) do
      if amount[2] <= now then
        heals[name][sender] = nil
      else
        sumheal = sumheal + amount[1]
      end
    end
  end
  return sumheal
end

function libpredict:UnitHasIncomingResurrection(unit)
  if not unit then return nil end
  local name = UnitName(unit)
  if not name then return nil end

  if not ress[name] then
    return nil
  else
    for sender, val in pairs(ress[name]) do
      if val == true then
        return val
      end
    end
  end
  return nil
end

local realm = GetRealmName()
local resetcache = CreateFrame("Frame")
local hotsetbonus = libtipscan:GetScanner("hotsetbonus")
resetcache:RegisterEvent("PLAYER_ENTERING_WORLD")
resetcache:RegisterEvent("LEARNED_SPELL_IN_TAB")
resetcache:RegisterEvent("CHARACTER_POINTS_CHANGED")
resetcache:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
resetcache:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    -- load and initialize previous caches of spell amounts
    pfUI_cache["prediction"] = pfUI_cache["prediction"] or {}
    pfUI_cache["prediction"][realm] = pfUI_cache["prediction"][realm] or {}
    pfUI_cache["prediction"][realm][player] = pfUI_cache["prediction"][realm][player] or {}
    pfUI_cache["prediction"][realm][player]["heals"] = pfUI_cache["prediction"][realm][player]["heals"] or {}
    cache = pfUI_cache["prediction"][realm][player]["heals"]
  end

  if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    local gear = ""
    for id = 1, 18 do
      gear = gear .. (GetInventoryItemLink("player",id) or "")
    end

    -- abort when inventory didn't change
    if gear == gear_string then return end
    gear_string = gear

    local setBonusCounter
    setBonusCounter = 0
    for i=1,10 do --there is no need to check slots above 10
      hotsetbonus:SetInventoryItem("player", i)
      if hotsetbonus:Find(L["healduration"]["Rejuvenation"]) then setBonusCounter = setBonusCounter + 1 end
    end
    rejuvDuration = setBonusCounter == 8 and 15 or 12
    setBonusCounter = 0
    for i =1,10 do
      hotsetbonus:SetInventoryItem("player", i)
      if hotsetbonus:Find(L["healduration"]["Renew"]) then setBonusCounter = setBonusCounter + 1 end
    end
    renewDuration = setBonusCounter == 5 and 18 or 15
  end

  -- flag all cached heals for renewal
  for k in pairs(cache) do
    if type(cache[k]) == "number" or type(cache[k]) == "string" then
      -- migrate old data
      local oldval = cache[k]
      cache[k] = { [1] = oldval }
    end

    -- flag for reset
    cache[k][2] = true
  end
end)

local function UpdateCache(spell, heal, crit)
  local heal = heal and tonumber(heal)
  if not spell or not heal then return end

  if not cache[spell] then
    -- no cache yet: save whatever we get
    cache[spell] = {}
    cache[spell][1] = crit and heal*2/3 or heal
    cache[spell][2] = crit
  elseif cache[spell][2] == true then
    -- flagged as stale (gear/skill change): always overwrite
    cache[spell][1] = crit and heal*2/3 or heal
    cache[spell][2] = crit
  elseif crit then
    -- crit: don't overwrite existing non-crit value
  else
    -- non-crit: save best value
    if cache[spell][1] < heal then
      cache[spell][1] = heal
    end
    cache[spell][2] = false
  end
end

-- Cooldown for local instant HoT hooks (prevents spam on click-to-cast)
local instantHotCooldown = {}
local INSTANT_HOT_COOLDOWN = 1.0  -- 1 Sekunde Cooldown (GCD ist 1.5s)

-- Pending HoTs Queue - wird nach Delay verifiziert
local pendingHots = {}

-- Gather Data by User Actions
hooksecurefunc("CastSpell", function(id, bookType)
  if not libpredict.sender.enabled then return end
  local effect, rank = libspell.GetSpellInfo(id, bookType)
  if not effect then return end
  spell_queue[1] = effect
  spell_queue[2] = effect.. ( rank or "" )
  spell_queue[3] = UnitName("target") and UnitCanAssist("player", "target") and UnitName("target") or UnitName("player")
  
  -- Extract rank number
  local rankNum = nil
  if rank and rank ~= "" then
    rankNum = tonumber((string.gsub(rank, "Rank ", ""))) or nil
  end
  
  -- Instant HoTs: UNIT_SPELLCAST_SUCCEEDED and C_UnitAuras, hook method as fallback
  
  if effect == REJUVENATION then
    local target = spell_queue[3]
    local now = pfUI.uf.now or GetTime()
    local key = "Reju" .. target
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CastSpell REJU INSTANT]|r target=%s rank=%s (Fallback)", target, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, target, "Reju", rejuvDuration, nil, "CastSpell-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Reju/"..target.."/"..rejuvDuration.."/"..rankStr.."/")
  elseif effect == RENEW then
    local target = spell_queue[3]
    local now = pfUI.uf.now or GetTime()
    local key = "Renew" .. target
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CastSpell RENEW INSTANT]|r target=%s rank=%s (Fallback)", target, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, target, "Renew", renewDuration, nil, "CastSpell-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Renew/"..target.."/"..renewDuration.."/"..rankStr.."/")
  end
end)

hooksecurefunc("CastSpellByName", function(effect, target)
  if not libpredict.sender.enabled then return end
  local effect, rank = libspell.GetSpellInfo(effect)
  if not effect then return end

  local default = UnitName("target") and UnitCanAssist("player", "target") and UnitName("target") or UnitName("player")

  target = target and type(target) == "string" and UnitName(target) or target
  target = target and target == true and UnitName("player") or target
  target = target and target == 1 and UnitName("player") or target

  -- Extract rank number
  local rankNum = nil
  if rank and rank ~= "" then
    rankNum = tonumber((string.gsub(rank, "Rank ", ""))) or nil
  end

  -- Only overwrite spell_queue if no cast is in progress
  -- (prevents instant spam from destroying the queue during a Regrowth cast)
  if not libpredict.sender.current_cast then
    spell_queue[1] = effect
    spell_queue[2] = effect.. ( rank or "" )
    spell_queue[3] = target or default
  end
  
  -- Instant HoTs: UNIT_SPELLCAST_SUCCEEDED and C_UnitAuras, hook method as fallback
  
  if effect == REJUVENATION then
    local hotTarget = target or default
    local now = pfUI.uf.now or GetTime()
    local key = "Reju" .. hotTarget
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CastSpellByName REJU INSTANT]|r target=%s rank=%s (Fallback)", hotTarget, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, hotTarget, "Reju", rejuvDuration, nil, "CastSpellByName-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Reju/"..hotTarget.."/"..rejuvDuration.."/"..rankStr.."/")
  elseif effect == RENEW then
    local hotTarget = target or default
    local now = pfUI.uf.now or GetTime()
    local key = "Renew" .. hotTarget
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CastSpellByName RENEW INSTANT]|r target=%s rank=%s (Fallback)", hotTarget, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, hotTarget, "Renew", renewDuration, nil, "CastSpellByName-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Renew/"..hotTarget.."/"..renewDuration.."/"..rankStr.."/")
  end
end)

hooksecurefunc("UseAction", function(slot, target, selfcast)
  if not libpredict.sender.enabled then return end
  if not IsCurrentAction(slot) then return end
  local kind, id = GetActionInfo(slot)
  local effect, rank
  if kind == "spell" then
    local spellInfo = C_Spell.GetSpellInfo(id)
    effect, rank = spellInfo.name, spellInfo.rank
  elseif kind == "macro" then
    effect, rank = GetMacroSpell(id)
  end
  if not effect then return end
  spell_queue[1] = effect
  spell_queue[2] = effect.. ( rank or "" )
  spell_queue[3] = selfcast and UnitName("player") or UnitName("target") and UnitCanAssist("player", "target") and UnitName("target") or UnitName("player")
  
  -- Extract rank number
  local rankNum = nil
  if rank and rank ~= "" then
    rankNum = tonumber((string.gsub(rank, "Rank ", ""))) or nil
  end
  
  -- Instant HoTs: UNIT_SPELLCAST_SUCCEEDED and C_UnitAuras, hook method as fallback
  
  if effect == REJUVENATION then
    local hotTarget = spell_queue[3]
    local now = pfUI.uf.now or GetTime()
    local key = "Reju" .. hotTarget
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[UseAction REJU INSTANT]|r target=%s rank=%s (Fallback)", hotTarget, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, hotTarget, "Reju", rejuvDuration, nil, "UseAction-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Reju/"..hotTarget.."/"..rejuvDuration.."/"..rankStr.."/")
  elseif effect == RENEW then
    local hotTarget = spell_queue[3]
    local now = pfUI.uf.now or GetTime()
    local key = "Renew" .. hotTarget
    
    -- Cooldown-Check
    if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then
      return
    end
    instantHotCooldown[key] = now
    
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[UseAction RENEW INSTANT]|r target=%s rank=%s (Fallback)", hotTarget, tostring(rankNum or "?")))
    end
    libpredict:Hot(player, hotTarget, "Renew", renewDuration, nil, "UseAction-Instant", rankNum)
    local rankStr = rankNum and tostring(rankNum) or "0"
    libpredict.sender:SendHealCommMsg("Renew/"..hotTarget.."/"..renewDuration.."/"..rankStr.."/")
  end
end)

libpredict.sender = CreateFrame("Frame", "pfPredictionSender", UIParent)
libpredict.sender.enabled = true
libpredict.sender.SendHealCommMsg = function(self, msg)
  -- Smart channel selection: Only send to relevant channel to avoid duplicates
  if IsInRaid() then
    -- In raid: Only send to RAID (includes all raid members)
    SendAddonMessage("HealComm", msg, "RAID")
  elseif IsInGroup() then
    -- In party: Only send to PARTY
    SendAddonMessage("HealComm", msg, "PARTY")
  end
  -- Note: BATTLEGROUND channel not used (no reliable way to detect BG in Vanilla)
  -- BG groups are handled by RAID channel
end
libpredict.sender.SendResCommMsg = function(self, msg)
  -- Smart channel selection: Only send to relevant channel to avoid duplicates
  if IsInRaid() then
    -- In raid: Only send to RAID (includes all raid members)
    SendAddonMessage("CTRA", msg, "RAID")
  elseif IsInGroup() then
    -- In party: Only send to PARTY
    SendAddonMessage("CTRA", msg, "PARTY")
  end
  -- Note: BATTLEGROUND channel not used (no reliable way to detect BG in Vanilla)
  -- BG groups are handled by RAID channel
end

libpredict.sender:SetScript("OnUpdate", function()
  -- trigger delayed regrowth timers
  local now = pfUI.uf.now or GetTime()
  if this.regrowth_timer and now > this.regrowth_timer then
    local target = this.regrowth_target or player
    local duration = 20
    local startTime = this.regrowth_start
    local rank = this.regrowth_rank

    libpredict:Hot(player, target, "Regr", duration, startTime, "OnUpdate", rank)
    local rankStr = rank and tostring(rank) or "0"
    libpredict.sender:SendHealCommMsg("Regr/"..target.."/"..duration.."/"..rankStr.."/")
    
    -- Apply next queued Regrowth if available
    this.regrowth_target = this.regrowth_target_next
    this.regrowth_start = this.regrowth_start_next
    this.regrowth_rank = this.regrowth_rank_next
    this.regrowth_target_next = nil
    this.regrowth_start_next = nil
    this.regrowth_rank_next = nil
    this.regrowth_timer = nil
  end
end)

-- Own casts arrive as "player"; every other caster fires once per unit token
-- it currently holds (raidN, target, nameplateN, ...), so other-unit handlers
-- drop the repeats by castGUID.
libpredict.sender:RegisterEvent("UNIT_SPELLCAST_SENT")
libpredict.sender:RegisterEvent("UNIT_SPELLCAST_START")
libpredict.sender:RegisterEvent("UNIT_SPELLCAST_DELAYED")
libpredict.sender:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
libpredict.sender:RegisterEvent("UNIT_SPELLCAST_FAILED")
libpredict.sender:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
libpredict.sender:RegisterEvent("UNIT_SPELLCAST_STOP")
libpredict.sender:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- Shared cleanup helper for failed/interrupted casts
local function onCastFailed()
  local s = libpredict.sender
  if s.healing then
    libpredict:HealStop(UnitName("player"))
    s:SendHealCommMsg("Healstop")
    s.healing = nil
  elseif s.resurrecting then
    local target = s.current_cast_target or spell_queue[3]
    libpredict:RessStop(UnitName("player"))
    s:SendHealCommMsg("Resurrection/stop/")
    s:SendResCommMsg("RESNO " .. (target or ""))
    s.resurrecting = nil
  end
  if s.current_cast == REGROWTH then
    s.regrowth_timer = nil
    s.regrowth_start = nil
    s.regrowth_target_next = nil
    s.regrowth_start_next = nil
  end
  s.castGUID = nil
  s.current_cast = nil
  s.current_cast_target = nil
end

-- Real heal amounts: own heals refresh the spell cache, other group healers'
-- heals fill foreignCache (one event per hit target for AoE heals like PoH).
local function OnHeal()
  -- arg4=sourceGUID, arg12=spellId, arg13=spellName, arg15=amount, arg18=critical
  local spellId, spellName, amount, isCrit = arg12, arg13, arg15, arg18 == 1
  if not spellName or not amount or amount <= 0 then return end

  if IsPlayerGuid(arg4) then
    if spell_queue[1] == spellName then
      UpdateCache(spell_queue[2], amount, isCrit)
    end
    return
  end

  local casterName = resolveNameFromGuid(arg4)
  if not casterName then return end

  local spellKey = spellName .. (C_Spell.GetSpellSubtext(spellId) or "")

  foreignCache[casterName] = foreignCache[casterName] or {}
  local existing = foreignCache[casterName][spellKey]
  -- Store highest non-crit value for best prediction accuracy
  if isCrit then
    -- Estimate base from crit (vanilla crit = 150%)
    local base = math.floor(amount * 2 / 3)
    if not existing or base > existing then
      foreignCache[casterName][spellKey] = base
    end
  else
    if not existing or amount > existing then
      foreignCache[casterName][spellKey] = amount
    end
  end
end

local lastOtherCast = {}  -- [event] = castGUID of the last other-unit event handled

libpredict.sender:SetScript("OnEvent", function()
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    if arg2 == "SPELL_HEAL" then OnHeal() end
    return
  end

  -- UNIT_SPELLCAST_SENT: arg1=unit, arg2=target token, arg3=castGUID, arg4=spellID
  -- every other UNIT_SPELLCAST_*: arg1=unit, arg2=castGUID, arg3=spellID
  local unit = arg1
  if unit == "player" then
    if event == "UNIT_SPELLCAST_SENT" then
      sentTargets[arg3] = arg2 ~= "" and UnitName(arg2) or nil
    elseif event == "UNIT_SPELLCAST_START" then
      OnOwnCastStart(arg3, arg2)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      OnOwnCastSucceeded(arg3, arg2)
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
      sentTargets[arg2] = nil
      -- a refused cast (cooldown, range) fails under its own castGUID and
      -- must not cancel the heal that is still casting
      if arg2 == this.castGUID then onCastFailed() end
    elseif event == "UNIT_SPELLCAST_DELAYED" then
      -- delayTimeMs is the pushback so far; HealComm wants each step
      local _, _, _, _, _, _, _, _, _, _, delayMs = C_Spell.CastingInfo()
      if this.healing and delayMs and delayMs > this.delayMs then
        local step = delayMs - this.delayMs
        this.delayMs = delayMs
        libpredict:HealDelay(player, step)
        this:SendHealCommMsg("Healdelay/" .. step .. "/")
      end
    end
    return
  end

  if UnitIsUnit(unit, "player") or lastOtherCast[event] == arg2 then return end
  lastOtherCast[event] = arg2

  if event == "UNIT_SPELLCAST_START" then
    OnOtherCastStart(unit, arg3, arg2)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    OnOtherCastSucceeded(unit, arg3, arg2)
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
    OnOtherCastInterrupted(unit)
  elseif event == "UNIT_SPELLCAST_STOP" then
    castTargets[arg2] = nil
  end
end)

function libpredict:GetHotDuration(unit, spell)
  if unit == UNKNOWNOBJECT or unit == UKNOWNBEING then return end
  
  -- Live aura timer first (C_UnitAuras via libdebuff)
  if pfUI.api.libdebuff then
    local guid = UnitGUID(unit)
    if guid then
      local spellName = spell
      
      -- Map short spell codes to full names
      if spell == "Reju" then
        spellName = REJUVENATION
      elseif spell == "Regr" then
        spellName = REGROWTH
      elseif spell == "Renew" then
        spellName = RENEW
      end
      
      local start, duration, timeleft, rank, casterGuid = pfUI.api.libdebuff:GetBestAuraCast(guid, spellName)
      
      if start and duration and timeleft then
        if libpredict.debug then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[GetHotDuration]|r %s on %s via libdebuff: dur=%.1fs timeleft=%.1fs rank=%d", 
            spell, unit, duration, timeleft, rank or 0))
        end
        return start, duration, timeleft
      end
    end
  end
  
  -- FALLBACK: the HealComm/cast-fed table, for HoTs C_UnitAuras has no timer for
  local start, duration, timeleft
  local now = pfUI.uf.now or GetTime()
  
  local unitName = UnitName(unit)
  local unitdata = hots[unitName]
  
  if unitdata and unitdata[spell] then
    local spellData = unitdata[spell]
    if spellData.start and spellData.duration then
      local endTime = spellData.start + spellData.duration
      if endTime > now - 1 then
        start = spellData.start
        duration = spellData.duration
        timeleft = endTime - now
        
        if libpredict.debug then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[GetHotDuration]|r %s on %s via prediction: dur=%.1fs timeleft=%.1fs", 
            spell, unit, duration, timeleft))
        end
      end
    end
  end

  return start, duration, timeleft
end

-- Debug command: /hotdebug - Show HoT tracking status
_G.SLASH_HOTDEBUG1 = "/hotdebug"
_G.SlashCmdList.HOTDEBUG = function()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff========================================|r")
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[HoT Tracking Debug]|r")
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff========================================|r")
  
  if pfUI.api.libdebuff then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PRIMARY]|r libdebuff integration: ACTIVE")
    DEFAULT_CHAT_FRAME:AddMessage("  Using C_UnitAuras timers")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[PRIMARY]|r libdebuff integration: NOT AVAILABLE")
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[FALLBACK]|r Legacy prediction system: ACTIVE")
  DEFAULT_CHAT_FRAME:AddMessage("  Using hook method + HealComm messages")
  
  -- Show active HoTs in tracking
  local hotCount = 0
  for target, spells in pairs(hots) do
    for spell, data in pairs(spells) do
      hotCount = hotCount + 1
    end
  end
  
  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[TRACKED]|r %d HoTs in legacy system", hotCount))
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff========================================|r")
  DEFAULT_CHAT_FRAME:AddMessage("Tip: /libpredict.debug = true for verbose logging")
end

pfUI.api.libpredict = libpredict