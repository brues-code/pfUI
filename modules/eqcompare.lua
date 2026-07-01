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

  local function startsWith(str, start)
    return string.sub(str, 1, string.len(start)) == start
  end

  local function ExtractAttributes(tooltip)
    local name = tooltip:GetName()

    -- get the name/header of the last set comparison tooltip
    local comparetooltip = pfUI.eqcompare.tooltip:GetName()
    local iname = _G[comparetooltip .. "TextLeft1"] and _G[comparetooltip .. "TextLeft1"]:GetText()

    -- only run once per item
    if tooltip.pfCompLastName == iname then return end

    tooltip.pfCompData = {}
    tooltip.pfCompLastName = iname

    for i=1,30 do
      local widget = _G[name.."TextLeft"..i]
      if widget and widget:GetObjectType() == "FontString" then
        local text = widget:GetText()
        if text and not string.find(text, "-", 1, true) then
          local start = 1
          if startsWith(text, "\+") or startsWith(text, "\(") then start = 2 end

          local space = string.find(text, " ", 1, true)
          if space then
            local value = tonumber(string.sub(text, start, space-1))
            if value and text then
              -- we've found an attr
              local attr = string.sub(text, space, string.len(text))
              tooltip.pfCompData[attr] = { value = tonumber(value), widget = widget }
            end
          end
        end
      end
    end
  end

  local function CompareAttributes(data, targetData)
    if not data then return end

    for attr,v in pairs(data) do
      if targetData then
        local target = targetData[attr]
        if target then
          if v.value ~= target.value and v.widget:GetText() then
            if v.value > target.value then
              if not strfind(v.widget:GetText(), "|cff88ff88") and not strfind(v.widget:GetText(), "|cffff8888") then
                v.widget:SetText(v.widget:GetText() .. "|cff88ff88 (+" .. round(v.value - target.value, 1) .. ")")
              end
            elseif not v.widget.compSet then
              if not strfind(v.widget:GetText(), "|cff88ff88") and not strfind(v.widget:GetText(), "|cffff8888") then
                v.widget:SetText(v.widget:GetText() .. "|cffff8888 (-" .. round(target.value - v.value, 1) .. ")")
              end
            end
            target.processed = true
          else
            target.processed = true
          end
        else
          -- this attribute doesnt exist in target
          if v.widget and v.widget:GetText() then
            if not strfind(v.widget:GetText(), "|cff88ff88") and not strfind(v.widget:GetText(), "|cffff8888") then
              v.widget:SetText(v.widget:GetText() .. "|cff88ff88 (+" .. v.value .. ")")
            end
          end
        end
      end
    end

    for _,target in pairs(targetData) do
      if target and not target.processed then
        -- we are an extra value
        local text = target.widget:GetText()
        if text and not strfind(text, "|cff88ff88") and not strfind(text, "|cffff8888") then
          target.widget:SetText(text .. "|cff88ff88 (+" .. target.value .. ")")
        end
      end
    end
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
    return true
  end

  -- add HookScript method if not already existing
  GameTooltip.HookScript = GameTooltip.HookScript or HookScript
  ShoppingTooltip1.HookScript = ShoppingTooltip1.HookScript or HookScript
  ShoppingTooltip2.HookScript = ShoppingTooltip2.HookScript or HookScript

  pfUI.eqcompare.ShoppingTooltipShow = function()
    -- abort if no comparison tooltip has been set
    if not pfUI.eqcompare.tooltip then return end

    ExtractAttributes(this)
    ExtractAttributes(pfUI.eqcompare.tooltip)
    CompareAttributes(pfUI.eqcompare.tooltip.pfCompData, this.pfCompData)
  end

  -- Add Gametooltip Hooks
  GameTooltip:HookScript("OnShow", pfUI.eqcompare.GameTooltipShow)
  if C.tooltip.compare.basestats == "1" then
    ShoppingTooltip1:HookScript("OnShow", pfUI.eqcompare.ShoppingTooltipShow)
    ShoppingTooltip2:HookScript("OnShow", pfUI.eqcompare.ShoppingTooltipShow)
  end
end)
