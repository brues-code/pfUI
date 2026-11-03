-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libpredict ]]--
-- A pfUI library that detects, receives and sends heal predictions.
-- Healing predictions are done by caching the last known "normal" heal value of the
-- spell when last being used. Those chaches are cleared when new talents are detected.
-- The API provides function calls similar to later WoW expansions such as:
--   UnitGetIncomingHeals(unit)
--   UnitHasResurrection(unit)
--
-- UnitHasResurrection extends ClassicAPI's UnitHasIncomingResurrection, which
-- ends with the cast, to a resurrection that landed and waits for the target
-- to accept it.
--
-- The library is able to receive and send compatible messages to HealComm,
-- and announces the player's resurrections to HealComm and CTRA. It has an
-- option to disable the sending of those messages in case HealComm is
-- already active.
--
-- Casts are read from ClassicAPI's UNIT_SPELLCAST_* events and heal amounts
-- from COMBAT_LOG_EVENT_UNFILTERED. GetHotDuration() reads live HoT timers
-- from C_UnitAuras (via libdebuff) and falls back to the HealComm-fed table.

-- return instantly when another libpredict is already active
if pfUI.api.libpredict then return end

local heals, hots = {}, {}
local spell_queue = { "DUMMY", "DUMMYRank 9", "TARGET" }
local player = UnitName("player")
local cache, gear_string = {}, ""
local foreignCache = {}   -- [casterName][spellKey] = amount, in-memory cache for other healers
local rejuvDuration, renewDuration = 12, 15 --default durations
local healGuidToName = {} -- [casterGuid] = casterName, for interrupted-cast cleanup
local sentTargets = {}    -- [castGUID] = target name of an own cast, from UNIT_SPELLCAST_SENT
local resOffers = {}      -- [guid] = expiry of a landed resurrection the target has yet to accept
local RES_OFFER_TIMEOUT = 60 -- the target's resurrect popup declines itself after 60s

-- Tell the listeners of "libpredict:heals" that the heals on `target` (a
-- name) changed, and again at `expiry`, when a heal that is never stopped
-- drops out of UnitGetIncomingHeals.
local function HealsChanged(target, expiry)
  pfUI.events:TriggerEvent("libpredict:heals", target)
  if expiry then
    C_Timer.After(expiry - GetTime(), function()
      pfUI.events:TriggerEvent("libpredict:heals", target)
    end)
  end
end

-- Localized spell names resolved once from canonical rank-1 spellIDs.
-- Every rank shares the same name, so per-rank comparisons elsewhere can
-- be done against these constants without per-locale or per-rank tables.
local PRAYER_OF_HEALING = C_Spell.GetSpellName(596)   -- Prayer of Healing (Rank 1)
local REJUVENATION      = C_Spell.GetSpellName(774)   -- Rejuvenation (Rank 1)
local RENEW             = C_Spell.GetSpellName(139)   -- Renew (Rank 1)
local REGROWTH          = C_Spell.GetSpellName(8936)  -- Regrowth (Rank 1)

local libpredict = CreateFrame("Frame")
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
  
  if event == "CHAT_MSG_ADDON" and arg1 == "HealComm" then
    this:ParseChatMessage(arg4, arg2)
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

-- Build cache on world enter
libpredict:RegisterEvent("PLAYER_ENTERING_WORLD")
libpredict:RegisterEvent("RAID_ROSTER_UPDATE")
libpredict:RegisterEvent("PARTY_MEMBERS_CHANGED")
libpredict:HookScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" or event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
    cacheRaidNames()
  end
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

