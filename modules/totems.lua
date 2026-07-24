pfUI:RegisterModule("totems", function ()
  local slotColors = {
    [FIRE_TOTEM_SLOT]  = CreateColor(.5, .2, .1),
    [EARTH_TOTEM_SLOT] = CreateColor(.2, .4, .1),
    [WATER_TOTEM_SLOT] = CreateColor(.1, .4, .6),
    [AIR_TOTEM_SLOT]   = CreateColor(.4, .1, .7),
  }

  local totems = CreateFrame("Frame", "pfTotems", UIParent)
  totems:RegisterEvent("PLAYER_TOTEM_UPDATE")
  totems:RegisterEvent("PLAYER_ENTERING_WORLD")
  totems:SetScript("OnEvent", function()
    this:RefreshList()
  end)

  totems.OnEnter = function(self)
    local id = this:GetID()
    local spellID = select(7, GetTotemInfo(id))
    if not spellID or spellID == 0 then return end
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(spellID)
    GameTooltip:AddDoubleLine(T["Left Click"], T["Recast Totem"], nil, nil, nil, WHITE_FONT_COLOR:GetRGB())
    GameTooltip:AddDoubleLine(T["Right Click"], T["Target Totem"], nil, nil, nil, WHITE_FONT_COLOR:GetRGB())
    GameTooltip:Show()
  end

  totems.OnLeave = GameTooltip_Hide

  totems.OnClick = function(self)
    local id = this:GetID()
    if arg1 == "LeftButton" then
      local spellID = select(7, GetTotemInfo(id))
      if spellID and spellID > 0 then CastSpell(FindSpellBookSlotByID(spellID)) end
    elseif arg1 == "RightButton" then
      TargetTotem(id)
    end
  end

  totems.RefreshList = function(self)
    local count = 0
    for i = 1, MAX_TOTEMS do
      local _, _, start, duration, icon = GetTotemInfo(i)

      if start and start > 0 and icon and icon ~= "" then
        count = count + 1

        self.bar[count]:Show()
        self.bar[count]:SetBackdropBorderColor(slotColors[i]:GetRGB())
        self.bar[count].icon:SetTexture(icon)
        self.bar[count]:SetID(i)

        CooldownFrame_SetTimer(self.bar[count].cd, start, duration, 1)
      end
    end

    self:UpdateSize(count)
  end

  totems.UpdateSize = function(self, count)
    if not count or count == 0 then
      -- hide entire panel
      self:Hide()
    else
      -- hide remaining totems and show panel
      for i = count + 1, MAX_TOTEMS do self.bar[i]:Hide() end
      self:Show()
    end

    count = count and count > 0 and count or MAX_TOTEMS

    local thickness = self.iconsize + self.spacing*2
    local length = thickness * count
    if pfUI_config.totems.direction == "HORIZONTAL" then
      self:SetSize(length, thickness)
    else
      self:SetSize(thickness, length)
    end
  end

  totems.UpdateConfig = function(self)
    local rawborder, border = GetBorderSize()
    self.iconsize = pfUI_config.totems.iconsize
    self.direction = pfUI_config.totems.direction
    self.spacing = tonumber(pfUI_config.totems.spacing) * GetPerfectPixel()
    self.showbg = pfUI_config.totems.showbg == "1" and true or nil

    for i = 1, MAX_TOTEMS do
      self.bar = self.bar or {}
      self.bar[i] = self.bar[i] or CreateFrame("Button", "pfTotemsBar"..i, totems)
      self.bar[i]:ClearAllPoints()

      if pfUI_config.totems.direction == "HORIZONTAL" then
        if self.bar[i-1] then
          self.bar[i]:SetPoint("LEFT", self.bar[i-1], "RIGHT", self.spacing*2, 0)
        else
          self.bar[i]:SetPoint("TOPLEFT", self, "TOPLEFT", self.spacing, -self.spacing)
        end
      else
        if self.bar[i-1] then
          self.bar[i]:SetPoint("TOP", self.bar[i-1], "BOTTOM", 0, -self.spacing*2)
        else
          self.bar[i]:SetPoint("TOPLEFT", self, "TOPLEFT", self.spacing, -self.spacing)
        end
      end

      self.bar[i]:SetSize(self.iconsize, self.iconsize)
      CreateBackdrop(self.bar[i], nil, true)

      self.bar[i].icon = self.bar[i].icon or self.bar[i]:CreateTexture(nil, "ARTWORK")
      self.bar[i].icon:SetTexCoord(.08, .92, .08, .92)
      SetAllPointsOffset(self.bar[i].icon, self.bar[i], 2,-2)

      self.bar[i].cdbg = self.bar[i].cdbg or CreateFrame("Frame", nil, self.bar[i])
      self.bar[i].cdbg:SetSize(self.iconsize - 3, self.iconsize - 3)
      self.bar[i].cdbg:SetPoint("CENTER", self.bar[i], "CENTER", 0, 0)
      self.bar[i].cd = self.bar[i].cd or CreateFrame(COOLDOWN_FRAME_TYPE, "pfTotemsBar"..i.."Cooldown", self.bar[i].cdbg, "CooldownFrameTemplate")
      self.bar[i].cd.pfCooldownStyleAnimation = 1
      self.bar[i].cd.pfCooldownType = "ALL"

      self.bar[i]:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      self.bar[i]:SetScript("OnClick", self.OnClick)
      self.bar[i]:SetScript("OnEnter", self.OnEnter)
      self.bar[i]:SetScript("OnLeave", self.OnLeave)
    end

    self:RefreshList()
    self:ClearAllPoints()
    self:SetPoint("BOTTOM", 0, 75)
    UpdateMovable(self, true)

    if self.showbg then
      CreateBackdrop(self)
      self.backdrop:Show()
    elseif self.backdrop then
      self.backdrop:Hide()
    end
  end

  -- add totems to the pfUI global space
  pfUI.totems = totems
  pfUI.totems:UpdateConfig()
end)
