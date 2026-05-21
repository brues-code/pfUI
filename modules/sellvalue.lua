pfUI:RegisterModule("sellvalue", "vanilla:tbc", function ()
  local function AddVendorPrices(frame, id, count)
    if not id then return end
    -- Sell price comes from the engine (item DBC); buy price from pfSellData
    -- (curated vendor data, since vendor purchase prices aren't a static field).
    local sell = C_Item.GetItemSellPriceByID(id) or 0
    local buy = pfSellData[id]
    if sell == 0 and not buy then return end

    if not MerchantFrame:IsShown() and sell > 0 then
      SetTooltipMoney(frame, sell * count)
    end

    if IsShiftKeyDown() or C.tooltip.vendor.showalways == "1" then
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
    end
    frame:Show()
  end

  pfUI.sellvalue = CreateFrame("Frame", "pfGameTooltip", GameTooltip)
  pfUI.sellvalue:SetScript("OnShow", function()
    if GameTooltip:HasItem() then
      local _, _, id = GameTooltip:GetItem()
      if id then
        local count = tonumber(libtooltip:GetItemCount()) or 1
        AddVendorPrices(GameTooltip, id, math.max(count, 1))
      end
    end
  end)

  hooksecurefunc("SetItemRef", function()
    if IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if ItemRefTooltip:HasItem() then
      local _, _, id = ItemRefTooltip:GetItem()
      if id then AddVendorPrices(ItemRefTooltip, id, 1) end
    end
  end)
end)
