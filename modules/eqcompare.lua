pfUI:RegisterModule("eqcompare", function ()
  local sides = { "Left", "Right" }

  local function AddHeader(tooltip)
    local name = tooltip:GetName()

    -- shift all entries one line down
    for i=tooltip:NumLines(), 1, -1 do
      for _, side in pairs(sides) do
        local current = _G[name.."Text"..side..i]
        local below = _G[name.."Text"..side..i+1]

        if current and current:IsShown() then
          local text = current:GetText()
          local r, g, b = current:GetTextColor()

          if text and text ~= "" then
            if tooltip:NumLines() < i+1 then
              -- add new line if required
              tooltip:AddLine(text, r, g, b, true)
            else
              -- update existing lines
              below:SetText(text)
              below:SetTextColor(r, g, b)
              below:Show()

              -- hide processed line
              current:Hide()
            end
          end
        end
      end
    end

    -- add label to first line
    _G[name.."TextLeft1"]:SetTextColor(.5, .5, .5, 1)
    _G[name.."TextLeft1"]:SetText(CURRENTLY_EQUIPPED)
    _G[name.."TextLeft1"]:Show()

    -- update tooltip sizes
    tooltip:Show()
  end

  -- Numeric slotTable keyed by Enum.InventoryType (from
  -- C_Item.GetItemInventoryTypeByID). Pair-slot types (finger / trinket /
  -- one-hand weapon) list both destinations so both comparison tooltips
  -- can be shown at once.
  local slotTable = {
    [1]  = { "HeadSlot" },
    [2]  = { "NeckSlot" },
    [3]  = { "ShoulderSlot" },
    [4]  = { "ShirtSlot" },
    [5]  = { "ChestSlot" },
    [6]  = { "WaistSlot" },
    [7]  = { "LegsSlot" },
    [8]  = { "FeetSlot" },
    [9]  = { "WristSlot" },
    [10] = { "HandsSlot" },
    [11] = { "Finger0Slot", "Finger1Slot" },
    [12] = { "Trinket0Slot", "Trinket1Slot" },
    [13] = { "MainHandSlot", "SecondaryHandSlot" },  -- one-hand weapon
    [14] = { "SecondaryHandSlot" },                  -- shield
    [15] = { "RangedSlot" },                         -- ranged (bow)
    [16] = { "BackSlot" },
    [17] = { "MainHandSlot" },                       -- two-hand weapon
    [19] = { "TabardSlot" },
    [20] = { "ChestSlot" },                          -- robe
    [21] = { "MainHandSlot" },
    [22] = { "SecondaryHandSlot" },
    [23] = { "SecondaryHandSlot" },                  -- holdable (off-hand)
    [24] = { "AmmoSlot" },
    [25] = { "RangedSlot" },                         -- thrown
    [26] = { "RangedSlot" },                         -- ranged-right (wand/gun/crossbow)
    [28] = { "RangedSlot" },                         -- relic
  }

  local BASE_STAT_KEYS = {
    "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "ITEM_MOD_BLOCK_VALUE",
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT",
    "ITEM_MOD_STAMINA_SHORT",  "ITEM_MOD_INTELLECT_SHORT",
    "ITEM_MOD_SPIRIT_SHORT",   "ITEM_MOD_MANA_SHORT",
    "ITEM_MOD_HEALTH_SHORT",
    "RESISTANCE0_NAME", "RESISTANCE1_NAME", "RESISTANCE2_NAME",
    "RESISTANCE3_NAME", "RESISTANCE4_NAME", "RESISTANCE5_NAME",
    "RESISTANCE6_NAME",
  }
  local EXTENDED_STAT_KEYS = {
    "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    "ITEM_MOD_CRIT_SPELL_RATING",
    "ITEM_MOD_CRIT_MELEE_RATING",  "ITEM_MOD_CRIT_RANGED_RATING",
    "ITEM_MOD_HIT_MELEE_RATING",   "ITEM_MOD_HIT_RANGED_RATING",
    "ITEM_MOD_HIT_SPELL_RATING",
    "ITEM_MOD_MANA_REGENERATION",  "ITEM_MOD_DEFENSE_SKILL_RATING",
    "ITEM_MOD_DODGE_RATING", "ITEM_MOD_PARRY_RATING",
    "ITEM_MOD_BLOCK_RATING",
  }
  local STAT_LABELS = {}
  local BASE_STAT_LABEL_TO_KEY = {}  -- reverse map for inline base-stat match
  do
    local function noun(fmt)
      return fmt and (string.gsub(string.gsub(fmt, "^%%c?%%d ", ""), "^%s+", "")) or nil
    end
    local baseFmt = {
      ITEM_MOD_STRENGTH_SHORT  = "ITEM_MOD_STRENGTH",
      ITEM_MOD_AGILITY_SHORT   = "ITEM_MOD_AGILITY",
      ITEM_MOD_STAMINA_SHORT   = "ITEM_MOD_STAMINA",
      ITEM_MOD_INTELLECT_SHORT = "ITEM_MOD_INTELLECT",
      ITEM_MOD_SPIRIT_SHORT    = "ITEM_MOD_SPIRIT",
      ITEM_MOD_MANA_SHORT      = "ITEM_MOD_MANA",
      ITEM_MOD_HEALTH_SHORT    = "ITEM_MOD_HEALTH",
    }
    for shortKey, fmtKey in pairs(baseFmt) do
      STAT_LABELS[shortKey] = _G[shortKey] or noun(_G[fmtKey]) or shortKey
    end
    for i = 0, 6 do
      STAT_LABELS["RESISTANCE"..i.."_NAME"] = _G["RESISTANCE"..i.."_NAME"]
    end
    STAT_LABELS.ITEM_MOD_ATTACK_POWER_SHORT        = _G.ITEM_MOD_ATTACK_POWER_SHORT or _G.ATTACK_POWER_TOOLTIP or "Attack Power"
    STAT_LABELS.ITEM_MOD_RANGED_ATTACK_POWER_SHORT = _G.ITEM_MOD_RANGED_ATTACK_POWER_SHORT or _G.RANGED_ATTACK_POWER or "Ranged Attack Power"
    STAT_LABELS.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT   = _G.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT or "Spell Damage"
    STAT_LABELS.ITEM_MOD_SPELL_HEALING_DONE_SHORT  = _G.ITEM_MOD_SPELL_HEALING_DONE_SHORT or "Spell Healing"
    STAT_LABELS.ITEM_MOD_CRIT_MELEE_RATING         = _G.ITEM_MOD_CRIT_MELEE_RATING or "Melee Crit %"
    STAT_LABELS.ITEM_MOD_CRIT_RANGED_RATING        = _G.ITEM_MOD_CRIT_RANGED_RATING or "Ranged Crit %"
    STAT_LABELS.ITEM_MOD_HIT_MELEE_RATING          = _G.ITEM_MOD_HIT_MELEE_RATING or "Melee Hit %"
    STAT_LABELS.ITEM_MOD_HIT_RANGED_RATING         = _G.ITEM_MOD_HIT_RANGED_RATING or "Ranged Hit %"
    STAT_LABELS.ITEM_MOD_HIT_SPELL_RATING          = _G.ITEM_MOD_HIT_SPELL_RATING or "Spell Hit %"
    STAT_LABELS.ITEM_MOD_MANA_REGENERATION         = _G.ITEM_MOD_MANA_REGENERATION or "Mana Regen"
    STAT_LABELS.ITEM_MOD_DEFENSE_SKILL_RATING      = _G.ITEM_MOD_DEFENSE_SKILL_RATING or "Defense"
    STAT_LABELS.ITEM_MOD_DAMAGE_PER_SECOND_SHORT   = _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or "DPS"
    STAT_LABELS.ITEM_MOD_CRIT_SPELL_RATING         = _G.ITEM_MOD_CRIT_SPELL_RATING or "Spell Crit %"
    STAT_LABELS.ITEM_MOD_DODGE_RATING              = _G.ITEM_MOD_DODGE_RATING or "Dodge Rating"
    STAT_LABELS.ITEM_MOD_PARRY_RATING              = _G.ITEM_MOD_PARRY_RATING or "Parry Rating"
    STAT_LABELS.ITEM_MOD_BLOCK_RATING              = _G.ITEM_MOD_BLOCK_RATING or "Block Rating"
    STAT_LABELS.ITEM_MOD_BLOCK_VALUE               = _G.ITEM_MOD_BLOCK_VALUE or "Block Value"

    -- Reverse map for base-stat inline matching (label → key)
    for _, key in ipairs(BASE_STAT_KEYS) do
      local label = STAT_LABELS[key]
      if label then BASE_STAT_LABEL_TO_KEY[label] = key end
    end
    if _G.BLOCK then
      BASE_STAT_LABEL_TO_KEY[_G.BLOCK] = "ITEM_MOD_BLOCK_VALUE"
    end
    if _G.DPS_TEMPLATE then
      local n = string.gsub(_G.DPS_TEMPLATE, "%%.-f%s*", "")
      n = string.gsub(n, "^[%s%(]+", "")
      n = string.gsub(n, "[%s%)]+$", "")
      if n ~= "" then BASE_STAT_LABEL_TO_KEY[n] = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" end
    end
  end

  local function AnnotateBaseStatsInline(tooltip, delta)
    for _, region in ipairs({tooltip:GetRegions()}) do
      if region and region.GetObjectType and region:GetObjectType() == "FontString" then
        local text = region:GetText()
        if text and text ~= ""
           and not strfind(text, "|cff88ff88", 1, true)
           and not strfind(text, "|cffff8888", 1, true) then
          -- Match "value noun" tooltip lines. Base stats look like
          -- "+5 Strength" / "5 Fire Resistance" / "20 Block"; DPS looks
          -- like "(84.5 damage per second)". Same shape once we accept
          -- an optional leading "(", an optional "+", and decimals.
          local _, endIdx = strfind(text, "^%(?%+?[%d%.]+%s+")
          if endIdx then
            local rest = string.sub(text, endIdx + 1)
            rest = gsub(rest, "[%s%)]+$", "")
            local key = BASE_STAT_LABEL_TO_KEY[rest]
            local v = key and delta[key]
            if v and v ~= 0 then
              local shown = (key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT") and round(v, 1) or v
              local color = shown > 0 and "|cff88ff88" or "|cffff8888"
              local sign = shown > 0 and "+" or ""
              region:SetText(text .. " " .. color .. "(" .. sign .. shown .. ")|r")
            end
          end
        end
      end
    end
  end

  local function AppendSummaryBlock(tooltip, delta, keys)
    local first = true
    for _, key in ipairs(keys) do
      local v = delta[key]
      if v and v ~= 0 then
        if first then
          tooltip:AddLine(" ")
          tooltip:AddLine(T["Compared to equipped:"] or "Compared to equipped:", 0.6, 0.6, 0.6)
          first = false
        end
        local shown = (key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT") and round(v, 1) or v
        local color = shown > 0 and "|cff88ff88" or "|cffff8888"
        local sign = shown > 0 and "+" or ""
        tooltip:AddDoubleLine(STAT_LABELS[key] or key, color .. sign .. shown .. "|r")
      end
    end
  end

  pfUI.eqcompare = {}
  pfUI.eqcompare.tooltip = GameTooltip

  local function AnnotateTooltip(tooltip)
    if not IsShiftKeyDown() and C.tooltip.compare.showalways ~= "1" then return end

    local _, newLink, itemID = tooltip:GetItem()
    if not itemID then return end
    local invType = C_Item.GetItemInventoryTypeByID(itemID)
    local slots = invType and slotTable[invType]
    if not slots then return end

    local _, border = GetBorderSize()

    -- determine screen part
    local ltrigger = GetScreenWidth() / 2
    local x = GetCursorPosition()
    x = x / UIParent:GetEffectiveScale()
    if x > ltrigger then ltrigger = nil end

    -- first equipped comparison tooltip
    local slotID = GetInventorySlotInfo(slots[1])
    ShoppingTooltip1:SetOwner(tooltip, "ANCHOR_NONE")
    ShoppingTooltip1:ClearAllPoints()
    if ltrigger then
      ShoppingTooltip1:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMRIGHT", 0, 0)
    else
      ShoppingTooltip1:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMLEFT", -border*2-1, 0)
    end
    ShoppingTooltip1:SetInventoryItem("player", slotID)
    ShoppingTooltip1:Show()
    AddHeader(ShoppingTooltip1)

    -- second tooltip for pair slots (finger / trinket / 1H weapon)
    if slots[2] then
      local slotID_other = GetInventorySlotInfo(slots[2])
      ShoppingTooltip2:SetOwner(tooltip, "ANCHOR_NONE")
      ShoppingTooltip2:ClearAllPoints()
      if ltrigger then
        ShoppingTooltip2:SetPoint("BOTTOMLEFT", ShoppingTooltip1, "BOTTOMRIGHT", 0, 0)
      else
        ShoppingTooltip2:SetPoint("BOTTOMRIGHT", ShoppingTooltip1, "BOTTOMLEFT", -border*2-1, 0)
      end
      ShoppingTooltip2:SetInventoryItem("player", slotID_other)
      ShoppingTooltip2:Show()
      AddHeader(ShoppingTooltip2)
    end

    if C.tooltip.compare.basestats == "1" then
      local equippedLink = GetInventoryItemLink("player", slotID)
      if newLink and equippedLink then
        local delta = C_Item.GetItemStatDelta(equippedLink, newLink)
        if delta then
          if C.tooltip.compare.extendedstats == "1" then
            local keys = {}
            for _, k in ipairs(BASE_STAT_KEYS)     do table.insert(keys, k) end
            for _, k in ipairs(EXTENDED_STAT_KEYS) do table.insert(keys, k) end
            AppendSummaryBlock(tooltip, delta, keys)
          else
            AnnotateBaseStatsInline(tooltip, delta)
          end
        end
      end
    end
  end
  pfUI.eqcompare.AnnotateTooltip = AnnotateTooltip

  GameTooltip.HookScript = GameTooltip.HookScript or HookScript
  pfUI.eqcompare.GameTooltipShow = function() AnnotateTooltip(this) end

  GameTooltip:HookScript("OnShow", pfUI.eqcompare.GameTooltipShow)
end)
