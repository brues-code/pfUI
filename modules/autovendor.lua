pfUI:RegisterModule("autovendor", "vanilla:tbc", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()
  local processed = {}

  local function RepairItems()
    local cost, possible = GetRepairAllCost()
    if cost > 0 and possible then
      DEFAULT_CHAT_FRAME:AddMessage(T["Your items have been repaired for"] .. " " .. CreateGoldString(cost))
      RepairAllItems()
    end
  end

  local function HasGreyItems()
    for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
        local quality = C_Item.GetItemQuality(ItemLocation:CreateFromBagAndSlot(bag,slot))
        if quality and quality == LE_ITEM_QUALITY_POOR then return true end
      end
    end
  end

  local function GetNextGreyItem()
    for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
        local quality = C_Item.GetItemQuality(ItemLocation:CreateFromBagAndSlot(bag,slot))
        if quality and quality == LE_ITEM_QUALITY_POOR and not processed[bag.."x"..slot] then
          processed[bag.."x"..slot] = true
          return bag, slot
        end
      end
    end
  end

  local autovendor = CreateFrame("Frame", "pfMoneyUpdate", nil)
  autovendor:Hide()

  autovendor:SetScript("OnShow", function()
    processed = {}
    this.count = 0
    this.gold = GetMoney()
  end)

  autovendor:SetScript("OnUpdate", function()
    -- throttle to to one item per .1 second
    if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + .1 end

    -- scan for the next grey item
    local bag, slot = GetNextGreyItem()
    if not bag or not slot then
      this:Hide()
      return
    end

    -- double check to only sell grey
    local quality = C_Item.GetItemQuality(ItemLocation:CreateFromBagAndSlot(bag,slot))
    if quality ~= LE_ITEM_QUALITY_POOR then
      return
    end

    -- get value
    local id = C_Container.GetContainerItemID(bag, slot)
    if pfSellData[id] then
      local _, _, sell, buy = strfind(pfSellData[id], "(.*),(.*)")
      this.count = this.count + 1
    end

    -- abort if the merchant window disappeared
    if not this.merchant then return end

    -- clear cursor and sell the item
    ClearCursor()
    UseContainerItem(bag, slot)
  end)

  autovendor:SetScript("OnHide", function()
    if this.count > 0 then
      local gold = this.gold
      QueueFunction(function()
        local income = GetMoney() - gold
        DEFAULT_CHAT_FRAME:AddMessage(T["Your vendor trash has been sold and you earned"] .. " " .. CreateGoldString(income))
      end)
    end
  end)

  autovendor:RegisterEvent("MERCHANT_SHOW")
  autovendor:RegisterEvent("MERCHANT_CLOSED")
  autovendor:RegisterEvent("MERCHANT_UPDATE")
  autovendor:SetScript("OnEvent", function()
    autovendor.button:Update()

    if event == "MERCHANT_CLOSED" then
      autovendor.merchant = nil
      autovendor:Hide()
    elseif event == "MERCHANT_SHOW" then
      autovendor.merchant = true
      if C["global"]["autorepair"] == "1" then
        RepairItems()
      end

      if C["global"]["autosell"] == "1" then
        if C_MerchantFrame.GetNumJunkItems() > 0 then
          C_MerchantFrame.SellAllJunkItems()
        else
          autovendor:Show()
        end
        autovendor.button:Hide()
      else
        autovendor.button:Show()
      end

      MerchantRepairText:SetText("")
      if MerchantRepairItemButton:IsShown() then
        autovendor.button:ClearAllPoints()
        autovendor.button:SetPoint("RIGHT", MerchantRepairItemButton, "LEFT", -4*bpad, 0)
      else
        autovendor.button:ClearAllPoints()
        autovendor.button:SetPoint("RIGHT", MerchantBuyBackItemItemButton, "LEFT", -14, 0)
      end
    end
  end)

  -- Setup Autosell button
  autovendor.button = CreateFrame("Button", "pfMerchantAutoVendorButton", MerchantFrame)
  autovendor.button:SetWidth(36)
  autovendor.button:SetHeight(36)
  autovendor.button.icon = autovendor.button:CreateTexture("ARTWORK")
  autovendor.button.icon:SetTexture("Interface\\Icons\\Spell_Shadow_SacrificialShield")
  autovendor.button:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(T["Sell Grey Items"])
    GameTooltip:Show()
  end)

  autovendor.button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  SkinButton(autovendor.button, nil, nil, nil, autovendor.button.icon)

  autovendor.button:SetScript("OnClick", function()
    autovendor:Show()
  end)

  autovendor.button.Update = function()
    if not autovendor:IsVisible() then
      if HasGreyItems() then
        autovendor.button:Enable()
        autovendor.button.icon:SetDesaturated(false)
      else
        autovendor.button:Disable()
        autovendor.button.icon:SetDesaturated(true)
      end
    else
      autovendor.button:Disable()
      autovendor.button.icon:SetDesaturated(true)
    end
  end

  -- Hook MerchantFrame_Update
  if not pfMerchantFrame_Update then
    local pfMerchantFrame_Update = MerchantFrame_Update
    function _G.MerchantFrame_Update()
      if MerchantFrame.selectedTab == 1 and C["global"]["autosell"] ~= "1" then
        autovendor.button:Show()
      else
        autovendor.button:Hide()
      end
      pfMerchantFrame_Update()
    end
  end
end)
