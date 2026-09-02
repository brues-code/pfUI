pfUI:RegisterModule("nameplates", function ()
  -- disable original castbars
  pcall(SetCVar, "ShowVKeyCastbar", 0)

  -- Local function references for performance
  local GetTime = GetTime
  local UnitName = UnitName
  local UnitClass = UnitClass
  local UnitLevel = UnitLevel
  local UnitIsPlayer = UnitIsPlayer
  local UnitIsDead = UnitIsDead
  local UnitAffectingCombat = UnitAffectingCombat
  local UnitIsUnit = UnitIsUnit
  local UnitCanAssist = UnitCanAssist
  local UnitHealth = UnitHealth
  local UnitHealthMax = UnitHealthMax
  local pairs = pairs
  local tonumber = tonumber
  local strlower = strlower
  local strfind = strfind
  local strlen = strlen
  local floor = floor
  local ceil = ceil
  local abs = abs
  local mathmod = math.mod

  local unitcolors = {
    ["ENEMY_NPC"] = { .9, .2, .3, .8 },
    ["NEUTRAL_NPC"] = { 1, 1, .3, .8 },
    ["FRIENDLY_NPC"] = { .6, 1, 0, .8 },
    ["ENEMY_PLAYER"] = { .9, .2, .3, .8 },
    ["FRIENDLY_PLAYER"] = { .2, .6, 1, .8 }
  }

  local offtanks = {}

  local combatstate = {
    -- gets overwritten by user config
    ["OFFTANK"]  = { r = .7, g = .4, b = .2, a = 1 },
    ["NOTHREAT"] = { r = .7, g = .7, b = .2, a = 1 },
    ["THREAT"]   = { r = .7, g = .2, b = .2, a = 1 },
    ["CASTING"]  = { r = .7, g = .2, b = .7, a = 1 },
    ["STUN"]     = { r = .2, g = .7, b = .7, a = 1 },
    ["NONE"]     = { r = .2, g = .2, b = .2, a = 1 },
  }

  local elitestrings = {
    ["elite"] = "+",
    ["rareelite"] = "R+",
    ["rare"] = "R",
    ["boss"] = "B"
  }

  -- Friendly zone nameplate disable state
  local savedHostileState = nil
  local savedFriendlyState = nil
  local inFriendlyZone = false
  local myGuild = nil
  local platecount = 0
  local registry = {}
  -- Subset of registry that currently has a unit assigned (between
  -- NAME_PLATE_UNIT_ADDED and _REMOVED). The central loop iterates this instead
  -- of the full pool so hidden pool slots aren't touched every tick.
  local visiblePlates = {}

  local raidGuidCache = {}  -- guid -> name (rebuilt on RAID_ROSTER_UPDATE/PARTY_MEMBERS_CHANGED)
  
  -- Per-GUID cast state, populated from ClassicAPI's UNIT_SPELLCAST_* events
  -- (which now fire for nameplate tokens) and cleared on STOP / plate removal /
  -- expiry. This replaces the old per-tick C_Spell poll on every visible plate:
  -- cast detection is event driven, and GetCastInfo just reads this cache.
  local castState = {}
  -- guid -> nameplate, maintained on NAME_PLATE_UNIT_ADDED/_REMOVED so a cast
  -- event can find its plate in O(1) and only cache casts we actually show.
  local plateByGuid = {}

  -- One-shot C_Spell poll. Builds the cast struct for a UNIT_SPELLCAST_* event
  -- (the payload carries no timing) and seeds a plate that spawns while its unit
  -- is already mid-cast (its START fired before the plate existed). Picks cast
  -- vs channel itself. Never called per frame.
  local function PollCastInfo(unit)
    if not unit then return nil end
    local name, _, texture, startMs, endMs, _, _, _, spellID = C_Spell.UnitCastingInfo(unit)
    local isChannel
    if not name then
      name, _, texture, startMs, endMs, _, _, spellID = C_Spell.UnitChannelInfo(unit)
      isChannel = true
    end
    if not name or not startMs or not endMs then return nil end
    return {
      spellName = name,
      spellID   = spellID,
      icon      = texture,
      startTime = startMs / 1000,
      endTime   = endMs / 1000,
      duration  = (endMs - startMs) / 1000,
      isChannel = isChannel,
    }
  end

  -- Read a unit's current cast from the event-driven cache (keyed by GUID).
  -- Returns the cached struct while the cast is still active, else nil (and
  -- prunes the expired entry). Same struct shape and callers as before, minus
  -- the per-tick poll.
  local function GetCastInfo(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local info = castState[guid]
    if info and info.endTime > GetTime() then return info end
    if info then castState[guid] = nil end
    return nil
  end
  
  local debuffCache = {}    -- guid -> { [spellID] = { start, duration } }
  -- Reusable per-plate debuff display buffer (avoid GC churn from per-call table creation)
  local debuffDisplayBuf = {}  -- [i] = { effect, texture, stacks, dtype, duration, timeleft }
  for i = 1, 16 do debuffDisplayBuf[i] = {} end
  local threatMemory = {}   -- guid -> true if mob had player targeted
  -- local debuffSeen = {}     -- reusable table for debuff tracking (avoid GC churn)

  -- PERF: visiblePlateCount maintained event-driven (NAME_PLATE_UNIT_ADDED/_REMOVED)
  local visiblePlateCount = 0

  -- ============================================================================
  -- OPTIMIZATION: Config caching
  -- ============================================================================
  local cfg = {}
  local function CacheConfig()
    cfg.showcastbar = C.nameplates["showcastbar"] == "1"
    cfg.targetcastbar = C.nameplates["targetcastbar"] == "1"
    cfg.notargalpha = tonumber(C.nameplates.notargalpha) or 0.5
    if cfg.notargalpha > 1 then cfg.notargalpha = cfg.notargalpha / 100 end
    -- Clamp to 0.99 so non-target plates never reach 1.0 (used for target detection)
    if cfg.notargalpha > 0.99 then cfg.notargalpha = 0.99 end
    cfg.namefightcolor = C.nameplates.namefightcolor == "1"
    cfg.spellname = C.nameplates.spellname == "1"
    cfg.showhp = C.nameplates.showhp == "1"
    cfg.showdebuffs = C.nameplates["showdebuffs"] == "1"
    cfg.showdebuffs_hostile = C.nameplates["showdebuffs_hostile"] == "1"
    cfg.showdebuffs_friendly = C.nameplates["showdebuffs_friendly"] == "1"
    cfg.owndebuffs = C.nameplates["owndebuffs"] == "1"
    cfg.targetzoom = C.nameplates.targetzoom == "1"
    cfg.zoomval = (tonumber(C.nameplates.targetzoomval) or 0.4) + 1
    cfg.width = tonumber(C.nameplates.width) or 120
    cfg.heighthealth = tonumber(C.nameplates.heighthealth) or 8
    cfg.targetglow = C.nameplates.targetglow == "1"
    cfg.targethighlight = C.nameplates.targethighlight == "1"
    cfg.outcombatstate = C.nameplates.outcombatstate == "1"
    cfg.barcombatstate = C.nameplates.barcombatstate == "1"
    cfg.ccombatcasting = C.nameplates.ccombatcasting == "1"
    cfg.ccombatthreat = C.nameplates.ccombatthreat == "1"
    cfg.ccombatnothreat = C.nameplates.ccombatnothreat == "1"
    cfg.ccombatstun = C.nameplates.ccombatstun == "1"
    cfg.ccombatofftank = C.nameplates.ccombatofftank == "1"
    cfg.use_unitfonts = C.nameplates.use_unitfonts == "1"
    cfg.font_size = cfg.use_unitfonts and C.global.font_unit_size or C.global.font_size
    cfg.hptextformat = C.nameplates.hptextformat
    -- NEW: Cache debuff config
    cfg.debufftimers = C.nameplates.debufftimers == "1"
    cfg.debuffanim = tonumber(C.nameplates.debuffanim) or 0
    cfg.debufftext = tonumber(C.nameplates.debufftext) or 1

    -- Rebuild offtanks lookup table
    offtanks = {}
    for k, v in pairs({strsplit("#", C.nameplates.combatofftanks)}) do
      if v ~= "" then offtanks[string.lower(v)] = true end
    end
  end

  local function RebuildOfftanks()
    offtanks = {}
    for k, v in pairs({strsplit("#", C.nameplates.combatofftanks)}) do
      if v ~= "" then offtanks[string.lower(v)] = true end
    end
  end
  RebuildOfftanks()

  -- ============================================================================
  -- OPTIMIZATION: Frame state cache
  -- ============================================================================
  local frameState = {
    now = 0,
    targetGuid = nil,
    mouseoverGuid = nil,
  }

  -- cache default border color
  local er, eg, eb, ea = GetStringColor(pfUI_config.appearance.border.color)

  local NULL_GUID           = "0x0000000000000000"

  local function RebuildRaidGuidCache()
    for k in pairs(raidGuidCache) do raidGuidCache[k] = nil end
    for i = 1, GetNumRaidMembers() do
      local g = UnitGUID("raid"..i)
      if g then raidGuidCache[g] = UnitName("raid"..i) end
    end
    for i = 1, GetNumPartyMembers() do
      local g = UnitGUID("party"..i)
      if g then raidGuidCache[g] = UnitName("party"..i) end
    end
    local pg = UnitGUID("player")
    if pg then raidGuidCache[pg] = UnitName("player") end
  end

  local combatColorCache = {}  -- guid -> { color, expires }

  local function GetCombatStateColor(guid, token)
    -- PERF: Quick exit if player not in combat
    if not UnitAffectingCombat("player") then return false end
    if not token then return false end
    if UnitCanAssist("player", token) then return false end

    -- PERF: 0.2s throttle per guid - color changes are not time-critical
    local now = frameState.now
    local cached = combatColorCache[guid]
    if cached and cached.expires > now then
      return cached.color
    end

    if not UnitAffectingCombat(token) then return false end

    -- The mob's current target via the nameplate token chain (ClassicAPI):
    -- "nameplateNtarget" resolves to whatever this plate's unit is targeting,
    -- so no GetUnitField("target") or SuperWoW "<guid>target" token needed.
    local target = token .. "target"
    local mobTargetGuid = UnitGUID(target)
    local hasTarget = mobTargetGuid and mobTargetGuid ~= NULL_GUID
    local color = false

    local castInfo = GetCastInfo(token)
    local isCasting = castInfo and castInfo.endTime and now < castInfo.endTime
    local targetingPlayer = hasTarget and UnitIsUnit(target, "player")

    if targetingPlayer then
      threatMemory[guid] = true
    elseif hasTarget and not isCasting then
      threatMemory[guid] = nil
    end

    -- PERF: O(1) GUID lookup via raidGuidCache instead of O(40) loop
    local targetName = hasTarget and (UnitName(target) or raidGuidCache[mobTargetGuid])

    if cfg.ccombatcasting and isCasting then
      color = combatstate.CASTING
    elseif cfg.ccombatthreat and (targetingPlayer or threatMemory[guid]) then
      color = combatstate.THREAT
    elseif cfg.ccombatofftank and targetName and offtanks[strlower(targetName)] then
      color = combatstate.OFFTANK
    elseif cfg.ccombatofftank and pfUI.uf and pfUI.uf.raid and targetName and pfUI.uf.raid.tankrole[targetName] then
      color = combatstate.OFFTANK
    elseif cfg.ccombatnothreat and hasTarget then
      color = combatstate.NOTHREAT
    elseif cfg.ccombatstun and not hasTarget then
      color = combatstate.STUN
    end

    combatColorCache[guid] = combatColorCache[guid] or {}
    combatColorCache[guid].color = color
    combatColorCache[guid].expires = now + 0.2

    return color
  end

  local function DoNothing()
    return
  end

  local function DisableObject(object)
    if not object then return end
    if not object.GetObjectType then return end

    local otype = object:GetObjectType()

    if otype == "Texture" then
      object:SetTexture("")
      object:SetTexCoord(0, 0, 0, 0)
    elseif otype == "FontString" then
      object:SetWidth(0.001)
    elseif otype == "StatusBar" then
      object:SetStatusBarTexture("")
    end
  end

  -- Numeric CreatureType.dbc id for the plate's unit (8 = Critter, 11 = Totem).
  -- It's fixed per unit, so cache it and reset on plate reuse. nil while the GUID
  -- can't resolve yet (incl. the no-SuperWoW case, where cachedGuid is empty).
  -- Locale-proof and covers custom units for free -- no name tables needed.
  local function CreatureType(plate)
    local guid = plate.cachedGuid
    if not guid or guid == "" then return nil end
    if not plate.creatureType then
      plate.creatureType = UnitCreatureTypeID(guid)  -- nil retries next call
    end
    return plate.creatureType
  end

  -- Totem icon, read straight from the game:
  --   * Passive totems self-cast their provided buff, so they carry exactly one
  --     aura whose icon IS the totem's icon (Totem::Summon TOTEM_PASSIVE).
  --   * Active totems (Searing/Magma/Fire Nova) cast at enemies and hold no
  --     self-aura, so their icon arrives via UNIT_SPELLCAST_SUCCEEDED (cached
  --     into plate.totemIcon by the event handler); nil here until then.
  local function TotemPlate(plate)
    if C.nameplates.totemicons ~= "1" then return nil end
    if CreatureType(plate) ~= 11 then return nil end
    if plate.totemIcon then return plate.totemIcon end
    local aura = C_UnitAuras.GetBuffDataByIndex(plate.cachedGuid, 1)
    if aura then plate.totemIcon = aura.icon end
    return plate.totemIcon
  end

  local function HidePlate(unittype, fullhp, target, plate)
    -- keep some plates always visible according to config
    if C.nameplates.fullhealth == "1" and not fullhp then return nil end
    if C.nameplates.target == "1" and target then return nil end

    -- return true when something needs to be hidden
    if C.nameplates.enemynpc == "1" and unittype == "ENEMY_NPC" then
      return true
    elseif C.nameplates.enemyplayer == "1" and unittype == "ENEMY_PLAYER" then
      return true
    elseif C.nameplates.neutralnpc == "1" and unittype == "NEUTRAL_NPC" then
      return true
    elseif C.nameplates.friendlynpc == "1" and unittype == "FRIENDLY_NPC" then
      return true
    elseif C.nameplates.friendlyplayer == "1" and unittype == "FRIENDLY_PLAYER" then
      return true
    elseif C.nameplates.critters == "1" and CreatureType(plate) == 8 then
      return true
    elseif C.nameplates.totems == "1" and CreatureType(plate) == 11 then
      return true
    end

    -- nothing to hide
    return nil
  end

  local function abbrevname(t)
    return string.sub(t,1,1)..". "
  end

  local function GetNameString(name)
    local abbrev = pfUI_config.unitframes.abbrevname == "1" or nil
    local size = 20

    -- first try to only abbreviate the first word
    if abbrev and name and strlen(name) > size then
      name = string.gsub(name, "^(%S+) ", abbrevname)
    end

    -- abbreviate all if it still doesn't fit
    if abbrev and name and strlen(name) > size then
      name = string.gsub(name, "(%S+) ", abbrevname)
    end

    return name
  end


  local function GetUnitType(red, green, blue)
    if red > .9 and green < .2 and blue < .2 then
      return "ENEMY_NPC"
    elseif red > .9 and green > .9 and blue < .2 then
      return "NEUTRAL_NPC"
    elseif red < .2 and green < .2 and blue > 0.9 then
      return "FRIENDLY_PLAYER"
    elseif red < .2 and green > .9 and blue < .2 then
      return "FRIENDLY_NPC"
    end
  end

  local filter, list, cache
  local function DebuffFilterPopulate()
    -- initialize variables
    filter = C.nameplates["debuffs"]["filter"]
    if filter == "none" then return end
    list = C.nameplates["debuffs"][filter]
    cache = {}

    -- populate list
    for _, val in pairs({strsplit("#", list)}) do
      cache[strlower(val)] = true
    end
  end

  local function DebuffFilter(effect)
    if filter == "none" then return true end
    if not cache then DebuffFilterPopulate() end

    if filter == "blacklist" and cache[strlower(effect)] then
      return nil
    elseif filter == "blacklist" then
      return true
    elseif filter == "whitelist" and cache[strlower(effect)] then
      return true
    elseif filter == "whitelist" then
      return nil
    end
  end

  local function CreateDebuffIcon(plate, index)
    plate.debuffs[index] = CreateFrame("Frame", plate.platename.."Debuff"..index, plate)
    plate.debuffs[index]:Hide()
    plate.debuffs[index]:SetFrameLevel(4)

    plate.debuffs[index].icon = plate.debuffs[index]:CreateTexture(nil, "BACKGROUND")
    plate.debuffs[index].icon:SetTexture(.3,1,.8,1)
    plate.debuffs[index].icon:SetAllPoints(plate.debuffs[index])

    plate.debuffs[index].stacks = plate.debuffs[index]:CreateFontString(nil, "OVERLAY")
    plate.debuffs[index].stacks:SetAllPoints(plate.debuffs[index])
    plate.debuffs[index].stacks:SetJustifyH("RIGHT")
    plate.debuffs[index].stacks:SetJustifyV("BOTTOM")
    plate.debuffs[index].stacks:SetTextColor(1,1,0)

    -- PERF: Use lightweight fake cooldown frame when animation disabled
    -- The Model-based CooldownFrameTemplate causes major lag with many nameplates
    if cfg.debuffanim ~= 1 then
      plate.debuffs[index].cd = CreateFrame("Frame", plate.platename.."Debuff"..index.."Cooldown", plate.debuffs[index])
      plate.debuffs[index].cd:SetAllPoints(plate.debuffs[index])
      plate.debuffs[index].cd:SetFrameLevel(6)
      plate.debuffs[index].cd:SetScript("OnUpdate", CooldownFrame_OnUpdateModel)
      plate.debuffs[index].cd.AdvanceTime = DoNothing
      plate.debuffs[index].cd.SetSequence = DoNothing
      plate.debuffs[index].cd.SetSequenceTime = DoNothing
    else
      -- Use CooldownFrameTemplate for animation
      plate.debuffs[index].cd = CreateFrame(COOLDOWN_FRAME_TYPE, plate.platename.."Debuff"..index.."Cooldown", plate.debuffs[index], "CooldownFrameTemplate")
      plate.debuffs[index].cd:SetAllPoints(plate.debuffs[index])
      plate.debuffs[index].cd:SetFrameLevel(6)
    end

    -- Set initial config flags (will be cached per-cooldown later)
    plate.debuffs[index].cd.pfCooldownStyleAnimation = cfg.debuffanim
    plate.debuffs[index].cd.pfCooldownStyleText = cfg.debufftext
    plate.debuffs[index].cd.pfCooldownType = "ALL"
  end

  local function UpdateDebuffConfig(nameplate, i)
    if not nameplate.debuffs[i] then return end

    -- update debuff positions
    local width = tonumber(C.nameplates.width)
    local debuffsize = tonumber(C.nameplates.debuffsize)
    local debuffoffset = tonumber(C.nameplates.debuffoffset)
    local limit = floor(width / debuffsize)
    local font = C.nameplates.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    local font_style = C.nameplates.name.fontstyle

    local aligna, alignb, offs, space
    if C.nameplates.debuffs["position"] == "BOTTOM" then
      aligna, alignb, offs, space = "TOPLEFT", "BOTTOMLEFT", -debuffoffset, -1
    else
      aligna, alignb, offs, space = "BOTTOMLEFT", "TOPLEFT", debuffoffset, 1
    end

    nameplate.debuffs[i].stacks:SetFont(font, font_size, font_style)
    nameplate.debuffs[i]:ClearAllPoints()
    if i == 1 then
      nameplate.debuffs[i]:SetPoint(aligna, nameplate.health, alignb, 0, offs)
    elseif i <= limit then
      nameplate.debuffs[i]:SetPoint("LEFT", nameplate.debuffs[i-1], "RIGHT", 1, 0)
    elseif i > limit and limit > 0 then
      nameplate.debuffs[i]:SetPoint(aligna, nameplate.debuffs[i-limit], alignb, 0, space)
    end

    nameplate.debuffs[i]:SetSize(debuffsize, debuffsize)
    
    -- Update cooldown display settings
    if nameplate.debuffs[i].cd then
      local cooldown_text = tonumber(C.nameplates.debufftext) or 1
      local cooldown_anim = tonumber(C.nameplates.debuffanim) or 0
      nameplate.debuffs[i].cd.pfCooldownStyleText = cooldown_text
      nameplate.debuffs[i].cd.pfCooldownStyleAnimation = cooldown_anim
      
    end
  end

  -- create nameplate core
local nameplates = CreateFrame("Frame", "pfNameplates", UIParent)
nameplates:RegisterEvent("PLAYER_ENTERING_WORLD")
nameplates:RegisterEvent("PLAYER_TARGET_CHANGED")
nameplates:RegisterEvent("PLAYER_LOGOUT")
nameplates:RegisterEvent("UNIT_COMBO_POINTS")
nameplates:RegisterEvent("PLAYER_COMBO_POINTS")
nameplates:RegisterEvent("ZONE_CHANGED_NEW_AREA")
nameplates:RegisterEvent("RAID_ROSTER_UPDATE")
nameplates:RegisterEvent("PARTY_MEMBERS_CHANGED")
nameplates:RegisterEvent("NAME_PLATE_CREATED")
nameplates:RegisterEvent("NAME_PLATE_UNIT_ADDED")
nameplates:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
nameplates:RegisterEvent("UNIT_AURA")
nameplates:RegisterEvent("UNIT_FLAGS")
nameplates:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
nameplates:RegisterEvent("UNIT_SPELLCAST_START")
nameplates:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
nameplates:RegisterEvent("UNIT_SPELLCAST_STOP")
nameplates:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
nameplates:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
nameplates:RegisterEvent("PLAYER_GUILD_UPDATE")
  
  nameplates:SetScript("OnEvent", function()
    -- Stop event handling during logout to prevent crash 132
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      this:SetScript("OnUpdate", nil)
      if nameplates.mouselook then
        nameplates.mouselook:SetScript("OnUpdate", nil)
      end
      return

    elseif event == "PLAYER_GUILD_UPDATE" and arg1 == 'player' then
      myGuild = GetGuildInfo("player")

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
      if event == "PLAYER_ENTERING_WORLD" then
        CacheConfig()
        this:SetGameVariables()
        RebuildRaidGuidCache()
        frameState.targetGuid = UnitGUID("target")
        myGuild = GetGuildInfo("player")
      end
      
      -- Handle friendly zone nameplate disable feature
      local disableHostile = C.nameplates["disable_hostile_in_friendly"] == "1"
      local disableFriendly = C.nameplates["disable_friendly_in_friendly"] == "1"
      
      if disableHostile or disableFriendly then
        local pvpType = GetZonePVPInfo()
        local nowFriendly = (pvpType == "friendly")
        
        if nowFriendly and not inFriendlyZone then
          -- Entering friendly zone - save current state and hide based on options
          inFriendlyZone = true
          savedHostileState = C.nameplates["showhostile"]
          savedFriendlyState = C.nameplates["showfriendly"]
          
          if disableHostile then
            _G.NAMEPLATES_ON = nil
            HideNameplates()
          end
          
          if disableFriendly then
            _G.FRIENDNAMEPLATES_ON = nil
            HideFriendNameplates()
          end
        elseif not nowFriendly and inFriendlyZone then
          -- Leaving friendly zone - restore previous state
          inFriendlyZone = false
          
          if savedHostileState == "1" then
            _G.NAMEPLATES_ON = true
            ShowNameplates()
          end
          
          if savedFriendlyState == "1" then
            _G.FRIENDNAMEPLATES_ON = true
            ShowFriendNameplates()
          end
          
          savedHostileState = nil
          savedFriendlyState = nil
        end
      end

    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
      RebuildRaidGuidCache()

    elseif event == "NAME_PLATE_CREATED" then
      -- arg1 = the nameplate Frame; build the pfUI overlay once per pool slot
      if arg1 and not registry[arg1] then
        nameplates.OnCreate(arg1)
        registry[arg1] = arg1
      end

    elseif event == "NAME_PLATE_UNIT_ADDED" then
      -- arg1 = "nameplateN" unit token. Cache the GUID for cache keys and the
      -- token itself for token-based UnitX reads (stable per plate lifetime).
      local plate = C_NamePlate.GetNamePlateForUnit(arg1)
      if plate and plate.nameplate then
        visiblePlates[plate] = plate
        local guid = UnitGUID(arg1)
        plate.nameplate.cachedGuid = guid
        plate.nameplate.unit = arg1
        plate.nameplate.creatureType = nil  -- recompute for the new unit
        plate.nameplate.totemIcon = nil
        if guid then
          plateByGuid[guid] = plate.nameplate
          -- Seed: the unit may already be mid-cast (its UNIT_SPELLCAST_START
          -- fired before this plate existed). One poll here catches that;
          -- ongoing casts arrive via the event.
          castState[guid] = PollCastInfo(arg1)
        end
        nameplates.OnShow(plate)
      end
      visiblePlateCount = visiblePlateCount + 1

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
      visiblePlateCount = visiblePlateCount > 0 and visiblePlateCount - 1 or 0
      -- arg1 = "nameplateN" unit token; UnitGUID still resolves inside the
      -- handler (the slot is freed after dispatch returns)
      local plate = C_NamePlate.GetNamePlateForUnit(arg1)
      if plate then visiblePlates[plate] = nil end
      local guid = UnitGUID(arg1)
      if guid then
        if debuffCache[guid] then debuffCache[guid] = nil end
        if threatMemory[guid] then threatMemory[guid] = nil end
        if combatColorCache[guid] then combatColorCache[guid] = nil end
        if castState[guid] then castState[guid] = nil end
        if plateByGuid[guid] then plateByGuid[guid] = nil end
        if plate and plate.nameplate and plate.nameplate.cachedGuid == guid then
          plate.nameplate.cachedGuid = nil
          plate.nameplate.unit = nil
        end
      end

    elseif event == "UNIT_FLAGS" then
      if arg1 and strfind(arg1, "^nameplate") then
        local plate = C_NamePlate.GetNamePlateForUnit(arg1)
        if plate and plate.nameplate then
          plate.nameplate.eventcache = true
        end
      end

    elseif event == "UPDATE_MOUSEOVER_UNIT" then
      local new = UnitGUID("mouseover")
      local old = frameState.mouseoverGuid
      if new ~= old then
        frameState.mouseoverGuid = new
        local po = old and plateByGuid[old]
        if po then po.eventcache = true end
        local pn = new and plateByGuid[new]
        if pn then pn.eventcache = true end
      end

    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
      -- ClassicAPI fires UNIT_SPELLCAST_* per unit token, including the caster's
      -- "nameplateN". The payload has no timing, so poll it (PollCastInfo picks
      -- cast vs channel) and cache -- only for a unit we have a plate for, so
      -- the table stays bounded to on-screen casters.
      if arg1 and strfind(arg1, "^nameplate") then
        local guid = UnitGUID(arg1)
        local plate = guid and plateByGuid[guid]
        if plate then
          castState[guid] = PollCastInfo(arg1)
          if castState[guid] then
            plate.castUpdate = true  -- bypass the throttle so the bar shows now
          end
        end
      end

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
      -- Cast/channel ended (natural, interrupted, or cancelled -- the poll fires
      -- STOP for all three). Clear the cached cast and refresh its plate.
      if arg1 and strfind(arg1, "^nameplate") then
        local guid = UnitGUID(arg1)
        if guid and castState[guid] then
          castState[guid] = nil
          local plate = plateByGuid[guid]
          if plate then plate.castUpdate = true end
        end
      end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      -- Active totems (Searing/Magma/Fire Nova) carry no self-aura, so their
      -- attack cast is the only icon source. Capture it once per totem, gated on
      -- creature type so a normal caster's spell never styles it as a totem.
      if arg1 and strfind(arg1, "^nameplate") then
        local guid = UnitGUID(arg1)
        local plate = guid and plateByGuid[guid]
        if plate and not plate.totemIcon and arg3 and CreatureType(plate) == 11 then
          local tex = C_Spell.GetSpellTexture(arg3)
          if tex then
            plate.totemIcon = tex
            plate.castUpdate = true  -- re-render now so the icon shows
          end
        end
      end

    elseif event == "UNIT_AURA" then
      -- ClassicAPI: fires with arg1 == "nameplateN" when a unit's aura set
      -- changes (add/remove/modify). Flag the matching plate so OnUpdate does a
      -- fresh C_UnitAuras read next tick instead of waiting on the 0.5s
      -- throttle -- covers expirations, dispels, refreshes, and stack changes
      -- in one event. Guard on the token prefix (UNIT_AURA also fires for
      -- target/party/raid).
      if arg1 and strfind(arg1, "^nameplate") then
        local plate = C_NamePlate.GetNamePlateForUnit(arg1)
        if plate and plate.nameplate then
          plate.nameplate.auraUpdate = true
        end
      end

    elseif event == "PLAYER_TARGET_CHANGED" then
      frameState.targetGuid = UnitGUID('target')
      -- Flag the target's plate for update
      local plate = C_NamePlate.GetNamePlateForUnit("target")
      if plate and plate.nameplate then
        plate.nameplate.targetUpdate = true
      end
      -- Also propagate to all plates for alpha/strata updates
      this.eventcache = true

    elseif event == "PLAYER_COMBO_POINTS" or event == "UNIT_COMBO_POINTS" then
      -- Only flag the target's plate for combo point update
      local plate = C_NamePlate.GetNamePlateForUnit("target")
      if plate and plate.nameplate then
        plate.nameplate.comboUpdate = true
      end
    else
      this.eventcache = true
    end
  end)

  nameplates:SetScript("OnUpdate", function()
    -- PERF: Throttle central OnUpdate to ~80 FPS (0.0125s)
    -- Saves ~44% calls at 144 FPS while staying above 50 FPS target-plate rate
    local now = GetTime()
    if (this.frameTick or 0) + 0.01 > now then return end
    this.frameTick = now

    -- PERF: Cache GetTime() once per frame
    frameState.now = now

    if this.eventcache then
      this.eventcache = nil
      for plate in pairs(visiblePlates) do
        plate.nameplate.eventcache = true
      end
    end

    for plate in pairs(visiblePlates) do
      if plate:IsVisible() then
        nameplates.OnUpdate(plate, frameState)
      end
    end
  end)

  -- combat tracker
  nameplates.combat = CreateFrame("Frame")
  nameplates.combat:RegisterEvent("PLAYER_ENTER_COMBAT")
  nameplates.combat:RegisterEvent("PLAYER_LEAVE_COMBAT")
  nameplates.combat:RegisterEvent("PLAYER_LOGOUT")
  nameplates.combat:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
    elseif event == "PLAYER_ENTER_COMBAT" then
      this.inCombat = 1
      if PlayerFrame then PlayerFrame.inCombat = 1 end
    elseif event == "PLAYER_LEAVE_COMBAT" then
      this.inCombat = nil
      if PlayerFrame then PlayerFrame.inCombat = nil end
      -- Clear threat memory when leaving combat
      for k in pairs(threatMemory) do
        threatMemory[k] = nil
      end
    end
  end)

  nameplates.OnCreate = function(frame)
    local parent = frame or this
    platecount = platecount + 1
    local platename = "pfNamePlate" .. platecount

    -- create pfUI nameplate overlay
    local nameplate = CreateFrame("Button", platename, parent)
    nameplate.platename = platename
    nameplate:EnableMouse(0)
    nameplate.parent = parent
    nameplate.cache = {}
    nameplate.original = {}

    -- create shortcuts for all known elements and disable them
    nameplate.original.healthbar, nameplate.original.castbar = parent:GetChildren()
    DisableObject(nameplate.original.healthbar)
    DisableObject(nameplate.original.castbar)

    for i, object in pairs({parent:GetRegions()}) do
      if NAMEPLATE_OBJECTORDER[i] and NAMEPLATE_OBJECTORDER[i] == "raidicon" then
        nameplate[NAMEPLATE_OBJECTORDER[i]] = object
      elseif NAMEPLATE_OBJECTORDER[i] then
        nameplate.original[NAMEPLATE_OBJECTORDER[i]] = object
        DisableObject(object)
      else
        DisableObject(object)
      end
    end

    nameplate.original.healthbar:HookScript("OnValueChanged", nameplates.OnValueChanged)

    -- adjust sizes and scaling of the nameplate
    nameplate:SetScale(UIParent:GetScale())

    nameplate.health = CreateFrame("StatusBar", nil, nameplate)
    nameplate.health:SetFrameLevel(4) -- keep above glow
    nameplate.health.text = nameplate.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameplate.health.text:SetAllPoints()
    nameplate.health.text:SetTextColor(1,1,1,1)

    nameplate.name = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.name:SetPoint("TOP", nameplate, "TOP", 0, 0)

    nameplate.glow = nameplate:CreateTexture(nil, "BACKGROUND")
    nameplate.glow:SetPoint("CENTER", nameplate.health, "CENTER", 0, 0)
    nameplate.glow:SetTexture(pfUI.media["img:dot"])
    nameplate.glow:Hide()

    nameplate.guild = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.guild:SetPoint("BOTTOM", nameplate.health, "BOTTOM", 0, 0)

    nameplate.level = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.level:SetPoint("RIGHT", nameplate.health, "LEFT", -3, 0)

    -- Create a dedicated high-level frame for the raid icon so it renders
    -- ABOVE nameplate.health (FrameLevel 4) and stays visible even when
    -- nameplates are toggled off (the Blizzard parent plate still exists).
    nameplate.raidiconframe = CreateFrame("Frame", nil, nameplate)
    nameplate.raidiconframe:SetFrameLevel(10)
    nameplate.raidiconframe:SetAllPoints(nameplate)
    nameplate.raidicon:SetParent(nameplate.raidiconframe)
    nameplate.raidicon:SetDrawLayer("OVERLAY", 7)
    if C.unitframes.blizzard_raidicons ~= "1" then
      nameplate.raidicon:SetTexture(pfUI.media["img:raidicons"])
    end

    nameplate.totem = CreateFrame("Frame", nil, nameplate)
    nameplate.totem:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    nameplate.totem:SetSize(32, 32)
    nameplate.totem.icon = nameplate.totem:CreateTexture(nil, "OVERLAY")
    nameplate.totem.icon:SetTexCoord(.078, .92, .079, .937)
    nameplate.totem.icon:SetAllPoints()
    CreateBackdrop(nameplate.totem)

    do -- debuffs
      nameplate.debuffs = {}
      CreateDebuffIcon(nameplate, 1)
    end

    do -- combopoints
      local combopoints = { }
      for i = 1, 5 do
        combopoints[i] = CreateFrame("Frame", nil, nameplate)
        combopoints[i]:Hide()
        combopoints[i]:SetFrameLevel(8)
        combopoints[i].tex = combopoints[i]:CreateTexture("OVERLAY")
        combopoints[i].tex:SetAllPoints()

        if i < 3 then
          combopoints[i].tex:SetTexture(1, .3, .3, .75)
        elseif i < 4 then
          combopoints[i].tex:SetTexture(1, 1, .3, .75)
        else
          combopoints[i].tex:SetTexture(.3, 1, .3, .75)
        end
      end
      nameplate.combopoints = combopoints
    end

    do -- castbar
      local castbar = CreateFrame("StatusBar", nil, nameplate.health)
      castbar:Hide()

      castbar:SetScript("OnShow", function()
        if C.nameplates.debuffs["position"] == "BOTTOM" then
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this, "BOTTOMLEFT", 0, -4)
        end
      end)

      castbar:SetScript("OnHide", function()
        if C.nameplates.debuffs["position"] == "BOTTOM" then
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this:GetParent(), "BOTTOMLEFT", 0, -4)
        end
      end)

      castbar.text = castbar:CreateFontString("Status", "DIALOG", "GameFontNormal")
      castbar.text:SetPoint("RIGHT", castbar, "LEFT", -4, 0)
      castbar.text:SetNonSpaceWrap(false)
      castbar.text:SetTextColor(1,1,1,.5)

      castbar.spell = castbar:CreateFontString("Status", "DIALOG", "GameFontNormal")
      castbar.spell:SetPoint("CENTER", castbar, "CENTER")
      castbar.spell:SetNonSpaceWrap(false)
      castbar.spell:SetTextColor(1,1,1,1)

      castbar.icon = CreateFrame("Frame", nil, castbar)
      castbar.icon.tex = castbar.icon:CreateTexture(nil, "BORDER")
      castbar.icon.tex:SetAllPoints()

      nameplate.castbar = castbar
    end

    -- Stagger tick to spread updates across frames (0.05s apart per plate)
    nameplate.tick = GetTime() + mathmod(platecount, 10) * 0.05

    parent.nameplate = nameplate
    -- NOTE: OnUpdate is now handled centrally, not per-plate/
    parent:SetScript("OnUpdate", nil)  -- Disable Blizzard's OnUpdate

    nameplates.OnConfigChange(parent)
  end

  nameplates.OnConfigChange = function(frame)
    local parent = frame
    local nameplate = frame.nameplate

    local font = C.nameplates.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    local font_style = C.nameplates.name.fontstyle
    local glowr, glowg, glowb, glowa = GetStringColor(C.nameplates.glowcolor)
    local hlr, hlg, hlb, hla = GetStringColor(C.nameplates.highlightcolor)
    local hptexture = pfUI.media[C.nameplates.healthtexture]
    local rawborder, default_border = GetBorderSize("nameplates")

    local plate_width = C.nameplates.width + 50
    local plate_height = C.nameplates.heighthealth + font_size + 5
    -- local plate_height_cast = C.nameplates.heighthealth + font_size + 5 + C.nameplates.heightcast + 5
    local combo_size = 5

    -- local width = tonumber(C.nameplates.width)
    -- local debuffsize = tonumber(C.nameplates.debuffsize)
    local healthoffset = tonumber(C.nameplates.health.offset)
    local orientation = C.nameplates.verticalhealth == "1" and "VERTICAL" or "HORIZONTAL"

    local c = combatstate -- load combat state colors
    c.CASTING.r, c.CASTING.g, c.CASTING.b, c.CASTING.a = GetStringColor(C.nameplates.combatcasting)
    c.THREAT.r, c.THREAT.g, c.THREAT.b, c.THREAT.a = GetStringColor(C.nameplates.combatthreat)
    c.NOTHREAT.r, c.NOTHREAT.g, c.NOTHREAT.b, c.NOTHREAT.a = GetStringColor(C.nameplates.combatnothreat)
    c.OFFTANK.r, c.OFFTANK.g, c.OFFTANK.b, c.OFFTANK.a = GetStringColor(C.nameplates.combatofftank)
    c.STUN.r, c.STUN.g, c.STUN.b, c.STUN.a = GetStringColor(C.nameplates.combatstun)

    RebuildOfftanks()

    nameplate:SetSize(plate_width, plate_height)
    nameplate:SetPoint("TOP", parent, "TOP", 0, 0)

    nameplate.name:SetFont(font, font_size, font_style)
    local nameTextPos = C.nameplates.nametextpos or "CENTER"
    local nameAnchor = nameTextPos == "RIGHT" and { "BOTTOMRIGHT", "TOPRIGHT" }
                    or nameTextPos == "CENTER" and { "BOTTOM", "TOP" }
                    or { "BOTTOMLEFT", "TOPLEFT" }
    nameplate.name:ClearAllPoints()
    nameplate.name:SetPoint(nameAnchor[1], nameplate.health, nameAnchor[2], 0, -healthoffset)
    nameplate.name:SetJustifyH(nameTextPos)

    nameplate.health:SetOrientation(orientation)
    -- Bar anchors to the plate directly so the name's JustifyH (configurable
    -- below) can shift left/right without dragging the bar with it.
    nameplate.health:ClearAllPoints()
    nameplate.health:SetPoint("BOTTOM", nameplate, "BOTTOM", 0, 0)
    nameplate.health:SetStatusBarTexture(hptexture)
    nameplate.health:SetWidth(C.nameplates.width)
    nameplate.health:SetHeight(C.nameplates.heighthealth)
    nameplate.health.hlr, nameplate.health.hlg, nameplate.health.hlb, nameplate.health.hla = hlr, hlg, hlb, hla

    CreateBackdrop(nameplate.health, default_border)

    nameplate.health.text:SetFont(font, font_size - 2, "OUTLINE")
    nameplate.health.text:SetJustifyH(C.nameplates.hptextpos)

    nameplate.guild:SetFont(font, font_size, font_style)

    nameplate.glow:SetSize(C.nameplates.width + 60, C.nameplates.heighthealth + 30)
    nameplate.glow:SetVertexColor(glowr, glowg, glowb, glowa)

    nameplate.raidicon:ClearAllPoints()
    nameplate.raidicon:SetPoint("BOTTOM", nameplate.health, "TOP", C.nameplates.raidiconoffx, C.nameplates.raidiconoffy)
    nameplate.level:SetFont(font, font_size, font_style)
    nameplate.raidicon:SetSize(C.nameplates.raidiconsize, C.nameplates.raidiconsize)

    for i=1,16 do
      UpdateDebuffConfig(nameplate, i)
    end

    for i=1,5 do
      nameplate.combopoints[i]:SetSize(combo_size, combo_size)
      nameplate.combopoints[i]:SetPoint("TOPRIGHT", nameplate.health, "BOTTOMRIGHT", -(i-1)*(combo_size+default_border*3), -default_border*3)
      CreateBackdrop(nameplate.combopoints[i], default_border)
    end

    nameplate.castbar:SetPoint("TOPLEFT", nameplate.health, "BOTTOMLEFT", 0, -default_border*3)
    nameplate.castbar:SetPoint("TOPRIGHT", nameplate.health, "BOTTOMRIGHT", 0, -default_border*3)
    nameplate.castbar:SetHeight(C.nameplates.heightcast)
    -- Use the same castbar texture and color as the unit frame castbar (castbar.lua)
    local cbtexture = pfUI.media[C.appearance.castbar.texture]
    nameplate.castbar:SetStatusBarTexture(cbtexture or hptexture)
    local cbr, cbg, cbb, cba = GetStringColor(C.appearance.castbar.castbarcolor)
    nameplate.castbar:SetStatusBarColor(cbr, cbg, cbb, cba)
    -- reset endTime cache so color/texture refresh takes effect on next cast
    nameplate.castbar.lastEndTime = nil
    CreateBackdrop(nameplate.castbar, default_border)

    nameplate.castbar.text:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.spell:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.icon:SetPoint("BOTTOMLEFT", nameplate.castbar, "BOTTOMRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetPoint("TOPLEFT", nameplate.health, "TOPRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetWidth(C.nameplates.heightcast + default_border*3 + C.nameplates.heighthealth)
    CreateBackdrop(nameplate.castbar.icon, default_border)
  end

  nameplates.OnValueChanged = function()
    local plate = this:GetParent().nameplate
    if plate and plate.health then
      plate.health:SetMinMaxValues(plate.original.healthbar:GetMinMaxValues())
      plate.health:SetValue(plate.original.healthbar:GetValue())
    end
  end

  nameplates.OnDataChanged = function(self, plate)
    local visible = plate:IsVisible()
    local hp = plate.original.healthbar:GetValue()
    local hpmin, hpmax = plate.original.healthbar:GetMinMaxValues()
    local name = plate.original.name:GetText()
    local level = plate.original.level:IsShown() and plate.original.level:GetObjectType() == "FontString" and tonumber(plate.original.level:GetText()) or "??"

    -- reset per-unit cache when the plate is reassigned. Gate on GUID *and*
    -- name — name alone misses pool reuse between same-named units (e.g. plate
    -- held a player "Ironforge Guard" and is now reassigned to the NPC by the
    -- same name), which would leak a stale "PLAYER" hint into GetUnitInfo.
    -- Wipe the whole cache table: the PERF gates below ("only update X when
    -- X changed") would otherwise skip bar/color/text updates when the new
    -- unit happens to share a cached value with the previous occupant
    -- (e.g., both at 60% HP percentage on plate pool reuse → bar stays at
    -- the old fill until the new mob actually changes HP).
    if plate.cache.name ~= name or plate.cache.guid ~= plate.cachedGuid then
      table.wipe(plate.cache)
      plate.cache.name = name
      plate.cache.guid = plate.cachedGuid
      plate.cdCache = nil  -- new unit, reset spell-keyed timer cache
      plate.name:SetText(GetNameString(name))
    end

    local target = plate.istarget
    local mouseover = plate.cachedGuid and plate.cachedGuid == frameState.mouseoverGuid or nil
    local unitstr = target and "target" or mouseover and "mouseover" or plate.cachedGuid or nil

    -- target event sometimes fires too quickly, where nameplate identifiers are not
    -- yet updated. So while being inside this event, we cannot trust the unitstr.
    if event == "PLAYER_TARGET_CHANGED" then unitstr = nil end

    -- remove unitstr when it doesn't resolve to this plate's unit (stale istarget,
    -- stale mouseover guid or a despawned unit). Must run before the cache fills
    -- below -- an unrelated unitstr would poison cache.player/minion with the
    -- *other* unit's answer, and the nil-gate would then never recompute it.
    if unitstr and UnitName(unitstr) ~= name then unitstr = nil end

    -- resolve player vs npc from plate's own unit so libunitscan can't return
    -- a player record for an NPC sharing the same name (e.g. Chromie). Stored
    -- as true/false/nil so it doubles as the GetUnitInfo hint.
    if plate.cache.player == nil and unitstr then
      plate.cache.player = UnitIsPlayer(unitstr) and true or false
    end
    if plate.cache.minion == nil and unitstr then
      plate.cache.minion = UnitIsMinion(unitstr) and true or false
    end
    local class, ulevel, elite, player, guild
    if not plate.cache.minion then
      class, ulevel, elite, player, guild = GetUnitInfo(name, true, plate.cache.player)
    end
    if plate.cache.player ~= nil then player = plate.cache.player or nil end

    -- Use database level ONLY if current level is ?? (fixes ?? after reload, but doesn't override visible levels)
    local levelFromDB = false
    if level == "??" and ulevel and ulevel > 0 then
      level = ulevel
      levelFromDB = true
    end

    local red, green, blue = plate.original.healthbar:GetStatusBarColor()
    local unittype = GetUnitType(red, green, blue) or "ENEMY_NPC"
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size

    -- ignore players with npc names if plate level is lower than player level
    if ulevel and ulevel > (level == "??" and -1 or level) then player = nil end

    if player and unittype == "ENEMY_NPC" then unittype = "ENEMY_PLAYER" end
    if player and unittype == "FRIENDLY_NPC" then unittype = "FRIENDLY_PLAYER" end
    elite = plate.original.levelicon:IsShown() and not player and "boss" or elite
    if not class and not plate.cache.minion then plate.wait_for_scan = true end

    -- skip data updates on invisible frames
    if not visible then return end

    -- always make sure to keep plate visible
    plate:Show()

    plate.glow:SetShown(target and cfg.targetglow)

    -- target indicator
    if cfg.outcombatstate then
      local guid = plate.cachedGuid or ""

      -- determine color based on combat state
      local color = GetCombatStateColor(guid, plate.unit)
      if not color then color = combatstate.NONE end

      -- set border color
      plate.health.backdrop:SetBackdropBorderColor(color.r, color.g, color.b, color.a)
    elseif target and cfg.targethighlight then
      plate.health.backdrop:SetBackdropBorderColor(plate.health.hlr, plate.health.hlg, plate.health.hlb, plate.health.hla)
    elseif C.nameplates.outfriendlynpc == "1" and unittype == "FRIENDLY_NPC" then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outfriendly == "1" and unittype == "FRIENDLY_PLAYER" then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outneutral == "1" and strfind(unittype, "NEUTRAL") then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outenemy == "1" and strfind(unittype, "ENEMY") then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    else
      plate.health.backdrop:SetBackdropBorderColor(er,eg,eb,ea)
    end

    -- hide frames according to the configuration
    local TotemIcon = TotemPlate(plate)

    if TotemIcon then
      -- icon resolved from the totem's aura / attack cast (already a full path)
      plate.totem.icon:SetTexture(TotemIcon)

      plate.glow:Hide()
      plate.level:Hide()
      plate.name:Hide()
      plate.health:Hide()
      plate.guild:Hide()
      plate.totem:Show()
    elseif HidePlate(unittype, (hpmax-hp == hpmin), target, plate) then
      plate.level:SetPoint("RIGHT", plate.name, "LEFT", -3, 0)
      plate.name:SetParent(plate)
      plate.guild:SetPoint("BOTTOM", plate.name, "BOTTOM", -2, -(font_size + 2))

      plate.level:Show()
      plate.name:Show()
      plate.health:Hide()
      if guild and C.nameplates.showguildname == "1" then
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, -(font_size / 2) - 2)
      else
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, 0)
      end
      plate.totem:Hide()
    else
      plate.level:SetPoint("RIGHT", plate.health, "LEFT", -5, 0)
      plate.name:SetParent(plate.health)
      plate.guild:SetPoint("BOTTOM", plate.health, "BOTTOM", 0, -(font_size + 4))

      plate.level:Show()
      plate.name:Show()
      plate.health:Show()
      plate.glow:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
      plate.totem:Hide()
    end

    -- Gate level SetText behind a (level, elite) cache. string.format
    -- here was firing every OnDataChanged tick per plate; with the cache
    -- it only re-formats on real changes (level up / elite-state flip).
    if plate.cache.level ~= level or plate.cache.elite ~= elite then
      plate.cache.level = level
      plate.cache.elite = elite
      plate.level:SetFormattedText("%s%s", level, (elitestrings[elite] or ""))
    end

    -- Set level color from GetDifficultyColor when using DB level.
    -- No brightening here: adding a flat offset to all three channels
    -- desaturates every tier toward white and collapses the boundaries
    -- (orange reads as yellow, red reads as orange). Use Blizzard's values.
    -- Clearing cache.levelcolor forces the sync block in OnUpdate to
    -- re-colour once the ?? resolves and it takes ownership again.
    if levelFromDB and type(level) == "number" then
      local color = GetDifficultyColor(level)
      plate.level:SetTextColor(color.r, color.g, color.b, 1)
      plate.cache.levelcolor = nil
    end

    -- remember who owns the level colour so the two writers cannot fight
    plate.cache.levelfromdb = levelFromDB or nil

    if guild and C.nameplates.showguildname == "1" then
      plate.guild:SetText(guild)
      if guild == myGuild then
        plate.guild:SetTextColor(0, 0.9, 0, 1)
      else
        plate.guild:SetTextColor(0.8, 0.8, 0.8, 1)
      end
      plate.guild:Show()
    else
      plate.guild:Hide()
    end

    -- PERF: Only update bar + HP text when values actually changed
    if plate.cache.hp ~= hp or plate.cache.hpmax ~= hpmax then
      plate.cache.hp = hp
      plate.cache.hpmax = hpmax
      plate.health:SetMinMaxValues(hpmin, hpmax)
      plate.health:SetValue(hp)

    if cfg.showhp then
      local rhp, rhpmax, estimated
      local unit = plate.unit
      if unit then
        local npHp = UnitHealth(unit)
        local npMaxHp = UnitHealthMax(unit)
        if npHp and npHp > 0 and npMaxHp and npMaxHp > 0 and npMaxHp ~= 100 then
          rhp, rhpmax = npHp, npMaxHp
        end
      end

      -- Fallback to existing methods
      if not rhp then
        if hpmax > 100 or (round(hpmax/100*hp) ~= hp) then
          rhp, rhpmax = hp, hpmax
        elseif pfUI.libhealth and pfUI.libhealth.enabled then
          rhp, rhpmax, estimated = pfUI.libhealth:GetUnitHealthByName(name,level,tonumber(hp),tonumber(hpmax))
        end
      end

      local setting = cfg.hptextformat
      local hasdata = ( rhp and rhpmax ) or estimated or hpmax > 100 or (round(hpmax/100*hp) ~= hp)

      if setting == "curperc" and hasdata and rhp then
        plate.health.text:SetFormattedText("%s | %s%%", Abbreviate(rhp), ceil(hp/hpmax*100))
      elseif setting == "cur" and hasdata and rhp then
        plate.health.text:SetFormattedText("%s", Abbreviate(rhp))
      elseif setting == "curmax" and hasdata and rhp then
        plate.health.text:SetFormattedText("%s - %s", Abbreviate(rhp), Abbreviate(rhpmax))
      elseif setting == "curmaxs" and hasdata and rhp then
        plate.health.text:SetFormattedText("%s / %s", Abbreviate(rhp), Abbreviate(rhpmax))
      elseif setting == "curmaxperc" and hasdata and rhp then
        plate.health.text:SetFormattedText("%s - %s | %s%%", Abbreviate(rhp), Abbreviate(rhpmax), ceil(hp/hpmax*100))
      elseif setting == "curmaxpercs" and hasdata and rhp then
        plate.health.text:SetFormattedText("%s / %s | %s%%", Abbreviate(rhp), Abbreviate(rhpmax), ceil(hp/hpmax*100))
      elseif setting == "deficit" and rhp then
        plate.health.text:SetFormattedText("-%s" .. (hasdata and "" or "%%"), Abbreviate(rhpmax - rhp))
      else -- "percent" as fallback
        plate.health.text:SetFormattedText("%s%%", ceil(hp/hpmax*100))
      end
    else
      plate.health.text:SetText()
    end
    end -- hp cache gate

    local r, g, b, a = unpack(unitcolors[unittype])

    if class and (
      (unittype == "ENEMY_PLAYER" and C.nameplates["enemyclassc"] == "1") or
      (unittype == "FRIENDLY_PLAYER" and C.nameplates["friendclassc"] == "1")
    ) then
      r, g, b, a = PFUI_CLASS_COLORS[class]:GetRGBA()
    end

    if unitstr and UnitIsTapped(unitstr) and not UnitIsTappedByPlayer(unitstr) then
      r, g, b, a = .5, .5, .5, .8
    end

    if cfg.barcombatstate then
      local guid = plate.cachedGuid or ""
      local color = GetCombatStateColor(guid, plate.unit)

      if color then
        r, g, b, a = color.r, color.g, color.b, color.a
      end
    end

    if r ~= plate.cache.r or g ~= plate.cache.g or b ~= plate.cache.b then
      plate.health:SetStatusBarColor(r, g, b, a)
      plate.cache.r, plate.cache.g, plate.cache.b = r, g, b
    end

    -- Friendly player names take this colour when friendclassnamec is on.
    -- Ownership is recorded so the OnUpdate sync below stands down rather than
    -- racing us: both writers used to share cache.namecolor despite storing
    -- unrelated quantities (this colour vs Blizzard's name FontString), so
    -- either could suppress the other -- and since nameplate.cache survives
    -- pool reuse, a recycled plate could keep the previous unit's name colour.
    local ownname = unittype == "FRIENDLY_PLAYER" and C.nameplates["friendclassnamec"] == "1"
      and class and true or nil

    if plate.cache.ownname ~= ownname then
      plate.cache.ownname = ownname
      -- ownership flipped: whichever writer is now in charge must re-assert
      plate.cache.namecolor = nil
      plate.cache.ownnamecolor = nil
    end

    -- read the class colour directly rather than reusing the bar's r,g,b: the
    -- bar only carries a class colour when friendclassc happens to be on, and
    -- it also picks up the tapped-grey and barcombatstate overrides, neither of
    -- which belongs on the name.
    if ownname then
      local cr, cg, cb, ca = PFUI_CLASS_COLORS[class]:GetRGBA()
      if cr + cg + cb ~= plate.cache.ownnamecolor then
        plate.cache.ownnamecolor = cr + cg + cb
        plate.name:SetTextColor(cr, cg, cb, ca)
      end
    end

    if target and C.nameplates.cpdisplay == "1" then
      local cp = GetComboPoints("target")
      if plate.cpShown ~= cp then
        for i=1, 5 do plate.combopoints[i]:SetShown(i <= cp) end
        plate.cpShown = cp
      end
    elseif plate.cpShown then
      for i=1, 5 do plate.combopoints[i]:Hide() end
      plate.cpShown = nil
    end

    -- update debuffs
    local index = 1

    local isFriendly = unittype == "FRIENDLY_PLAYER" or unittype == "FRIENDLY_NPC"
    local showDebuffsForType = cfg.showdebuffs and (isFriendly and cfg.showdebuffs_friendly or (not isFriendly and cfg.showdebuffs_hostile))
    if showDebuffsForType then
      -- Pull debuffs from C_UnitAuras (HARMFUL range). owndebuffs adds the
      -- PLAYER filter token so only auras whose caster GUID matches the local
      -- player come through. debuffDisplayBuf is a module-level reusable
      -- buffer (no GC churn).
      local debuffCount = 0
      for i = 1, 16 do debuffDisplayBuf[i].effect = nil end
      if unitstr then
        local filter = cfg.owndebuffs and "HARMFUL|PLAYER" or "HARMFUL"
        local now = GetTime()
        -- positional UnitAura writes straight into the reusable buffer, so the
        -- per-plate scan allocates nothing (no per-aura table, no result array)
        local i = 1
        while debuffCount < 16 do
          local aname, icon, count, dispelType, duration, expirationTime = C_UnitAuras.UnitAura(unitstr, i, filter)
          if not aname then break end
          debuffCount = debuffCount + 1
          local b = debuffDisplayBuf[debuffCount]
          b.effect = aname
          b.texture = icon
          b.stacks = count
          b.dtype = dispelType
          b.duration = duration
          b.timeleft = (expirationTime and expirationTime > 0) and (expirationTime - now) or nil
          i = i + 1
        end
      end
      for i = 1, 16 do
        local effect, texture, stacks, dtype, duration, timeleft
        if debuffDisplayBuf[i].effect then
          local b = debuffDisplayBuf[i]
          effect, texture, stacks, dtype, duration, timeleft = b.effect, b.texture, b.stacks, b.dtype, b.duration, b.timeleft
        end

        if effect and texture and DebuffFilter(effect) then
          if not plate.debuffs[index] then
            CreateDebuffIcon(plate, index)
            UpdateDebuffConfig(plate, index)
          end

          plate.debuffs[index]:Show()
          plate.debuffs[index].icon:SetTexture(texture)
          plate.debuffs[index].icon:SetTexCoord(.078, .92, .079, .937)

          if stacks and stacks > 1 and C.nameplates.debuffs["showstacks"] == "1" then
            plate.debuffs[index].stacks:SetText(stacks)
            plate.debuffs[index].stacks:Show()
          else
            plate.debuffs[index].stacks:Hide()
          end

          if duration and timeleft and cfg.debufftimers then
            -- C_UnitAuras returns the Spell.dbc base duration, which talents
            -- can extend past — Shadow Affinity bumps SW:P from 18s to 24s,
            -- so a fresh cast has timeleft > duration and `now + timeleft -
            -- duration` lands in the future, which CooldownFrame_SetTimer
            -- treats as "not yet started" (no swirl). Widen to whichever is
            -- larger so start <= now.
            local effDuration = duration > timeleft and duration or timeleft
            plate.cdCache = plate.cdCache or {}
            local newStart = GetTime() + timeleft - effDuration
            local slotCache = plate.cdCache[index]
            local cachedStart = slotCache and slotCache.effect == effect and slotCache.start
            local cd = plate.debuffs[index].cd
            cd:Show()
            if not cachedStart or abs(cachedStart - newStart) > 0.5 then
              if not cd.configCached or cd.cachedAnim ~= cfg.debuffanim or cd.cachedText ~= cfg.debufftext then
                cd.pfCooldownStyleAnimation = cfg.debuffanim
                cd.pfCooldownStyleText = cfg.debufftext
                cd:SetAlpha(cfg.debuffanim == 1 and 1 or 0)
                cd.cachedAnim = cfg.debuffanim
                cd.cachedText = cfg.debufftext
                cd.configCached = true
              end
              CooldownFrame_SetTimer(cd, newStart, effDuration, 1)
              plate.cdCache[index] = plate.cdCache[index] or {}
              plate.cdCache[index].effect = effect
              plate.cdCache[index].start = newStart
            end
          end

          index = index + 1
        end
      end
    end

    -- hide remaining debuffs
    for i = index, 16 do
      if plate.debuffs[i] then
        plate.debuffs[i]:Hide()
      end
    end
  end

  nameplates.OnShow = function(frame)
    nameplates:OnDataChanged((frame or this).nameplate)
  end

  nameplates.OnUpdate = function(frame, state)
    local nameplate = frame.nameplate
    local now = state and state.now or GetTime()

    -- cachedGuid is maintained by NAME_PLATE_UNIT_ADDED / _REMOVED events.

    -- PERF: Intelligent throttling based on target/castbar status and plate count
    -- Use GUID comparison as primary target detection: instant, immune to alpha transitions,
    -- and immediately correct on de-target (unlike istarget which updates one tick later)
    local targetGuid = state and state.targetGuid
    local target = (targetGuid and nameplate.cachedGuid and targetGuid == nameplate.cachedGuid) or
                   (state and state.targetGuid and frame:GetAlpha() >= 0.99) or nil
    -- Target plate castbar runs on its own dedicated frame (nameplates.castbarFrame).
    -- For non-target plates with castbar active, use castbar throttle to ensure
    -- smooth animation without overloading the central loop.
    local isCastingNonTarget = not target and nameplate.castbar and nameplate.castbar:IsShown()
    if not isCastingNonTarget and not target and cfg.showcastbar and nameplate.cachedGuid then
      local castInfo = GetCastInfo(nameplate.unit)
      if castInfo and castInfo.endTime > now then
        isCastingNonTarget = true
      end
    end

    -- hide castbar before throttle if no cast active
    if not isCastingNonTarget and not target then
      if nameplate.castbar.isShown then
        nameplate.castbar.isShown = nil
        nameplate.castbar.lastEndTime = nil
        nameplate.castbar:Hide()
      end
    end

    local throttle
    if target then
      throttle = pfUI.throttle:Get("nameplates_target")
    elseif visiblePlateCount > 20 then
      throttle = pfUI.throttle:Get("nameplates_mass")
    else
      throttle = pfUI.throttle:Get("nameplates")
    end

    -- Non-target plates with active castbar use the castbar throttle
    if isCastingNonTarget then
      local cbThrottle = pfUI.throttle:Get("nameplates_castbar")
      if cbThrottle < throttle then throttle = cbThrottle end
    end

    -- Check for pending event updates (these bypass throttle for immediate response)
    local hasEventUpdate = nameplate.eventcache or nameplate.auraUpdate or nameplate.castUpdate or nameplate.targetUpdate or nameplate.comboUpdate

    -- Event updates bypass throttle
    if not hasEventUpdate and (nameplate.lasttick or 0) + throttle > now then return end
    nameplate.lasttick = now
    
    -- =========================================================================
    -- EVERYTHING BELOW RUNS AT THROTTLED RATE (50 FPS target, 10 FPS others)
    -- =========================================================================
    
    local update
    local original = nameplate.original
    local name = original.name:GetText()
    local mouseover = nameplate.cachedGuid and nameplate.cachedGuid == frameState.mouseoverGuid or nil

    -- trigger queued event update
    if hasEventUpdate then
      nameplates:OnDataChanged(nameplate)
      nameplate.eventcache = nil
      nameplate.auraUpdate = nil
      nameplate.castUpdate = nil
      nameplate.targetUpdate = nil
      nameplate.comboUpdate = nil
    end

    -- =========================================================================
    -- OVERLAP/CLICKTHROUGH HANDLING
    -- =========================================================================
    local useOverlap = C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0"
    local clickable = C.nameplates["clickthrough"] ~= "1"

    if not clickable then
      frame:EnableMouse(false)
      nameplate:EnableMouse(false)
    else
      local plate = useOverlap and nameplate or frame
      plate:EnableMouse(clickable)
    end

    if C.nameplates["overlap"] == "1" then
      if frame:GetWidth() > 1 then
        frame:SetSize(1, 1)
      end
    else
      if not nameplate.dwidth then
        nameplate.dwidth = floor(nameplate:GetWidth() * UIParent:GetScale())
      end

      if floor(frame:GetWidth()) ~= nameplate.dwidth then
        local nameW, nameH = nameplate:GetSize()
        local uiScale = UIParent:GetScale()
        frame:SetSize(nameW * uiScale, nameH * uiScale)
      end
    end

    local mouseEnabled = nameplate:IsMouseEnabled()
    if C.nameplates["clickthrough"] == "0" and C.nameplates["overlap"] == "1" and SpellIsTargeting() == mouseEnabled then
      nameplate:EnableMouse(not mouseEnabled)
    end

    -- Cache strata changes
    if nameplate.istarget ~= target then
      nameplate.target_strata = nil
    end

    if target and nameplate.target_strata ~= 1 then
      nameplate:SetFrameStrata("LOW")
      nameplate.target_strata = 1
    elseif not target and nameplate.target_strata ~= 0 then
      nameplate:SetFrameStrata("BACKGROUND")
      nameplate.target_strata = 0
    end

    nameplate.istarget = target

    -- Set non-target plate alpha
    local configAlpha = cfg.notargalpha or 0.5
    local desiredAlpha = (target or not state.targetGuid) and 1 or configAlpha

    if nameplate.cachedAlpha ~= desiredAlpha then
      nameplate:SetAlpha(desiredAlpha)
      nameplate.cachedAlpha = desiredAlpha
    end

    -- queue update on visual target update
    if nameplate.cache.target ~= target then
      nameplate.cache.target = target
      update = true
    end

    -- queue update on visual mouseover update
    if nameplate.cache.mouseover ~= mouseover then
      nameplate.cache.mouseover = mouseover
      update = true
    end

    -- trigger update when unit was found. Pass the cached player hint so the
    -- retry probes the same table OnDataChanged will read on the next pass —
    -- otherwise an NPC sharing a name with a known player flips wait_for_scan
    -- off here, then OnDataChanged re-sets it, every frame until the mob scan
    -- lands.
    if nameplate.wait_for_scan and not nameplate.cache.minion and GetUnitInfo(name, true, nameplate.cache.player) then
      nameplate.wait_for_scan = nil
      update = true
    end

    -- trigger update when name color changed (includes combat state check).
    -- Skipped once OnDataChanged owns the name colour (class-coloured friendly
    -- players), so the two writers cannot overwrite each other.
    if not nameplate.cache.ownname then
      local r, g, b = original.name:GetTextColor()
      local inCombatWithPlayer = cfg.namefightcolor and UnitAffectingCombat(nameplate.unit) and UnitAffectingCombat("player")

      if r + g + b ~= nameplate.cache.namecolor or (cfg.namefightcolor and nameplate.cache.inCombat ~= inCombatWithPlayer) then
        nameplate.cache.namecolor = r + g + b
        nameplate.cache.inCombat = inCombatWithPlayer

        if cfg.namefightcolor then
          if (r > .9 and g < .2 and b < .2) or inCombatWithPlayer then
            nameplate.name:SetTextColor(1,0.4,0.2,1)
          else
            nameplate.name:SetTextColor(r,g,b,1)
          end
        else
          nameplate.name:SetTextColor(1,1,1,1)
        end
        update = true
      end
    end

    -- trigger update when level color changed. Skipped while the level came
    -- from the database (?? plates), where OnDataChanged owns the colour --
    -- otherwise both writers race and cache.levelcolor goes stale, which
    -- leaves a recycled plate wearing the previous unit's colour.
    if not nameplate.cache.levelfromdb then
      local r, g, b = original.level:GetTextColor()
      if r + g + b ~= nameplate.cache.levelcolor then
        nameplate.cache.levelcolor = r + g + b
        nameplate.level:SetTextColor(r,g,b,1)
        update = true
      end
    end

    -- use timer based updates
    if not nameplate.tick or nameplate.tick < now then
      update = true
    end

    -- run full updates if required
    if update then
      nameplates:OnDataChanged(nameplate)
      nameplate.tick = now + .5
    end

    -- Zoom animation
    if target and cfg.targetzoom then
      if not nameplate.health.zoomed then
        local zoomval = cfg.zoomval
        local wc = cfg.width * zoomval
        local hc = cfg.heighthealth * (zoomval * .9)
        nameplate.health.targetWidth = wc
        nameplate.health.targetHeight = hc
      end
      
      local w, h = nameplate.health:GetSize()
      local wc, hc = nameplate.health.targetWidth, nameplate.health.targetHeight
      
      if wc and hc then
        if wc > w + 0.5 then
          nameplate.health:SetWidth(w*1.05)
          nameplate.health.zoomTransition = true
        elseif hc > h + 0.5 then
          nameplate.health:SetHeight(h*1.05)
          nameplate.health.zoomTransition = true
        else
          if nameplate.health.zoomTransition then
            nameplate.health:SetSize(wc, hc)
            nameplate.health.zoomTransition = nil
          end
          nameplate.health.zoomed = true
        end
      end
    elseif nameplate.health.zoomed or nameplate.health.zoomTransition then
      local w, h = nameplate.health:GetSize()
      local wc = cfg.width
      local hc = cfg.heighthealth

      if w > wc + 0.5 then
        nameplate.health:SetWidth(w*.95)
      elseif h > hc + 0.5 then
        nameplate.health:SetHeight(h*0.95)
      else
        nameplate.health:SetSize(wc, hc)
        nameplate.health.zoomTransition = nil
        nameplate.health.zoomed = nil
        nameplate.health.targetWidth = nil
        nameplate.health.targetHeight = nil
      end
    end

    -- Target plate castbar is handled by nameplates.castbarFrame (dedicated OnUpdate,
    -- engine framerate, decoupled from central loop). Only update non-target castbars here.
    local isTargetPlate = target or nameplate.istarget or (nameplate.health and nameplate.health.zoomed)
    if cfg.showcastbar and not cfg.targetcastbar and not isTargetPlate then
      local cbThrottle = pfUI.throttle:Get("nameplates_castbar")
      if visiblePlateCount > 20 then
        local massThrottle = pfUI.throttle:Get("nameplates_mass")
        if massThrottle > cbThrottle then cbThrottle = massThrottle end
      end
      if (nameplate.castbar_tick or 0) + cbThrottle <= now then
        nameplate.castbar_tick = now
        nameplates.UpdateCastbar(nameplate, now)
      end
    elseif cfg.showcastbar and cfg.targetcastbar and not isTargetPlate then
      if nameplate.castbar.isShown then
        nameplate.castbar.isShown = nil
        nameplate.castbar.lastEndTime = nil
        nameplate.castbar:Hide()
      end
    elseif not cfg.showcastbar then
      if nameplate.castbar.isShown then
        nameplate.castbar.isShown = nil
        nameplate.castbar.lastEndTime = nil
        nameplate.castbar:Hide()
      end
    end
  end

  -- ============================================================================
  -- DEDICATED TARGET CASTBAR FRAME
  -- Runs on its own OnUpdate, decoupled from the central nameplate loop.
  -- Mirrors the approach used in castbar.lua for the target unit frame castbar.
  -- ============================================================================

  -- Skip SetText when the rounded value hasn't changed since last frame.
  -- `string.format("%.2f", ...)` allocates a fresh string every call; this
  -- gate compares cheap integers and only formats when the displayed value
  -- would actually differ. Reset via lastEndTime-changed branch above.
  local function SetCastbarText(castbar, remaining)
    local rounded
    if C.unitframes.castbardecimals == "1" then
      rounded = floor(remaining * 10)
      if castbar.lastTextTick ~= rounded then
        castbar.lastTextTick = rounded
        castbar.text:SetText(rounded / 10)
      end
    else
      rounded = floor(remaining * 100)
      if castbar.lastTextTick ~= rounded then
        castbar.lastTextTick = rounded
        castbar.text:SetFormattedText("%.2f", remaining)
      end
    end
  end

  -- Shared castbar update logic (used by both dedicated frame and central loop)
  nameplates.UpdateCastbar = function(nameplate, now)
    if not nameplate or not nameplate.castbar then return end
    local castInfo = GetCastInfo(nameplate.unit)
    if not castInfo or castInfo.endTime < now then
      nameplate.castbar.isShown = nil
      nameplate.castbar.lastEndTime = nil
      nameplate.castbar:Hide()
      return
    end

    local isChannel = castInfo.isChannel
    local duration = castInfo.duration
    if nameplate.castbar.lastEndTime ~= castInfo.endTime then
      nameplate.castbar.lastEndTime = castInfo.endTime
      nameplate.castbar.lastTextTick = nil
      -- Relative 0..duration range to avoid float precision loss with large
      -- absolute timestamps.
      nameplate.castbar:SetMinMaxValues(0, duration)
      nameplate.castbar:SetStatusBarColor(GetStringColor(C.appearance.castbar[(isChannel and "channelcolor" or "castbarcolor")]))
      if castInfo.icon then
        nameplate.castbar.icon.tex:SetTexture(castInfo.icon)
        nameplate.castbar.icon.tex:SetTexCoord(.1,.9,.1,.9)
      end
      if cfg.spellname then
        nameplate.castbar.spell:SetText(castInfo.spellName)
      else
        nameplate.castbar.spell:SetText("")
      end
    end

    local barValue = isChannel and (castInfo.endTime - now) or (now - castInfo.startTime)
    if barValue < 0 then barValue = 0 end
    if barValue > duration then barValue = duration end
    nameplate.castbar:SetValue(barValue)
    SetCastbarText(nameplate.castbar, castInfo.endTime - now)
    if not nameplate.castbar.isShown then nameplate.castbar.isShown = true; nameplate.castbar:Show() end
  end

  -- Dedicated frame that updates ONLY the target plate castbar. Unthrottled:
  -- now that casts are event-driven, this just reads the cache + SetValue, so
  -- it animates the fill every frame for the smoothest sweep on the bar the
  -- player watches most. (Non-target plates stay throttled via the central
  -- loop's nameplates_castbar gate.)
  nameplates.castbarFrame = CreateFrame("Frame", nil, UIParent)
  nameplates.castbarFrame:SetScript("OnUpdate", function()
    if not cfg.showcastbar or not frameState.targetGuid then return end
    local nameplate = plateByGuid[frameState.targetGuid]
    if not nameplate then return end
    nameplates.UpdateCastbar(nameplate, GetTime())
  end)

  -- set nameplate game settings
  nameplates.SetGameVariables = function()
    -- update visibility (hostile)
    if C.nameplates["showhostile"] == "1" then
      _G.NAMEPLATES_ON = true
      ShowNameplates()
    else
      _G.NAMEPLATES_ON = nil
      HideNameplates()
    end

    -- update visibility (hostile)
    if C.nameplates["showfriendly"] == "1" then
      _G.FRIENDNAMEPLATES_ON = true
      ShowFriendNameplates()
    else
      _G.FRIENDNAMEPLATES_ON = nil
      HideFriendNameplates()
    end
  end

  nameplates:SetGameVariables()

  nameplates.UpdateConfig = function()
    -- Refresh config cache for all cfg.* values
    CacheConfig()
    RebuildOfftanks()
    
    -- update debuff filters
    DebuffFilterPopulate()

    -- Check friendly zone state when config changes
    local disableHostile = C.nameplates["disable_hostile_in_friendly"] == "1"
    local disableFriendly = C.nameplates["disable_friendly_in_friendly"] == "1"
    local pvpType = GetZonePVPInfo()
    local nowFriendly = (pvpType == "friendly")
    
    if nowFriendly and (disableHostile or disableFriendly) then
      if not inFriendlyZone then
        -- Just entered friendly zone or feature just enabled
        inFriendlyZone = true
        savedHostileState = C.nameplates["showhostile"]
        savedFriendlyState = C.nameplates["showfriendly"]
      end
      
      -- Apply current settings based on options
      if disableHostile then
        _G.NAMEPLATES_ON = nil
        HideNameplates()
      else
        -- Restore hostile if option is off but we're in friendly zone
        if savedHostileState == "1" then
          _G.NAMEPLATES_ON = true
          ShowNameplates()
        end
      end
      
      if disableFriendly then
        _G.FRIENDNAMEPLATES_ON = nil
        HideFriendNameplates()
      else
        -- Restore friendly if option is off but we're in friendly zone
        if savedFriendlyState == "1" then
          _G.FRIENDNAMEPLATES_ON = true
          ShowFriendNameplates()
        end
      end
      
      return -- Don't call SetGameVariables
    elseif inFriendlyZone and not (disableHostile or disableFriendly) then
      -- Both features disabled while in friendly zone - restore state
      inFriendlyZone = false
      
      if savedHostileState == "1" then
        C.nameplates["showhostile"] = savedHostileState
      end
      
      if savedFriendlyState == "1" then
        C.nameplates["showfriendly"] = savedFriendlyState
      end
      
      savedHostileState = nil
      savedFriendlyState = nil
      -- Fall through to SetGameVariables to restore nameplates
    end

    -- update nameplate visibility
    nameplates:SetGameVariables()

    -- apply all config changes
    for plate in pairs(registry) do
      nameplates.OnConfigChange(plate)
      if plate.nameplate and plate.nameplate.cachedGuid then
        nameplates:OnDataChanged(plate.nameplate)
      end
    end
  end

  local hookOnConfigChange = nameplates.OnConfigChange
  nameplates.OnConfigChange = function(self)
    hookOnConfigChange(self)

    local parent = self
    local nameplate = self.nameplate
    local plate = (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") and nameplate or parent

    -- disable all clicks for now
    parent:EnableMouse(false)
    nameplate:EnableMouse(false)

    -- adjust vertical offset
    if C.nameplates["vertical_offset"] ~= "0" then
      nameplate:SetPoint("TOP", parent, "TOP", 0, tonumber(C.nameplates["vertical_offset"]))
    end

    -- replace clickhandler
    if C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0" then
      plate:SetScript("OnClick", function() parent:Click() end)
    end

    -- enable mouselook on rightbutton down
    if C.nameplates["rightclick"] == "1" then
      plate:SetScript("OnMouseDown", nameplates.mouselook.OnMouseDown)
    else
      plate:SetScript("OnMouseDown", nil)
    end
  end

  local hookOnDataChanged = nameplates.OnDataChanged
  nameplates.OnDataChanged = function(self, nameplate)
    hookOnDataChanged(self, nameplate)

    -- make sure to keep mouse events disabled on parent nameplate
    if (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") then
      nameplate.parent:EnableMouse(false)
    end
  end

  -- enable mouselook on rightbutton down
  nameplates.mouselook = CreateFrame("Frame", nil, UIParent)
  nameplates.mouselook.time = nil
  nameplates.mouselook.frame = nil
  nameplates.mouselook.OnMouseDown = function()
    if arg1 and arg1 == "RightButton" then
      MouselookStart()

      -- start detection of the rightclick emulation
      nameplates.mouselook.time = GetTime()
      nameplates.mouselook.frame = this
      nameplates.mouselook:Show()
    end
  end

  nameplates.mouselook:SetScript("OnUpdate", function()
    -- break here if nothing to do
    if not this.time or not this.frame then
      this:Hide()
      return
    end

    -- if threshold is reached (0.5 second) no click action will follow
    if not IsMouselooking() and this.time + tonumber(C.nameplates["clickthreshold"]) < GetTime() then
      this:Hide()
      return
    end

    -- run a usual nameplate rightclick action
    if not IsMouselooking() then
      this.frame:Click("LeftButton")
      if UnitCanAttack("player", "target") and not nameplates.combat.inCombat then AttackTarget() end
      this:Hide()
      return
    end
  end)

  pfUI.nameplates = nameplates
end)