-- Own cast landed: HealStop, Regrowth timer, instant HoTs
local function OnOwnCastSucceeded(spellId, castGUID)
  local target = sentTargets[castGUID] or spell_queue[3]
  sentTargets[castGUID] = nil

  libpredict:HealStop(player)
  local spellName = C_Spell.GetSpellName(spellId)
  libpredict.sender.castGUID = nil
  libpredict.sender.current_cast = nil
  libpredict.sender.current_cast_target = nil

  if not target then return end

  -- HoTs — classify by name (rank-independent) instead of a hardcoded
  -- per-rank ID table.
  local hotType
  if spellName == REJUVENATION then hotType = "Reju"
  elseif spellName == RENEW then hotType = "Renew"
  elseif spellName == REGROWTH then hotType = "Regr"
  end
  if hotType then
    local rank = 0
    local rankSub = C_Spell.GetSpellSubtext(spellId)
    if rankSub and rankSub ~= "" then
      rank = tonumber((string.gsub(rankSub, "Rank ", ""))) or 0
    end
    if hotType == "Regr" then
      -- Regrowth's HoT follows its direct heal a moment later
      local start = GetTime()
      C_Timer.After(0.1, function()
        libpredict:Hot(player, target, hotType, 20, start, "UNIT_SPELLCAST_SUCCEEDED", rank)
        libpredict.sender:SendHealCommMsg(hotType .. "/" .. target .. "/20/" .. rank .. "/")
      end)
      return
    end
    local duration = hotType == "Reju" and rejuvDuration or renewDuration
    libpredict:Hot(player, target, hotType, duration, nil, "UNIT_SPELLCAST_SUCCEEDED", rank)
    libpredict.sender:SendHealCommMsg(hotType .. "/" .. target .. "/" .. duration .. "/" .. rank .. "/")
  end
end

-- Foreign cast-time heal started
local function OnOtherCastStart(unit, spellId)
  local spellName = C_Spell.GetSpellName(spellId)
  if not spellName then return end

  local casterGuid = UnitGUID(unit)
  local casterName = resolveNameFromGuid(casterGuid)
  if not casterName then return end

  local targetName = UnitSpellTargetName(unit)
  if not targetName then return end

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

-- Foreign cast landed: the predicted heal is fulfilled
local function OnOtherCastSucceeded(unit)
  local casterName = resolveNameFromGuid(UnitGUID(unit))
  if not casterName then return end

  libpredict:HealStop(casterName)
end

-- Foreign cast interrupted: remove cancelled heals
local function OnOtherCastInterrupted(unit)
  local casterGuid = UnitGUID(unit)
  if not casterGuid then return end
  local healName = healGuidToName[casterGuid]
  if healName then libpredict:HealStop(healName) end
end

-- Flag the unit frames showing `guid` to redraw their resurrection icon
local function RefreshResFrames(guid)
  for _, frame in pairs(pfUI.uf.frames) do
    if frame.unitstr and UnitGUID(frame.unitstr) == guid then
      pfUI.uf:QueueUpdate(frame, "indicators")
    end
  end
end

-- Drop resurrection offers the target accepted or let run out. Nothing reports
-- either, so a ticker checks while any offer is open.
local resTicker
local function CheckResOffers()
  local now = GetTime()
  for guid, expiry in pairs(resOffers) do
    local unit = UnitTokenFromGUID(guid)
    if now >= expiry or not (unit and UnitIsDeadOrGhost(unit)) then
      resOffers[guid] = nil
      RefreshResFrames(guid)
    end
  end
  if not next(resOffers) then
    resTicker:Cancel()
    resTicker = nil
  end
end

function libpredict:ParseComm(sender, msg)
  local msgtype, target, heal, time, rank

  if msg == "HealStop" or msg == "Healstop" or msg == "GrpHealstop" then
    msgtype = "Stop"
    -- DEBUG: Log when HealStop received
    if libpredict.debug then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[libpredict RX]|r HealStop from " .. tostring(sender))
    end
  elseif msg then
    local msgobj = {strsplit("/", msg)}

    if msgobj and msgobj[1] and msgobj[2] then
      -- legacy healcomm object
      if msgobj[1] == "GrpHealdelay" or msgobj[1] == "Healdelay" then
        msgtype, time = "Delay", msgobj[2]
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

function libpredict:ParseChatMessage(sender, msg)
  local msgtype, target, heal, time, rank = libpredict:ParseComm(sender, msg)

  if msgtype == "Stop" and sender then
    libpredict:HealStop(sender)
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
  elseif msgtype == "Hot" then
    -- Duplicate check: ignore same sender+target+spell within DUPLICATE_WINDOW
    local now = GetTime()
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

function libpredict:Heal(sender, target, amount, duration, senderGuid)
  if not sender or not target or not amount or not duration then
    return
  end

  local timeout = duration/1000 + GetTime()
  heals[target] = heals[target] or {}
  heals[target][sender] = { amount, timeout }
  if senderGuid then healGuidToName[senderGuid] = sender end
  HealsChanged(target, timeout)
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
    
    local now = GetTime()
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

  local now = GetTime()
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
        pfUI.uf:QueueUpdate(frame, "aura")
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
        HealsChanged(ttarget)
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
        HealsChanged(target, amount[2])
      end
    end
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
    local now = GetTime()
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

