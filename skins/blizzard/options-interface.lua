pfUI:RegisterSkin("Options - Interface", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()
  local cr, cg, cb = PFUI_CLASS_COLORS[UnitClassBase("player")]:GetRGB()

  StripTextures(InterfaceOptionsFrame)
  CreateBackdrop(InterfaceOptionsFrame, nil, nil, .75)
  CreateBackdropShadow(InterfaceOptionsFrame)

  local title = GetNoNameObject(InterfaceOptionsFrame, "FontString", "ARTWORK", ADDON_OPTIONS)
  title:ClearAllPoints()
  title:SetPoint("TOP", InterfaceOptionsFrame, "TOP", 0, -10)

  CreateBackdrop(InterfaceOptionsFrameAddOns, nil, true, .75)
  CreateBackdrop(InterfaceOptionsFramePanelContainer, nil, true, .75)
  SkinScrollbar(InterfaceOptionsFrameAddOnsListScrollBar)

  for _, button in ipairs(InterfaceOptionsFrameAddOns.buttons) do
    button:GetHighlightTexture():SetTexture(cr, cg, cb, .25)

    -- the list update swaps plus/minus textures on the toggle by path
    local toggle = _G[button:GetName() .. "Toggle"]
    SkinCollapseButton(toggle)
    toggle:SetPushedTexture("")
    toggle:SetHighlightTexture("")
    toggle.SetPushedTexture = function() end
  end

  -- ClassicAPI's own pages (Options\Panel.lua) number their controls
  local i = 1
  while _G["ClassicAPIOptionsControl" .. i] do
    local control = _G["ClassicAPIOptionsControl" .. i]
    local ctype = control:GetFrameType()
    if ctype == "CheckButton" then
      SkinCheckbox(control)
    elseif ctype == "Slider" then
      SkinSlider(control)
    else
      SkinDropDown(control, nil, nil, nil, true)
    end
    i = i + 1
  end

  SkinButton(InterfaceOptionsFrameDefaults)
  SkinButton(InterfaceOptionsFrameCancel)
  SkinButton(InterfaceOptionsFrameOkay)
  InterfaceOptionsFrameOkay:ClearAllPoints()
  InterfaceOptionsFrameOkay:SetPoint("RIGHT", InterfaceOptionsFrameCancel, "LEFT", -2*bpad, 0)
end)
