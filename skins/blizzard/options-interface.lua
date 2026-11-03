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
    button:GetHighlightTexture():SetColorTexture(cr, cg, cb, .25)

    -- the list update swaps plus/minus textures on the toggle by path
    local toggle = _G[button:GetName() .. "Toggle"]
    SkinCollapseButton(toggle)
    toggle:SetPushedTexture("")
    toggle:SetHighlightTexture("")
    toggle.SetPushedTexture = nop
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
    elseif ctype == "EditBox" then
      StripTextures(control, nil, "BACKGROUND")
      CreateBackdrop(control, nil, true)
    elseif ctype == "Button" then
      -- key binding buttons: UIPanelButtonTemplate2's slices are BACKGROUND
      StripTextures(control, nil, "BACKGROUND")
      SkinButton(control)
    elseif _G[control:GetName() .. "Button"] then
      SkinDropDown(control, nil, nil, nil, true)
    end
    -- a control type without a branch stays unskinned; erroring here would
    -- stop the loop and leave every later control unskinned too
    i = i + 1
  end

  -- the pages scroll with retail's MinimalScrollBar, not the old named
  -- UIPanelScrollBar, so SkinScrollbar does not fit. Its steppers and thumb set
  -- their atlas again on every state change, so their art is hidden, not cleared
  i = 1
  while _G["ClassicAPIOptionsScrollBar" .. i] do
    local bar = _G["ClassicAPIOptionsScrollBar" .. i]
    local thumb = bar.Track.Thumb

    StripTextures(bar)
    bar.Background:Hide()
    for _, stepper in ipairs({ bar.Back, bar.Forward }) do
      stepper.Texture:Hide()
      stepper.Overlay:SetAlpha(0)
    end
    SkinArrowButton(bar.Back, "up")
    SkinArrowButton(bar.Forward, "down")

    thumb.Begin:Hide()
    thumb.Middle:Hide()
    thumb.End:Hide()
    thumb.thumbTexture:Hide()

    bar.bg = CreateFrame("Frame", nil, bar)
    bar.bg:SetPoint("TOPLEFT", bar.Back, "BOTTOMLEFT", 0, -3)
    bar.bg:SetPoint("BOTTOMRIGHT", bar.Forward, "TOPRIGHT", 0, 3)
    CreateBackdrop(bar.bg, nil, true)

    bar.thumb = bar.bg:CreateTexture(nil, "ARTWORK")
    bar.thumb:SetColorTexture(.8, .8, .8, .8)
    bar.thumb:SetPoint("TOP", thumb, "TOP", 0, -4)
    bar.thumb:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 4)
    bar.thumb:SetPoint("LEFT", bar.bg, "LEFT", 1, 0)
    bar.thumb:SetPoint("RIGHT", bar.bg, "RIGHT", -1, 0)
    i = i + 1
  end

  SkinButton(InterfaceOptionsFrameDefaults)
  SkinButton(InterfaceOptionsFrameCancel)
  SkinButton(InterfaceOptionsFrameOkay)
  InterfaceOptionsFrameOkay:ClearAllPoints()
  InterfaceOptionsFrameOkay:SetPoint("RIGHT", InterfaceOptionsFrameCancel, "LEFT", -2*bpad, 0)
end)