-- Whether a resurrection is being cast at the unit, or landed and waits for
-- the unit to accept it
function libpredict:UnitHasResurrection(unit)
  return UnitHasIncomingResurrection(unit) or resOffers[UnitGUID(unit)] ~= nil
end

local realm = GetRealmName()
local resetcache = CreateFrame("Frame")

-- set bonus spells that lengthen a HoT
local REJUVENATION_SET_BONUS = 21871 -- Stormrage Raiment (8)
local RENEW_SET_BONUS = 26171        -- Garments of the Oracle (5)

-- the set bonus spells the equipped gear grants
local function GetActiveSetBonuses()
  local pieces = {}
  for slot = 1, 19 do
    local setID = C_Item.GetItemSetID({ equipmentSlotIndex = slot })
    if setID then pieces[setID] = (pieces[setID] or 0) + 1 end
  end

  local active = {}
  for setID, count in pairs(pieces) do
    for _, bonus in ipairs(C_Item.GetItemSetInfo(setID).bonuses) do
      if count >= bonus.threshold then active[bonus.spellID] = true end
    end
  end
  return active
end
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

    local bonuses = GetActiveSetBonuses()
    rejuvDuration = bonuses[REJUVENATION_SET_BONUS] and 15 or 12
    renewDuration = bonuses[RENEW_SET_BONUS] and 18 or 15
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
    local now = GetTime()
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
    local now = GetTime()
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
    local now = GetTime()
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
    local now = GetTime()
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
    local now = GetTime()
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
    local now = GetTime()
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
-- cleared when a HealComm addon already broadcasts this player's casts
libpredict.sender.enabled = true
libpredict.sender.SendHealCommMsg = function(self, msg)
  if not self.enabled then return end
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
  if not self.enabled then return end
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

-- Own casts arrive as "player". Other casters only matter as group members
-- (the only names resolveNameFromGuid knows), so their events are filtered to
-- the group's tokens, and solo nobody else's casts arrive at all. A member in
-- a raid also fires as raidN for its own casts; the handler drops those by
-- UnitIsUnit, and other repeats by castGUID.
local GROUP_CAST_EVENTS = {
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
}
local castunits = {}
local function RegisterCastEvents()
  local n, token = 0, IsInRaid() and "raid" or "party"
  castunits[1] = "player"
  for i = 1, IsInRaid() and GetNumRaidMembers() or GetNumPartyMembers() do
    castunits[i + 1] = token .. i
    n = i
  end
  for i = table.getn(castunits), n + 2, -1 do castunits[i] = nil end
  for i = 1, table.getn(GROUP_CAST_EVENTS) do
    libpredict.sender:RegisterUnitEvent(GROUP_CAST_EVENTS[i], unpack(castunits))
  end
end
RegisterCastEvents()
libpredict.sender:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
libpredict.sender:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
libpredict.sender:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
libpredict.sender:RegisterEvent("PARTY_MEMBERS_CHANGED")
libpredict.sender:RegisterEvent("RAID_ROSTER_UPDATE")
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
    s:SendHealCommMsg("Resurrection/stop/")
    s:SendResCommMsg("RESNO " .. (target or ""))
    s.resurrecting = nil
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

-- A landed resurrection: the target has an offer to accept, which outlasts
-- UnitHasIncomingResurrection's end with the cast
local function OnResurrect()
  -- arg8=destGUID
  resOffers[arg8] = GetTime() + RES_OFFER_TIMEOUT
  RefreshResFrames(arg8)
  resTicker = resTicker or C_Timer.NewTicker(.1, CheckResOffers)
end

local lastOtherCast = {}  -- [event] = castGUID of the last other-unit event handled

libpredict.sender:SetScript("OnEvent", function()
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    if arg2 == "SPELL_HEAL" then OnHeal()
    elseif arg2 == "SPELL_RESURRECT" then OnResurrect() end
    return
  elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
    RegisterCastEvents()
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
    OnOtherCastStart(unit, arg3)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    OnOtherCastSucceeded(unit)
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
    OnOtherCastInterrupted(unit)
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
  local now = GetTime()
  
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