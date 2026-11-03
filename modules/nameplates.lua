pfUI:RegisterModule("nameplates", function ()
  -- disable original castbars
  pcall(SetCVar, "ShowVKeyCastbar", 0)

  -- Local function references for performance
  local GetTime = GetTime
  local UnitName = UnitName
  local UnitGUID = UnitGUID
  local UnitIsPlayer = UnitIsPlayer
  local UnitAffectingCombat = UnitAffectingCombat
  local UnitIsUnit = UnitIsUnit
  local UnitHealth = UnitHealth
  local UnitHealthMax = UnitHealthMax
  local UnitLevel = UnitLevel
  local UnitClassification = UnitClassification
  local UnitIsTapped = UnitIsTapped
  local UnitIsTappedByPlayer = UnitIsTappedByPlayer
  local UnitSelectionType = UnitSelectionType
  local UnitCreatureTypeID = UnitCreatureTypeID
  local UnitCreatedBySpell = UnitCreatedBySpell
  local pairs = pairs
  local next = next
  local tonumber = tonumber
  local strlower = strlower
  local strlen = strlen
  local floor = floor
  local ceil = ceil
  local abs = abs

  -- Everything a plate shows is driven by events. The engine's own nameplate
  -- regions are blanked at creation and never read again: a bound plate reads
  -- its unit through its "nameplateN" token, which ClassicAPI feeds every unit
  -- event (UNIT_HEALTH, UNIT_FLAGS, UNIT_TARGET, UNIT_AURA_DELTA, the casts,
  -- ...), each registered on the plate's own frame against that token. There
  -- is no per-tick loop over the plates and no periodic refresh: the only
  -- OnUpdate is `driver`, shown while a castbar sweeps or the target zoom
  -- animates and hidden the moment both sets run dry.

  local unitcolors = {
    ["ENEMY_NPC"] = { .9, .2, .3, .8 },
    ["NEUTRAL_NPC"] = { 1, 1, .3, .8 },
    ["FRIENDLY_NPC"] = { .6, 1, 0, .8 },
    ["ENEMY_PLAYER"] = { .9, .2, .3, .8 },
    ["FRIENDLY_PLAYER"] = { .2, .6, 1, .8 }
  }

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

  -- UnitSelectionType: 0 hostile, 1 unfriendly, 2 neutral, 3 friendly (or a
  -- PvP-flagged player), 4 unflagged player. Type 3 is ambiguous, so the
  -- player check promotes *_NPC to *_PLAYER.
  local selectionTypes = {
    [0] = "ENEMY_NPC",
    [1] = "ENEMY_NPC",
    [2] = "NEUTRAL_NPC",
    [3] = "FRIENDLY_NPC",
    [4] = "FRIENDLY_PLAYER",
  }

  local NULL_GUID = "0x0000000000000000"
  local ZOOM_TIME = 0.2

  local registry = {}     -- engine plate -> true, every pool slot carrying a pfUI overlay
  local plateByGuid = {}  -- guid -> overlay, the plates currently bound to a unit
  local plateByUnit = {}  -- "nameplateN" -> overlay, the same set by token
  local castState = {}    -- guid -> cast struct (see PollCastInfo)
  local threatMemory = {} -- guid -> true once the mob targeted the player
  local raidGuidCache = {}  -- guid -> name of the player's group
  local offtanks = {}
  local zooming = {}      -- overlay -> true while its target zoom animates
  local auraSlots = {}    -- reusable GetAuraSlots buffer for the per-plate aura scan
  local targetGuid
  local playerInCombat
  local mouseBlocked      -- a spell is waiting for a ground target, so the overlays let clicks through
  local myGuild
  local platecount = 0

  -- Friendly zone nameplate disable state
  local savedHostileState = nil
  local savedFriendlyState = nil
  local inFriendlyZone = false

  -- ============================================================================
  -- Config caching
  -- ============================================================================
  local cfg = {}
  local castFormatter = C_StringUtil.CreateNumericRuleFormatter()
  local debufffilter, debufflist

  local function DebuffFilterPopulate()
    debufffilter = C.nameplates.debuffs.filter
    debufflist = {}
    if debufffilter ~= "none" then
      for _, val in pairs({strsplit("#", C.nameplates.debuffs[debufffilter])}) do
        debufflist[strlower(val)] = true
      end
    end
  end

  local function DebuffFilter(effect)
    if debufffilter == "none" then return true end
    local listed = debufflist[strlower(effect)]
    if debufffilter == "blacklist" then return not listed end
    return listed
  end

  local function CacheConfig()
    local N = C.nameplates
    cfg.showcastbar = N.showcastbar == "1"
    cfg.targetcastbar = N.targetcastbar == "1"
    cfg.notargalpha = tonumber(N.notargalpha) or 0.5
    if cfg.notargalpha > 1 then cfg.notargalpha = cfg.notargalpha / 100 end
    if cfg.notargalpha > 1 then cfg.notargalpha = 1 end
    cfg.namefightcolor = N.namefightcolor == "1"
    cfg.spellname = N.spellname == "1"
    cfg.showhp = N.showhp == "1"
    cfg.hptextformat = N.hptextformat
    cfg.showdebuffs = N.showdebuffs == "1"
    cfg.showdebuffs_hostile = N.showdebuffs_hostile == "1"
    cfg.showdebuffs_friendly = N.showdebuffs_friendly == "1"
    -- owndebuffs adds the PLAYER filter token so only auras whose caster GUID
    -- matches the local player come through
    cfg.debufffilter = N.owndebuffs == "1" and "HARMFUL|PLAYER" or "HARMFUL"
    cfg.showstacks = N.debuffs.showstacks == "1"
    cfg.debuffbottom = N.debuffs.position == "BOTTOM"
    cfg.targetzoom = N.targetzoom == "1"
    cfg.zoomval = (tonumber(N.targetzoomval) or 0.4) + 1
    cfg.width = tonumber(N.width) or 120
    cfg.heighthealth = tonumber(N.heighthealth) or 8
    cfg.targetglow = N.targetglow == "1"
    cfg.targethighlight = N.targethighlight == "1"
    cfg.outcombatstate = N.outcombatstate == "1"
    cfg.barcombatstate = N.barcombatstate == "1"
    cfg.combatstate = cfg.outcombatstate or cfg.barcombatstate
    cfg.ccombatcasting = N.ccombatcasting == "1"
    cfg.ccombatthreat = N.ccombatthreat == "1"
    cfg.ccombatnothreat = N.ccombatnothreat == "1"
    cfg.ccombatstun = N.ccombatstun == "1"
    cfg.ccombatofftank = N.ccombatofftank == "1"
    cfg.font_size = N.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    cfg.totemicons = N.totemicons == "1"
    cfg.cpdisplay = N.cpdisplay == "1"
    cfg.showguildname = N.showguildname == "1"
    cfg.abbrevname = C.unitframes.abbrevname == "1"
    cfg.friendclassnamec = N.friendclassnamec == "1"
    -- the plate castbars' text bindings hold this formatter, so they pick the
    -- change up on their next tick
    if C.unitframes.castbardecimals == "1" then
      castFormatter:SetBreakpoints({ { threshold = 0, step = .1, rounding = Enum.NumericRuleFormatRounding.Down, format = "%.1f" } })
    else
      castFormatter:SetBreakpoints({ { threshold = 0, format = "%.2f" } })
    end
    cfg.fullhealth = N.fullhealth == "1"
    cfg.keeptarget = N.target == "1"
    cfg.critters = N.critters == "1"
    cfg.totems = N.totems == "1"
    cfg.hide = {
      ENEMY_NPC = N.enemynpc == "1",
      ENEMY_PLAYER = N.enemyplayer == "1",
      NEUTRAL_NPC = N.neutralnpc == "1",
      FRIENDLY_NPC = N.friendlynpc == "1",
      FRIENDLY_PLAYER = N.friendlyplayer == "1",
    }
    cfg.outline = {
      FRIENDLY_NPC = N.outfriendlynpc == "1",
      FRIENDLY_PLAYER = N.outfriendly == "1",
      NEUTRAL_NPC = N.outneutral == "1",
      ENEMY_NPC = N.outenemy == "1",
      ENEMY_PLAYER = N.outenemy == "1",
    }
    cfg.classcolor = {
      ENEMY_PLAYER = N.enemyclassc == "1",
      FRIENDLY_PLAYER = N.friendclassc == "1",
    }
    cfg.overlap = N.overlap == "1"
    cfg.useoverlay = cfg.overlap or N.vertical_offset ~= "0"  -- the overlay takes the clicks
    cfg.clickable = N.clickthrough ~= "1"
    cfg.rightclick = N.rightclick == "1"
    cfg.hlr, cfg.hlg, cfg.hlb, cfg.hla = GetStringColor(N.highlightcolor)
    cfg.br, cfg.bg, cfg.bb, cfg.ba = GetStringColor(C.appearance.border.color)

    local c = combatstate
    c.CASTING.r, c.CASTING.g, c.CASTING.b, c.CASTING.a = GetStringColor(N.combatcasting)
    c.THREAT.r, c.THREAT.g, c.THREAT.b, c.THREAT.a = GetStringColor(N.combatthreat)
    c.NOTHREAT.r, c.NOTHREAT.g, c.NOTHREAT.b, c.NOTHREAT.a = GetStringColor(N.combatnothreat)
    c.OFFTANK.r, c.OFFTANK.g, c.OFFTANK.b, c.OFFTANK.a = GetStringColor(N.combatofftank)
    c.STUN.r, c.STUN.g, c.STUN.b, c.STUN.a = GetStringColor(N.combatstun)

    offtanks = {}
    for _, v in pairs({strsplit("#", N.combatofftanks)}) do
      if v ~= "" then offtanks[strlower(v)] = true end
    end

    DebuffFilterPopulate()
  end
  CacheConfig()

  local function RebuildRaidGuidCache()
    table.wipe(raidGuidCache)
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

  -- ============================================================================
  -- Casts
  -- ============================================================================

  -- One-shot C_Spell poll. Builds the cast struct for a UNIT_SPELLCAST_* event
  -- (the payload carries no timing) and seeds a plate that binds while its unit
  -- is already mid-cast (its START fired before the plate existed). Picks cast
  -- vs channel itself. A cast whose start was never seen has no duration.
  local function PollCastInfo(unit)
    local name, _, texture, _, _, _, _, noInterrupt, spellID = C_Spell.UnitCastingInfo(unit)
    local duration, isChannel
    if name then
      duration = UnitCastingDuration(unit)
    else
      name, _, texture, _, _, _, noInterrupt, spellID = C_Spell.UnitChannelInfo(unit)
      duration = name and UnitChannelDuration(unit)
      isChannel = true
    end
    if not duration then return nil end
    return {
      spellName = name,
      spellID   = spellID,
      icon      = texture,
      duration  = duration,
      isChannel = isChannel,
      noInterrupt = noInterrupt,
    }
  end

  -- ============================================================================
  -- Plate state
  -- ============================================================================

  -- Updaters reference each other, so they are declared ahead and defined below.
  local UpdateBarColor, UpdateBorder, UpdateNameColor, UpdateLayout, UpdateDebuffs
  local UpdateLevel, UpdateCombatColor, UpdateCast, HideCast, SetZoom, Unbind

  -- Numeric CreatureType.dbc id for the plate's unit (8 = Critter, 11 = Totem).
  -- It's fixed per unit, so cache it and reset on bind. nil while the creature
  -- cache hasn't answered yet, in which case the next call asks again.
  local function CreatureType(plate)
    if not plate.creatureType then
      plate.creatureType = UnitCreatureTypeID(plate.unit)
    end
    return plate.creatureType
  end

  -- The combat-state colour for a bound plate, or nil when the unit shows no
  -- combat state. The mob's target comes through the plate's token chain
  -- ("nameplateNtarget"). Runs on the events that can change the answer:
  -- UNIT_TARGET, UNIT_FLAGS, the casts, the player's combat state and the
  -- group roster -- never on a timer.
  local function CombatStateColor(plate)
    if not playerInCombat or plate.friendly or not plate.incombat then return nil end

    local guid = plate.guid
    local target = plate.targetToken
    local mobTargetGuid = UnitGUID(target)
    local hasTarget = mobTargetGuid and mobTargetGuid ~= NULL_GUID
    local info = castState[guid]
    local isCasting = info and not info.duration:HasExpired()
    local targetingPlayer = hasTarget and UnitIsUnit(target, "player")

    if targetingPlayer then
      threatMemory[guid] = true
    elseif hasTarget and not isCasting then
      threatMemory[guid] = nil
    end

    local targetName = hasTarget and (UnitName(target) or raidGuidCache[mobTargetGuid])

    if cfg.ccombatcasting and isCasting then
      return combatstate.CASTING
    elseif cfg.ccombatthreat and (targetingPlayer or threatMemory[guid]) then
      return combatstate.THREAT
    elseif cfg.ccombatofftank and targetName and offtanks[strlower(targetName)] then
      return combatstate.OFFTANK
    elseif cfg.ccombatofftank and pfUI.uf and pfUI.uf.raid and targetName and pfUI.uf.raid.tankrole[targetName] then
      return combatstate.OFFTANK
    elseif cfg.ccombatnothreat and hasTarget then
      return combatstate.NOTHREAT
    elseif cfg.ccombatstun and not hasTarget then
      return combatstate.STUN
    end
    return nil
  end

  -- Returns true when the colour changed.
  local function ReadCombatColor(plate)
    local color = cfg.combatstate and CombatStateColor(plate) or nil
    if color == plate.combatColor then return nil end
    plate.combatColor = color
    return true
  end

  function UpdateCombatColor(plate)
    if ReadCombatColor(plate) then
      UpdateBarColor(plate)
      UpdateBorder(plate)
    end
  end

  -- Returns true when the type (or the class behind its colour) changed.
  local function ReadUnitType(plate)
    local unit = plate.unit
    local player = UnitIsPlayer(unit) and true or nil
    local unittype = selectionTypes[UnitSelectionType(unit)] or "ENEMY_NPC"
    if player then
      if unittype == "ENEMY_NPC" then unittype = "ENEMY_PLAYER"
      elseif unittype == "FRIENDLY_NPC" then unittype = "FRIENDLY_PLAYER" end
    end
    local class = player and UnitClassBase(unit) or nil
    if unittype == plate.unittype and class == plate.class then return nil end
    plate.player, plate.unittype, plate.class = player, unittype, class
    plate.friendly = unittype == "FRIENDLY_PLAYER" or unittype == "FRIENDLY_NPC"
    return true
  end

  local function UpdateUnitType(plate)
    if not ReadUnitType(plate) then return end
    ReadCombatColor(plate)
    UpdateBarColor(plate)
    UpdateBorder(plate)
    UpdateNameColor(plate)
    UpdateLayout(plate)
    UpdateDebuffs(plate)
  end

  -- UNIT_FLAGS: the combat bit, and the reaction can move with it
  local function UpdateFlags(plate)
    local incombat = UnitAffectingCombat(plate.unit) and true or nil
    local changed = incombat ~= plate.incombat
    plate.incombat = incombat
    UpdateUnitType(plate)
    if changed then
      UpdateCombatColor(plate)
      UpdateNameColor(plate)
    end
  end

  -- UNIT_DYNAMIC_FLAGS: tapped by someone else greys the bar
  local function UpdateTapped(plate)
    local unit = plate.unit
    local tapped = UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit) and true or nil
    if tapped == plate.tapped then return end
    plate.tapped = tapped
    UpdateBarColor(plate)
  end

  function UpdateBarColor(plate)
    local unittype = plate.unittype
    local r, g, b, a = unpack(unitcolors[unittype])
    if plate.class and cfg.classcolor[unittype] then
      r, g, b, a = PFUI_CLASS_COLORS[plate.class]:GetRGBA()
    end
    if plate.tapped then
      r, g, b, a = .5, .5, .5, .8
    end
    if cfg.barcombatstate and plate.combatColor then
      local c = plate.combatColor
      r, g, b, a = c.r, c.g, c.b, c.a
    end
    local cache = plate.cache
    if r == cache.r and g == cache.g and b == cache.b then return end
    cache.r, cache.g, cache.b = r, g, b
    plate.health:SetStatusBarColor(r, g, b, a)
  end

  function UpdateBorder(plate)
    local r, g, b, a
    if cfg.outcombatstate then
      local c = plate.combatColor or combatstate.NONE
      r, g, b, a = c.r, c.g, c.b, c.a
    elseif plate.istarget and cfg.targethighlight then
      r, g, b, a = cfg.hlr, cfg.hlg, cfg.hlb, cfg.hla
    elseif cfg.outline[plate.unittype] then
      r, g, b, a = unpack(unitcolors[plate.unittype])
    else
      r, g, b, a = cfg.br, cfg.bg, cfg.bb, cfg.ba
    end
    local cache = plate.cache
    if r == cache.br and g == cache.bg and b == cache.bb then return end
    cache.br, cache.bg, cache.bb = r, g, b
    plate.health.backdrop:SetBackdropBorderColor(r, g, b, a)
  end

  -- Class colour for friendly players when friendclassnamec is on, the fight
  -- colour while the unit and the player are both in combat, white otherwise.
  function UpdateNameColor(plate)
    local r, g, b, a = 1, 1, 1, 1
    if cfg.friendclassnamec and plate.unittype == "FRIENDLY_PLAYER" and plate.class then
      r, g, b, a = PFUI_CLASS_COLORS[plate.class]:GetRGBA()
    elseif cfg.namefightcolor and playerInCombat and plate.incombat then
      r, g, b, a = 1, .4, .2, 1
    end
    local cache = plate.cache
    if r == cache.nr and g == cache.ng and b == cache.nb then return end
    cache.nr, cache.ng, cache.nb = r, g, b
    plate.name:SetTextColor(r, g, b, a)
  end

  local function abbrevname(t)
    return string.sub(t,1,1)..". "
  end

  local function GetNameString(name)
    if cfg.abbrevname and name and strlen(name) > 20 then
      -- first try to only abbreviate the first word
      name = string.gsub(name, "^(%S+) ", abbrevname)
      -- abbreviate all if it still doesn't fit
      if strlen(name) > 20 then
        name = string.gsub(name, "(%S+) ", abbrevname)
      end
    end
    return name
  end

  -- Name, and the guild or subname line under it. Returns true when the
  -- layout has to follow: the guild line moves the name-only anchors, and a
  -- totem swapped in place keeps its unit while its name and drop spell change.
  local function ReadName(plate)
    local unit = plate.unit
    local relayout
    local name = UnitName(unit)
    if name ~= plate.rawname then
      plate.rawname = name
      plate.name:SetText(GetNameString(name))
      -- a player too high to show a level is looked up by name
      UpdateLevel(plate)
      if plate.creatureType == 11 then relayout = true end
    end

    local guild = cfg.showguildname and (plate.player and GetGuildInfo(unit) or UnitSubName(unit)) or nil
    if guild then
      if guild ~= plate.guildtext then
        plate.guildtext = guild
        plate.guild:SetText(guild)
      end
      local mine = guild == myGuild
      if mine ~= plate.guildmine then
        plate.guildmine = mine
        if mine then
          plate.guild:SetTextColor(0, 0.9, 0, 1)
        else
          plate.guild:SetTextColor(0.8, 0.8, 0.8, 1)
        end
      end
    end
    local shown = guild and true or nil
    if shown ~= plate.guildshown then
      plate.guildshown = shown
      relayout = true
    end
    return relayout
  end

  -- UNIT_NAME_UPDATE
  local function UpdateName(plate)
    if ReadName(plate) then UpdateLayout(plate) end
  end

  -- UNIT_LEVEL / UNIT_CLASSIFICATION_CHANGED / PLAYER_LEVEL_UP
  function UpdateLevel(plate)
    local unit = plate.unit
    local level = UnitLevel(unit)
    local elite = UnitClassification(unit)
    if level <= 0 then
      if plate.player then
        level = GetPlayerLevel(plate.rawname) or level
      else
        -- UnitLevel answers -1 exactly where the engine shows the skull: a
        -- world boss, or a hostile ten or more levels above the player
        elite = "boss"
      end
    end
    plate.levelnum = level > 0 and level or nil
    if level <= 0 then level = "??" end

    local cache = plate.cache
    if cache.level == level and cache.elite == elite then return end
    cache.level, cache.elite = level, elite
    plate.level:SetFormattedText("%s%s", level, elitestrings[elite] or "")

    -- Blizzard's own tiers: adding a flat offset to the channels desaturates
    -- every tier toward white and collapses the boundaries
    if plate.levelnum then
      local color = GetDifficultyColor(plate.levelnum)
      plate.level:SetTextColor(color.r, color.g, color.b, 1)
    elseif plate.player then
      plate.level:SetTextColor(1, 1, 1, 1)
    else
      plate.level:SetTextColor(1, .1, .1, 1)
    end
  end

  local function ApplyHealth(plate)
    local hp, hpmax = plate.hp, plate.hpmax
    plate.health:SetMinMaxValues(0, hpmax)
    plate.health:SetValue(hp)
    if not cfg.showhp then return end

    local text = plate.health.text
    if hpmax <= 0 then
      text:SetText("")
      return
    end

    -- A unit outside the group reports its health as a percentage (max 100);
    -- libhealth may know the real numbers for a mob by name and level.
    local rhp, rhpmax, known
    if hpmax ~= 100 then
      rhp, rhpmax, known = hp, hpmax, true
    elseif pfUI.libhealth and pfUI.libhealth.enabled then
      rhp, rhpmax, known = pfUI.libhealth:GetUnitHealthByName(plate.rawname, plate.levelnum, hp, hpmax)
    end

    local perc = ceil(hp / hpmax * 100)
    local setting = cfg.hptextformat
    if not known then
      if setting == "deficit" then
        text:SetFormattedText("-%d%%", 100 - perc)
      else
        text:SetFormattedText("%d%%", perc)
      end
    elseif setting == "curperc" then
      text:SetFormattedText("%s | %d%%", Abbreviate(rhp), perc)
    elseif setting == "cur" then
      text:SetText(Abbreviate(rhp))
    elseif setting == "curmax" then
      text:SetFormattedText("%s - %s", Abbreviate(rhp), Abbreviate(rhpmax))
    elseif setting == "curmaxs" then
      text:SetFormattedText("%s / %s", Abbreviate(rhp), Abbreviate(rhpmax))
    elseif setting == "curmaxperc" then
      text:SetFormattedText("%s - %s | %d%%", Abbreviate(rhp), Abbreviate(rhpmax), perc)
    elseif setting == "curmaxpercs" then
      text:SetFormattedText("%s / %s | %d%%", Abbreviate(rhp), Abbreviate(rhpmax), perc)
    elseif setting == "deficit" then
      text:SetFormattedText("-%s", Abbreviate(rhpmax - rhp))
    else -- "percent" as fallback
      text:SetFormattedText("%d%%", perc)
    end
  end

  -- Bar and text. Returns true when full health flipped, which can hide or
  -- show the bar.
  local function ReadHealth(plate)
    local unit = plate.unit
    local hp, hpmax = UnitHealth(unit), UnitHealthMax(unit)
    if hp == plate.hp and hpmax == plate.hpmax then return nil end
    plate.hp, plate.hpmax = hp, hpmax
    ApplyHealth(plate)
    local fullhp = hp == hpmax
    if fullhp == plate.fullhp then return nil end
    plate.fullhp = fullhp
    return true
  end

  -- UNIT_HEALTH / UNIT_MAXHEALTH
  local function UpdateHealth(plate)
    if ReadHealth(plate) then UpdateLayout(plate) end
  end

  -- true when the bar should be hidden, leaving name and level
  local function HidePlate(plate)
    -- keep some plates always visible according to config
    if cfg.fullhealth and not plate.fullhp then return nil end
    if cfg.keeptarget and plate.istarget then return nil end

    if cfg.hide[plate.unittype] then return true end
    if cfg.critters and CreatureType(plate) == 8 then return true end
    if cfg.totems and CreatureType(plate) == 11 then return true end
    return nil
  end

  local function UpdateGlow(plate)
    plate.glow:SetShown(plate.istarget and cfg.targetglow and plate.mode ~= "totem")
  end

  -- Which of the three looks the plate wears: the totem icon alone, name and
  -- level without a bar, or the full plate. Re-anchors only when the look
  -- changes.
  function UpdateLayout(plate)
    local mode, icon
    if cfg.totemicons and CreatureType(plate) == 11 then
      -- UnitCreatedBySpell returns the totem-drop spell, whose icon IS the
      -- totem's icon. It's a broadcast descriptor field the client has for
      -- every summoned unit in range, so it resolves immediately for passive
      -- and active totems alike.
      local spellId = UnitCreatedBySpell(plate.unit)
      if spellId ~= plate.totemSpell then
        plate.totemSpell = spellId
        plate.totemIcon = spellId and C_Spell.GetSpellTexture(spellId) or nil
      end
      icon = plate.totemIcon
    end

    if icon then
      mode = "totem"
      if plate.totemShown ~= icon then
        plate.totemShown = icon
        plate.totem.icon:SetTexture(icon)
      end
    elseif HidePlate(plate) then
      mode = "name"
    else
      mode = "bar"
    end
    plate.mode = mode

    local key = plate.guildshown and mode .. "+guild" or mode
    if plate.layout ~= key then
      plate.layout = key
      local font_size = cfg.font_size

      if mode == "totem" then
        plate.level:Hide()
        plate.name:Hide()
        plate.health:Hide()
        plate.guild:Hide()
        plate.totem:Show()
      elseif mode == "name" then
        plate.level:SetPoint("RIGHT", plate.name, "LEFT", -3, 0)
        plate.name:SetParent(plate)
        plate.guild:SetPoint("BOTTOM", plate.name, "BOTTOM", -2, -(font_size + 2))
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, plate.guildshown and -(font_size / 2) - 2 or 0)

        plate.level:Show()
        plate.name:Show()
        plate.health:Hide()
        plate.guild:SetShown(plate.guildshown)
        plate.totem:Hide()
      else
        plate.level:SetPoint("RIGHT", plate.health, "LEFT", -5, 0)
        plate.name:SetParent(plate.health)
        plate.guild:SetPoint("BOTTOM", plate.health, "BOTTOM", 0, -(font_size + 4))
        plate.glow:SetPoint("CENTER", plate.health, "CENTER", 0, 0)

        plate.level:Show()
        plate.name:Show()
        plate.health:Show()
        plate.guild:SetShown(plate.guildshown)
        plate.totem:Hide()
      end
    end

    UpdateGlow(plate)
  end

  local function CreateDebuffIcon(plate, index)
    local icon = CreateFrame("Frame", plate.platename.."Debuff"..index, plate)
    icon:Hide()
    -- relative: a raised target plate can grow icons too
    icon:SetFrameLevel(plate.health:GetFrameLevel())

    icon.icon = icon:CreateTexture(nil, "BACKGROUND")
    icon.icon:SetColorTexture(.3,1,.8,1)
    icon.icon:SetAllPoints(icon)

    icon.stacks = icon:CreateFontString(nil, "OVERLAY")
    icon.stacks:SetAllPoints(icon)
    icon.stacks:SetJustifyH("RIGHT")
    icon.stacks:SetJustifyV("BOTTOM")
    icon.stacks:SetTextColor(1,1,0)

    icon.cd = CreateCooldown(icon, "aura", C.nameplates, "debuff_timers", plate.platename.."Debuff"..index.."Cooldown")
    icon.cd:SetFrameLevel(icon:GetFrameLevel() + 2)

    plate.debuffs[index] = icon
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
  end

  -- UNIT_AURA_DELTA: one GetAuraSlots enumeration, then positional by-slot
  -- reads straight onto the icons. The scan allocates nothing.
  function UpdateDebuffs(plate)
    local index = 1
    local friendly = plate.friendly
    if cfg.showdebuffs and (friendly and cfg.showdebuffs_friendly or (not friendly and cfg.showdebuffs_hostile)) then
      local unit = plate.unit
      local now = GetTime()
      local n = ScanAuraSlots(unit, cfg.debufffilter, auraSlots, 16)
      for i = 1, n do
        local effect, texture, stacks, _, duration, expirationTime = C_UnitAuras.UnitAuraBySlot(unit, auraSlots[i])
        if not effect then break end
        if texture and DebuffFilter(effect) then
          local icon = plate.debuffs[index]
          if not icon then
            CreateDebuffIcon(plate, index)
            UpdateDebuffConfig(plate, index)
            icon = plate.debuffs[index]
          end

          icon:Show()
          icon.icon:SetTexture(texture)
          icon.icon:SetTexCoord(.078, .92, .079, .937)

          if stacks and stacks > 1 and cfg.showstacks then
            icon.stacks:SetText(stacks)
            icon.stacks:Show()
          else
            icon.stacks:Hide()
          end

          local timeleft = expirationTime and expirationTime > 0 and (expirationTime - now)
          if duration and timeleft then
            -- C_UnitAuras returns the Spell.dbc base duration, which talents
            -- can extend past -- Shadow Affinity bumps SW:P from 18s to 24s,
            -- so a fresh cast has timeleft > duration and `now + timeleft -
            -- duration` lands in the future, which CooldownFrame_SetTimer
            -- treats as "not yet started" (no swirl). Widen to whichever is
            -- larger so start <= now.
            local effDuration = duration > timeleft and duration or timeleft
            local start = now + timeleft - effDuration
            icon.cd:Show()
            if icon.cdEffect ~= effect or abs(icon.cdStart - start) > 0.5 then
              CooldownFrame_SetTimer(icon.cd, start, effDuration, 1)
              icon.cdEffect = effect
              icon.cdStart = start
            end
          else
            icon.cd:Hide()
            icon.cdEffect = nil
          end

          index = index + 1
          if index > 16 then break end
        end
      end
    end

    -- hide remaining debuffs
    for i = index, table.getn(plate.debuffs) do
      plate.debuffs[i]:Hide()
    end
  end

  local function UpdateCombo(plate)
    local cp = plate.istarget and cfg.cpdisplay and GetComboPoints("target") or 0
    if plate.cpShown == cp then return end
    plate.cpShown = cp
    for i = 1, 5 do plate.combopoints[i]:SetShown(i <= cp) end
  end

  local function UpdateAlpha(plate)
    local alpha = (plate.istarget or not targetGuid) and 1 or cfg.notargalpha
    if plate.alpha == alpha then return end
    plate.alpha = alpha
    plate:SetAlpha(alpha)
  end

  -- The engine's plates draw in the world frame's stratum, under every UI
  -- stratum, and the overlay inherits it; a SetFrameStrata would lift it into
  -- the UI's and over the chat. The target rises above the other plates by
  -- level instead: raise the engine frame, then re-parent the overlay, which
  -- moves its whole subtree to the new parent level.
  local TARGET_RAISE = 20

  local function UpdateStacking(plate)
    local raised = plate.istarget and true or nil
    if plate.raised == raised then return end
    plate.raised = raised
    local parent = plate.parent
    parent:SetFrameLevel(plate.baselevel + (raised and TARGET_RAISE or 0))
    -- SetParent does nothing for the same parent, so it goes through nil
    plate:SetParent(nil)
    plate:SetParent(parent)
  end

  -- ============================================================================
  -- Animation driver: the target zoom. Shown only while a plate zooms.
  -- ============================================================================
  local driver = CreateFrame("Frame", nil, UIParent)
  driver:Hide()

  -- f = 0 is the configured bar, f = 1 the zoomed one
  function SetZoom(plate, f)
    plate.zoomf = f
    plate.health:SetSize(cfg.width * (1 + (cfg.zoomval - 1) * f), cfg.heighthealth * (1 + (cfg.zoomval * .9 - 1) * f))
  end

  -- Continues from wherever the bar is, so a target swap mid-zoom doesn't jump.
  local function StartZoom(plate, zoomIn)
    local f = plate.zoomf or 0
    if (zoomIn and f >= 1) or (not zoomIn and f <= 0) then return end
    plate.zoomIn = zoomIn
    plate.zoomStart = GetTime() - (zoomIn and f or 1 - f) * ZOOM_TIME
    zooming[plate] = true
    driver:Show()
  end

  driver:SetScript("OnUpdate", function()
    local now = GetTime()
    for plate in pairs(zooming) do
      local f = (now - plate.zoomStart) / ZOOM_TIME
      if f >= 1 then
        f = 1
        zooming[plate] = nil
      end
      SetZoom(plate, plate.zoomIn and f or 1 - f)
    end
    if not next(zooming) then this:Hide() end
  end)

  -- ============================================================================
  -- Castbars: the bar's timer and its text binding follow the cast's duration
  -- object on their own. Lua only starts, restyles and stops them.
  -- ============================================================================
  local function ShowCast(plate, info)
    local castbar = plate.castbar
    castbar:SetTimerDuration(info.duration, Enum.StatusBarInterpolation.Immediate,
      info.isChannel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
    castbar.timer:SetDuration(info.duration)
    castbar.timer:Enable()
    SetCastbarShield(castbar, castbar.icon, info.noInterrupt, info.isChannel)
    if info.icon then
      castbar.icon.tex:SetTexture(info.icon)
      castbar.icon.tex:SetTexCoord(.1,.9,.1,.9)
    end
    castbar.spell:SetText(cfg.spellname and info.spellName or "")
    -- armed exactly while the bar shows
    if castbar.expiry then castbar.expiry:Cancel() end
    castbar.expiry = C_Timer.NewTimer(info.duration:GetRemainingDuration(), castbar.onExpire)
    castbar:Show()
  end

  function HideCast(plate)
    local castbar = plate.castbar
    if not castbar.expiry then return end
    castbar.expiry:Cancel()
    castbar.expiry = nil
    castbar.timer:Disable()
    castbar:Hide()
  end

  -- Start or stop the plate's castbar from the cast cache and the config.
  function UpdateCast(plate)
    local info = castState[plate.guid]
    if info and not info.duration:HasExpired() and cfg.showcastbar and (plate.istarget or not cfg.targetcastbar) then
      ShowCast(plate, info)
    else
      HideCast(plate)
    end
  end

  -- The bar's cast ran out without a STOP: treat it as one.
  local function ExpireCast(plate)
    castState[plate.guid] = nil
    HideCast(plate)
    UpdateCombatColor(plate)
  end

  -- ============================================================================
  -- Cast events (per plate)
  -- ============================================================================
  local function OnCastStart(plate)
    -- the payload carries no timing, so poll it (PollCastInfo picks cast vs
    -- channel)
    castState[plate.guid] = PollCastInfo(plate.unit)
    UpdateCast(plate)
    UpdateCombatColor(plate)
  end

  local function OnCastStop(plate)
    -- ended: natural, interrupted or cancelled -- the poll fires STOP for all
    if not castState[plate.guid] then return end
    castState[plate.guid] = nil
    HideCast(plate)
    UpdateCombatColor(plate)
  end

  -- ============================================================================
  -- Target
  -- ============================================================================
  local function SetTarget(plate, istarget)
    plate.istarget = istarget
    UpdateStacking(plate)
    UpdateBorder(plate)
    UpdateLayout(plate)
    UpdateCombo(plate)
    UpdateCast(plate)
    if cfg.targetzoom then StartZoom(plate, istarget) end
  end

  -- ============================================================================
  -- Binding a plate to a unit
  -- ============================================================================

  -- Every unit event the plate listens to, on its own frame against its token.
  local PLATE_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_AURA_DELTA",
    "UNIT_FLAGS", "UNIT_DYNAMIC_FLAGS", "UNIT_FACTION",
    "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "UNIT_NAME_UPDATE",
    "UNIT_TARGET",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
  }
  local NUM_PLATE_EVENTS = table.getn(PLATE_EVENTS)

  local plateEvents = {
    UNIT_HEALTH = UpdateHealth,
    UNIT_MAXHEALTH = UpdateHealth,
    UNIT_AURA_DELTA = UpdateDebuffs,
    UNIT_FLAGS = UpdateFlags,
    UNIT_DYNAMIC_FLAGS = UpdateTapped,
    UNIT_FACTION = UpdateUnitType,
    UNIT_LEVEL = UpdateLevel,
    UNIT_CLASSIFICATION_CHANGED = UpdateLevel,
    UNIT_NAME_UPDATE = UpdateName,
    UNIT_TARGET = UpdateCombatColor,
    UNIT_SPELLCAST_START = OnCastStart,
    UNIT_SPELLCAST_CHANNEL_START = OnCastStart,
    UNIT_SPELLCAST_STOP = OnCastStop,
    UNIT_SPELLCAST_CHANNEL_STOP = OnCastStop,
  }

  local function OnPlateEvent()
    local handler = plateEvents[event]
    if handler then handler(this) end
  end

  -- State the previous occupant left behind
  local PER_UNIT = {
    "layout", "mode", "creatureType", "totemSpell", "totemIcon", "totemShown",
    "hp", "hpmax", "fullhp", "rawname", "levelnum", "guildtext", "guildshown",
    "guildmine", "unittype", "class", "player", "friendly", "combatColor",
    "incombat", "tapped",
  }
  local NUM_PER_UNIT = table.getn(PER_UNIT)

  -- Everything, from the unit. Bind and config changes. Reads first, then one
  -- pass over the visuals.
  local function Refresh(plate)
    local unit = plate.unit
    plate.incombat = UnitAffectingCombat(unit) and true or nil
    plate.tapped = UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit) and true or nil
    ReadUnitType(plate)
    ReadCombatColor(plate)
    ReadName(plate)
    ReadHealth(plate)
    UpdateBarColor(plate)
    UpdateBorder(plate)
    UpdateNameColor(plate)
    UpdateLayout(plate)
    UpdateDebuffs(plate)
    UpdateCombo(plate)
    UpdateStacking(plate)
    UpdateAlpha(plate)
    UpdateCast(plate)
    if cfg.targetzoom and plate.istarget then StartZoom(plate, true) end
  end

  function Unbind(unit)
    local plate = plateByUnit[unit]
    if not plate then return end
    local guid = plate.guid
    plateByUnit[unit] = nil
    if plateByGuid[guid] == plate then plateByGuid[guid] = nil end
    castState[guid] = nil
    threatMemory[guid] = nil
    -- Drop the subscriptions with the token: this slot is now free and the
    -- next plate to take it would otherwise feed this frame its events.
    plate:UnregisterAllEvents()
    HideCast(plate)
    zooming[plate] = nil
    if plate.zoomf and plate.zoomf > 0 then SetZoom(plate, 0) end
    plate.unit = nil
    plate.guid = nil
    plate.targetToken = nil
    plate.istarget = nil
  end

  local function Bind(unit)
    local parent = C_NamePlate.GetNamePlateForUnit(unit)
    local plate = parent and parent.nameplate
    if not plate then return end
    local guid = UnitGUID(unit)
    if not guid then return end

    -- ADDED can precede the REMOVED of this frame's or this unit's previous
    -- binding within one tick
    if plate.unit then Unbind(plate.unit) end
    local old = plateByGuid[guid]
    if old then Unbind(old.unit) end

    plate.unit = unit
    plate.guid = guid
    plate.targetToken = unit .. "target"
    plate.istarget = guid == targetGuid
    plateByGuid[guid] = plate
    plateByUnit[unit] = plate

    table.wipe(plate.cache)
    for i = 1, NUM_PER_UNIT do plate[PER_UNIT[i]] = nil end
    for i = 1, table.getn(plate.debuffs) do plate.debuffs[i].cdEffect = nil end

    -- Point this plate's own subscriptions at the token it just took. On a
    -- recycled frame these replace the previous unit rather than stacking:
    -- RegisterUnitEvent on an already-filtered registration swaps the units.
    for i = 1, NUM_PLATE_EVENTS do
      plate:RegisterUnitEvent(PLATE_EVENTS[i], unit)
    end

    -- the unit may already be mid-cast (its START fired before this plate
    -- existed); ongoing casts arrive via the event
    castState[guid] = PollCastInfo(unit)

    Refresh(plate)
  end

  -- ============================================================================
  -- Engine frame: size and click routing
  -- ============================================================================

  -- The engine stores a default size into the plate at every bind and shows it
  -- afterwards, so OnShow is the moment to put ours back. Overlap mode shrinks
  -- the engine frame to a point so the engine's own spacing stops pushing the
  -- plates apart; otherwise it matches the overlay so it stays the click target.
  local function ApplyFrameLayout(parent)
    local plate = parent.nameplate
    if cfg.overlap then
      parent:SetSize(1, 1)
    else
      local scale = UIParent:GetScale()
      parent:SetSize(plate:GetWidth() * scale, plate:GetHeight() * scale)
    end
    parent:EnableMouse(cfg.clickable and not cfg.useoverlay)
    plate:EnableMouse(cfg.clickable and cfg.useoverlay and not mouseBlocked)
  end

  local function OnEngineShow()
    if this.nameplate then ApplyFrameLayout(this) end
  end

  -- CURRENT_SPELL_CAST_CHANGED: while a spell waits for a ground target the
  -- engine's own plate lets the click through; the overlay has to step aside.
  local function UpdateSpellTargeting()
    if not (cfg.useoverlay and cfg.clickable) then return end
    local blocked = SpellIsTargeting() and true or nil
    if blocked == mouseBlocked then return end
    mouseBlocked = blocked
    for _, plate in pairs(plateByGuid) do
      plate:EnableMouse(not blocked)
    end
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

  local function OverlayClick()
    this.parent:Click()
  end

  -- create nameplate core
  local nameplates = CreateFrame("Frame", "pfNameplates", UIParent)

  nameplates.OnCreate = function(parent)
    platecount = platecount + 1
    local platename = "pfNamePlate" .. platecount

    -- create pfUI nameplate overlay
    local nameplate = CreateFrame("Button", platename, parent)
    nameplate.platename = platename
    nameplate:EnableMouse(false)
    nameplate.parent = parent
    nameplate.baselevel = parent:GetFrameLevel()
    nameplate.cache = {}

    -- Each plate watches its own unit. With RegisterUnitEvent the token IS the
    -- subscription: the event arrives only at the plate it concerns, and
    -- `this` is already that plate. Bind points the registration at the new
    -- token; Unbind drops it.
    nameplate:SetScript("OnEvent", OnPlateEvent)

    -- Blank the engine's drawing. Its regions come in creation order: border,
    -- glow, name, level, skull, raid icon -- the raid icon is the one kept.
    DisableObject(parent:GetChildren())
    for i, object in pairs({parent:GetRegions()}) do
      if i == 6 then
        nameplate.raidicon = object
      else
        DisableObject(object)
      end
    end

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
        combopoints[i].tex = combopoints[i]:CreateTexture(nil, "OVERLAY")
        combopoints[i].tex:SetAllPoints()

        if i < 3 then
          combopoints[i].tex:SetColorTexture(1, .3, .3, .75)
        elseif i < 4 then
          combopoints[i].tex:SetColorTexture(1, 1, .3, .75)
        else
          combopoints[i].tex:SetColorTexture(.3, 1, .3, .75)
        end
      end
      nameplate.combopoints = combopoints
    end

    do -- castbar
      local castbar = CreateFrame("StatusBar", nil, nameplate.health)
      castbar:Hide()

      castbar:SetScript("OnShow", function()
        if cfg.debuffbottom then
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this, "BOTTOMLEFT", 0, -4)
        end
      end)

      castbar:SetScript("OnHide", function()
        if cfg.debuffbottom then
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this:GetParent(), "BOTTOMLEFT", 0, -4)
        end
      end)

      castbar.text = castbar:CreateFontString("Status", "OVERLAY", "GameFontNormal")
      castbar.text:SetPoint("RIGHT", castbar, "LEFT", -4, 0)
      castbar.text:SetNonSpaceWrap(false)
      castbar.text:SetTextColor(1,1,1,.5)

      castbar.timer = C_DurationUtil.CreateDurationTextBinding()
      castbar.timer:SetFontString(castbar.text)
      castbar.timer:SetFormatter(castFormatter)
      castbar.onExpire = function() ExpireCast(nameplate) end

      castbar.spell = castbar:CreateFontString("Status", "OVERLAY", "GameFontNormal")
      castbar.spell:SetPoint("CENTER", castbar, "CENTER")
      castbar.spell:SetNonSpaceWrap(false)
      castbar.spell:SetTextColor(1,1,1,1)

      castbar.icon = CreateFrame("Frame", nil, castbar)
      castbar.icon.tex = castbar.icon:CreateTexture(nil, "BORDER")
      castbar.icon.tex:SetAllPoints()

      nameplate.castbar = castbar
    end

    parent.nameplate = nameplate
    parent:HookScript("OnShow", OnEngineShow)

    nameplates.OnConfigChange(parent)
  end

  nameplates.OnConfigChange = function(parent)
    local nameplate = parent.nameplate

    local font = C.nameplates.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
    local font_size = cfg.font_size
    local font_style = C.nameplates.name.fontstyle
    local glowr, glowg, glowb, glowa = GetStringColor(C.nameplates.glowcolor)
    local hptexture = pfUI.media[C.nameplates.healthtexture]
    local _, default_border = GetBorderSize("nameplates")

    local plate_width = C.nameplates.width + 50
    local plate_height = C.nameplates.heighthealth + font_size + 5
    local combo_size = 5

    local healthoffset = tonumber(C.nameplates.health.offset)
    local orientation = C.nameplates.verticalhealth == "1" and "VERTICAL" or "HORIZONTAL"

    nameplate:SetSize(plate_width, plate_height)
    nameplate:SetPoint("TOP", parent, "TOP", 0, tonumber(C.nameplates.vertical_offset) or 0)

    nameplate.name:SetFont(font, font_size, font_style)
    local nameTextPos = C.nameplates.nametextpos or "CENTER"
    local nameAnchor = nameTextPos == "RIGHT" and { "BOTTOMRIGHT", "TOPRIGHT" }
                    or nameTextPos == "CENTER" and { "BOTTOM", "TOP" }
                    or { "BOTTOMLEFT", "TOPLEFT" }
    nameplate.name:ClearAllPoints()
    nameplate.name:SetPoint(nameAnchor[1], nameplate.health, nameAnchor[2], 0, -healthoffset)
    nameplate.name:SetJustifyH(nameTextPos)

    nameplate.health:SetOrientation(orientation)
    nameplate.health:SetRotatesTexture(orientation == "VERTICAL")
    -- Bar anchors to the plate directly so the name's JustifyH (configurable
    -- below) can shift left/right without dragging the bar with it.
    nameplate.health:ClearAllPoints()
    nameplate.health:SetPoint("BOTTOM", nameplate, "BOTTOM", 0, 0)
    nameplate.health:SetStatusBarTexture(hptexture)
    zooming[nameplate] = nil
    SetZoom(nameplate, 0)

    CreateBackdrop(nameplate.health, default_border)

    nameplate.health.text:SetFont(font, font_size - 2, "OUTLINE")
    nameplate.health.text:SetJustifyH(C.nameplates.hptextpos)
    if not cfg.showhp then nameplate.health.text:SetText("") end

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
    CreateBackdrop(nameplate.castbar, default_border)

    nameplate.castbar.text:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.spell:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.icon:SetPoint("BOTTOMLEFT", nameplate.castbar, "BOTTOMRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetPoint("TOPLEFT", nameplate.health, "TOPRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetWidth(C.nameplates.heightcast + default_border*3 + C.nameplates.heighthealth)
    CreateBackdrop(nameplate.castbar.icon, default_border)

    -- the anchors above are re-applied by the next layout pass, and the
    -- colour caches no longer describe what is on screen
    nameplate.layout = nil
    table.wipe(nameplate.cache)

    -- click routing: the overlay forwards to the engine plate when it is the
    -- one under the mouse; right mouse-look on whichever takes the clicks
    local clicker = cfg.useoverlay and nameplate or parent
    local other = cfg.useoverlay and parent or nameplate
    nameplate:SetScript("OnClick", cfg.useoverlay and OverlayClick or nil)
    clicker:SetScript("OnMouseDown", cfg.rightclick and nameplates.mouselook.OnMouseDown or nil)
    other:SetScript("OnMouseDown", nil)

    ApplyFrameLayout(parent)
  end

  -- ============================================================================
  -- Nameplate visibility switches
  -- ============================================================================
  nameplates.SetGameVariables = function()
    -- update visibility (hostile)
    if C.nameplates["showhostile"] == "1" then
      _G.NAMEPLATES_ON = true
      ShowNameplates()
    else
      _G.NAMEPLATES_ON = nil
      HideNameplates()
    end

    -- update visibility (friendly)
    if C.nameplates["showfriendly"] == "1" then
      _G.FRIENDNAMEPLATES_ON = true
      ShowFriendNameplates()
    else
      _G.FRIENDNAMEPLATES_ON = nil
      HideFriendNameplates()
    end
  end

  nameplates:SetGameVariables()

  -- Handle friendly zone nameplate disable feature
  local function UpdateZone()
    local disableHostile = C.nameplates["disable_hostile_in_friendly"] == "1"
    local disableFriendly = C.nameplates["disable_friendly_in_friendly"] == "1"
    if not (disableHostile or disableFriendly) then return end

    local nowFriendly = GetZonePVPInfo() == "friendly"

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

  nameplates.UpdateConfig = function()
    CacheConfig()

    -- Check friendly zone state when config changes
    local disableHostile = C.nameplates["disable_hostile_in_friendly"] == "1"
    local disableFriendly = C.nameplates["disable_friendly_in_friendly"] == "1"
    local nowFriendly = GetZonePVPInfo() == "friendly"

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
      elseif savedHostileState == "1" then
        -- Restore hostile if option is off but we're in friendly zone
        _G.NAMEPLATES_ON = true
        ShowNameplates()
      end

      if disableFriendly then
        _G.FRIENDNAMEPLATES_ON = nil
        HideFriendNameplates()
      elseif savedFriendlyState == "1" then
        -- Restore friendly if option is off but we're in friendly zone
        _G.FRIENDNAMEPLATES_ON = true
        ShowFriendNameplates()
      end
    else
      if inFriendlyZone and not (disableHostile or disableFriendly) then
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
      end

      -- update nameplate visibility
      nameplates:SetGameVariables()
    end

    -- apply all config changes
    for parent in pairs(registry) do
      nameplates.OnConfigChange(parent)
      local plate = parent.nameplate
      if plate.unit then
        -- the config decides what the plate shows, so read the unit again
        for i = 1, NUM_PER_UNIT do plate[PER_UNIT[i]] = nil end
        Refresh(plate)
      end
    end
  end

  -- ============================================================================
  -- Module events
  -- ============================================================================
  local events = {}

  events.PLAYER_LOGOUT = function()
    -- Stop event handling during logout to prevent crash 132. The plates hold
    -- their own unit subscriptions, so silencing this frame alone would leave
    -- them dispatching through logout. Leaving the world destroys the units
    -- before PLAYER_LOGOUT fires, and a destroyed plate already dropped its
    -- events and lost its methods, so only the live ones need silencing.
    nameplates:UnregisterAllEvents()
    nameplates:SetScript("OnEvent", nil)
    driver:SetScript("OnUpdate", nil)
    for parent in pairs(registry) do
      local plate = parent.nameplate
      if plate and plate.UnregisterAllEvents then
        plate:UnregisterAllEvents()
        plate:SetScript("OnEvent", nil)
      end
    end
  end

  events.PLAYER_ENTERING_WORLD = function()
    CacheConfig()
    nameplates:SetGameVariables()
    RebuildRaidGuidCache()
    targetGuid = UnitGUID("target")
    playerInCombat = UnitAffectingCombat("player") and true or nil
    myGuild = GetGuildInfo("player")
    UpdateZone()
  end

  events.ZONE_CHANGED_NEW_AREA = UpdateZone

  events.PLAYER_GUILD_UPDATE = function(unit)
    if unit ~= "player" then return end
    myGuild = GetGuildInfo("player")
    for _, plate in pairs(plateByGuid) do UpdateName(plate) end
  end

  events.RAID_ROSTER_UPDATE = function()
    RebuildRaidGuidCache()
    -- the offtank list reads the group by name
    for _, plate in pairs(plateByGuid) do UpdateCombatColor(plate) end
  end
  events.PARTY_MEMBERS_CHANGED = events.RAID_ROSTER_UPDATE

  events.NAME_PLATE_CREATED = function(frame)
    -- arg1 = the nameplate Frame; build the pfUI overlay once per pool slot
    if frame and not registry[frame] then
      nameplates.OnCreate(frame)
      registry[frame] = true
    end
  end

  events.NAME_PLATE_UNIT_ADDED = Bind
  events.NAME_PLATE_UNIT_REMOVED = Unbind

  events.PLAYER_TARGET_CHANGED = function()
    local old = targetGuid
    targetGuid = UnitGUID("target")
    if old == targetGuid then return end

    local oldplate = old and plateByGuid[old]
    local newplate = targetGuid and plateByGuid[targetGuid]
    if oldplate then SetTarget(oldplate, nil) end
    if newplate then SetTarget(newplate, true) end

    -- having a target at all dims every other plate
    if (old == nil) ~= (targetGuid == nil) then
      for _, plate in pairs(plateByGuid) do UpdateAlpha(plate) end
    else
      if oldplate then UpdateAlpha(oldplate) end
      if newplate then UpdateAlpha(newplate) end
    end
  end

  events.PLAYER_COMBO_POINTS = function()
    local plate = targetGuid and plateByGuid[targetGuid]
    if plate then UpdateCombo(plate) end
  end
  events.UNIT_COMBO_POINTS = events.PLAYER_COMBO_POINTS

  events.PLAYER_REGEN_DISABLED = function()
    playerInCombat = true
    for _, plate in pairs(plateByGuid) do
      UpdateCombatColor(plate)
      UpdateNameColor(plate)
    end
  end

  events.PLAYER_REGEN_ENABLED = function()
    playerInCombat = nil
    table.wipe(threatMemory)
    for _, plate in pairs(plateByGuid) do
      UpdateCombatColor(plate)
      UpdateNameColor(plate)
    end
  end

  events.PLAYER_LEVEL_UP = function()
    -- difficulty colours, and the skull threshold, move with the player
    for _, plate in pairs(plateByGuid) do
      plate.cache.level = nil
      UpdateLevel(plate)
    end
  end

  events.CURRENT_SPELL_CAST_CHANGED = UpdateSpellTargeting

  -- The interruptible flips only fire for target and focus, not nameplate
  -- tokens. castState is keyed by GUID, so they still reach those units' plates.
  events.UNIT_SPELLCAST_INTERRUPTIBLE = function(unit)
    local guid = UnitGUID(unit)
    local info = guid and castState[guid]
    local plate = info and plateByGuid[guid]
    if not plate then return end
    info.noInterrupt = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
    UpdateCast(plate)
  end
  events.UNIT_SPELLCAST_NOT_INTERRUPTIBLE = events.UNIT_SPELLCAST_INTERRUPTIBLE

  -- auto-attack state, for the right-click emulation below
  events.PLAYER_ENTER_COMBAT = function()
    nameplates.autoattack = true
    if PlayerFrame then PlayerFrame.inCombat = 1 end
  end

  events.PLAYER_LEAVE_COMBAT = function()
    nameplates.autoattack = nil
    if PlayerFrame then PlayerFrame.inCombat = nil end
  end

  for name in pairs(events) do
    if name == "UNIT_COMBO_POINTS" then
      nameplates:RegisterUnitEvent(name, "player")
    elseif name == "UNIT_SPELLCAST_INTERRUPTIBLE" or name == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
      nameplates:RegisterUnitEvent(name, "target", "focus")
    else
      nameplates:RegisterEvent(name)
    end
  end

  nameplates:SetScript("OnEvent", function()
    events[event](arg1)
  end)

  -- ============================================================================
  -- Right-click mouselook
  -- ============================================================================
  nameplates.mouselook = {}
  nameplates.mouselook.OnMouseDown = function()
    if arg1 and arg1 == "RightButton" then
      MouselookStart()

      -- start detection of the rightclick emulation
      nameplates.mouselook.time = GetTime()
      nameplates.mouselook.frame = this
    end
  end

  -- releasing the button ends the mouselook. GLOBAL_MOUSE_UP fires for every
  -- release, while PLAYER_STOPPED_LOOKING needs the camera to have moved, and
  -- a click doesn't move it.
  pfUI.events:RegisterFrameEventAndCallback("GLOBAL_MOUSE_UP", function(_, button)
    local mouselook = nameplates.mouselook
    if button ~= "RightButton" or not mouselook.frame then return end

    -- past the threshold (0.5 second) it was a drag, so no click action follows
    if mouselook.time + tonumber(C.nameplates["clickthreshold"]) >= GetTime() then
      -- run a usual nameplate rightclick action
      mouselook.frame:Click("LeftButton")
      if UnitCanAttack("player", "target") and not nameplates.autoattack then AttackTarget() end
    end
    mouselook.frame = nil
  end)

  pfUI.nameplates = nameplates
end)
