pfUI:RegisterModule("itemcount", function ()
  -- Walk the 19 equipment slots looking for this item. C_Item.GetItemCount
  -- bundles "bags + equipped" with no breakdown; we need to subtract the
  -- equipped count to get a bags-only number.
  local function CountEquipped(id)
    local count = 0
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
      if GetInventoryItemID("player", slot) == id then
        count = count + 1
      end
    end
    return count
  end

  local function AddCounts(frame, id)
    if not id or id == HEARTHSTONE_ITEM_ID or C_Item.GetItemUniquenessByID(id) == 1 then return end

    local total = C_Item.GetItemCount(id, true)  -- bags + bank + equipped
    if total < 1 then return end

    local bagsAndEquipped = C_Item.GetItemCount(id, false)
    local equipped = CountEquipped(id)
    local bags = bagsAndEquipped - equipped
    if bags < 0 then bags = 0 end
    local bank = total - bagsAndEquipped
    if bank < 0 then bank = 0 end

    frame:AddLine(" ")
    if bags > 0     then frame:AddDoubleLine("Bags:",     bags,     1, 1, 1, 1, 1, 1) end
    if bank > 0     then frame:AddDoubleLine("Bank:",     bank,     1, 1, 1, 1, 1, 1) end
    if equipped > 0 then frame:AddDoubleLine("Equipped:", equipped, 1, 1, 1, 1, 1, 1) end
    frame:AddDoubleLine("Total:", total, 1, 1, 1, 1, 1, 1)
    frame:Show()
  end

  pfUI.itemcount = CreateFrame("Frame", "pfItemCountTooltip", GameTooltip)
  pfUI.itemcount:SetScript("OnShow", function()
    if GameTooltip:HasItem() then
      local _, _, id = GameTooltip:GetItem()
      if id then AddCounts(GameTooltip, id) end
    end
  end)

  pfUI.hooksecurefunc("SetItemRef", function()
    if ItemRefTooltip:HasItem() then
      local _, _, id = ItemRefTooltip:GetItem()
      if id then AddCounts(ItemRefTooltip, id) end
    end
  end)
end)
