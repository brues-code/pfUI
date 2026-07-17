pfUI:RegisterModule("newitem", function ()
  if not pfUI.bag then return end
  if C.appearance.bags.newitem ~= "1" then return end

  pfUI.newitem = {}

  local color = CreateColor(strsplit(",", C.appearance.bags.newitem_color))

  function pfUI.newitem:UpdateSlot(bag, slot)
    if bag < 0 or bag > 4 then return end
    if not pfUI.bags[bag] then return end
    if not pfUI.bags[bag].slots[slot] then return end

    local frame = pfUI.bags[bag].slots[slot].frame

    if not frame.newitem then
      local glow = frame:CreateTexture(nil, "OVERLAY")
      glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
      glow:SetBlendMode("ADD")
      glow:SetVertexColor(color:GetRGBA())
      glow:SetPoint("CENTER", frame, "CENTER")
      glow:Hide()
      frame.newitem = glow

      frame:HookScript("OnEnter", function()
        C_NewItems.RemoveNewItem(bag, slot)
      end)
    end

    local w = frame:GetWidth()
    if w > 0 then frame.newitem:SetSize(w * 1.8, w * 1.8) end

    frame.newitem:SetShown(frame.hasItem and C_NewItems.IsNewItem(bag, slot))
  end

  -- The new-item set can change without any slot's contents changing (an item
  -- acknowledged, pruned when it leaves the bags, or ClearAll) -- re-evaluate
  -- every decorated slot when that happens.
  function pfUI.newitem:RefreshAll()
    for bag in pairs(pfUI.bags) do
      local slots = pfUI.bags[bag] and pfUI.bags[bag].slots
      if slots then
        for slot in pairs(slots) do
          pfUI.newitem:UpdateSlot(bag, slot)
        end
      end
    end
  end

  -- per-slot: pfUI re-runs UpdateSlot whenever a slot's contents change.
  hooksecurefunc(pfUI.bag, "UpdateSlot", function(self, bag, slot)
    pfUI.newitem:UpdateSlot(bag, slot)
  end)

  EventRegistry:RegisterFrameEventAndCallback("BAG_NEW_ITEMS_UPDATED", function()
    pfUI.newitem:RefreshAll()
  end)

  pfUI.events:RegisterCallback("bag:closed", function(_, object)
    if object then return end
    C_NewItems.ClearAll()
  end, "newitem")
end)
