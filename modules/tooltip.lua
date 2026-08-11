pfUI:RegisterModule("tooltip", function ()
  local rawborder, default_border = GetBorderSize()

  pfUI.tooltip = CreateFrame('Frame', "pfTooltip", GameTooltip)
  pfUI.tooltip.anchorframe = CreateFrame('Frame', "pfTooltipAnchor", UIParent)
  pfUI.tooltip.anchorframe:SetSize(128, 72)
  pfUI.tooltip.anchorframe:SetPoint("TOP", UIParent, "TOP", 0, -50)
  pfUI.tooltip.anchorframe:Hide()
  UpdateMovable(pfUI.tooltip.anchorframe)

  function pfUI.tooltip:GetAnchorPoint()
    local prefix = "TOP"
    local suffix = "RIGHT"
    local px, py = UIParent:GetCenter()
    local tx, ty = this.anchorframe:GetCenter()
    if (tx < px) then
      suffix = "LEFT"
    end
    if (ty < py) then
      prefix = "BOTTOM"
    end
    return prefix..suffix
  end

  if C.tooltip.position == "cursor" then
    -- Cursor mode makes the tooltip follow the mouse. The client has no
    -- mouse-move event, so following means polling GetCursorPosition() via an
    -- invisible follower frame that the tooltip anchors to. The follower is
    -- only shown while a tooltip is visible -- an OnUpdate fires only while its
    -- frame is shown, so the poll stops the moment the tooltip hides instead
    -- of running forever.
    local follower, Reposition
    if C.tooltip.cursoralign ~= "native" then
      local size = tonumber(C.tooltip.cursoroffset) * 2
      follower = CreateFrame("Frame", nil, UIParent)
      follower:SetSize(size, size)
      follower:Hide()

      Reposition = function()
        local scale = UIParent:GetScale()
        local x, y = GetCursorPosition()
        follower:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/scale, y/scale)
        if C.tooltip.cursoralign == "top" then
          follower:SetWidth(GameTooltip:GetWidth())
        end
      end

      follower:SetScript("OnUpdate", function()
        -- throttle - cursor following doesn't need to be every frame
        if (this.tick or 0) > GetTime() then return end
        this.tick = GetTime() + (pfUI.throttle and pfUI.throttle:Get("tooltip_cursor") or 0.1)
        Reposition()
      end)

      -- stop polling as soon as the tooltip is gone
      pfUI.tooltip:SetScript("OnHide", function() follower:Hide() end)
    end

    function _G.GameTooltip_SetDefaultAnchor(tooltip, parent)
      tooltip:SetOwner(parent, "ANCHOR_CURSOR")
      if not follower then return end

      -- position the follower right away so the tooltip doesn't flash at a
      -- stale spot before the first OnUpdate tick
      follower:Show()
      Reposition()

      if C.tooltip.cursoralign == "top" then
        tooltip:SetPoint("BOTTOMLEFT", follower, "TOPLEFT", 0, 0)
      elseif C.tooltip.cursoralign == "left" then
        tooltip:SetPoint("BOTTOMRIGHT", follower, "LEFT", 0, 0)
      elseif C.tooltip.cursoralign == "right" then
        tooltip:SetPoint("BOTTOMLEFT", follower, "RIGHT", 0, 0)
      end
    end
  end

  function pfUI.tooltip:GetUnit()
    pfUI.tooltip.unit = "none"
    if GameTooltip:HasUnit() then
      local _, guid = GameTooltip:GetUnitGUID()
      local token = guid and UnitTokenFromGUID(guid)
      if token then pfUI.tooltip.unit = token end
    end
    return pfUI.tooltip.unit
  end

  pfUI.tooltip.dodge = {
    "pfPanelRight", "pfChatRight"
  }

  if C.appearance.bags.movable == "0" then
    table.insert(pfUI.tooltip.dodge, "pfBag")
  end

  pfUI.tooltip:SetAllPoints()
  pfUI.tooltip:SetScript("OnShow", function()
      pfUI.tooltip:Update()
      if GameTooltip:GetAnchorType() == "ANCHOR_NONE" then
        GameTooltip:ClearAllPoints()
        if C.tooltip.position == "bottom" then
          if pfUI.panel and pfUI.panel.right:IsShown() then
            GameTooltip:SetPoint("BOTTOMRIGHT", pfUI.panel.right, "TOPRIGHT", 0, default_border*2)
          else
            GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -5, 5)
          end
        elseif C.tooltip.position == "chat" then
          local anchor = nil

          for _, frame in pairs(pfUI.tooltip.dodge) do
            if _G[frame] and _G[frame]:IsShown() then
              anchor = _G[frame]
            end
          end

          if anchor then
            GameTooltip:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, default_border*3)
          else
            GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -5, 5)
          end
        elseif C.tooltip.position == "free" then
          local point = this:GetAnchorPoint()
          if point then
            GameTooltip:SetPoint(point, this.anchorframe, point, 0, 0)
          end
        end
      end
    end)

  pfUI.tooltipStatusBar = CreateFrame('Frame', nil, GameTooltipStatusBar)
  pfUI.tooltipStatusBar:SetPoint("TOPLEFT", 0, 8)
  pfUI.tooltipStatusBar:SetPoint("TOPRIGHT", 0, 8)
  pfUI.tooltipStatusBar:SetHeight(12)
  pfUI.tooltipStatusBar:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  pfUI.tooltipStatusBar:SetScript("OnEvent", function()
    this.name = UnitName("mouseover")
    this.level = UnitLevel("mouseover")
  end)

  pfUI.tooltipStatusBar.text = CreateFrame("Frame", nil, pfUI.tooltipStatusBar)
  pfUI.tooltipStatusBar.text:SetFrameLevel(16)
  pfUI.tooltipStatusBar.text:SetAllPoints()

  pfUI.tooltipStatusBar.HP = pfUI.tooltipStatusBar.text:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  pfUI.tooltipStatusBar.HP:SetAllPoints()
  pfUI.tooltipStatusBar.HP:SetNonSpaceWrap(false)
  pfUI.tooltipStatusBar.HP:SetFontObject(GameFontWhite)
  pfUI.tooltipStatusBar.HP:SetFont(C.tooltip.font_tooltip, C.tooltip.font_tooltip_size + 2, "OUTLINE")

  if GameTooltip.SetClampRectInsets then
    GameTooltip:SetClampRectInsets(0, 0, 16, 0)
  else
    GameTooltipStatusBar:SetClampedToScreen(true)
    pfUI.tooltipStatusBar:SetClampedToScreen(true)
  end

  pfUI.tooltipStatusBar:SetScript("OnUpdate", function()
    local hp = GameTooltipStatusBar:GetValue()
    local _, hpmax = GameTooltipStatusBar:GetMinMaxValues()
    local rhp, rhpmax, estimated

    if hpmax > 100 or (round(hpmax/100*hp) ~= hp) then
      rhp, rhpmax = hp, hpmax
    elseif pfUI.libhealth and pfUI.libhealth.enabled then
      rhp, rhpmax, estimated = pfUI.libhealth:GetUnitHealthByName(this.name, this.level, tonumber(hp), tonumber(hpmax))
    end

    if C.tooltip.alwaysperc == "0" and ( estimated or hpmax > 100 or round(hpmax/100*hp) ~= hp ) then
      pfUI.tooltipStatusBar.HP:SetText(string.format("%s / %s", Abbreviate(rhp), Abbreviate(rhpmax)))
    elseif hpmax > 0 then
      pfUI.tooltipStatusBar.HP:SetText(string.format("%s%%", ceil(hp/hpmax*100)))
    else
      pfUI.tooltipStatusBar.HP:SetText("")
    end
  end)

  GameTooltipStatusBar:SetHeight(8)
  GameTooltipStatusBar:ClearAllPoints()
  GameTooltipStatusBar:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, default_border)
  GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", GameTooltip, "TOPRIGHT", 0, default_border)
  GameTooltipStatusBar:SetStatusBarTexture(pfUI.media[C.tooltip.statusbar.texture])
  CreateBackdrop(GameTooltipStatusBar, nil, nil, tonumber(C.tooltip.alpha))
  CreateBackdropShadow(GameTooltipStatusBar)

  GameTooltipStatusBar.SetStatusBarColor_orig = GameTooltipStatusBar.SetStatusBarColor
  GameTooltipStatusBar.SetStatusBarColor = function() return end

  -- A row of buff icons anchored above the tooltip for mouseover units.
  -- Icons come from a ClassicAPI object pool: ReleaseAll hides the whole
  -- set each refresh, then we Acquire and re-anchor left-to-right.
  local BUFF_SIZE, BUFF_SPACING, BUFF_MAX = 20, 2, 32
  pfUI.tooltip.buffs = CreateFrame("Frame", "pfTooltipBuffs", GameTooltip)
  pfUI.tooltip.buffs:SetPoint("BOTTOMLEFT", GameTooltipStatusBar, "TOPLEFT", 0, default_border + 2)
  pfUI.tooltip.buffs:SetHeight(BUFF_SIZE)

  local function CreateBuffIcon()
    local icon = CreateFrame("Frame", nil, pfUI.tooltip.buffs)
    icon:SetSize(BUFF_SIZE, BUFF_SIZE)
    icon.texture = icon:CreateTexture(nil, "BACKGROUND")
    icon.texture:SetTexCoord(.07, .93, .07, .93)
    icon.texture:SetAllPoints(icon)
    CreateBackdrop(icon)

    icon.stacks = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    icon.stacks:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)
    icon.stacks:SetFont(C.tooltip.font_tooltip, C.tooltip.font_tooltip_size, "OUTLINE")
    icon.stacks:SetTextColor(1, 1, 1, 1)

    icon.timer = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    icon.timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.timer:SetFont(C.tooltip.font_tooltip, C.tooltip.font_tooltip_size, "OUTLINE")
    icon.timer:SetTextColor(1, 1, 1, 1)
    return icon
  end

  pfUI.tooltip.buffpool = CreateObjectPool(CreateBuffIcon, function(_, icon)
    icon:Hide()
    icon:ClearAllPoints()
  end)

  -- Tick the remaining-time text on the visible icons. OnUpdate only fires
  -- while the row is shown, so it stops as soon as the tooltip hides.
  pfUI.tooltip.buffs:SetScript("OnUpdate", function()
    local now = GetTime()
    if (this.tick or 0) > now then return end
    this.tick = now + 0.1
    for icon in pfUI.tooltip.buffpool:EnumerateActive() do
      local timeleft = icon.expirationTime and icon.expirationTime > 0 and (icon.expirationTime - now) or 0
      icon.timer:SetText(timeleft > 0 and GetColoredTimeString(timeleft) or "")
    end
  end)

  function pfUI.tooltip:UpdateBuffs(unit)
    pfUI.tooltip.buffpool:ReleaseAll()

    if C.tooltip.showbuffs ~= "1" or not unit or unit == "none" then
      pfUI.tooltip.buffs:Hide()
      return
    end

    local prev, count = nil, 0
    for i = 1, BUFF_MAX do
      local aura = C_UnitAuras.GetBuffDataByIndex(unit, i)
      if not aura then break end

      count = count + 1
      local icon = pfUI.tooltip.buffpool:Acquire()
      icon.texture:SetTexture(aura.icon)
      icon.stacks:SetText(aura.applications and aura.applications > 1 and aura.applications or "")

      icon.expirationTime = aura.expirationTime
      local timeleft = aura.expirationTime and aura.expirationTime > 0 and (aura.expirationTime - GetTime()) or 0
      icon.timer:SetText(timeleft > 0 and GetColoredTimeString(timeleft) or "")

      if prev then
        icon:SetPoint("LEFT", prev, "RIGHT", BUFF_SPACING, 0)
      else
        icon:SetPoint("BOTTOMLEFT", pfUI.tooltip.buffs, "BOTTOMLEFT", 0, 0)
      end
      icon:Show()
      prev = icon
    end

    if count > 0 then
      pfUI.tooltip.buffs:SetWidth(count * BUFF_SIZE + (count - 1) * BUFF_SPACING)
      pfUI.tooltip.buffs:Show()
    else
      pfUI.tooltip.buffs:Hide()
    end
  end

  function pfUI.tooltip:Update()
      local unit = pfUI.tooltip:GetUnit()
      pfUI.tooltip:UpdateBuffs(unit)
      if unit == "none" then
        if C.tooltip.itemid == "1" and GameTooltip:HasItem() then
          local _, _, itemID = GameTooltip:GetItem()
          GameTooltip:AddLine(T["ItemID"] .. ": " .. itemID, .25,.5,1)
          GameTooltip:Show()
        elseif C.tooltip.spellid == "1" and GameTooltip:HasSpell() then
          local _, _, spellID = GameTooltip:GetSpell()
          GameTooltip:AddLine(T["SpellID"] .. ": " .. spellID, .25,.5,1)
          GameTooltip:Show()
        end

        return
      end

      local pvpname = UnitPVPName(unit)
      local name = UnitName(unit)
      local validTarget, target = pcall(UnitName, unit .. 'target')
      local class = UnitClassBase(unit)
      local guild, rankstr, rankid = GetGuildInfo(unit)
      local reaction = UnitReaction(unit, "player")
      local pvptitle = gsub(gsub(pvpname or name, name, "", 1), "^%s*(.-)%s*$", "%1")
      local hp = UnitHealth(unit)
      local hpm = UnitHealthMax(unit)

      if name then
        if UnitIsPlayer(unit) and class then
          local color = PFUI_CLASS_COLORS[class]
          GameTooltipStatusBar:SetStatusBarColor_orig(color:GetRGB())
          GameTooltip:SetBackdropBorderColor(color:GetRGB())
          GameTooltipTextLeft1:SetText("|c" .. color.colorStr .. name)
        elseif reaction then
          local color = UnitReactionColor[reaction]
          GameTooltipStatusBar:SetStatusBarColor_orig(color.r, color.g, color.b)
          GameTooltip:SetBackdropBorderColor(color.r, color.g, color.b)
        end
        if pvptitle ~= name and pvptitle ~= "" then
          GameTooltip:AppendText(" |cff666666["..pvptitle.."]|r")
        end
      end

      if guild then
        local rank = ""
        local lead = ""
        if C.tooltip.extguild == "1" then
          if rankstr then rank = " |cffaaaaaa(" .. rankstr .. ")"  end
          if rankid and rankid == 0 then lead = "|cffffcc00*|r" end
        end

        GameTooltip:AddLine("<" .. guild .. ">" .. lead .. rank, 0.3, 1, 0.5)
      end

      if validTarget and target then
        local targetClass = UnitClassBase(unit .. "target")
        local targetReaction = UnitReaction("player",unit .. "target")
        if UnitIsPlayer(unit .. "target") and targetClass then
          local color = PFUI_CLASS_COLORS[targetClass]
          GameTooltip:AddLine(target, color.r, color.g, color.b)
        elseif targetReaction then
          local color = UnitReactionColor[targetReaction]
          if color then
            GameTooltip:AddLine(target, color.r, color.g, color.b)
          else
            GameTooltip:AddLine(target, .5, .5, .5)
          end
        end
      end

      if C.tooltip.movespeed == "1" then
        local currentSpeed = GetUnitSpeed(unit)
        if currentSpeed and currentSpeed > 0 then
          local pct = floor(currentSpeed / 7 * 100 + 0.5)
          GameTooltip:AddLine(T["Speed"] .. ": " .. pct .. "%", 0.7, 0.7, 1)
        end
      end

      if C.tooltip.unitid == "1" and not UnitIsPlayer(unit) then
        local npcID = C_CreatureInfo.GetCreatureID(UnitGUID(unit))
        if npcID then
          GameTooltip:AddLine(T["UnitID"] .. ": " .. npcID, .25,.5,1)
        end
      end

      if hp and hpm then
        if hp >= 1000 then hp = round(hp / 1000, 1) .. "k" end
        if hpm >= 1000 then hpm = round(hpm / 1000, 1) .. "k" end
        pfUI.tooltipStatusBar.HP:SetText(hp .. " / " .. hpm)
      end
      GameTooltip:Show()
    end

  if C.tooltip.aurasource == "1" or C.tooltip.spellid == "1" then
    hooksecurefunc(GameTooltip, "SetUnitAura", function(self, ...)
      local aura = C_UnitAuras.GetAuraDataByIndex(unpack(arg))
      if not aura then return end
      if C.tooltip.aurasource == "1" then
        local caster = aura.sourceUnit and UnitName(aura.sourceUnit)
        if not caster and aura.sourceGUID then
          caster = UnitNameFromGUID(aura.sourceGUID)
        end
        if caster and caster ~= "" then
          self:AddLine(T["Cast by"] .. ": " .. caster, .25,.5,1)
        end
      end
      if C.tooltip.spellid == "1" then
        self:AddLine(T["SpellID"] .. ": " .. aura.spellId, .25,.5,1)
      end
      self:Show()
    end)
  end
end)
