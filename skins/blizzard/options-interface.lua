pfUI:RegisterSkin("Options - Interface", function ()
  local cr, cg, cb = PFUI_CLASS_COLORS[UnitClassBase("player")]:GetRGB()

  -- retail's MinimalScrollBar, not the old named UIPanelScrollBar, so
  -- SkinScrollbar does not fit. Its steppers and thumb set their atlas again on
  -- every state change, so their art is hidden, not cleared
  local function SkinMinimalScrollBar(bar)
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
  end

  -- ClassicAPI before its Settings window (v1.20.6 and older) has the
  -- Interface Options frame, and its own pages number their controls. pfUI
  -- supports both until it requires a ClassicAPI with the Settings window
  local function SkinInterfaceOptionsFrame()
    local rawborder, border = GetBorderSize()
    local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

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

    i = 1
    while _G["ClassicAPIOptionsScrollBar" .. i] do
      SkinMinimalScrollBar(_G["ClassicAPIOptionsScrollBar" .. i])
      i = i + 1
    end

    SkinButton(InterfaceOptionsFrameDefaults)
    SkinButton(InterfaceOptionsFrameCancel)
    SkinButton(InterfaceOptionsFrameOkay)
    InterfaceOptionsFrameOkay:ClearAllPoints()
    InterfaceOptionsFrameOkay:SetPoint("RIGHT", InterfaceOptionsFrameCancel, "LEFT", -2*bpad, 0)
  end

  if not SettingsPanel then
    SkinInterfaceOptionsFrame()
    return
  end

  -- the category list pools its rows, and its group headers and spacers have
  -- no toggle. On every state change a row sets the art of its hover and
  -- selection highlight, and swaps the toggle's plus/minus textures by path
  local function SkinCategoryRow(_, row)
    if row.skinned or not row.Toggle then return end
    row.skinned = true

    row.Texture.SetTexture = function(self)
      self:SetColorTexture(cr, cg, cb, .25)
    end

    SkinCollapseButton(row.Toggle)
    row.Toggle.icon:ClearAllPoints()
    row.Toggle.icon:SetPoint("CENTER", 0, 0)
    row.Toggle:SetPushedTexture("")
    row.Toggle:SetHighlightTexture("")
    row.Toggle.SetPushedTexture = nop
  end

  local panel = SettingsPanel
  local list = panel:GetCategoryList()
  local settingsList = panel:GetSettingsList()

  -- ClassicAPI draws the window with a tooltip-border backdrop, a dark fill
  -- (Bg) and a dark title bar in NineSlice
  panel.Bg:Hide()
  StripTextures(panel.NineSlice)
  CreateBackdrop(panel, nil, nil, .75)
  CreateBackdropShadow(panel)
  SkinCloseButton(panel.ClosePanelButton, panel.backdrop, -6, -6)

  -- and frames the category list and the settings with a border frame each
  CreateBackdrop(panel.CategoryListBorder, nil, true, .75)
  CreateBackdrop(panel.ContainerBorder, nil, true, .75)
  SkinMinimalScrollBar(list.ScrollBar)
  SkinMinimalScrollBar(settingsList.ScrollBar)

  -- MinimalTab sets its three pieces again on every state change
  for _, tab in ipairs({ panel.GameTab, panel.AddOnsTab }) do
    tab.Left:Hide()
    tab.Middle:Hide()
    tab.Right:Hide()
    CreateBackdrop(tab, nil, true)
  end

  StripTextures(panel.SearchBox, nil, "BACKGROUND")
  CreateBackdrop(panel.SearchBox, nil, true)

  SkinButton(panel.CloseButton)
  SkinButton(panel.ApplyButton)
  SkinButton(settingsList.Header.DefaultsButton)

  list.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, SkinCategoryRow)
  -- a new data provider makes the list release and acquire every row again,
  -- so the rows that already exist get the skin and redraw their state in it
  list:CreateCategories()

  -- the settings list pools its rows as well, one pool for each kind of
  -- control. Each kind keeps its widgets under the keys retail gives them
  local function SkinSettingsDropdown(control)
    local dropdown = control.Dropdown

    -- WowStyle1DropdownTemplate sets its arrow again on every state change
    dropdown.Left:Hide()
    dropdown.Middle:Hide()
    dropdown.Right:Hide()
    dropdown.Arrow:SetAlpha(0)
    SkinButton(dropdown)
    -- the template names the stock menu style, so pfUI's default does not apply
    dropdown.menuMixin = pfUIMenuStyleMixin

    dropdown.icon = dropdown:CreateTexture(nil, "OVERLAY")
    dropdown.icon:SetTexture(pfUI.media["img:down"])
    dropdown.icon:SetVertexColor(1, .9, .1)
    dropdown.icon:SetAlpha(.8)
    dropdown.icon:SetSize(12, 12)
    dropdown.icon:SetPoint("RIGHT", -4, 0)

    SkinArrowButton(control.DecrementButton, "left")
    SkinArrowButton(control.IncrementButton, "right")
  end

  local function SkinSettingsRow(_, row)
    if row.skinned then return end
    row.skinned = true

    if row.Checkbox then
      SkinCheckbox(row.Checkbox)
    end

    if row.SliderWithSteppers then
      SkinSlider(row.SliderWithSteppers.Slider)
      SkinArrowButton(row.SliderWithSteppers.Back, "left")
      SkinArrowButton(row.SliderWithSteppers.Forward, "right")
    end

    if row.Control and row.Control.Dropdown then
      SkinSettingsDropdown(row.Control)
    end

    -- ClassicAPI's number box
    if row.EditBox then
      StripTextures(row.EditBox, nil, "BACKGROUND")
      CreateBackdrop(row.EditBox, nil, true)
    end

    -- a button control's button, an expandable section's bar and the two keys
    -- of a key binding row
    for _, key in ipairs({ "Button", "Button1", "Button2" }) do
      local button = row[key]
      if button then
        SkinButton(button)
        -- shown on a key while it waits for a key press
        if button.SelectedHighlight then
          button.SelectedHighlight:SetColorTexture(cr, cg, cb, .25)
        end
      end
    end
  end

  -- the list stays empty until the window first opens, so every row it shows
  -- comes through here
  settingsList.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, SkinSettingsRow)
end)
