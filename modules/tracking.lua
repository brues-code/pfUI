pfUI:RegisterModule("tracking", function ()

  MINIMAP_TRACKING_FRAME:UnregisterAllEvents()
  MINIMAP_TRACKING_FRAME:Hide()

  local rawborder, border = GetBorderSize()
  local size = tonumber(C.appearance.minimap.tracking_size)
  local pulse = C.appearance.minimap.tracking_pulse == "1"

  -- Tracking spells come from ClassicAPI's native GetNumTrackingTypes /
  -- GetTrackingInfo (see the DLL's docs/API.md "Tracking"). The DLL
  -- enumerates them straight from the spellbook by tracking-aura effect,
  -- so there is no spell table to maintain here and server-custom trackers
  -- (e.g. Turtle's Find Trees) are picked up automatically.

  local state = {
    texture = nil,
    spells = {}
  }

  pfUI.tracking = CreateFrame("Button", "pfUITracking", UIParent)
  pfUI.tracking.invalidSpells = {}

  pfUI.tracking:SetFrameStrata("HIGH")
  CreateBackdrop(pfUI.tracking, border)
  CreateBackdropShadow(pfUI.tracking)

  pfUI.tracking:SetPoint("TOPLEFT", pfUI.minimap, -10, -10)
  UpdateMovable(pfUI.tracking)
  pfUI.tracking:SetWidth(size)
  pfUI.tracking:SetHeight(size)

  pfUI.tracking.icon = pfUI.tracking:CreateTexture("BACKGROUND")
  pfUI.tracking.icon:SetTexCoord(.08, .92, .08, .92)
  pfUI.tracking.icon:SetAllPoints(pfUI.tracking)

  pfUI.tracking.menu = CreateFrame("Frame", "pfUIDropDownMenuTracking", nil, "UIDropDownMenuTemplate")

  pfUI.tracking:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.tracking:RegisterEvent("PLAYER_AURAS_CHANGED")
  pfUI.tracking:RegisterEvent("SPELLS_CHANGED")
  pfUI.tracking:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
  pfUI.tracking:SetScript("OnEvent", function()
    if event == "SPELLS_CHANGED" then
      state.spells = {}
    end
    this:RefreshSpells()
    this:RefreshMenu()
  end)

  pfUI.tracking:SetScript("OnUpdate", function()
    if this.pulse then
      local _,_,_,alpha = this.icon:GetVertexColor()
      local fpsmod = GetFramerate() / 30
      if not alpha or alpha >= 0.9 then
        this.modifier = -0.03 / fpsmod
      elseif alpha <= .5 then
        this.modifier = 0.03  / fpsmod
      end
      this.icon:SetVertexColor(1,1,1,alpha + this.modifier)
    end
  end)

  pfUI.tracking:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  pfUI.tracking:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      pfUI.tracking:InitMenu()
      ToggleDropDownMenu(1, nil, pfUI.tracking.menu, this, -5, -5)
    end
    if arg1 == "LeftButton" and state.texture then
      CancelTrackingBuff()
    end
  end)

  pfUI.tracking:SetScript("OnEnter", function()
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
    if state.texture then
      GameTooltip:SetTrackingSpell()
    else
      GameTooltip:SetText(T["No tracking spell active"])
    end
    GameTooltip:Show()
  end)

  pfUI.tracking:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  function pfUI.tracking:RefreshSpells()
    state.spells = {}
    if not GetNumTrackingTypes then return end

    -- Druid Track Humanoids (5225) only casts in Cat Form. Hide it out of
    -- form so the menu never offers a tracker that would fail to cast.
    local isCatForm = pfUI.tracking:PlayerIsDruidInCatForm(UnitClassBase("player"))

    for i = 1, GetNumTrackingTypes() do
      local name, texture, _, _, spellId = GetTrackingInfo(i)
      local castable = not (spellId == 5225 and not isCatForm)
      if name and texture and castable
        and not pfUI.tracking.invalidSpells[name] then
        state.spells[i] = {
          index   = i,        -- tracking index, passed to SetTracking()
          name    = name,
          texture = texture,
          spellId = spellId,
        }
      end
    end
  end

  function pfUI.tracking:RefreshMenu()
    local texture = GetTrackingTexture()
    if texture and texture ~= state.texture then
      state.texture = texture
      pfUI.tracking.pulse = nil
      pfUI.tracking.icon:SetTexture(texture)
      pfUI.tracking.icon:SetVertexColor(1,1,1,1)
      pfUI.tracking:Show()
    elseif not texture then
      state.texture = nil

      if pulse and next(state.spells) ~= nil then
        pfUI.tracking.pulse = true
        pfUI.tracking.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        pfUI.tracking.icon:SetVertexColor(1,1,1,1)
        pfUI.tracking:Show()
      else
        pfUI.tracking.pulse = nil
        pfUI.tracking:Hide()
      end
    end
  end

  function pfUI.tracking:PlayerIsDruidInCatForm(playerClass)
    return playerClass == "DRUID" and GetShapeshiftFormID() == 1
  end

  function pfUI.tracking:InitMenu()
    UIDropDownMenu_Initialize(pfUI.tracking.menu, function ()
      UIDropDownMenu_AddButton({text = T["Minimap Tracking"], isTitle = 1})
      for _, spell in pairs(state.spells) do
        UIDropDownMenu_AddButton({
          text = spell.name,
          icon = spell.texture,
          tCoordLeft = .1,
          tCoordRight = .9,
          tCoordTop = .1,
          tCoordBottom = .9,
          checked = spell.texture == state.texture,
          arg1 = spell,
          func = function (arg1)
            SetTracking(arg1.index)
            CloseDropDownMenus()
          end
        })
      end
    end, "MENU")
  end
end)