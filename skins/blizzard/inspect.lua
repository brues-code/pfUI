local slots = {
  "HeadSlot",
  "NeckSlot",
  "ShoulderSlot",
  "BackSlot",
  "ChestSlot",
  "ShirtSlot",
  "TabardSlot",
  "WristSlot",
  "HandsSlot",
  "WaistSlot",
  "LegsSlot",
  "FeetSlot",
  "Finger0Slot",
  "Finger1Slot",
  "Trinket0Slot",
  "Trinket1Slot",
  "MainHandSlot",
  "SecondaryHandSlot",
  "RangedSlot",
}

pfUI:RegisterSkin("Inspect", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  HookAddonOrVariable("Blizzard_InspectUI", function()
    local cache = {}

    CreateBackdrop(InspectFrame, nil, nil, .75)
    CreateBackdropShadow(InspectFrame)

    InspectFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
    InspectFrame.backdrop:SetPoint("BOTTOMRIGHT", -30, 72)
    InspectFrame:SetHitRectInsets(10,30,10,72)
    EnableMovable("InspectFrame", "Blizzard_InspectUI", INSPECTFRAME_SUBFRAMES)

    SkinCloseButton(InspectFrameCloseButton, InspectFrame.backdrop, -6, -6)

    InspectFrame:DisableDrawLayer("ARTWORK")

    InspectNameText:ClearAllPoints()
    InspectNameText:SetPoint("TOP", InspectFrame.backdrop, "TOP", 0, -10)

    -- Turtle WoW has up to 4 inspect tabs: Character, Honor, Arena, Talents
    for i = 1, 4 do
      local tab = _G["InspectFrameTab"..i]
      if tab then
        local lastTab = _G["InspectFrameTab"..(i-1)]
        tab:ClearAllPoints()
        if lastTab then
          tab:SetPoint("LEFT", lastTab, "RIGHT", border*2 + 1, 0)
        else
          tab:SetPoint("TOPLEFT", InspectFrame.backdrop, "BOTTOMLEFT", bpad, -(border + (border == 1 and 1 or 2)))
        end
        SkinTab(tab)
      end
    end

    do -- Character Tab
      StripTextures(InspectPaperDollFrame)

      EnableClickRotate(InspectModelFrame)
      local rotL = InspectModelRotateLeftButton or InspectModelFrameRotateLeftButton
      if rotL then rotL:Hide() end
      local rotR = InspectModelRotateRightButton or InspectModelFrameRotateRightButton
      if rotR then rotR:Hide() end

      for _, slot in pairs(slots) do
        local frame = _G["Inspect"..slot]
        StripTextures(frame)
        CreateBackdrop(frame)
        SetAllPointsOffset(frame.backdrop, frame, 0)

        HandleIcon(frame.backdrop, _G["Inspect"..slot.."IconTexture"])

        local funce = frame:GetScript("OnEnter")
        frame:SetScript("OnEnter", function()
          local bid = this:GetID()
          if not GetInventoryItemLink(InspectFrame.unit, this:GetID()) and this.hasItem then
            GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
            GameTooltip:SetHyperlink("item:"..cache[bid]["id"])
            GameTooltip:Show()
          else
            funce()
          end
        end)
      end

      -- Colour a slot's border from the item's quality. Via the !!!ClassicAPI
      -- Item mixin: ContinueOnItemLoad fires now if the data is cached, else
      -- when ITEM_DATA_LOAD_RESULT lands — replacing the old QueueFunction
      -- retry poll. Guards against the inspect target / slot changing before
      -- the (possibly async) load returns.
      local function ColorSlot(slot, id, itemID, vslot)
        local item = Item:CreateFromItemID(itemID)
        if item:IsItemEmpty() then return end

        item:ContinueOnItemLoad(function()
          if not InspectFrame.unit then return end
          if GetInventoryItemID(InspectFrame.unit, id) ~= itemID then return end

          local quality = item:GetItemQuality()
          if not quality then return end

          local r, g, b = GetItemQualityColor(quality)
          slot.backdrop:SetBackdropBorderColor(r, g, b)

          if ShaguScore then
            if not slot.scoreText then
              slot.scoreText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
              slot.scoreText:SetFont(pfUI.font_default, 12, "OUTLINE")
              slot.scoreText:SetPoint("TOPRIGHT", 0, 0)
            end
            local itemLevel = ShaguScore.Database[itemID] or 0
            local score = ShaguScore:Calculate(vslot, quality, itemLevel)
            if score and score > 0 then
              slot.scoreText:SetText(score)
              slot.scoreText:SetTextColor(r, g, b)
            else
              slot.scoreText:SetText("")
            end
          end
        end)
      end

      local function UpdateSlots()
        if not InspectFrame.unit then return end

        local guild, title = GetGuildInfo(InspectFrame.unit)
        if guild then
          InspectGuildText:SetPoint("TOP", InspectLevelText, "BOTTOM", 0, -1)
          InspectGuildText:SetText(format(TEXT(GUILD_TITLE_TEMPLATE), title, guild))
          InspectGuildText:Show()
        else
          InspectGuildText:SetText("")
          InspectGuildText:Hide()
        end

        for _, vslot in pairs(slots) do
          local id = GetInventorySlotInfo(vslot)
          local itemID = GetInventoryItemID(InspectFrame.unit, id)
          local slot = _G["Inspect" .. vslot]

          if itemID then
            ColorSlot(slot, id, itemID, vslot)
          elseif not slot.hasItem then
            -- genuinely empty slot: reset to a plain backdrop
            CreateBackdrop(slot)
            SetAllPointsOffset(slot.backdrop, slot, 0)
            if slot.scoreText then
              slot.scoreText:SetText("")
            end
          end
          -- (hasItem but itemID still nil = inspect inventory not synced yet;
          --  InspectPaperDollItemSlotButton_Update re-fires UpdateSlots)
        end
      end

      hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        local bid = button:GetID()
        local link = GetInventoryItemLink(InspectFrame.unit, bid)
        if link then
          local _,_,itemID = string.find(link, 'item:(%d+)')
          cache[bid] = cache[bid] or {}
          cache[bid]["id"] = itemID
          cache[bid]["tex"] = GetInventoryItemTexture(InspectFrame.unit, button:GetID())
          cache[bid]["count"] = GetInventoryItemCount(InspectFrame.unit, button:GetID())
          cache[bid]["name"] = UnitName(InspectFrame.unit)
        elseif cache[bid] and UnitName(InspectFrame.unit) == cache[bid].name then
          -- restore cache information
          SetItemButtonTexture(button, cache[bid]["tex"])
          SetItemButtonCount(button, cache[bid]["count"])
          button.hasItem = 1
        end

        UpdateSlots()
      end)
    end

    do -- Honor Tab
      StripTextures(InspectHonorFrame)

      CreateBackdrop(InspectHonorFrameProgressBar)
      InspectHonorFrameProgressBar:SetStatusBarTexture(pfUI.media["img:bar"])
      InspectHonorFrameProgressBar:SetHeight(24)
    end

    -- NOTE: Turtle WoW's Talent tab (InspectTalentsFrame / TWTalentFrame) is
    -- skinned in modules/turtle-wow.lua, which activates once this skin is
    -- registered (it gates on pfUI.skin["Inspect"]).
  end)
end)
