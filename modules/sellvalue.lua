pfUI:RegisterModule("sellvalue", function ()
  local function AddVendorPrices(frame, id, count)
    if not id then return end
    local sell = C_Item.GetItemSellPriceByID(id) or 0
    local buy = pfSellData[id]
    if sell == 0 and not buy then return end

    if C.tooltip.vendor.showalways == "1" or IsShiftKeyDown() then
      frame:AddLine(" ")

      if sell > 0 then
        if count > 1 then
          frame:AddDoubleLine(T["Sell"] .. ":", CreateGoldString(sell) .. "|cff555555  //  " .. CreateGoldString(sell*count), 1, 1, 1)
        else
          frame:AddDoubleLine(T["Sell"] .. ":", CreateGoldString(sell), 1, 1, 1)
        end
      end

      if buy then
        if count > 1 then
          frame:AddDoubleLine(T["Buy"] .. ":", CreateGoldString(buy) .. "|cff555555  //  " .. CreateGoldString(buy*count), 1, 1, 1)
        else
          frame:AddDoubleLine(T["Buy"] .. ":", CreateGoldString(buy), 1, 1, 1)
        end
      end
    elseif not MerchantFrame:IsShown() and sell > 0 then
        SetTooltipMoney(frame, sell * count)
    end
    frame:Show()
  end

  hooksecurefunc("SetItemRef", function()
    if IsModifierKeyDown() then return end
    if ItemRefTooltip:HasItem() then
      local _, _, id = ItemRefTooltip:GetItem()
      if id then AddVendorPrices(ItemRefTooltip, id, 1) end
    end
  end)

  local TooltipHooks = {
    SetLootRollItem = {
      id = GetLootRollItemID,
      count = function(slot)
        local _, _, count = GetLootRollItemInfo(slot)
        return count
      end
    },
    SetLootItem = {
      id = GetLootSlotItemID,
      count = function(slot)
        local _, _, count = GetLootSlotInfo(slot)
        return count
      end
    },
    SetQuestLogItem = {
      id = GetQuestLogItemID,
      count = function(type, index)
        local itemCount, _;
        if type == "choice" then
          _, _, itemCount = GetQuestLogChoiceInfo(index);
        else
          _, _, itemCount = GetQuestLogRewardInfo(index)
        end
        return itemCount
      end,
    },
    SetQuestItem = {
      id = GetQuestItemID,
      count = function(type, index)
        local _, _, count = GetQuestItemInfo(type, index);
        return count
      end,
    },
    SetHyperlink = { id = C_Item.GetItemInfoInstant },
    SetBagItem = { id = C_Container.GetContainerItemID },
    SetInboxItem = {
      id = GetInboxItemID,
      count = function(index)
        local _, _, _, count = GetInboxItem(index)
        return count
      end,
    },
    SetSendMailItem = {
      id = function()
        local _, id = GetSendMailItemLink()
        return id
      end,
    },
    SetInventoryItem = { id = GetInventoryItemID },
    SetTradeSkillItem = {
      id = function(skillIndex, reagentIndex)
        if reagentIndex then
          return GetTradeSkillReagentItemID(skillIndex, reagentIndex)
        else
          return GetTradeSkillItemID(skillIndex)
        end
      end,
      count = function(skillIndex, reagentIndex)
        if reagentIndex then
          local _, _, itemCount = GetTradeSkillReagentInfo(skillIndex, reagentIndex)
          return itemCount
        else
          return GetTradeSkillNumMade(skillIndex)
        end
      end,
    },
    SetAuctionItem = {
      id = GetAuctionItemLink,
      count = function(viewType, index)
        local _, _, count = GetAuctionItemInfo(viewType, index)
        return count
      end,
    },
    SetAuctionSellItem = { id = GetAuctionSellItemLink },
    SetTradePlayerItem = { id = GetTradePlayerItemLink },
    SetTradeTargetItem = {
      id = GetTradeTargetItemLink,
      count = function(id)
        local _, _, count = GetTradeTargetItemInfo(id)
        return count
      end,
    },
    SetMerchantItem = {
      id = GetMerchantItemID,
      count = function(index)
        local _, _, _, itemCount = GetMerchantItemInfo(index)
        return itemCount
      end
    },
    SetCraftItem = {
      id = function(recipeIndex, reagentIndex)
        return GetCraftReagentItemID(recipeIndex, reagentIndex)
      end
    },
    SetBuybackItem = { id = C_MerchantFrame.GetBuybackItemID }
  }

  -- OnTooltipSetItem fires inside every Set* call, before the hooks below run,
  -- with the GUID of the item object behind the tooltip. Items the player holds
  -- (bags, bank, equipped, buyback, trade, send-mail) have one, and their stack
  -- count comes straight from it; rows without an object (loot, merchant,
  -- auctions, quests, ...) pass nil and fall back to the setter's own count.
  local itemGUID
  GameTooltip:HookScript("OnTooltipSetItem", function()
    itemGUID = arg1
  end)

  local function StackCount(entry, arg1, arg2, arg3)
    local count = itemGUID and C_Item.GetStackCount(itemGUID) or 0
    if count > 0 then return count end
    return entry.count and entry.count(arg1, arg2, arg3) or 1
  end

  local function makeHook(entry)
    return function(tooltip, arg1, arg2, arg3)
      AddVendorPrices(tooltip, entry.id(arg1, arg2, arg3), StackCount(entry, arg1, arg2, arg3))
      itemGUID = nil
    end
  end

  local function HookTooltip(tooltip)
    for setter, entry in pairs(TooltipHooks) do
      hooksecurefunc(tooltip, setter, makeHook(entry))
    end
  end

  HookTooltip(GameTooltip)
end)
