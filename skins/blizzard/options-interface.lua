pfUI:RegisterSkin("Options - Interface", function ()
  local cr, cg, cb = PFUI_CLASS_COLORS[UnitClassBase("player")]:GetRGB()

  -- retail's MinimalScrollBar, not the old named UIPanelScrollBar, so
  -- SkinScrollbar does not fit. Its steppers and thumb set their atlas again on
  -- every state change, so their art is hidden, not cleared. Newer ClassicAPI
  -- draws retail's own bar (track pieces); older versions draw a classic bar
  -- (Background, stepper Overlay, thumbTexture)
  local function SkinMinimalScrollBar(bar)
    local track, thumb = bar.Track, bar.Track.Thumb

    if track.Begin then
      track.Begin:Hide()
      track.Middle:Hide()
      track.End:Hide()
    end
    if bar.Background then
      StripTextures(bar)
      bar.Background:Hide()
    end
    for _, stepper in ipairs({ bar.Back, bar.Forward }) do
      stepper.Texture:Hide()
      if stepper.Overlay then stepper.Overlay:SetAlpha(0) end
    end
    SkinArrowButton(bar.Back, "up")
    SkinArrowButton(bar.Forward, "down")

    thumb.Begin:Hide()
    thumb.Middle:Hide()
    thumb.End:Hide()
    if thumb.thumbTexture then thumb.thumbTexture:Hide() end

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

  -- the category list pools its rows, and its group headers and spacers have
  -- no toggle. On every state change a row sets the art of its hover and
  -- selection highlight (an atlas in newer ClassicAPI, a file in older
  -- versions), and swaps the toggle's art: open/closed atlases, or older
  -- versions' minus/plus files
  local function SkinCategoryRow(_, row)
    if row.skinned or not row.Toggle then return end
    row.skinned = true

    local function Highlight(self)
      self:SetColorTexture(cr, cg, cb, .25)
      self:SetAllPoints(row)
    end
    row.Texture.SetAtlas = Highlight
    row.Texture.SetTexture = Highlight

    SkinCollapseButton(row.Toggle)
    row.Toggle.SetNormalTexture = function(self, tex)
      local open = tex and (strfind(tex, "open") or strfind(tex, "MinusButton"))
      self.icon.text:SetText(open and "-" or "+")
      self.icon:Show()
    end
    row.Toggle.icon:ClearAllPoints()
    row.Toggle.icon:SetPoint("CENTER", 0, 0)
    row.Toggle:SetPushedTexture("")
    row.Toggle:SetHighlightTexture("")
    row.Toggle.SetPushedTexture = nop
  end

  local panel = SettingsPanel
  local list = panel:GetCategoryList()
  local settingsList = panel:GetSettingsList()

  -- ClassicAPI draws the window with a background (Bg: retail's flat panel
  -- frame, or a dark fill in older versions) and a NineSlice frame holding
  -- the border and the title
  panel.Bg:Hide()
  StripTextures(panel.NineSlice)
  CreateBackdrop(panel, nil, nil, .75)
  CreateBackdropShadow(panel)
  SkinCloseButton(panel.ClosePanelButton, panel.backdrop, -6, -6)

  -- and frames the category list and the settings: newer ClassicAPI with
  -- retail's inner frame atlas (an unnamed texture on the panel), older
  -- versions with a border frame each
  if panel.CategoryListBorder then
    CreateBackdrop(panel.CategoryListBorder, nil, true, .75)
    CreateBackdrop(panel.ContainerBorder, nil, true, .75)
  else
    for _, region in ipairs({ panel:GetRegions() }) do
      if region.GetAtlas and region:GetAtlas() == "Options_InnerFrame" then
        region:Hide()
      end
    end
    CreateBackdrop(list, nil, true, .75)
    CreateBackdrop(panel.Container, nil, true, .75)
  end
  SkinMinimalScrollBar(list.ScrollBar)
  SkinMinimalScrollBar(settingsList.ScrollBar)

  -- MinimalTab sets its three pieces again on every state change. Newer
  -- ClassicAPI draws retail's tab: art 23 pixels tall along the bottom of the
  -- 37 pixel button, with the text near the bottom, so the backdrop covers
  -- only that strip. Older versions centre the text on the whole button
  for _, tab in ipairs({ panel.GameTab, panel.AddOnsTab }) do
    tab.Left:Hide()
    tab.Middle:Hide()
    tab.Right:Hide()
    if tab.selectedLeftTexture then
      CreateBackdrop(tab)
      tab.backdrop:ClearAllPoints()
      tab.backdrop:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
      tab.backdrop:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
      tab.backdrop:SetHeight(23)
    else
      CreateBackdrop(tab, nil, true)
    end
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

    -- the dropdown sets its art again on every state change: WowStyle2's
    -- background and arrow atlases, or the older WowStyle1 stand-in's three
    -- label pieces and arrow
    if dropdown.Background then dropdown.Background:SetAlpha(0) end
    if dropdown.Left then
      dropdown.Left:Hide()
      dropdown.Middle:Hide()
      dropdown.Right:Hide()
    end
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

    -- WowStyle2IconButtonTemplate steppers set their background and icon
    -- atlases again on every state change; the older steppers have neither
    for _, stepper in ipairs({ control.DecrementButton, control.IncrementButton }) do
      if stepper.Background then stepper.Background:SetAlpha(0) end
      if stepper.Icon then stepper.Icon:SetAlpha(0) end
    end
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
      -- newer ClassicAPI draws retail's bar, three atlas pieces, with the
      -- slider spanning the row's height, so it is anchored by its sides
      -- alone for SkinSlider's height. Older versions draw a backdrop bar
      local slider = row.SliderWithSteppers.Slider
      if slider.Left then
        slider.Left:Hide()
        slider.Middle:Hide()
        slider.Right:Hide()
        slider:ClearAllPoints()
        slider:SetPoint("LEFT", 19, 0)
        slider:SetPoint("RIGHT", -19, 0)
      end
      SkinSlider(slider)
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
