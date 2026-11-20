pfUI:RegisterModule("newitem", function ()
  if not pfUI.bag then return end
  if C.appearance.bags.newitem ~= "1" then return end

  pfUI.newitem = {}

  local r, g, b, a = pfUI.api.GetStringColor(C.appearance.bags.newitem_color)

  function pfUI.newitem:UpdateSlot(bag, slot)
    if bag < 0 or bag > 4 then return end
    if not pfUI.bags[bag] then return end
    if not pfUI.bags[bag].slots[slot] then return end

    local frame = pfUI.bags[bag].slots[slot].frame

    if frame.hasItem and C_NewItems.IsNewItem(bag, slot) then
      if not frame.newitem then
        local glow = frame:CreateTexture(nil, "OVERLAY")
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(r, g, b, a)
        glow:SetPoint("CENTER", frame, "CENTER")
        glow:Hide()
        glow.RefreshSize = function(g)
          local w = g:GetParent():GetWidth()
          if w > 0 then g:SetSize(w * 1.8, w * 1.8) end
        end
        frame.newitem = glow

        frame:HookScript("OnEnter", function()
          C_NewItems.RemoveNewItem(bag, slot)
          glow:Hide()
        end)
      end
      frame.newitem:RefreshSize()
      frame.newitem:Show()
    elseif frame.newitem and frame.newitem:IsShown() then
      frame.newitem:Hide()
    end
  end

  -- An item can become new without its slot's contents changing (loot onto a
  -- stack it already holds) -- re-evaluate every decorated slot when one does.
  -- Clearing a flag fires no event, so the code that clears one hides the
  -- glow itself, as the stock bag button does.
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

  pfUI.events:RegisterFrameEventAndCallback("BAG_NEW_ITEMS_UPDATED", function()
    pfUI.newitem:RefreshAll()
  end)

  pfUI.events:RegisterCallback("bag:closed", function(_, object)
    if object then return end
    C_NewItems.ClearAll()
    pfUI.newitem:RefreshAll()
  end, "newitem")
end)
