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

  -- Base stats are annotated INLINE on their tooltip stat line. We match
  -- by label (the trailing noun after the "N " value prefix), so we need
  -- the localized noun for each ClassicAPI key. Primary stats come from
  -- vanilla's "%c%d Stat" format strings (with the noun stripped out);
  -- resistances are already plain nouns.
  local BASE_STAT_LABEL_TO_KEY = {}
  do
    local function noun(fmt)
      return fmt and (string.gsub(string.gsub(fmt, "^%%c?%%d ", ""), "^%s+", "")) or nil
    end
    local baseFmt = {
      { key = "ITEM_MOD_STRENGTH_SHORT",  fmt = "ITEM_MOD_STRENGTH" },
      { key = "ITEM_MOD_AGILITY_SHORT",   fmt = "ITEM_MOD_AGILITY" },
      { key = "ITEM_MOD_STAMINA_SHORT",   fmt = "ITEM_MOD_STAMINA" },
      { key = "ITEM_MOD_INTELLECT_SHORT", fmt = "ITEM_MOD_INTELLECT" },
      { key = "ITEM_MOD_SPIRIT_SHORT",    fmt = "ITEM_MOD_SPIRIT" },
      { key = "ITEM_MOD_MANA_SHORT",      fmt = "ITEM_MOD_MANA" },
      { key = "ITEM_MOD_HEALTH_SHORT",    fmt = "ITEM_MOD_HEALTH" },
    }
    for _, e in ipairs(baseFmt) do
      local label = _G[e.key] or noun(_G[e.fmt])
      if label then BASE_STAT_LABEL_TO_KEY[label] = e.key end
    end
    for i = 0, 6 do
      local label = _G["RESISTANCE"..i.."_NAME"]
      if label then BASE_STAT_LABEL_TO_KEY[label] = "RESISTANCE"..i.."_NAME" end
    end
  end

  -- Extended stats (attack power, crit/hit ratings, spell power, defense,
  -- DPS, mana regen) aren't emitted as their own tooltip lines by vanilla
  -- in a shape we can reliably match — they're mixed into equip-spell
  -- descriptions ("Equip: Increases your critical strike chance by 1%").
  -- Aggregate them into a Blizzard-style summary block at the bottom.
  local EXTENDED_STAT_LABELS = {
    ITEM_MOD_ATTACK_POWER_SHORT        = _G.ITEM_MOD_ATTACK_POWER_SHORT or _G.ATTACK_POWER_TOOLTIP or "Attack Power",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = _G.ITEM_MOD_RANGED_ATTACK_POWER_SHORT or _G.RANGED_ATTACK_POWER or "Ranged Attack Power",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT   = _G.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT or "Spell Damage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT  = _G.ITEM_MOD_SPELL_HEALING_DONE_SHORT or "Spell Healing",
    ITEM_MOD_CRIT_MELEE_RATING         = _G.ITEM_MOD_CRIT_MELEE_RATING or "Melee Crit %",
    ITEM_MOD_CRIT_RANGED_RATING        = _G.ITEM_MOD_CRIT_RANGED_RATING or "Ranged Crit %",
    ITEM_MOD_HIT_MELEE_RATING          = _G.ITEM_MOD_HIT_MELEE_RATING or "Melee Hit %",
    ITEM_MOD_HIT_RANGED_RATING         = _G.ITEM_MOD_HIT_RANGED_RATING or "Ranged Hit %",
    ITEM_MOD_HIT_SPELL_RATING          = _G.ITEM_MOD_HIT_SPELL_RATING or "Spell Hit %",
    ITEM_MOD_MANA_REGENERATION         = _G.ITEM_MOD_MANA_REGENERATION or "Mana Regen",
    ITEM_MOD_DEFENSE_SKILL_RATING      = _G.ITEM_MOD_DEFENSE_SKILL_RATING or "Defense",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT   = _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or "DPS",
  }
  local EXTENDED_STAT_ORDER = {
    "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
    "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    "ITEM_MOD_CRIT_MELEE_RATING",
    "ITEM_MOD_CRIT_RANGED_RATING",
    "ITEM_MOD_HIT_MELEE_RATING",
    "ITEM_MOD_HIT_RANGED_RATING",
    "ITEM_MOD_HIT_SPELL_RATING",
    "ITEM_MOD_MANA_REGENERATION",
    "ITEM_MOD_DEFENSE_SKILL_RATING",
  }

  local function AnnotateBaseStats(tooltip, delta)
    for _, region in ipairs({tooltip:GetRegions()}) do
      if region and region.GetObjectType and region:GetObjectType() == "FontString" then
        local text = region:GetText()
        if text and text ~= ""
           and not strfind(text, "|cff88ff88", 1, true)
           and not strfind(text, "|cffff8888", 1, true) then
          -- Widget text shape we care about: "+5 Strength" / "5 Fire Resistance".
          -- Match the "+N " / "N " prefix, then look up the rest verbatim.
          local _, endIdx = strfind(text, "^%+?%d+%s+")
          if endIdx then
            local rest = string.sub(text, endIdx + 1)
            rest = gsub(rest, "%s+$", "")
            local key = BASE_STAT_LABEL_TO_KEY[rest]
            local v = key and delta[key]
            if v and v ~= 0 then
              local color = v > 0 and "|cff88ff88" or "|cffff8888"
              local sign = v > 0 and "+" or ""
              region:SetText(text .. " " .. color .. "(" .. sign .. v .. ")|r")
            end
          end
        end
      end
    end
  end

  local function AppendExtendedSummary(tooltip, delta)
    local first = true
    for _, key in ipairs(EXTENDED_STAT_ORDER) do
      local v = delta[key]
      if v and v ~= 0 then
        if first then
          tooltip:AddLine(" ")
          tooltip:AddLine(T["Compared to equipped:"] or "Compared to equipped:", 0.6, 0.6, 0.6)
          first = false
        end
        -- DPS is a float derived from damage/delay in ClassicAPI; every
        -- other extended stat is an integer. Round DPS to 1 decimal so
        -- the summary shows "+4.3 DPS" instead of "+4.34302…".
        local shown = (key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT") and round(v, 1) or v
        local color = shown > 0 and "|cff88ff88" or "|cffff8888"
        local sign = shown > 0 and "+" or ""
        tooltip:AddDoubleLine(EXTENDED_STAT_LABELS[key] or key, color .. sign .. shown .. "|r")
      end
    end
    if not first then tooltip:Show() end  -- re-measure after adding lines
  end

  pfUI.eqcompare = {}
  pfUI.eqcompare.GameTooltipShow = function()
    -- use this tooltip for the next comparison
    pfUI.eqcompare.tooltip = this

    if not IsShiftKeyDown() and C.tooltip.compare.showalways ~= "1" then return end

    -- Resolve the item's slot numerically instead of scanning tooltip text
    -- for a localized INVTYPE_* label. GameTooltip:GetItem() returns
    -- (name, link, itemID); the slotTable is keyed by Enum.InventoryType.
    local _, _, itemID = this:GetItem()
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

    -- first tooltip
    local slotID = GetInventorySlotInfo(slots[1])
    ShoppingTooltip1:SetOwner(this, "ANCHOR_NONE")
    ShoppingTooltip1:ClearAllPoints()
    if ltrigger then
      ShoppingTooltip1:SetPoint("BOTTOMLEFT", this, "BOTTOMRIGHT", 0, 0)
    else
      ShoppingTooltip1:SetPoint("BOTTOMRIGHT", this, "BOTTOMLEFT", -border*2-1, 0)
    end
    ShoppingTooltip1:SetInventoryItem("player", slotID)
    ShoppingTooltip1:Show()
    AddHeader(ShoppingTooltip1)

    -- second tooltip for pair slots (finger / trinket / 1H weapon)
    if slots[2] then
      local slotID_other = GetInventorySlotInfo(slots[2])
      ShoppingTooltip2:SetOwner(this, "ANCHOR_NONE")
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

    -- Fetch the delta once; annotate base stats inline (green +/red -
    -- next to their existing tooltip line), then aggregate extended
    -- stats (attack power, crit/hit ratings, spell power, DPS, …) into
    -- a "Compared to equipped:" block at the bottom. The extended-stats
    -- summary is a sub-option of the whole comparison — if base-stat
    -- comparison is off, we're not doing comparisons at all.
    if C.tooltip.compare.basestats == "1" then
      local _, newLink = this:GetItem()
      local equippedLink = GetInventoryItemLink("player", slotID)
      if newLink and equippedLink then
        local delta = C_Item.GetItemStatDelta(equippedLink, newLink)
        if delta then
          AnnotateBaseStats(this, delta)
          if C.tooltip.compare.extendedstats == "1" then AppendExtendedSummary(this, delta) end
        end
      end
    end
    return true
  end

  -- add HookScript method if not already existing
  GameTooltip.HookScript = GameTooltip.HookScript or HookScript

  -- Add Gametooltip Hook
  GameTooltip:HookScript("OnShow", pfUI.eqcompare.GameTooltipShow)
end)
