pfUI:RegisterModule("combatlog", function ()
  -- Classic Era's Blizzard_CombatLog in ChatFrame2. ClassicAPI runs the
  -- engine: COMBAT_LOG_EVENT, CombatLogAddFilter, and the kept entries that
  -- the log refills itself from when its filter changes.

  -- Classic's combat log GlobalStrings that the 1.12 client lacks
  for name, text in pairs(L["combatlog"]) do
    _G[name] = text
  end

  local COMBATLOG = ChatFrame2

  local bit_bor = bit.bor
  local bit_band = bit.band
  local tinsert = tinsert
  local math_floor = math.floor
  local format = format
  local gsub = gsub
  local strsub = strsub

  local CombatLog_Object_IsA = CombatLog_Object_IsA
  local COMBATLOG_OBJECT_NONE = COMBATLOG_OBJECT_NONE
  local COMBATLOG_OBJECT_RAIDTARGET_MASK = COMBATLOG_OBJECT_RAIDTARGET_MASK
  local COMBATLOG_OBJECT_RAIDTARGET1 = COMBATLOG_OBJECT_RAIDTARGET1
  local COMBATLOG_OBJECT_RAIDTARGET2 = COMBATLOG_OBJECT_RAIDTARGET2
  local COMBATLOG_OBJECT_RAIDTARGET3 = COMBATLOG_OBJECT_RAIDTARGET3
  local COMBATLOG_OBJECT_RAIDTARGET4 = COMBATLOG_OBJECT_RAIDTARGET4
  local COMBATLOG_OBJECT_RAIDTARGET5 = COMBATLOG_OBJECT_RAIDTARGET5
  local COMBATLOG_OBJECT_RAIDTARGET6 = COMBATLOG_OBJECT_RAIDTARGET6
  local COMBATLOG_OBJECT_RAIDTARGET7 = COMBATLOG_OBJECT_RAIDTARGET7
  local COMBATLOG_OBJECT_RAIDTARGET8 = COMBATLOG_OBJECT_RAIDTARGET8
  local COMBATLOG_FILTER_MINE = COMBATLOG_FILTER_MINE
  local COMBATLOG_FILTER_MY_PET = COMBATLOG_FILTER_MY_PET
  local COMBATLOG_FILTER_FRIENDLY_UNITS = COMBATLOG_FILTER_FRIENDLY_UNITS
  local COMBATLOG_FILTER_HOSTILE_UNITS = COMBATLOG_FILTER_HOSTILE_UNITS
  local COMBATLOG_FILTER_HOSTILE_PLAYERS = COMBATLOG_FILTER_HOSTILE_PLAYERS
  local COMBATLOG_FILTER_NEUTRAL_UNITS = COMBATLOG_FILTER_NEUTRAL_UNITS
  local COMBATLOG_FILTER_UNKNOWN_UNITS = COMBATLOG_FILTER_UNKNOWN_UNITS

  -- spell school bits (Constants.lua on later clients)
  local SCHOOL_MASK_NONE = 0
  local SCHOOL_MASK_PHYSICAL = 1
  local SCHOOL_MASK_HOLY = 2
  local SCHOOL_MASK_FIRE = 4
  local SCHOOL_MASK_NATURE = 8
  local SCHOOL_MASK_FROST = 16
  local SCHOOL_MASK_SHADOW = 32
  local SCHOOL_MASK_ARCANE = 64

  -- ChatConfigFrame's cap on saved filters
  local MAX_COMBATLOG_FILTERS = 20

  -- assigned further down, called by functions defined before them
  local Blizzard_CombatLog_Filters, Blizzard_CombatLog_CurrentSettings
  local CombatLogQuickButtonFrame, CombatLogQuickButtonFrameProgressBar
  local Blizzard_CombatLog_GenerateFullEventList, Blizzard_CombatLog_GenerateFullFlagList
  local Blizzard_CombatLog_ApplyFilters, Blizzard_CombatLog_Refilter, Blizzard_CombatLog_RefilterUpdate
  local Blizzard_CombatLog_CreateActionMenu, Blizzard_CombatLog_CreateSpellMenu
  local Blizzard_CombatLog_CreateUnitMenu, Blizzard_CombatLog_CreateFilterMenu
  local Blizzard_CombatLog_UnitMenuClick, Blizzard_CombatLog_SpellMenuClick
  local CombatLog_OnEvent, CombatLog_AddEvent, CreateCombatLogContextMenu, NewFilter
  local Blizzard_CombatLog_Update_QuickButtons, Blizzard_CombatLog_QuickButton_OnClick, ShowQuickButton

  -- runs the refilter a step per frame, and takes COMBAT_LOG_EVENT
  local CombatLogUpdateFrame = CreateFrame("Frame")

  -- ChatEdit_InsertLink for 1.12's single chat edit box
  local function InsertLink(text)
    if text and ChatFrameEditBox:IsVisible() then
      ChatFrameEditBox:Insert(text)
      return true
    end
  end

  local function CanCreateFilters()
    return #Blizzard_CombatLog_Filters.filters < MAX_COMBATLOG_FILTERS
  end

  -- BUFF / DEBUFF
  local AURA_TYPE_BUFF = "BUFF";
  local AURA_TYPE_DEBUFF = "DEBUFF"

  -- Message Limit
  local COMBATLOG_LIMIT_PER_FRAME = 1;
  local COMBATLOG_HIGHLIGHT_MULTIPLIER = 1.5;

  -- Default Colors
  local COMBATLOG_DEFAULT_COLORS = {
    -- Unit names
    unitColoring = {
      [COMBATLOG_FILTER_MINE]  = {a=1.0,r=0.70,g=0.70,b=0.70}; --{a=1.0,r=0.14,g=1.00,b=0.15};
      [COMBATLOG_FILTER_MY_PET]  = {a=1.0,r=0.70,g=0.70,b=0.70}; --{a=1.0,r=0.14,g=0.80,b=0.15};
      [COMBATLOG_FILTER_FRIENDLY_UNITS]  = {a=1.0,r=0.34,g=0.64,b=1.00};
      [COMBATLOG_FILTER_HOSTILE_UNITS]  = {a=1.0,r=0.75,g=0.05,b=0.05};
      [COMBATLOG_FILTER_HOSTILE_PLAYERS]  = {a=1.0,r=0.75,g=0.05,b=0.05};
      [COMBATLOG_FILTER_NEUTRAL_UNITS]  = {a=1.0,r=0.75,g=0.05,b=0.05}; -- {a=1.0,r=0.80,g=0.80,b=0.14};
      [COMBATLOG_FILTER_UNKNOWN_UNITS]  = {a=1.0,r=0.75,g=0.75,b=0.75};
    };
    -- School coloring
    schoolColoring = {
      [SCHOOL_MASK_NONE] = {a=1.0,r=1.00,g=1.00,b=1.00};
      [SCHOOL_MASK_PHYSICAL] = {a=1.0,r=1.00,g=1.00,b=0.00};
      [SCHOOL_MASK_HOLY]  = {a=1.0,r=1.00,g=0.90,b=0.50};
      [SCHOOL_MASK_FIRE]  = {a=1.0,r=1.00,g=0.50,b=0.00};
      [SCHOOL_MASK_NATURE]  = {a=1.0,r=0.30,g=1.00,b=0.30};
      [SCHOOL_MASK_FROST]  = {a=1.0,r=0.50,g=1.00,b=1.00};
      [SCHOOL_MASK_SHADOW]  = {a=1.0,r=0.50,g=0.50,b=1.00};
      [SCHOOL_MASK_ARCANE]  = {a=1.0,r=1.00,g=0.50,b=1.00};
    };
    -- Defaults
    defaults = {
      spell = {a=1.0,r=1.00,g=1.00,b=1.00};
      damage = {a=1.0,r=1.00,g=1.00,b=0.00};
    };
    -- Line coloring
    eventColoring = {
    };

    -- Highlighted events
    highlightedEvents = {
      ["PARTY_KILL"] = true;
    };
  };
  local COMBATLOG_DEFAULT_SETTINGS = {
    -- Settings
    fullText = true;
    textMode = TEXT_MODE_A;
    timestamp = false;
    timestampFormat = TEXT_MODE_A_TIMESTAMP;
    unitColoring = false;
    sourceColoring = true;
    destColoring = true;
    lineColoring = true;
    lineHighlighting = true;
    abilityColoring = false;
    abilityActorColoring = false;
    abilitySchoolColoring = false;
    abilityHighlighting = true;
    actionColoring = false;
    actionActorColoring = false;
    actionHighlighting = false;
    amountColoring = false;
    amountActorColoring = false;
    amountSchoolColoring = false;
    amountHighlighting = true;
    schoolNameColoring = false;
    schoolNameActorColoring = false;
    schoolNameHighlighting = true;
    noMeleeSwingColoring = false;
    missColoring = true;
    braces = false;
    unitBraces = true;
    sourceBraces = true;
    destBraces = true;
    spellBraces = false;
    itemBraces = true;
    showHistory = true;
    lineColorPriority = 1; -- 1 = source->dest->event, 2 = dest->source->event, 3 = event->source->dest
    unitIcons = true;
    hideBuffs = false;
    hideDebuffs = false;
    --unitTokens = true;
  };

  --
  -- Combat Log Icons
  --
  local COMBATLOG_ICON_RAIDTARGET1 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1.blp:0|t";
  local COMBATLOG_ICON_RAIDTARGET2 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2.blp:0|t";
  local COMBATLOG_ICON_RAIDTARGET3 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3.blp:0|t";
  local COMBATLOG_ICON_RAIDTARGET4 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4.blp:0|t";
  local COMBATLOG_ICON_RAIDTARGET5 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5.blp:0|t";
  local COMBATLOG_ICON_RAIDTARGET6 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6.blp:0|t";
  local COMBATLOG_ICON_RAIDTARGET7 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7.blp:0|t";
  local COMBATLOG_ICON_RAIDTARGET8 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8.blp:0|t";

  --
  -- Default Event List
  --
  local COMBATLOG_EVENT_LIST = {
    ["ENVIRONMENTAL_DAMAGE"] = true,
    ["SWING_DAMAGE"] = true,
    ["SWING_MISSED"] = true,
    ["RANGE_DAMAGE"] = true,
    ["RANGE_MISSED"] = true,
    ["SPELL_CAST_START"] = false,
    ["SPELL_CAST_SUCCESS"] = false,
    ["SPELL_CAST_FAILED"] = false,
    ["SPELL_MISSED"] = true,
    ["SPELL_DAMAGE"] = true,
    ["SPELL_HEAL"] = true,
    ["SPELL_ENERGIZE"] = true,
    ["SPELL_DRAIN"] = true,
    ["SPELL_LEECH"] = true,
    ["SPELL_SUMMON"] = true,
    ["SPELL_RESURRECT"] = true,
    ["SPELL_CREATE"] = true,
    ["SPELL_INSTAKILL"] = true,
    ["SPELL_INTERRUPT"] = true,
    ["SPELL_EXTRA_ATTACKS"] = true,
    ["SPELL_DURABILITY_DAMAGE"] = true,
    ["SPELL_DURABILITY_DAMAGE_ALL"] = true,
    ["SPELL_AURA_APPLIED"] = false,
    ["SPELL_AURA_APPLIED_DOSE"] = false,
    ["SPELL_AURA_REMOVED"] = false,
    ["SPELL_AURA_REMOVED_DOSE"] = false,
    ["SPELL_AURA_BROKEN"] = false,
    ["SPELL_AURA_BROKEN_SPELL"] = false,
    ["SPELL_AURA_REFRESH"] = false,
    ["SPELL_DISPEL"] = true,
    ["SPELL_STOLEN"] = true,
    ["ENCHANT_APPLIED"] = true,
    ["ENCHANT_REMOVED"] = true,
    ["SPELL_PERIODIC_MISSED"] = true,
    ["SPELL_PERIODIC_DAMAGE"] = true,
    ["SPELL_PERIODIC_HEAL"] = true,
    ["SPELL_PERIODIC_ENERGIZE"] = true,
    ["SPELL_PERIODIC_DRAIN"] = true,
    ["SPELL_PERIODIC_LEECH"] = true,
    ["SPELL_DISPEL_FAILED"] = true,
    ["DAMAGE_SHIELD"] = false,
    ["DAMAGE_SHIELD_MISSED"] = false,
    ["DAMAGE_SPLIT"] = false,
    ["PARTY_KILL"] = true,
    ["UNIT_DIED"] = true,
    ["UNIT_DESTROYED"] = true,
    ["SPELL_BUILDING_DAMAGE"] = true,
    ["SPELL_BUILDING_HEAL"] = true,
    ["UNIT_DISSIPATES"] = true,
    ["UNIT_LOYALTY"] = true,
  };

  local COMBATLOG_FLAG_LIST = {
    [COMBATLOG_FILTER_MINE] = true,
    [COMBATLOG_FILTER_MY_PET] = true,
    [COMBATLOG_FILTER_FRIENDLY_UNITS] = true,
    [COMBATLOG_FILTER_HOSTILE_UNITS] = true,
    [COMBATLOG_FILTER_HOSTILE_PLAYERS] = true,
    [COMBATLOG_FILTER_NEUTRAL_UNITS] = true,
    [COMBATLOG_FILTER_UNKNOWN_UNITS] = true,
  };

  local EVENT_TEMPLATE_FORMATS = {
    ["SPELL_AURA_BROKEN_SPELL"] = TEXT_MODE_A_STRING_3,
    ["SPELL_CAST_START"] = TEXT_MODE_A_STRING_2,
    ["SPELL_CAST_SUCCESS"] = TEXT_MODE_A_STRING_2
  };

  --
  -- Generates a new event list from the COMBATLOG_EVENT_LIST global
  --
  -- I wish there was a better way built in to do this.
  --
  -- Returns:
  -- An array, indexed by the events, with a value of true
  --
  function Blizzard_CombatLog_GenerateFullEventList ( )
    local eventList = {}
    for event, v in pairs ( COMBATLOG_EVENT_LIST ) do
      eventList[event] = true;
    end
    return eventList;
  end

  function Blizzard_CombatLog_GenerateFullFlagList(flag)
    local flagList = {};
    for k, v in pairs(COMBATLOG_FLAG_LIST) do
      flagList[k] = flag;
    end
    return flagList;
  end

  --
  -- Default CombatLog Filter
  -- This table is used to create new CombatLog filters
  --
  local DEFAULT_COMBATLOG_FILTER_TEMPLATE = {
    -- Descriptive Information
    hasQuickButton = true;
    quickButtonDisplay = {
      solo = true;
      party = true;
      raid = true;
    };

    -- Default Color and Formatting Options
    settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS);

    -- Coloring
    colors = CopyTable(COMBATLOG_DEFAULT_COLORS);

    -- The actual client filters
    filters = {
      [1] = {
        eventList = Blizzard_CombatLog_GenerateFullEventList();
        sourceFlags = {
          [COMBATLOG_FILTER_MINE] = true,
          [COMBATLOG_FILTER_MY_PET] = true;
        };
        destFlags = nil;
      };
      [2] = {
        eventList = Blizzard_CombatLog_GenerateFullEventList();
        sourceFlags = nil;
        destFlags = {
          [COMBATLOG_FILTER_MINE] = true,
          [COMBATLOG_FILTER_MY_PET] = true;
        };
      };
    };
  };

  --
  -- Persistant Variables
  --
  --
  -- Default Filters
  --
  local Blizzard_CombatLog_Filter_Defaults = {
    -- All of the filters
    filters = {
      [1] = {
        -- Descriptive Information
        name = QUICKBUTTON_NAME_SELF;
        hasQuickButton = true;
        quickButtonName = QUICKBUTTON_NAME_SELF;
        quickButtonDisplay = {
          solo = true;
          party = true;
          raid = true;
        };
        tooltip = QUICKBUTTON_NAME_SELF_TOOLTIP;

        -- Default Color and Formatting Options
        settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS);

        -- Coloring
        colors = CopyTable(COMBATLOG_DEFAULT_COLORS);

        -- The actual client filters
        filters = {
          [1] = {
            eventList = {
                  ["ENVIRONMENTAL_DAMAGE"] = true,
                  ["SWING_DAMAGE"] = true,
                  ["SWING_MISSED"] = true,
                  ["RANGE_DAMAGE"] = true,
                  ["RANGE_MISSED"] = true,
                  --["SPELL_CAST_START"] = true,
                  --["SPELL_CAST_SUCCESS"] = true,
                  --["SPELL_CAST_FAILED"] = true,
                  ["SPELL_MISSED"] = true,
                  ["SPELL_DAMAGE"] = true,
                  ["SPELL_HEAL"] = true,
                  ["SPELL_ENERGIZE"] = true,
                  ["SPELL_DRAIN"] = true,
                  ["SPELL_LEECH"] = true,
                  ["SPELL_INSTAKILL"] = true,
                  ["SPELL_INTERRUPT"] = true,
                  ["SPELL_EXTRA_ATTACKS"] = true,
                  --["SPELL_DURABILITY_DAMAGE"] = true,
                  --["SPELL_DURABILITY_DAMAGE_ALL"] = true,
                  ["SPELL_AURA_APPLIED"] = true,
                  ["SPELL_AURA_APPLIED_DOSE"] = true,
                  ["SPELL_AURA_REMOVED"] = true,
                  ["SPELL_AURA_REMOVED_DOSE"] = true,
                  ["SPELL_AURA_BROKEN"] = true,
                ["SPELL_AURA_BROKEN_SPELL"] = true,
                ["SPELL_AURA_REFRESH"] = true,
                  ["SPELL_DISPEL"] = true,
                  ["SPELL_STOLEN"] = true,
                  ["ENCHANT_APPLIED"] = true,
                  ["ENCHANT_REMOVED"] = true,
                  ["SPELL_PERIODIC_MISSED"] = true,
                  ["SPELL_PERIODIC_DAMAGE"] = true,
                  ["SPELL_PERIODIC_HEAL"] = true,
                  ["SPELL_PERIODIC_ENERGIZE"] = true,
                  ["SPELL_PERIODIC_DRAIN"] = true,
                  ["SPELL_PERIODIC_LEECH"] = true,
                  ["SPELL_DISPEL_FAILED"] = true,
                  --["DAMAGE_SHIELD"] = true,
                  --["DAMAGE_SHIELD_MISSED"] = true,
                  --["DAMAGE_SPLIT"] = true,
                  ["PARTY_KILL"] = true,
                  ["UNIT_DIED"] = true,
                  ["UNIT_DESTROYED"] = true,
                  ["UNIT_DISSIPATES"] = true
            };
            sourceFlags = {
              [COMBATLOG_FILTER_MINE] = true,
              [COMBATLOG_FILTER_MY_PET] = true;
            };
            destFlags = nil;
          };
          [2] = {
            eventList = {
                  --["ENVIRONMENTAL_DAMAGE"] = true,
                  ["SWING_DAMAGE"] = true,
                  ["SWING_MISSED"] = true,
                  ["RANGE_DAMAGE"] = true,
                  ["RANGE_MISSED"] = true,
                  --["SPELL_CAST_START"] = true,
                  --["SPELL_CAST_SUCCESS"] = true,
                  --["SPELL_CAST_FAILED"] = true,
                  ["SPELL_MISSED"] = true,
                  ["SPELL_DAMAGE"] = true,
                  ["SPELL_HEAL"] = true,
                  ["SPELL_ENERGIZE"] = true,
                  ["SPELL_DRAIN"] = true,
                  ["SPELL_LEECH"] = true,
                  ["SPELL_INSTAKILL"] = true,
                  ["SPELL_INTERRUPT"] = true,
                  ["SPELL_EXTRA_ATTACKS"] = true,
                  --["SPELL_DURABILITY_DAMAGE"] = true,
                  --["SPELL_DURABILITY_DAMAGE_ALL"] = true,
                  --["SPELL_AURA_APPLIED"] = true,
                  --["SPELL_AURA_APPLIED_DOSE"] = true,
                  --["SPELL_AURA_REMOVED"] = true,
                  --["SPELL_AURA_REMOVED_DOSE"] = true,
                  ["SPELL_DISPEL"] = true,
                  ["SPELL_STOLEN"] = true,
                  ["ENCHANT_APPLIED"] = true,
                  ["ENCHANT_REMOVED"] = true,
                  --["SPELL_PERIODIC_MISSED"] = true,
                  --["SPELL_PERIODIC_DAMAGE"] = true,
                  --["SPELL_PERIODIC_HEAL"] = true,
                  --["SPELL_PERIODIC_ENERGIZE"] = true,
                  --["SPELL_PERIODIC_DRAIN"] = true,
                  --["SPELL_PERIODIC_LEECH"] = true,
                  ["SPELL_DISPEL_FAILED"] = true,
                  --["DAMAGE_SHIELD"] = true,
                  --["DAMAGE_SHIELD_MISSED"] = true,
                  --["DAMAGE_SPLIT"] = true,
                  ["PARTY_KILL"] = true,
                  ["UNIT_DIED"] = true,
                  ["UNIT_DESTROYED"] = true,
                  ["UNIT_DISSIPATES"] = true
            };
            sourceFlags = nil;
            destFlags = {
              [COMBATLOG_FILTER_MINE] = true,
              [COMBATLOG_FILTER_MY_PET] = true;
            };
          };
        };
      };
      [2] = {
        -- Descriptive Information
        name = QUICKBUTTON_NAME_EVERYTHING;
        hasQuickButton = true;
        quickButtonName = QUICKBUTTON_NAME_EVERYTHING;
        quickButtonDisplay = {
          solo = true;
          party = true;
          raid = true;
        };
        tooltip = QUICKBUTTON_NAME_EVERYTHING_TOOLTIP;

        -- Settings
        settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS);

        -- Coloring
        colors = CopyTable(COMBATLOG_DEFAULT_COLORS);

        -- The actual client filters
        filters = {
          [1] = {
            eventList = Blizzard_CombatLog_GenerateFullEventList();
            sourceFlags = Blizzard_CombatLog_GenerateFullFlagList(true);
            destFlags = nil;
          };
          [2] = {
            eventList = Blizzard_CombatLog_GenerateFullEventList();
            sourceFlags = nil;
            destFlags = Blizzard_CombatLog_GenerateFullFlagList(true);
          };
        };
      };
      [3] = {
        -- Descriptive Information
        name = QUICKBUTTON_NAME_ME;
        hasQuickButton = true;
        quickButtonName = QUICKBUTTON_NAME_ME;
        quickButtonDisplay = {
          solo = true;
          party = true;
          raid = true;
        };
        tooltip = QUICKBUTTON_NAME_ME_TOOLTIP;

        -- Settings
        settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS);

        -- Coloring
        colors = CopyTable(COMBATLOG_DEFAULT_COLORS);

        -- The actual client filters
        filters = {
          [1] = {
            eventList = Blizzard_CombatLog_GenerateFullEventList();
            sourceFlags = Blizzard_CombatLog_GenerateFullFlagList(false);
            destFlags = nil;
          };
          [2] = {
            eventList = Blizzard_CombatLog_GenerateFullEventList();
            sourceFlags = nil;
            destFlags =  {
              [COMBATLOG_FILTER_MINE] = true,
              [COMBATLOG_FILTER_MY_PET] = true;
            };
          };
        };
      };
      [4] = {
        -- Descriptive Information
        name = QUICKBUTTON_NAME_KILLS;
        hasQuickButton = false;
        quickButtonName = QUICKBUTTON_NAME_KILLS;
        quickButtonDisplay = {
          solo = true;
          party = true;
          raid = true;
        };
        tooltip = QUICKBUTTON_NAME_KILLS_TOOLTIP;

        -- Settings
        settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS);

        -- Coloring
        colors = CopyTable(COMBATLOG_DEFAULT_COLORS);

        -- The actual client filters
        filters = {
          [1] = {
            eventList = {
              ["PARTY_KILL"] = true,
              ["UNIT_DIED"] = true,
              ["UNIT_DESTROYED"] = true,
              ["UNIT_DISSIPATES"] = true
            };
            sourceFlags = Blizzard_CombatLog_GenerateFullFlagList(true);
            destFlags = nil;
          };
          [2] = {
            eventList = {
              ["PARTY_KILL"] = true,
              ["UNIT_DIED"] = true,
              ["UNIT_DESTROYED"] = true,
              ["UNIT_DISSIPATES"] = true
            };
            sourceFlags = nil;
            destFlags = Blizzard_CombatLog_GenerateFullFlagList(true);
          };
        };
      };
    };

    -- Current Filter
    currentFilter = 1;
  };

  -- Combat Log Filter Resetting Code
  --
  -- args:
  --  config - the configuration array we are about to apply
  --
  function Blizzard_CombatLog_ApplyFilters(config)
    if ( not config ) then
      return;
    end
    CombatLogResetFilter()

    -- Loop over all associated filters
    local eventList;
    for k,v in pairs(config.filters) do
      local eList
      -- Only use the first filter's eventList because for some reason each filter that the player can see actually
      -- has two filters, one for source flags and one for dest flags (??), even though only the eventList for the source
      -- flags is updated properly
      eventList = config.filters[1].eventList;
      if ( eventList ) then
        for k2,v2 in pairs(eventList) do
          if ( v2 == true ) then
          -- The true comparison is because check boxes whose parent is unchecked will be non-false but not "true"
            eList = eList and (eList .. "," .. k2) or k2
          end
        end
      end

      local sourceFlags, destFlags;
      if ( v.sourceFlags ) then
        sourceFlags = 0;
        for k2, v2 in pairs(v.sourceFlags) do
          -- Support for GUIDs
          if ( type (k2) == "string" ) then
            sourceFlags = k2;
            break;
          end
          -- Otherwise OR bits
          if ( v2 ) then
            sourceFlags = bit_bor(sourceFlags, k2);
          end
        end
      end
      if ( v.destFlags ) then
        destFlags = 0;
        for k2, v2 in pairs(v.destFlags) do
          -- Support for GUIDs
          if ( type (k2) == "string" ) then
            destFlags = k2;
            break;
          end
          -- Otherwise OR bits
          if ( v2 ) then
            destFlags = bit_bor(destFlags, k2);
          end
        end
      end
      if ( type(sourceFlags) == "string" and destFlags == 0 ) then
        destFlags = nil;
      end
      if ( type(destFlags) == "string" and sourceFlags == 0 ) then
        sourceFlags = nil;
      end

      -- This is a HACK!!!  Need filters to be able to accept empty or zero sourceFlags or destFlags
      if ( sourceFlags == 0 or destFlags == 0 ) then
        CombatLogAddFilter("", COMBATLOG_FILTER_MINE, nil);
      else
        CombatLogAddFilter(eList, sourceFlags, destFlags);
      end
    end
  end

  --
  -- Combat Log Repopulation Code
  --

  -- Message Limit

  local COMBATLOG_MESSAGE_LIMIT = 300;

  --
  -- Repopulate the combat log with message history
  --
  function Blizzard_CombatLog_Refilter()
    local count = CombatLogGetNumEntries();

    COMBATLOG:SetMaxLines(COMBATLOG_MESSAGE_LIMIT);

    -- count should be between 1 and COMBATLOG_MESSAGE_LIMIT
    count = max(1, min(count, COMBATLOG_MESSAGE_LIMIT));

    CombatLogSetCurrentEntry(0);

    -- Clear the combat log
    COMBATLOG:Clear();

    -- Moved setting the max value here, since we don't really need to reset the max every frame, do we?
    -- We can't add events while refiltering (:AddFilter short circuits) so this should be safe optimization.
    CombatLogQuickButtonFrameProgressBar:SetMinMaxValues(0, count);
    CombatLogQuickButtonFrameProgressBar:SetValue(0);
    CombatLogQuickButtonFrameProgressBar:Show();

    -- Enable the distributed frame
    CombatLogUpdateFrame.refiltering = true;
    CombatLogUpdateFrame:SetScript("OnUpdate", Blizzard_CombatLog_RefilterUpdate)

    Blizzard_CombatLog_RefilterUpdate()
  end

  --
  -- This is a single frame "step" in the refiltering process
  --
  function Blizzard_CombatLog_RefilterUpdate()
    local valid = CombatLogGetCurrentEntry(); -- CombatLogAdvanceEntry(0);

    -- Clear the combat log
    local total = 0;
    while (valid and total < COMBATLOG_LIMIT_PER_FRAME) do
      -- Log to the window
      local text, r, g, b, a = CombatLog_OnEvent(Blizzard_CombatLog_CurrentSettings, CombatLogGetCurrentEntry());
      -- NOTE: be sure to pass in nil for the color id or the color id may override the r, g, b values for this message
      if ( text ) then
        COMBATLOG:BackFillMessage(text, r, g, b);
      end

      -- count can be
      --  positive to advance from oldest to newest
      --  negative to advance from newest to oldest
      valid = CombatLogAdvanceEntry(-1)
      total = total + 1;
    end

    -- Show filtering progress bar
    CombatLogQuickButtonFrameProgressBar:SetValue(CombatLogQuickButtonFrameProgressBar:GetValue() + total);

    if ( not valid or (CombatLogQuickButtonFrameProgressBar:GetValue() >= COMBATLOG_MESSAGE_LIMIT) ) then
      CombatLogUpdateFrame.refiltering = false
      CombatLogUpdateFrame:SetScript("OnUpdate", nil)
      CombatLogQuickButtonFrameProgressBar:Hide();
    end
  end

  --
  -- Creates the action menu popup
  --
  do
    local eventType
    local actionMenu = {
      [1] = {
        text = "string.format(BLIZZARD_COMBAT_LOG_MENU_SPELL_HIDE, eventType)",
        func = function () Blizzard_CombatLog_SpellMenuClick ("HIDE",  nil, nil, eventType); end;
      },
    };
    function Blizzard_CombatLog_CreateActionMenu(eventType_arg)
      -- Update upvalues
      eventType = eventType_arg
      actionMenu[1].text = string.format(BLIZZARD_COMBAT_LOG_MENU_SPELL_HIDE, eventType_arg);
      return actionMenu
    end
  end

  --
  -- Creates the spell menu popup
  --
  do
    local spellName, spellId, eventType
    local spellMenu = {
      [1] = {
        text = "string.format(BLIZZARD_COMBAT_LOG_MENU_SPELL_LINK, spellName)",
        func = function () Blizzard_CombatLog_SpellMenuClick ("LINK", spellName, spellId, eventType); end;
      },
    };
    local spellMenu2 = {
      [2] = {
        text = "string.format(BLIZZARD_COMBAT_LOG_MENU_SPELL_HIDE, eventType)",
        func = function () Blizzard_CombatLog_SpellMenuClick ("HIDE", spellName, spellId, eventType); end;
      },
    };
    function Blizzard_CombatLog_CreateSpellMenu(spellName_arg, spellId_arg, eventType_arg)
      -- Update upvalues
      spellName, spellId, eventType = spellName_arg, spellId_arg, eventType_arg;
      -- Update menu text and filters
      spellMenu[1].text = string.format(BLIZZARD_COMBAT_LOG_MENU_SPELL_LINK, spellName);
      if ( eventType ) then
        spellMenu2[2].text = string.format(BLIZZARD_COMBAT_LOG_MENU_SPELL_HIDE, eventType);
        -- Copy the table references over
        spellMenu[2] = spellMenu2[2];
      else
        -- Remove the table reference, it is still stored in its closure
        spellMenu[2] = nil;
      end
      return spellMenu;
    end
  end

  --
  -- Temporary Menu
  --
  do
    function Blizzard_CombatLog_CreateUnitMenu(unitName, unitGUID, special)
      local displayName = unitName;
      if ( (unitGUID == UnitGUID("player")) and (_G["COMBAT_LOG_UNIT_YOU_ENABLED"] == "1") ) then
        displayName = UNIT_YOU;
      end
      local unitMenu = {
        [1] = {
          text = string.format(BLIZZARD_COMBAT_LOG_MENU_BOTH, displayName); -- Dummy text
          func = function () Blizzard_CombatLog_UnitMenuClick ("BOTH", unitName, unitGUID, special); end;
        },
        [2] = {
          text = string.format(BLIZZARD_COMBAT_LOG_MENU_INCOMING, displayName);
          func = function () Blizzard_CombatLog_UnitMenuClick ("INCOMING", unitName, unitGUID, special); end;
        },
        [3] = {
          text = string.format(BLIZZARD_COMBAT_LOG_MENU_OUTGOING, displayName);
          func = function () Blizzard_CombatLog_UnitMenuClick ("OUTGOING", unitName, unitGUID, special); end;
        },
        [4] = {
          divider = true;
        },
        [5] = {
          text = BLIZZARD_COMBAT_LOG_MENU_EVERYTHING;
          func = function () Blizzard_CombatLog_UnitMenuClick ("EVERYTHING", unitName, unitGUID, special); end;
        },
        [6] = {
          text = BLIZZARD_COMBAT_LOG_MENU_SAVE;
          func = function () Blizzard_CombatLog_UnitMenuClick ("SAVE", unitName, unitGUID, special); end;
          disabled = not CanCreateFilters();
        },
        [7] = {
          text = BLIZZARD_COMBAT_LOG_MENU_RESET;
          func = function () Blizzard_CombatLog_UnitMenuClick ("RESET", unitName, unitGUID, special); end;
        },
      };

      if ( unitGUID ~= UnitGUID("player") ) then
        table.insert(unitMenu, 4, {
          text = string.format(BLIZZARD_COMBAT_LOG_MENU_OUTGOING_ME, displayName);
          func = function () Blizzard_CombatLog_UnitMenuClick ("OUTGOING_ME", unitName, unitGUID, special); end;
        } );
      end
      return unitMenu
    end
  end
  -- Create additional filter dropdown list
  do
    local menu = {};
    function Blizzard_CombatLog_CreateFilterMenu()
      local count = 1;
      for index, value in pairs(menu) do
        if ( not value ) then
          value = {};
        else
          for k, v in pairs(value) do
            value[k] = nil;
          end
        end
      end
      local selectedIndex = Blizzard_CombatLog_Filters.currentFilter;
      local checked;
      for index, value in ipairs(Blizzard_CombatLog_Filters.filters) do
        if ( not value.onQuickBar ) then
          if ( not menu[count] ) then
            menu[count] = {};
          end
          menu[count].text = value.name;
          menu[count].func = function () Blizzard_CombatLog_QuickButton_OnClick(index); end;
          if ( selectedIndex == index ) then
            checked = 1;
          else
            checked = nil;
          end
          menu[count].checked =  checked;
          count = count+1;
        end
      end
      return menu;
    end
  end
  --
  -- Handle mini menu clicks
  --
  -- args:
  --  event - "EVERYTHING" | "RESET" | "INCOMING" | "OUTGOING" | "BOTH"
  --  unitName - string for the units name
  --  unitGUID - unique global unit ID for the specific unit
  --  special - bit code for special filters, such as raid targets
  --
  function Blizzard_CombatLog_UnitMenuClick(event, unitName, unitGUID, unitFlags)
    if ( event == "SAVE" ) then
      NewFilter(Blizzard_CombatLog_CurrentSettings);
      return;
    elseif ( event == "RESET" ) then
      Blizzard_CombatLog_CurrentSettings = Blizzard_CombatLog_Filters.filters[Blizzard_CombatLog_Filters.currentFilter];
      Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings);
      Blizzard_CombatLog_Update_QuickButtons()
    else
      -- Copy the current settings
      local previousSettings = Blizzard_CombatLog_CurrentSettings;
      Blizzard_CombatLog_CurrentSettings = {};

      for k,v in pairs( previousSettings ) do
        Blizzard_CombatLog_CurrentSettings[k] = v;
      end

      -- Erase the filter criteria
      Blizzard_CombatLog_CurrentSettings.filters = {};  -- We want to be careful not to destroy the active data, so the user can reset

      if ( event == "EVERYTHING" ) then
        -- Reset all filtering.
        CombatLogResetFilter()
        --Blizzard_CombatLog_CurrentSettings = Blizzard_CombatLog_Filters.contextMenu[event];
        CombatLogAddFilter(nil, nil, nil)
        tinsert ( Blizzard_CombatLog_CurrentSettings.filters, {} );
      end
      if ( event == "INCOMING" or event == "BOTH" ) then
        if ( unitFlags ) then
          tinsert ( Blizzard_CombatLog_CurrentSettings.filters, { destFlags = { [unitFlags] = true; } } );
        else
          tinsert ( Blizzard_CombatLog_CurrentSettings.filters, { destFlags = { [unitGUID] = true; } } );
        end
      end
      if ( event == "OUTGOING" or event == "BOTH" ) then
        if ( unitFlags ) then
          tinsert ( Blizzard_CombatLog_CurrentSettings.filters, { sourceFlags = { [unitFlags] = true; } } );
        else
          tinsert ( Blizzard_CombatLog_CurrentSettings.filters, { sourceFlags = { [unitGUID] = true; } } );
        end
      end
      if ( event == "OUTGOING_ME" ) then
        if ( unitFlags ) then
          tinsert ( Blizzard_CombatLog_CurrentSettings.filters, { sourceFlags = { [unitFlags] = true; }; destFlags = { [COMBATLOG_FILTER_MINE] = true; } } );
        else
          tinsert ( Blizzard_CombatLog_CurrentSettings.filters, { sourceFlags = { [unitGUID] = true; }; destFlags = { [COMBATLOG_FILTER_MINE] = true; } } );
        end
      end

      -- If the context menu is not resetting, then we need to create an event list,
      -- So that right click removal works when the user right clicks
      --

      -- Fill the event list
      local fullEventList = Blizzard_CombatLog_GenerateFullEventList();

      -- Insert to the active data
      for k,v in pairs (Blizzard_CombatLog_CurrentSettings.filters) do
        v.eventList = fullEventList;
      end

      -- Apply the generated filters
      Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings);
      -- Let the system know that this filter is temporary and unhighlight any quick buttons
      Blizzard_CombatLog_CurrentSettings.isTemp = true;
      Blizzard_CombatLog_Update_QuickButtons()
    end

    -- Reset the combat log text box! (Grats!)
    Blizzard_CombatLog_Refilter();
  end

  --
  -- Handle spell mini menu clicks
  -- args:
  --  action - "HIDE" | "LINK"
  -- spellName - Spell or ability's name
  -- spellId - Spell or ability's id (100, 520, 30000, etc)
  -- event - the event type that generated this message
  --
  function Blizzard_CombatLog_SpellMenuClick(action, spellName, spellId, eventType)
    if ( action == "HIDE" ) then
      for k,v in pairs (Blizzard_CombatLog_CurrentSettings.filters) do
        if ( type (v.eventList) ~= "table" ) then
          v.eventList = Blizzard_CombatLog_GenerateFullEventList();
        end
        v.eventList[eventType] = false;
      end
    elseif ( action == "LINK" ) then
      if ( not InsertLink(GetSpellLink(spellId)) ) then
        ChatFrame_OpenChat(GetSpellLink(spellId));
      end
      return;
    end

    -- Apply the newly reconstituted filters
    Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings);

    -- Reset the combat log text box! (Grats!)
    Blizzard_CombatLog_Refilter();
  end

  --[[
  -- Converts 4 floats into FF code
  --
  --]]
  local function CombatLog_Color_FloatToText(r,g,b,a)
    if ( type(r) == "table" ) then
      r, g, b, a = r.r, r.g, r.b, r.a;
    end
    a = min(1, a or 1) * 255
    r = min(1, r) * 255
    g = min(1, g) * 255
    b = min(1, b) * 255

    -- local fmt = "%.2x";
    return format("%.2x%.2x%.2x%.2x", math_floor(a), math_floor(r), math_floor(g), math_floor(b))
  end

  --
  -- Gets the appropriate color for an event type
  --

  -- If this needs to return a new table per event (ie, the table gets modified), then just replace the "defaultColorArray" in the function with
  -- a new table creation.
  local defaultColorArray = {a=1.0,r=0.5,g=0.5,b=0.5}
  local function CombatLog_Color_ColorArrayByEventType( event )
    return Blizzard_CombatLog_CurrentSettings.colors.eventColoring[event] or defaultColorArray
  end

  --
  -- Gets the appropriate color for a unit type
  --

  local function CombatLog_Color_ColorArrayByUnitType(unitFlags, settings)
    local array = nil;
    if ( not settings ) then
      settings = Blizzard_CombatLog_CurrentSettings;
    end
    for mask,colorArray in pairs( settings.colors.unitColoring ) do
      if ( CombatLog_Object_IsA (unitFlags, mask) )then
        array = colorArray;
        break;
      end
    end
    return array or defaultColorArray
  end

  --
  -- Gets the appropriate color for a  spell school
  --
  local function CombatLog_Color_ColorArrayBySchool(school, settings)
    if ( not settings ) then
      settings = Blizzard_CombatLog_CurrentSettings;
    end
    if ( not school ) then
      return settings.colors.schoolColoring.default;
    end

    return settings.colors.schoolColoring[school] or settings.colors.defaults.spell;
  end

  --
  -- Gets the appropriate color for a  spell school
  --

  local highlightColorTable = {}
  local function CombatLog_Color_HighlightColorArray(colorArray)
    highlightColorTable.r = colorArray.r * COMBATLOG_HIGHLIGHT_MULTIPLIER;
    highlightColorTable.g = colorArray.g * COMBATLOG_HIGHLIGHT_MULTIPLIER;
    highlightColorTable.b = colorArray.b * COMBATLOG_HIGHLIGHT_MULTIPLIER;
    highlightColorTable.a = colorArray.a;

    return highlightColorTable
  end

  --
  -- Returns a string associated with a numeric power type
  --

  local powerTypeToStringLookup =
  {
    [Enum.PowerType.Mana] = MANA,
    [Enum.PowerType.Rage] = RAGE,
    [Enum.PowerType.Focus] = FOCUS,
    [Enum.PowerType.Energy] = ENERGY,
    [Enum.PowerType.Happiness] = HAPPINESS,
  };

  local function CombatLog_String_PowerType(powerType)
    -- Previous behavior was specifically returning an empty string in this case
    if ( not powerType ) then
      return "";
    end

    -- Previous behavior was returning nil if powerType didn't match one of the explicitly checked types
    return powerTypeToStringLookup[powerType];
  end

  local function CombatLog_String_SchoolString(school)
    if ( not school or school == SCHOOL_MASK_NONE ) then
      return STRING_SCHOOL_UNKNOWN;
    end

    local schoolString = C_Spell.GetSchoolString(school);
    return schoolString or STRING_SCHOOL_UNKNOWN
  end

  local function CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overenergize )
    local resultStr;
    -- Result String formatting
    local useOverhealing = overhealing and overhealing > 0;
    local useOverkill = overkill and overkill > 0;
    local useOverEnergize = overenergize and overenergize > 0;
    local useAbsorbed = absorbed and absorbed > 0;
    if ( resisted or blocked or critical or glancing or crushing or useOverhealing or useOverkill or useAbsorbed or overenergize ) then
      resultStr = nil;

      if ( resisted ) then
        if ( resisted < 0 ) then --Its really a vulnerability
          resultStr = format(TEXT_MODE_A_STRING_RESULT_VULNERABILITY, -resisted);
        else
          resultStr = format(TEXT_MODE_A_STRING_RESULT_RESIST, resisted);
        end
      end
      if ( blocked ) then
        if ( resultStr ) then
          resultStr = resultStr.." "..format(TEXT_MODE_A_STRING_RESULT_BLOCK, blocked);
        else
          resultStr = format(TEXT_MODE_A_STRING_RESULT_BLOCK, blocked);
        end
      end
      if ( useAbsorbed ) then
        if ( resultStr ) then
          resultStr = resultStr.." "..format(TEXT_MODE_A_STRING_RESULT_ABSORB, absorbed);
        else
          resultStr = format(TEXT_MODE_A_STRING_RESULT_ABSORB, absorbed);
        end
      end
      if ( glancing ) then
        if ( resultStr ) then
          resultStr = resultStr.." "..TEXT_MODE_A_STRING_RESULT_GLANCING;
        else
          resultStr = TEXT_MODE_A_STRING_RESULT_GLANCING;
        end
      end
      if ( crushing ) then
        if ( resultStr ) then
          resultStr = resultStr.." "..TEXT_MODE_A_STRING_RESULT_CRUSHING;
        else
          resultStr = TEXT_MODE_A_STRING_RESULT_CRUSHING;
        end
      end
      if ( useOverhealing ) then
        if ( resultStr ) then
          resultStr = resultStr.." "..format(TEXT_MODE_A_STRING_RESULT_OVERHEALING, overhealing);
        else
          resultStr = format(TEXT_MODE_A_STRING_RESULT_OVERHEALING, overhealing);
        end
      end
      if ( useOverkill ) then
        if ( resultStr ) then
          resultStr = resultStr.." "..format(TEXT_MODE_A_STRING_RESULT_OVERKILLING, overkill);
        else
          resultStr = format(TEXT_MODE_A_STRING_RESULT_OVERKILLING, overkill);
        end
      end
      if ( useOverEnergize ) then
        if ( resultStr ) then
          resultStr = resultStr.." "..format(TEXT_MODE_A_STRING_RESULT_OVERENERGIZE, overenergize);
        else
          resultStr = format(TEXT_MODE_A_STRING_RESULT_OVERENERGIZE, overenergize);
        end
      end
      if ( critical ) then
        local critString = TEXT_MODE_A_STRING_RESULT_CRITICAL;
        if ( spellId ) then
          critString = TEXT_MODE_A_STRING_RESULT_CRITICAL_SPELL;
        end
        if ( resultStr ) then
          resultStr = resultStr.." "..critString;
        else
          resultStr = critString;
        end
      end
    end

    return resultStr;
  end

  --
  -- Get the appropriate raid icon for a unit
  --
  local function CombatLog_String_GetIcon ( unitFlags, direction )

    -- Check for an appropriate icon for this unit
    local raidTarget = bit_band(unitFlags, COMBATLOG_OBJECT_RAIDTARGET_MASK);
    if ( raidTarget == 0 ) then
      return "";
    end

    local iconString = "";
    local icon = nil;
    local iconBit = 0;

    if ( raidTarget == COMBATLOG_OBJECT_RAIDTARGET1 ) then
      icon = COMBATLOG_ICON_RAIDTARGET1;
      iconBit = COMBATLOG_OBJECT_RAIDTARGET1;
    elseif ( raidTarget == COMBATLOG_OBJECT_RAIDTARGET2 ) then
      icon = COMBATLOG_ICON_RAIDTARGET2;
      iconBit = COMBATLOG_OBJECT_RAIDTARGET2;
    elseif ( raidTarget == COMBATLOG_OBJECT_RAIDTARGET3 ) then
      icon = COMBATLOG_ICON_RAIDTARGET3;
      iconBit = COMBATLOG_OBJECT_RAIDTARGET3;
    elseif ( raidTarget == COMBATLOG_OBJECT_RAIDTARGET4 ) then
      icon = COMBATLOG_ICON_RAIDTARGET4;
      iconBit = COMBATLOG_OBJECT_RAIDTARGET4;
    elseif ( raidTarget == COMBATLOG_OBJECT_RAIDTARGET5 ) then
      icon = COMBATLOG_ICON_RAIDTARGET5;
      iconBit = COMBATLOG_OBJECT_RAIDTARGET5;
    elseif ( raidTarget == COMBATLOG_OBJECT_RAIDTARGET6 ) then
      icon = COMBATLOG_ICON_RAIDTARGET6;
      iconBit = COMBATLOG_OBJECT_RAIDTARGET6;
    elseif ( raidTarget == COMBATLOG_OBJECT_RAIDTARGET7 ) then
      icon = COMBATLOG_ICON_RAIDTARGET7;
      iconBit = COMBATLOG_OBJECT_RAIDTARGET7;
    elseif ( raidTarget == COMBATLOG_OBJECT_RAIDTARGET8 ) then
      icon = COMBATLOG_ICON_RAIDTARGET8;
      iconBit = COMBATLOG_OBJECT_RAIDTARGET8;
    end

    -- Insert the Raid Icon if it exists
    if ( icon ) then
      --
      -- Insert a hyperlink for that icon

      if ( direction == "source" ) then
        iconString = format(TEXT_MODE_A_STRING_SOURCE_ICON, iconBit, icon);
      else
        iconString = format(TEXT_MODE_A_STRING_DEST_ICON, iconBit, icon);
      end
    end

    return iconString;
  end

  --
  -- Gets the appropriate color for a unit type
  --
  --
  local function CombatLog_Color_ColorStringByUnitType(unitFlags)
    local colorArray = CombatLog_Color_ColorArrayByUnitType(unitFlags);

    return  CombatLog_Color_FloatToText(colorArray.r, colorArray.g, colorArray.b, colorArray.a )
  end

  --[[
  -- Handles events and dumps them to the specified frame.
  --]]

  -- Add settings as an arg

  local defaultCombatLogLineColor = { a = 1.00, r = 1.00, g = 1.00, b = 1.00 };

  function CombatLog_OnEvent(filterSettings, timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, ...)
    -- [environmentalDamageType]
    -- [spellName, spellRank, spellSchool]
    -- [damage, school, [resisted, blocked, absorbed, crit, glancing, crushing]]

    -- Upvalue this, we're gonna use it a lot
    local settings = filterSettings.settings;

    local lineColor = defaultCombatLogLineColor;
    local sourceColor, destColor = nil, nil;

    local braceColor = "FFFFFFFF";
    local abilityColor = "FFFFFF00";

    -- Processing variables
    local textMode = settings.textMode;
    local timestampEnabled = settings.timestamp;
    local hideBuffs = settings.hideBuffs;
    local hideDebuffs = settings.hideDebuffs;
    local sourceEnabled = true;
    local falseSource = false;
    local destEnabled = true;
    local valueEnabled = true;
    local valueTypeEnabled = true;
    local resultEnabled = true;
    local powerTypeEnabled = true;
    local extraSpellEnabled = false;
    local valueIsItem = false;
    local withPoints = false;
    local forceDestPossessive = false;

    -- Get the initial string
    local schoolString;
    local resultStr = nil;

    local formatString = TEXT_MODE_A_STRING_1;
    if ( EVENT_TEMPLATE_FORMATS[event] ) then
      formatString = EVENT_TEMPLATE_FORMATS[event];
    end

    -- Replacements to do:
    -- * Src, Dest, Action, Spell, Amount, Result

    -- Spell standard order
    local spellId, spellName, spellSchool = nil, nil, nil;
    local extraSpellId, extraSpellName, extraSpellSchool = nil, nil, nil;

    -- For Melee/Ranged swings and enchants
    local nameIsNotSpell;
    local extraNameIsNotSpell = false;

    -- Damage standard order
    local amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, overhealing = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil;
    -- Miss argument order
    local missType, isOffHand, amountMissed;
    -- Aura arguments
    local auraType; -- BUFF or DEBUFF
    -- Energize Arguments
    local overEnergize = nil;

    -- Enchant arguments
    local itemId, itemName;

    -- Special Spell values
    local valueType = 1;  -- 1 = School, 2 = Power Type
    local extraAmount; -- Used for Drains and Leeches
    local powerType; -- Used for energizes, drains and leeches
    local environmentalType; -- Used for environmental damage
    local message; -- Used for server spell messages
    local originalEvent = event; -- Used for spell links
    local remainingPoints; --Used for absorbs with the correct flag set (like Power Word: Shield)

    --Extra data for PARTY_KILL, SPELL_INSTAKILL and UNIT_DIED
    local unconsciousOnDeath = 0;

    -- Generic disabling stuff
    if ( not sourceName or CombatLog_Object_IsA(sourceFlags, COMBATLOG_OBJECT_NONE) ) then
      sourceEnabled = false;
    end
    if ( not destName or CombatLog_Object_IsA(destFlags, COMBATLOG_OBJECT_NONE) ) then
      destEnabled = false;
    end

    local subVal = strsub(event, 1, 5)

    -- Swings
    if ( subVal == "SWING" ) then
      spellName = ACTION_SWING;
      nameIsNotSpell = true;
    end

    -- Break out the arguments into variable
    if ( event == "SWING_DAMAGE" ) then
      -- Damage standard
      amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = ...;

      -- Parse the result string
      resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

      if ( not resultStr ) then
        resultEnabled = false;
      end

      if ( overkill > 0 ) then
        amount = amount - overkill;
      end

    elseif ( event == "SWING_MISSED" ) then
      spellName = ACTION_SWING;

      -- Miss type
      missType, isOffHand, amountMissed = ...;

      -- Result String
      if( missType == "RESIST" or missType == "BLOCK" or missType == "ABSORB" ) then
        resultStr = format(_G["TEXT_MODE_A_STRING_RESULT_"..missType], amountMissed);
      else
        resultStr = _G["ACTION_SWING_MISSED_"..missType];
      end

      -- Miss Type
      if ( settings.fullText and missType ) then
        event = format("%s_%s", event, missType);
      end

      -- Disable appropriate sections
      nameIsNotSpell = true;
      valueEnabled = false;
      resultEnabled = true;

    elseif ( subVal == "SPELL" ) then -- Spell standard arguments
      spellId, spellName, spellSchool = ...;

      if ( event == "SPELL_DAMAGE" or event == "SPELL_BUILDING_DAMAGE") then
        -- Damage standard
        amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = select(4, ...);

        -- Parse the result string
        resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

        if ( not resultStr ) then
          resultEnabled = false
        end

        if ( overkill > 0 ) then
          amount = amount - overkill;
        end
      elseif ( event == "SPELL_MISSED" ) then
        -- Miss type
        missType,  isOffHand, amountMissed = select(4, ...);

        resultEnabled = true;
        -- Result String
        if( missType == "RESIST" or missType == "BLOCK" or missType == "ABSORB" ) then
          if ( amountMissed ~= 0 ) then
            resultStr = format(_G["TEXT_MODE_A_STRING_RESULT_"..missType], amountMissed);
          else
            resultEnabled = false;
          end
        else
          resultStr = _G["ACTION_SWING_MISSED_"..missType];
        end

        -- Miss Event
        if ( missType ) then
          event = format("%s_%s", event, missType);
        end

        -- Disable appropriate sections
        valueEnabled = false;
      elseif ( event == "SPELL_HEAL" or event == "SPELL_BUILDING_HEAL") then
        -- Did the heal crit?
        amount, overhealing, absorbed, critical = select(4, ...);

        -- Parse the result string
        resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

        if ( not resultStr ) then
          resultEnabled = false
        end

        -- Temporary Spell School Hack
        school = spellSchool;

        -- Disable appropriate sections
        valueEnabled = true;
        valueTypeEnabled = true;

        amount = amount - overhealing;
      elseif ( event == "SPELL_ENERGIZE" ) then
        -- Set value type to be a power type
        valueType = 2;

        -- Did the heal crit?
        amount, powerType = select(4, ...);

        -- Parse the result string
        resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

        if ( not resultStr ) then
          resultEnabled = false
        end

        -- Disable appropriate sections
        valueEnabled = true;
        valueTypeEnabled = true;
      elseif ( strsub(event, 1, 14) == "SPELL_PERIODIC" ) then

        if ( event == "SPELL_PERIODIC_MISSED" ) then
          -- Miss type
          missType, isOffHand, amountMissed = select(4, ...);

          -- Result String
          if ( missType == "ABSORB" ) then
            resultStr = CombatLog_String_DamageResultString( resisted, blocked, amountMissed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );
          else
            resultStr = _G["ACTION_SPELL_PERIODIC_MISSED_"..missType];
          end

          -- Miss Event
          if ( settings.fullText and missType ) then
            event = format("%s_%s", event, missType);
          end

          -- Disable appropriate sections
          valueEnabled = false;
          resultEnabled = true;
        elseif ( event == "SPELL_PERIODIC_DAMAGE" ) then
          -- Damage standard
          amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = select(4, ...);

          -- Parse the result string
          resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

          -- Disable appropriate sections
          if ( not resultStr ) then
            resultEnabled = false
          end

          if ( overkill > 0 ) then
            amount = amount - overkill;
          end
        elseif ( event == "SPELL_PERIODIC_HEAL" ) then
          -- Did the heal crit?
          amount, overhealing, absorbed, critical = select(4, ...);

          -- Parse the result string
          resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

          if ( not resultStr ) then
            resultEnabled = false
          end

          -- Temporary Spell School Hack
          school = spellSchool;

          -- Disable appropriate sections
          valueEnabled = true;
          valueTypeEnabled = true;

          amount = amount - overhealing;
        elseif ( event == "SPELL_PERIODIC_DRAIN" ) then
          -- Special attacks
          amount, powerType, extraAmount = select(4, ...);

          -- Set value type to be a power type
          valueType = 2;

          -- Result String
          --resultStr = _G[textModeString .. "RESULT"];
          --resultStr = gsub(resultStr,"$resultString", _G["ACTION_"..event.."_RESULT"]);

          -- Disable appropriate sections
          if ( not resultStr ) then
            resultEnabled = false
          end
          valueEnabled = true;
        elseif ( event == "SPELL_PERIODIC_LEECH" ) then
          -- Special attacks
          amount, powerType, extraAmount = select(4, ...);

          -- Set value type to be a power type
          valueType = 2;

          -- Result String
          resultStr = format(_G["ACTION_SPELL_PERIODIC_LEECH_RESULT"], nil, nil, nil, nil, nil, nil, nil, CombatLog_String_PowerType(powerType), nil, extraAmount) --"($extraAmount $powerType Gained)"

          -- Disable appropriate sections
          if ( not resultStr ) then
            resultEnabled = false
          end
          valueEnabled = true;
        elseif ( event == "SPELL_PERIODIC_ENERGIZE" ) then
          -- Set value type to be a power type
          valueType = 2;

          -- Did the heal crit?
          amount, powerType = select(4, ...);

          -- Parse the result string
          --resultStr = _G[textModeString .. "RESULT"];
          --resultStr = gsub(resultStr,"$resultString", _G["ACTION_"..event.."_RESULT"]);
          resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

          if ( not resultStr ) then
            resultEnabled = false
          end

          -- Disable appropriate sections
          valueEnabled = true;
          valueTypeEnabled = true;
        end
      elseif ( event == "SPELL_CAST_START" ) then -- Spellcast
        if ( not destName ) then
          destEnabled = false;
        end
        if ( not sourceName ) then
          sourceName = COMBATLOG_UNKNOWN_UNIT;
          sourceEnabled = true;
          falseSource = true;
        end

        -- Disable appropriate types
        resultEnabled = false;
        valueEnabled = false;
      elseif ( event == "SPELL_CAST_SUCCESS" ) then
        if ( not destName ) then
          destEnabled = false;
        end
        if ( not sourceName ) then
          sourceName = COMBATLOG_UNKNOWN_UNIT;
          sourceEnabled = true;
          falseSource = true;
        end

        -- Disable appropriate types
        resultEnabled = false;
        valueEnabled = false;
      elseif ( event == "SPELL_CAST_FAILED" ) then
        if ( not destName ) then
          destEnabled = false;
        end
        -- Miss reason
        missType = select(4, ...);

        -- Result String
        resultStr = format("(%s)", missType);
        --resultStr = gsub(_G[textModeString .. "RESULT"],"$resultString", missType);

        -- Disable appropriate sections
        valueEnabled = false;
        destEnabled = false;

        if ( not resultStr ) then
          resultEnabled = false;
        end
      elseif ( event == "SPELL_DRAIN" ) then -- Special Spell effects
        -- Special attacks
        amount, powerType, extraAmount = select(4, ...);

        -- Set value type to be a power type
        valueType = 2;

        -- Disable appropriate sections
        if ( not resultStr ) then
          resultEnabled = false;
        end
        valueEnabled = true;
      elseif ( event == "SPELL_LEECH" ) then
        -- Special attacks
        amount, powerType, extraAmount = select(4, ...);

        -- Set value type to be a power type
        valueType = 2;

        -- Result String
        resultStr = format(_G["ACTION_SPELL_LEECH_RESULT"], nil, nil, nil, nil, nil, nil, nil, CombatLog_String_PowerType(powerType), nil, extraAmount)

        -- Disable appropriate sections
        if ( not resultStr ) then
          resultEnabled = false;
        end
        valueEnabled = true;
      elseif ( event == "SPELL_INTERRUPT" ) then
        -- Spell interrupted
        extraSpellId, extraSpellName, extraSpellSchool = select(4, ...);

        -- Replace the value token with a spell token
        if ( extraSpellId ) then
          extraSpellEnabled = true;
        end

        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = false;
        valueTypeEnabled = false;
      elseif ( event == "SPELL_EXTRA_ATTACKS" ) then
        -- Special attacks
        amount = select(4, ...);

        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = true;
        valueTypeEnabled = false;
      elseif ( event == "SPELL_SUMMON" ) then
        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = false;
      elseif ( event == "SPELL_RESURRECT" ) then
        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = false;
      elseif ( event == "SPELL_CREATE" ) then
        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = false;
      elseif ( event == "SPELL_INSTAKILL" ) then
        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = false;

        unconsciousOnDeath = select(5, ...);
      elseif ( event == "SPELL_DURABILITY_DAMAGE" ) then
        itemId, itemName = select(4, ...);

        -- Disable appropriate sections
        valueIsItem = true;
        resultEnabled = false;
        valueEnabled = true;
      elseif ( event == "SPELL_DURABILITY_DAMAGE_ALL" ) then
        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = false;
      elseif ( event == "SPELL_DISPEL_FAILED" ) then
        -- Extra Spell standard
        extraSpellId, extraSpellName, extraSpellSchool = select(4, ...);

        -- Replace the value token with a spell token
        if ( extraSpellId ) then
          extraSpellEnabled = true;
        end

        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = false;
      elseif ( event == "SPELL_DISPEL" or event == "SPELL_STOLEN" ) then
        -- Extra Spell standard, Aura standard
        extraSpellId, extraSpellName, extraSpellSchool, auraType = select(4, ...);

        -- Event Type
        event = format("%s_%s", event, auraType);

        -- Replace the value token with a spell token
        if ( extraSpellId ) then
          extraSpellEnabled = true;
          valueEnabled = true;
        else
          valueEnabled = false;
        end

        -- Disable appropriate sections
        resultEnabled = false;
      elseif ( event == "SPELL_AURA_BROKEN" or event == "SPELL_AURA_BROKEN_SPELL") then

        -- Extra Spell standard, Aura standard
        if(event == "SPELL_AURA_BROKEN") then
          auraType = select(4, ...);
        else
          extraSpellId, extraSpellName, extraSpellSchool, auraType = select(4, ...);
        end

        -- Abort if buff/debuff is not set to true
        if ( hideBuffs and auraType == AURA_TYPE_BUFF ) then
          return;
        elseif ( hideDebuffs and auraType == AURA_TYPE_DEBUFF ) then
          return;
        end

        -- Event Type
        event = format("%s_%s", event, auraType);

        -- Replace the value token with a spell token
        if ( extraSpellId ) then
          extraSpellEnabled = true;
          valueEnabled = true;
        else
          forceDestPossessive = true;
          valueEnabled = false;
        end

        resultEnabled = false;
      elseif ( event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REMOVED" or event == "SPELL_AURA_REFRESH") then -- Aura Events
        -- Aura standard
        auraType, remainingPoints = select(4, ...);

        -- Abort if buff/debuff is not set to true
        if ( hideBuffs and auraType == AURA_TYPE_BUFF ) then
          return;
        elseif ( hideDebuffs and auraType == AURA_TYPE_DEBUFF ) then
          return;
        end

        formatString = TEXT_MODE_A_STRING_1;

        -- Event Type
        event = format("%s_%s", event, auraType);

        if ( remainingPoints and settings.fullText ) then
          withPoints = true;
        end

        resultEnabled = false;
        valueEnabled = false;
      elseif ( event == "SPELL_AURA_APPLIED_DOSE" or event == "SPELL_AURA_REMOVED_DOSE" ) then
        -- Aura standard
        auraType, amount = select(4, ...);

        -- Abort if buff/debuff is not set to true
        if ( hideBuffs and auraType == AURA_TYPE_BUFF ) then
          return;
        elseif ( hideDebuffs and auraType == AURA_TYPE_DEBUFF ) then
          return;
        end

        -- Event Type
        event = format("%s_%s", event, auraType);

        -- Disable appropriate sections
        resultEnabled = false;
        valueEnabled = true;
        valueTypeEnabled = false;

      end
    elseif ( subVal == "RANGE" ) then
      --spellName = ACTION_RANGED;
      --nameIsNotSpell = true;

      -- Shots are spells, technically
      spellId, spellName, spellSchool = ...;
      if ( event == "RANGE_DAMAGE" ) then
        -- Damage standard
        amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = select(4, ...);

        -- Parse the result string
        resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize);

        if ( not resultStr ) then
          resultEnabled = false
        end

        -- Disable appropriate sections
        nameIsNotSpell = true;

        if ( overkill > 0 ) then
          amount = amount - overkill;
        end
      elseif ( event == "RANGE_MISSED" ) then
        spellName = ACTION_RANGED;

        -- Miss type
        missType, isOffHand, amountMissed = select(4,...);

        -- Result String
        if( missType == "RESIST" or missType == "BLOCK" or missType == "ABSORB" ) then
          resultStr = format(_G["TEXT_MODE_A_STRING_RESULT_"..missType], amountMissed);
        else
          resultStr = _G["ACTION_RANGE_MISSED_"..missType];
        end

        -- Miss Type
        if ( settings.fullText and missType ) then
          event = format("%s_%s", event, missType);
        end

        -- Disable appropriate sections
        nameIsNotSpell = true;
        valueEnabled = false;
        resultEnabled = true;
      end
    elseif ( event == "DAMAGE_SHIELD" ) then -- Damage Shields
      -- Spell standard, Damage standard
      spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing = ...;

      -- Parse the result string
      resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

      -- Disable appropriate sections
      if ( not resultStr ) then
        resultEnabled = false
      end

      if ( overkill > 0 ) then
        amount = amount - overkill;
      end
    elseif ( event == "DAMAGE_SHIELD_MISSED" ) then
      -- Spell standard, Miss type
      spellId, spellName, spellSchool, missType = ...;

      -- Result String
      resultStr = _G["ACTION_DAMAGE_SHIELD_MISSED_"..missType];

      -- Miss Event
      if ( settings.fullText and missType ) then
        event = format("%s_%s", event, missType);
      end

      -- Disable appropriate sections
      valueEnabled = false;
      if ( not resultStr ) then
        resultEnabled = false;
      end
    elseif ( event == "PARTY_KILL" ) then -- Unique Events
      -- Disable appropriate sections
      resultEnabled = false;
      valueEnabled = false;

      unconsciousOnDeath = select(5, ...);
    elseif ( event == "ENCHANT_APPLIED" ) then
      -- Get the enchant name, item id and item name
      spellName, itemId, itemName = ...;
      nameIsNotSpell = true;

      -- Disable appropriate sections
      valueIsItem = true;
      resultEnabled = false;
      forceDestPossessive = true;
    elseif ( event == "ENCHANT_REMOVED" ) then
      -- Get the enchant name, item id and item name
      spellName, itemId, itemName = ...;
      nameIsNotSpell = true;

      -- Disable appropriate sections
      valueIsItem = true;
      resultEnabled = false;
      sourceEnabled = false;
      forceDestPossessive = true;
    elseif ( event == "UNIT_DIED" or event == "UNIT_DESTROYED" or event == "UNIT_DISSIPATES" ) then
      -- Swap Source with Dest
      sourceName = destName;
      sourceGUID = destGUID;
      sourceFlags = destFlags;

      -- Disable appropriate sections
      resultEnabled = false;
      sourceEnabled = true;
      destEnabled = false;
      valueEnabled = false;

    elseif ( event == "ENVIRONMENTAL_DAMAGE" ) then
      --Environmental Type, Damage standard
      environmentalType, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing = ...
      environmentalType = string.upper(environmentalType);

      -- Miss Event
      spellName = _G["ACTION_ENVIRONMENTAL_DAMAGE_"..environmentalType];
      spellSchool = school;
      nameIsNotSpell = true;

      -- Parse the result string
      resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

      -- Environmental Event
      if ( settings.fullText and environmentalType ) then
        event = "ENVIRONMENTAL_DAMAGE_"..environmentalType;
      end

      if ( not resultStr ) then
        resultEnabled = false;
      end

      if ( overkill > 0 ) then
        amount = amount - overkill;
      end
    elseif ( event == "DAMAGE_SPLIT" ) then
      -- Spell Standard Arguments, Damage standard
      spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing = ...;

      -- Parse the result string
      resultStr = CombatLog_String_DamageResultString( resisted, blocked, absorbed, critical, glancing, crushing, overhealing, textMode, spellId, overkill, overEnergize );

      if ( not resultStr ) then
        resultEnabled = false
      end

      if ( overkill > 0 ) then
        amount = amount - overkill;
      end
    elseif ( event == "UNIT_LOYALTY" ) then
      local gained = ...
      if ( gained == 1 ) then
        resultStr = _G["PET_LOYALTY_GAIN"];
      else
        resultStr = _G["PET_LOYALTY_LOSS"];
      end
      formatString = "%6$s";
    end

    -- Throw away all of the assembled strings and just grab a premade one
    if ( settings.fullText ) then
      local formatStringEvent;
      if (withPoints) then
        formatStringEvent = format("ACTION_%s_WITH_POINTS_FULL_TEXT", event);
      else
        formatStringEvent = format("ACTION_%s_FULL_TEXT", event);
      end

      -- Get the base string
      if ( _G[formatStringEvent] ) then
        formatString = _G[formatStringEvent];
      end

      -- Set any special cases
      if ( not sourceEnabled ) then
        formatStringEvent = formatStringEvent.."_NO_SOURCE";
      end
      if ( not destEnabled ) then
        formatStringEvent = formatStringEvent.."_NO_DEST";
      end

      if (event=="DAMAGE_SPLIT" and resultStr) then
        if (amount == 0) then
          formatStringEvent = "ACTION_DAMAGE_SPLIT_ABSORBED_FULL_TEXT";
        else
          formatStringEvent = "ACTION_DAMAGE_SPLIT_RESULT_FULL_TEXT";
        end
      end

      -- Get the special cased string
      if ( _G[formatStringEvent] ) then
        formatString = _G[formatStringEvent];
      end

      sourceEnabled = true;
      destEnabled = true;
      valueEnabled = true;
    end

    -- Actor name construction.
    --
    local sourceNameStr = "";
    local destNameStr = "";
    local sourceIcon = "";
    local destIcon = "";
    local spellNameStr = spellName;
    local extraSpellNameStr = extraSpellName;
    local itemNameStr = itemName;
    local actionEvent = "ACTION_"..event;

    --This is to get PARTY_KILL COMBAT_LOG_EVENTs on UnconsciousOnDeath units to display properly without new CombatLog events.
    if ( event == "PARTY_KILL" ) then
      if ( unconsciousOnDeath == 1 ) then
        actionEvent = "ACTION_PARTY_KILL_UNCONSCIOUS";

        if ( settings.fullText ) then
          formatString = _G["ACTION_PARTY_KILL_UNCONSCIOUS_FULL_TEXT"];
        end
      end
    end

    --This is to get SPELL_INSTAKILL COMBAT_LOG_EVENTs on UnconsciousOnDeath units to display properly without new CombatLog events.
    if ( event == "SPELL_INSTAKILL" ) then
      if ( unconsciousOnDeath == 1 ) then
        actionEvent = "ACTION_SPELL_INSTAKILL_UNCONSCIOUS";

        if ( settings.fullText ) then
          if ( not sourceEnabled ) then
            formatString = _G["ACTION_SPELL_INSTAKILL_UNCONSCIOUS_FULL_TEXT_NO_SOURCE"];
          else
            formatString = _G["ACTION_SPELL_INSTAKILL_UNCONSCIOUS_FULL_TEXT"];
          end
        end
      end
    end

    --This is to get the UNIT_DIED COMBAT_LOG_EVENTs for UnconsciousOnDeath units to display properly without new CombatLog events.
    if ( event == "UNIT_DIED" ) then
      if ( unconsciousOnDeath == 1 ) then
        actionEvent = "ACTION_UNIT_BECCOMES_UNCONSCIOUS";

        if ( settings.fullText ) then
          formatString = _G["ACTION_UNIT_BECOMES_UNCONSCIOUS_FULL_TEXT"];
        end
      end
    end

    local actionStr = _G[actionEvent];
    local timestampStr = timestamp;
    local powerTypeString = "";

    -- If this ever succeeds, the event string is missing.
    --
    if ( not actionStr ) then
      actionStr = event;
    end

    -- Initialize the strings now
    sourceNameStr, destNameStr = sourceName, destName;

    -- Special changes for localization when not in full text mode
    if ( not settings.fullText and COMBAT_LOG_UNIT_YOU_ENABLED == "1" ) then
      -- Replace your name with "You";
      if ( sourceName and CombatLog_Object_IsA(sourceFlags, COMBATLOG_FILTER_MINE) ) then
          sourceNameStr = UNIT_YOU_SOURCE;
      end
      if ( destName and CombatLog_Object_IsA(destFlags, COMBATLOG_FILTER_MINE) ) then
          destNameStr = UNIT_YOU_DEST;
      end
      -- Apply the possessive form to the source
      if ( sourceName and spellName and _G[actionEvent.."_POSSESSIVE"] == "1" ) then
        if ( sourceName and CombatLog_Object_IsA(sourceFlags, COMBATLOG_FILTER_MINE) ) then
          sourceNameStr = UNIT_YOU_SOURCE_POSSESSIVE;
        end
      end
      -- Apply the possessive form to the source
      if ( destName and ( extraSpellName or itemName ) ) then
        if ( destName and CombatLog_Object_IsA(destFlags, COMBATLOG_FILTER_MINE) ) then
          destNameStr = UNIT_YOU_DEST_POSSESSIVE;
        end
      end

    -- If its full text mode
    else
      -- Apply the possessive form to the source
      if ( sourceName and spellName and _G[actionEvent.."_POSSESSIVE"] == "1" ) then
        sourceNameStr = format(TEXT_MODE_A_STRING_POSSESSIVE, sourceNameStr);
      end

      -- Apply the possessive form to the dest if the dest has a spell
      if ( ( extraSpellName or forceDestPossessive ) and destName ) then
        destNameStr = format(TEXT_MODE_A_STRING_POSSESSIVE, destNameStr);
      end
    end

    -- Unit Icons
    if ( settings.unitIcons ) then
      if ( sourceName ) then
        sourceIcon = CombatLog_String_GetIcon(sourceRaidFlags, "source");
      end
      if ( destName ) then
        destIcon = CombatLog_String_GetIcon(destRaidFlags, "dest");
      end
    end

    -- Get the source color
    if ( sourceName ) then
      sourceColor = CombatLog_Color_ColorStringByUnitType( sourceFlags );
    end

    -- Get the dest color
    if ( destName ) then
      destColor = CombatLog_Color_ColorStringByUnitType( destFlags );
    end

    -- Whole line coloring
    if ( settings.lineColoring ) then
      if ( settings.lineColorPriority == 3 or ( not sourceName and not destName) ) then
        lineColor = CombatLog_Color_ColorArrayByEventType( event, filterSettings );
      else
        if ( ( settings.lineColorPriority == 1 and sourceName ) or not destName ) then
          lineColor = CombatLog_Color_ColorArrayByUnitType( sourceFlags, filterSettings );
        elseif ( ( settings.lineColorPriority == 2 and destName ) ) then
          lineColor = CombatLog_Color_ColorArrayByUnitType( destFlags, filterSettings );
        else
          lineColor = CombatLog_Color_ColorArrayByUnitType( sourceFlags, filterSettings );
        end
      end
    end

    -- Power Type
    if ( powerType ) then
      powerTypeString =  CombatLog_String_PowerType(powerType);
    end

    -- Only replace if there's an amount
    if ( amount ) then
      local amountColor;

      -- Color amount numbers
      if ( settings.amountColoring ) then
        -- To make white swings white
        if ( settings.noMeleeSwingColoring and school == SCHOOL_MASK_PHYSICAL and not spellId )  then
          -- Do nothing
        elseif ( settings.amountActorColoring ) then
          if ( sourceName ) then
            amountColor = CombatLog_Color_ColorArrayByUnitType( sourceFlags, filterSettings );
          elseif ( destName ) then
            amountColor = CombatLog_Color_ColorArrayByUnitType( destFlags, filterSettings );
          end
        elseif ( settings.amountSchoolColoring ) then
          amountColor = CombatLog_Color_ColorArrayBySchool(school, filterSettings);
        else
          amountColor = filterSettings.colors.defaults.damage;
        end

      end
      -- Highlighting
      if ( settings.amountHighlighting ) then
        local colorArray;
        if ( not amountColor ) then
          colorArray = lineColor;
        else
          colorArray = amountColor;
        end
        amountColor  = CombatLog_Color_HighlightColorArray (colorArray);
      end

      if ( amountColor ) then
        amountColor = CombatLog_Color_FloatToText(amountColor);
        amount = format("|c%s%s|r", amountColor, amount);
      end

      schoolString = CombatLog_String_SchoolString(school);
      local schoolNameColor = nil;
      -- Color school names
      if ( settings.schoolNameColoring ) then
        if ( settings.noMeleeSwingColoring and school == SCHOOL_MASK_PHYSICAL and not spellId )  then
        elseif ( settings.schoolNameActorColoring ) then
            if ( sourceName ) then
              schoolNameColor = CombatLog_Color_ColorArrayByUnitType( sourceFlags, filterSettings );
            elseif ( destName ) then
              schoolNameColor = CombatLog_Color_ColorArrayByUnitType( destFlags, filterSettings );
            end
        else
          schoolNameColor = CombatLog_Color_ColorArrayBySchool( school, filterSettings );
        end
      end
      -- Highlighting
      if ( settings.schoolNameHighlighting ) then
        local colorArray;
        if ( not schoolNameColor ) then
          colorArray = lineColor;
        else
          colorArray = schoolNameColor;
        end
        schoolNameColor  = CombatLog_Color_HighlightColorArray (colorArray);
      end
      if ( schoolNameColor ) then
        schoolNameColor = CombatLog_Color_FloatToText(schoolNameColor);
        schoolString = format("|c%s%s|r", schoolNameColor, schoolString);
      end

    end

    -- Color source names
    if ( settings.unitColoring ) then
      if ( sourceName and settings.sourceColoring ) then
        sourceNameStr = format("|c%s%s|r", sourceColor, sourceNameStr);
      end
      if ( destName and settings.destColoring ) then
        destNameStr = format("|c%s%s|r", destColor, destNameStr);
      end
    end

    -- If there's an action (always)
    if ( actionStr ) then
      local actionColor = nil;
      -- Color ability names
      if ( settings.actionColoring ) then

        if ( settings.actionActorColoring ) then
          if ( sourceName ) then
            actionColor = CombatLog_Color_ColorArrayByUnitType( sourceFlags, filterSettings );
          elseif ( destName ) then
            actionColor = CombatLog_Color_ColorArrayByUnitType( destFlags, filterSettings );
          end
        elseif ( settings.actionSchoolColoring and spellSchool ) then
          actionColor = CombatLog_Color_ColorArrayBySchool( spellSchool, filterSettings );
        else
          actionColor = CombatLog_Color_ColorArrayByEventType(event);
        end
      -- Special option to only color "Miss" if there's no damage
      elseif ( settings.missColoring ) then

        if ( event ~= "SWING_DAMAGE" and
          event ~= "RANGE_DAMAGE" and
          event ~= "SPELL_DAMAGE" and
          event ~= "SPELL_PERIODIC_DAMAGE" ) then

          if ( settings.actionActorColoring ) then
            actionColor = CombatLog_Color_ColorArrayByUnitType( sourceFlags, filterSettings );
          elseif ( settings.actionSchoolColoring ) then
            actionColor = CombatLog_Color_ColorArrayBySchool( spellSchool, filterSettings );
          else
            actionColor = CombatLog_Color_ColorArrayByEventType(event);
          end

        end
      end

      -- Highlighting
      if ( settings.actionHighlighting ) then
        local colorArray;
        if ( not actionColor ) then
          colorArray = lineColor;
        else
          colorArray = actionColor;
        end
        actionColor = CombatLog_Color_HighlightColorArray (colorArray);
      end

      if ( actionColor ) then
        actionColor = CombatLog_Color_FloatToText(actionColor);
        actionStr = format("|c%s%s|r", actionColor, actionStr);
      end

    end
    -- If there's a spell name
    if ( spellName ) then
      local spellAbilityColor = nil;
      -- Color ability names
      if ( settings.abilityColoring ) then
        if ( settings.abilityActorColoring ) then
          spellAbilityColor = CombatLog_Color_ColorArrayByUnitType( sourceFlags, filterSettings );
        elseif ( settings.abilitySchoolColoring ) then
          spellAbilityColor = CombatLog_Color_ColorArrayBySchool( spellSchool, filterSettings );
        else
          if ( spellSchool ) then
            spellAbilityColor = filterSettings.colors.defaults.spell;
          end
        end
      end

      -- Highlight this color
      if ( settings.abilityHighlighting ) then
        local colorArray;
        if ( not spellAbilityColor ) then
          colorArray = lineColor;
        else
          colorArray = spellAbilityColor;
        end
        spellAbilityColor  = CombatLog_Color_HighlightColorArray (colorArray);
      end
      if ( spellAbilityColor ) then
        spellAbilityColor = CombatLog_Color_FloatToText(spellAbilityColor);
        if ( itemId ) then
          spellNameStr = spellName;
        else
          spellNameStr = format("|c%s%s|r", spellAbilityColor, spellName);
        end
      end
    end

    -- If there's a spell name
    if ( extraSpellName ) then
      local extraAbilityColor = nil;
      -- Color ability names
      if ( settings.abilityColoring ) then

        if ( settings.abilitySchoolColoring ) then
          extraAbilityColor = CombatLog_Color_ColorArrayBySchool( extraSpellSchool, filterSettings );
        else
          if ( extraSpellSchool ) then
            extraAbilityColor = CombatLog_Color_ColorArrayBySchool( SCHOOL_MASK_HOLY, filterSettings );
          else
            extraAbilityColor = CombatLog_Color_ColorArrayBySchool( nil, filterSettings );
          end
        end
      end
      -- Highlight this color
      if ( settings.abilityHighlighting ) then
        local colorArray;
        if ( not extraAbilityColor ) then
          colorArray = lineColor;
        else
          colorArray = extraAbilityColor;
        end
        extraAbilityColor  = CombatLog_Color_HighlightColorArray (colorArray);
      end
      if ( extraAbilityColor ) then
        extraAbilityColor = CombatLog_Color_FloatToText(extraAbilityColor);
        extraSpellNameStr = format("|c%s%s|r", extraAbilityColor, extraSpellName);
      end
    end

    -- Whole line highlighting
    if ( settings.lineHighlighting ) then
      if ( filterSettings.colors.highlightedEvents[event] ) then
        lineColor = CombatLog_Color_HighlightColorArray (lineColor);
      end
    end

    -- Build braces
    if ( settings.braces ) then
      -- Unit specific braces
      if ( settings.unitBraces ) then
        if ( sourceName and settings.sourceBraces ) then
          sourceNameStr = format(TEXT_MODE_A_STRING_BRACE_UNIT, braceColor, sourceNameStr, braceColor);
        end

        if ( destName and settings.destBraces ) then
          destNameStr = format(TEXT_MODE_A_STRING_BRACE_UNIT, braceColor, destNameStr, braceColor);
        end
      end

      -- Spell name braces
      if ( spellName and settings.spellBraces ) then
        if ( not itemId ) then
          spellNameStr = format(TEXT_MODE_A_STRING_BRACE_SPELL, braceColor, spellNameStr, braceColor);
        end
      end
      if ( extraSpellName and settings.spellBraces ) then
        extraSpellNameStr = format(TEXT_MODE_A_STRING_BRACE_SPELL, braceColor, extraSpellNameStr, braceColor);
      end

      -- Build item braces
      if ( itemName and settings.itemBraces ) then
        itemNameStr = format(TEXT_MODE_A_STRING_BRACE_ITEM, braceColor, itemNameStr, braceColor);
      end
    end

    local sourceString = "";
    local spellString = "";
    local actionString = "";
    local destString = "";
    local valueString = "";
    local resultString = "";
    local remainingPointsString = "";

    if ( sourceEnabled and sourceName and falseSource ) then
      sourceString = sourceName;
    elseif ( sourceEnabled and sourceName ) then
      sourceString = format(TEXT_MODE_A_STRING_SOURCE_UNIT, sourceIcon, sourceGUID, sourceName, sourceNameStr);
    end

    if ( spellName ) then
      if ( nameIsNotSpell ) then
        spellString = format(TEXT_MODE_A_STRING_ACTION, originalEvent, spellNameStr);
      else
        spellString = format(TEXT_MODE_A_STRING_SPELL, spellId, 0, originalEvent, spellNameStr, spellId);
      end
    end

    if ( actionString ) then
      actionString = format(TEXT_MODE_A_STRING_ACTION, originalEvent, actionStr);
    end

    if ( destEnabled and destName ) then
      destString = format(TEXT_MODE_A_STRING_DEST_UNIT, destIcon, destGUID, destName, destNameStr);
    end

    if ( valueEnabled ) then
      if ( extraSpellEnabled and extraSpellNameStr ) then
        if ( extraNameIsNotSpell ) then
          valueString = extraSpellNameStr;
        else
          valueString = format(TEXT_MODE_A_STRING_SPELL_EXTRA, extraSpellId, 0, originalEvent, extraSpellNameStr, spellId);
        end
      elseif ( valueIsItem and itemNameStr ) then
        valueString = format(TEXT_MODE_A_STRING_ITEM, itemId, itemNameStr);
      elseif ( amount ) then
        if ( valueTypeEnabled ) then
          if ( valueType == 1 and schoolString ) then
            valueString = format(TEXT_MODE_A_STRING_VALUE_SCHOOL, amount, schoolString);
          elseif ( valueType == 2 and powerTypeString ) then
            valueString = format(TEXT_MODE_A_STRING_VALUE_TYPE, amount, powerTypeString);
          end
        end
        if ( valueString == "" ) then
          valueString = amount;
        end
      end
    end

    if ( resultEnabled and resultStr ) then
      resultString = resultStr;
    end

    if ( not schoolString ) then
      schoolString = "";
    end
    if ( not powerTypeString ) then
      powerTypeString = "";
    end
    if ( not amount ) then
      amount = "";
    end

    if ( not extraAmount) then
      extraAmount = "";
    end

    if ( sourceString == "" and not hideCaster ) then
      sourceString = UNKNOWN;
    end

    if ( destEnabled and destString == "" ) then
      destString = UNKNOWN;
    end

    if ( remainingPoints ) then
      remainingPointsString = format(TEXT_MODE_A_STRING_REMAINING_POINTS, remainingPoints);
    end

    local finalString = format(formatString, sourceString, spellString, actionString, destString, valueString, resultString, schoolString, powerTypeString, amount, extraAmount, remainingPointsString);

    finalString = gsub(finalString, " [ ]+", " " ); -- extra white spaces
    finalString = gsub(finalString, " ([.,])", "%1" ); -- spaces before periods or comma
    finalString = gsub(finalString, "^([ .,]+)", "" ); -- spaces, period or comma at the beginning of a line

    if ( timestampEnabled and timestamp ) then
      -- Replace the timestamp
      finalString = format(TEXT_MODE_A_STRING_TIMESTAMP, date(settings.timestampFormat, timestamp), finalString);
    end

    -- NOTE: be sure to pass back nil for the color id or the color id may override the r, g, b values for this message line
    return finalString, lineColor.r, lineColor.g, lineColor.b;
  end

  -- Process the event and add it to the combat log
  function CombatLog_AddEvent(...)
    -- Add the messages
    local text, r, g, b, a = CombatLog_OnEvent(Blizzard_CombatLog_CurrentSettings, ... );
    if ( text ) then
      COMBATLOG:AddMessage(text, r, g, b, a);
    end
  end

  --
  -- Combat Log Global Functions
  --

  --[[
  --
  --  Returns the correct {} code for the combat log bit
  --
  --  args:
  --  bit - a bit exactly equal to a raid target icon.
  --]]
  local function Blizzard_CombatLog_BitToBraceCode(bit)
    if ( bit == COMBATLOG_OBJECT_RAIDTARGET1 ) then
      return "{"..strlower(RAID_TARGET_1).."}";
    elseif ( bit == COMBATLOG_OBJECT_RAIDTARGET2 ) then
      return "{"..strlower(RAID_TARGET_2).."}";
    elseif ( bit == COMBATLOG_OBJECT_RAIDTARGET3 ) then
      return "{"..strlower(RAID_TARGET_3).."}";
    elseif ( bit == COMBATLOG_OBJECT_RAIDTARGET4 ) then
      return "{"..strlower(RAID_TARGET_4).."}";
    elseif ( bit == COMBATLOG_OBJECT_RAIDTARGET5 ) then
      return "{"..strlower(RAID_TARGET_5).."}";
    elseif ( bit == COMBATLOG_OBJECT_RAIDTARGET6 ) then
      return "{"..strlower(RAID_TARGET_6).."}";
    elseif ( bit == COMBATLOG_OBJECT_RAIDTARGET7 ) then
      return "{"..strlower(RAID_TARGET_7).."}";
    elseif ( bit == COMBATLOG_OBJECT_RAIDTARGET8 ) then
      return "{"..strlower(RAID_TARGET_8).."}";
    end
    return "";
  end

  -- The format of the data describing context menu entries was originally written for the legacy menus
  -- but is being funneled into the updated menu system to minimize any changes.
  function CreateCombatLogContextMenu(region, tbls)
    MenuUtil.CreateContextMenu(region, function(owner, rootDescription)
      rootDescription:SetTag("MENU_COMBAT_LOG", tbls);

      for index, tbl in ipairs(tbls) do
        if tbl.divider then
          rootDescription:CreateDivider();
        else
          local button = rootDescription:CreateButton(tbl.text, tbl.func);

          -- We can invert 'disabled' here as none of it's uses were functions. If functions are added,
          -- a function wrapper can be passed instead that inverts the return value of the added function.
          button:SetEnabled(not tbl.disabled);
        end
      end
    end);
  end

  -- CombatLogQuickButtonTemplate
  local function CreateQuickButton(name)
    local button = CreateFrame("Button", name, CombatLogQuickButtonFrame)
    button:SetHeight(20)
    button:SetNormalFontObject(GameFontDisable)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetScript("OnClick", function(self)
      Blizzard_CombatLog_QuickButton_OnClick(self:GetID())
      PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end)
    button:SetScript("OnEnter", function(self)
      if self.tooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, 1)
        GameTooltip:Show()
      end
    end)
    button:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    return button
  end

  function Blizzard_CombatLog_Update_QuickButtons()
    local baseName = "CombatLogQuickButtonFrame";
    local buttonName, button, textWidth;
    local buttonIndex = 1;
    -- subtract the width of the dropdown button
    local maxWidth = COMBATLOG:GetUnscaledWidth() - 31;

    local additionalFilterButton = CombatLogQuickButtonFrame.AdditionalFilterButton;

    local totalWidth = 0;
    local padding = 13;
    local showMoreQuickButtons = true;
    local hasOffBar = false;
    for index, filter in ipairs(Blizzard_CombatLog_Filters.filters) do
      buttonName = baseName.."Button"..buttonIndex;
      button = _G[buttonName];
      if ( ShowQuickButton(filter) and showMoreQuickButtons ) then
        if ( not button ) then
          button = CreateQuickButton(buttonName);
        end
        button:SetText(filter.name);
        textWidth = button:GetTextWidth();
        totalWidth = totalWidth + textWidth + padding;
        if ( totalWidth <= maxWidth ) then
          button:SetWidth(textWidth+padding);
          button:SetID(index);
          button:Show();
          button.tooltip = filter.tooltip;
          if ( buttonIndex > 1 ) then
            button:SetPoint("LEFT", _G[baseName.."Button"..buttonIndex-1], "RIGHT", 3, 0);
          else
            button:SetPoint("LEFT", CombatLogQuickButtonFrame, "LEFT", 3, 0);
          end
          if ( Blizzard_CombatLog_Filters.currentFilter == index and (Blizzard_CombatLog_CurrentSettings and not Blizzard_CombatLog_CurrentSettings.isTemp) ) then
            button:LockHighlight();
          else
            button:UnlockHighlight();
          end
          filter.onQuickBar = true;
        else
          -- Don't show anymore buttons if the maxwidth has been exceeded
          showMoreQuickButtons = false;
          hasOffBar = true;
          button:Hide();
          filter.onQuickBar = false;
        end
        buttonIndex = buttonIndex + 1;
      else
        filter.onQuickBar = false;
        if ( button ) then
          button:Hide();
        end
      end
    end

    -- Hide remaining buttons
    repeat
      button = _G[baseName.."Button"..buttonIndex];
      if ( button ) then
        button:Hide();
      end
      buttonIndex = buttonIndex+1;
    until not button;

    additionalFilterButton:SetShown(hasOffBar);
  end

  function Blizzard_CombatLog_QuickButton_OnClick(id)
    Blizzard_CombatLog_Filters.currentFilter = id;
    Blizzard_CombatLog_CurrentSettings = Blizzard_CombatLog_Filters.filters[Blizzard_CombatLog_Filters.currentFilter];
    Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings);
    if ( Blizzard_CombatLog_CurrentSettings.settings.showHistory ) then
      Blizzard_CombatLog_Refilter();
    end
    Blizzard_CombatLog_Update_QuickButtons();
  end

  function ShowQuickButton(filter)
    if ( filter.hasQuickButton ) then
      if ( IsInRaid() ) then
        return filter.quickButtonDisplay.raid;
      elseif ( IsInGroup() ) then
        return filter.quickButtonDisplay.party;
      else
        return filter.quickButtonDisplay.solo;
      end
    else
      return false;
    end;
  end

  -- Right-click menus and chat links for the log's unit, icon, spell and
  -- action links. Unit, icon and action links have no tooltip, so they stop
  -- here; a plain click on a spell link shows the spell.
  local HookSetItemRef = SetItemRef
  _G.SetItemRef = function(link, text, button)
    if strsub(link, 1, 4) == "unit" then
      local _, guid, name = strsplit(":", link)
      if IsModifiedClick("CHATLINK") then
        InsertLink(name)
      elseif button == "RightButton" then
        CreateCombatLogContextMenu(COMBATLOG, Blizzard_CombatLog_CreateUnitMenu(name, guid))
      end
      return
    elseif strsub(link, 1, 4) == "icon" then
      local _, iconBit = strsplit(":", link)
      iconBit = tonumber(iconBit)
      if button == "RightButton" then
        CreateCombatLogContextMenu(COMBATLOG, Blizzard_CombatLog_CreateUnitMenu(Blizzard_CombatLog_BitToBraceCode(iconBit), nil, iconBit))
      elseif IsModifiedClick("CHATLINK") then
        InsertLink(Blizzard_CombatLog_BitToBraceCode(iconBit))
      end
      return
    elseif strsub(link, 1, 6) == "action" then
      local _, event = strsplit(":", link)
      if button == "RightButton" then
        CreateCombatLogContextMenu(COMBATLOG, Blizzard_CombatLog_CreateActionMenu(event))
      end
      return
    elseif strsub(link, 1, 5) == "spell" then
      local _, spellId, _, event = strsplit(":", link)
      spellId = tonumber(spellId)
      if IsModifiedClick("CHATLINK") then
        if spellId > 0 then
          InsertLink(GetSpellLink(spellId))
        end
        return
      elseif button == "RightButton" and event then
        CreateCombatLogContextMenu(COMBATLOG, Blizzard_CombatLog_CreateSpellMenu(text, spellId, event))
        return
      end
    end
    HookSetItemRef(link, text, button)
  end

  -- Turtle's ChatFrame_OnHyperlinkShow handles spell:<id>:<a>:<b> links
  -- itself, never reaching SetItemRef, and the log's spell:<id>:0:<subevent>
  -- links have that shape. Elsewhere the original forwards them there anyway.
  local HookChatFrame_OnHyperlinkShow = ChatFrame_OnHyperlinkShow
  _G.ChatFrame_OnHyperlinkShow = function(link, text, button)
    if strfind(link, "^spell:%d+:%d+:%u[%u_]*$") then
      SetItemRef(link, text, button)
      return
    end
    return HookChatFrame_OnHyperlinkShow(link, text, button)
  end

  -- CombatConfig_CreateCombatFilter: adds a copy of filter, or a new one from
  -- the template, and returns its index
  local function CreateCombatFilter(name, filter)
    local newFilter = CopyTable(filter or DEFAULT_COMBATLOG_FILTER_TEMPLATE)
    if not name or name == "" then
      name = format(DEFAULT_COMBATLOG_FILTER_NAME, #Blizzard_CombatLog_Filters.filters)
    end
    newFilter.name = name
    newFilter.tooltip = ""
    -- the unit menu's filter is temporary; its saved copy is not
    newFilter.isTemp = nil
    tinsert(Blizzard_CombatLog_Filters.filters, newFilter)
    Blizzard_CombatLog_Update_QuickButtons()
    return #Blizzard_CombatLog_Filters.filters
  end

  -- COPY_COMBAT_FILTER and CREATE_COMBAT_FILTER: asks for a name, then
  -- passes the new filter's index to done
  function NewFilter(filter, done)
    CreateQuestionDialog(ENTER_FILTER_NAME, { ACCEPT, function()
      local index = CreateCombatFilter(this:GetParent().input:GetText(), filter)
      if done then done(index) end
    end }, { CANCEL }, true)
  end

  -- a fresh copy, so the defaults stay as they are for a reset
  _G.pfUI_combatlog = _G.pfUI_combatlog or CopyTable(Blizzard_CombatLog_Filter_Defaults)
  Blizzard_CombatLog_Filters = _G.pfUI_combatlog
  Blizzard_CombatLog_CurrentSettings = Blizzard_CombatLog_Filters.filters[Blizzard_CombatLog_Filters.currentFilter]

  -- The bar above the log: a button per quick filter, a menu for the filters
  -- that don't fit, and the refilter's progress.
  CombatLogQuickButtonFrame = CreateFrame("Frame", "CombatLogQuickButtonFrame", COMBATLOG)
  CombatLogQuickButtonFrame:SetHeight(24)
  CombatLogQuickButtonFrame:SetPoint("BOTTOMLEFT", COMBATLOG, "TOPLEFT")
  CombatLogQuickButtonFrame:SetPoint("BOTTOMRIGHT", COMBATLOG, "TOPRIGHT")
  CombatLogQuickButtonFrame:SetScript("OnShow", Blizzard_CombatLog_Update_QuickButtons)
  CombatLogQuickButtonFrame:SetScript("OnSizeChanged", Blizzard_CombatLog_Update_QuickButtons)
  -- chat.lua makes room for the bar above the docked log, and passes the
  -- log's lines through unparsed (it sets pfCombatLog again on each refresh)
  COMBATLOG.CombatLogQuickButtonFrame = CombatLogQuickButtonFrame
  COMBATLOG.pfCombatLog = true

  -- Blizzard's AdjustCombatLogHeight. FCF_DockUpdate pins every docked frame
  -- but the first to the top of DEFAULT_CHAT_FRAME, which puts the bar over
  -- the tabs, so the log's top goes back down by the bar's height each time.
  -- A tab sits on its frame's Background, so the log's Background reaches up
  -- over the bar to keep the tab in line with the others.
  local barHeight = CombatLogQuickButtonFrame:GetHeight()
  local background = _G[COMBATLOG:GetName().."Background"]
  background:SetPoint("TOPLEFT", COMBATLOG, "TOPLEFT", -2, 3 + barHeight)
  background:SetPoint("TOPRIGHT", COMBATLOG, "TOPRIGHT", 2, 3 + barHeight)

  hooksecurefunc("FCF_DockUpdate", function()
    if COMBATLOG.isDocked and DOCKED_CHAT_FRAMES[1] ~= COMBATLOG then
      COMBATLOG:SetPoint("TOPLEFT", DEFAULT_CHAT_FRAME, "TOPLEFT", 0, -barHeight)
    end
  end)

  CombatLogQuickButtonFrameProgressBar = CreateFrame("StatusBar", nil, CombatLogQuickButtonFrame)
  CombatLogQuickButtonFrameProgressBar:SetHeight(4)
  CombatLogQuickButtonFrameProgressBar:SetPoint("TOPLEFT", CombatLogQuickButtonFrame, "TOPLEFT", 0, 2)
  CombatLogQuickButtonFrameProgressBar:SetPoint("TOPRIGHT", CombatLogQuickButtonFrame, "TOPRIGHT", 0, 2)
  CombatLogQuickButtonFrameProgressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  CombatLogQuickButtonFrameProgressBar:SetStatusBarColor(0, 1, .3)
  CombatLogQuickButtonFrameProgressBar:Hide()

  local filterButton = CreateFrame("Button", nil, CombatLogQuickButtonFrame)
  filterButton:SetWidth(28)
  filterButton:SetHeight(28)
  filterButton:SetPoint("TOPRIGHT", CombatLogQuickButtonFrame, "TOPRIGHT")
  filterButton:SetHitRectInsets(6, 6, 7, 7)
  filterButton:SetNormalTexture("Interface\\MainMenuBar\\UI-MainMenu-ScrollDownButton-Up")
  filterButton:SetPushedTexture("Interface\\MainMenuBar\\UI-MainMenu-ScrollDownButton-Down")
  filterButton:SetHighlightTexture("Interface\\MainMenuBar\\UI-MainMenu-ScrollDownButton-Highlight", "ADD")
  filterButton:SetScript("OnMouseDown", function(self)
    CreateCombatLogContextMenu(self, Blizzard_CombatLog_CreateFilterMenu())
  end)
  filterButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ADDITIONAL_FILTERS, 1, 1, 1)
    GameTooltip:Show()
  end)
  filterButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  CombatLogQuickButtonFrame.AdditionalFilterButton = filterButton

  -- The 1.12 text log's events keep firing for whatever else reads them, but
  -- stop reaching this frame. Its message groups stay saved, so the text log
  -- comes back when this module is disabled. Groups with no COMBAT_LOG_EVENT
  -- counterpart keep showing here.
  local textgroups = {
    COMBAT_ERROR = true, COMBAT_MISC_INFO = true, COMBAT_XP_GAIN = true, COMBAT_HONOR_GAIN = true,
    COMBAT_FACTION_CHANGE = true, SPELL_TRADESKILLS = true, SPELL_ITEM_ENCHANTMENTS = true,
  }
  local replaced = {}
  for group, events in pairs(ChatTypeGroup) do
    if not textgroups[group] and (strfind(group, "^COMBAT_") or strfind(group, "^SPELL_")) then
      for _, event in pairs(events) do
        replaced[event] = true
      end
    end
  end

  local OnEvent = COMBATLOG:GetScript("OnEvent")
  COMBATLOG:SetScript("OnEvent", function(self, event, ...)
    if replaced[event] then return end
    return OnEvent(self, event, ...)
  end)

  -- What the settings window (modules/combatlog_config.lua) works on. It is
  -- built the first time it opens.
  local log = {
    GetFilters = function() return Blizzard_CombatLog_Filters end,
    -- replaces the saved filters with the defaults and shows the first
    Reset = function()
      _G.pfUI_combatlog = CopyTable(Blizzard_CombatLog_Filter_Defaults)
      Blizzard_CombatLog_Filters = _G.pfUI_combatlog
      Blizzard_CombatLog_QuickButton_OnClick(1)
    end,
    NewFilter = NewFilter,
    SelectFilter = Blizzard_CombatLog_QuickButton_OnClick,
    UpdateQuickButtons = Blizzard_CombatLog_Update_QuickButtons,
    FormatEvent = CombatLog_OnEvent,
  }

  local config
  local function ShowConfig()
    config = config or pfUI.combatlog.CreateConfig(log)
    config:Show()
  end

  -- "Settings" in the Combat Log tab's right-click menu, as on later clients.
  -- Each tab's menu keeps its own initialize function.
  local dropdown = _G[COMBATLOG:GetName().."TabDropDown"]
  local initialize = dropdown.initialize
  dropdown.initialize = function()
    initialize()
    if UIDROPDOWNMENU_MENU_LEVEL == 1 then
      local info = UIDropDownMenu_CreateInfo()
      info.text = SETTINGS
      info.func = ShowConfig
      info.notCheckable = 1
      UIDropDownMenu_AddButton(info)
    end
  end

  -- Unlike Blizzard's, the log keeps taking events while another tab is
  -- selected, so switching back to it shows what happened meanwhile instead
  -- of rebuilding it from the kept entries (which only reach back 300s).
  CombatLogUpdateFrame:SetScript("OnEvent", function(self, event)
    if event == "COMBAT_LOG_EVENT" then
      CombatLog_AddEvent(CombatLogGetCurrentEventInfo())
    else
      -- quick buttons show by solo, party or raid
      Blizzard_CombatLog_Update_QuickButtons()
    end
  end)
  CombatLogUpdateFrame:RegisterEvent("COMBAT_LOG_EVENT")
  CombatLogUpdateFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
  CombatLogUpdateFrame:RegisterEvent("RAID_ROSTER_UPDATE")

  -- apply the saved filter and refill the log from the kept entries, which
  -- outlast a /reload
  Blizzard_CombatLog_QuickButton_OnClick(Blizzard_CombatLog_Filters.currentFilter)
end)
