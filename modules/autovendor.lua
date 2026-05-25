pfUI:RegisterModule("autovendor", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  local function RepairItems()
    local cost, possible = GetRepairAllCost()
    if cost > 0 and possible then
      DEFAULT_CHAT_FRAME:AddMessage(T["Your items have been repaired for"] .. " " .. CreateGoldString(cost))
      RepairAllItems()
    end
  end

  -- Trigger the engine's sell-all-junk path and report the gold income to
  -- chat. C_MerchantFrame.SellAllJunkItems handles its own one-per-frame
  -- pacing to avoid CMSG_SELL_ITEM flooding, so we just wait a beat before
  -- sampling the final gold delta.
  local function SellJunkAndReport()
    if C_MerchantFrame.GetNumJunkItems() <= 0 then return end
    local startGold = GetMoney()
    C_MerchantFrame.SellAllJunkItems()

    local reporter = CreateFrame("Frame")
    reporter.deadline = GetTime() + 0.3
    reporter:SetScript("OnUpdate", function()
      if GetTime() < this.deadline then return end
      this:SetScript("OnUpdate", nil)
      this:Hide()
      local income = GetMoney() - startGold
      if income > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(T["Your vendor trash has been sold and you earned"] .. " " .. CreateGoldString(income))
      end
    end)
  end

  local autovendor = CreateFrame("Frame", "pfMoneyUpdate", nil)
  autovendor:RegisterEvent("MERCHANT_SHOW")
  autovendor:RegisterEvent("MERCHANT_UPDATE")
  autovendor:SetScript("OnEvent", function()
    autovendor.button:Update()

    if event == "MERCHANT_SHOW" then
      if C["global"]["autorepair"] == "1" then RepairItems() end

      if C["global"]["autosell"] == "1" then
        SellJunkAndReport()
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

  autovendor.button:SetScript("OnClick", SellJunkAndReport)

  autovendor.button.Update = function()
    if C_MerchantFrame.GetNumJunkItems() > 0 then
      autovendor.button:Enable()
      autovendor.button.icon:SetDesaturated(false)
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
