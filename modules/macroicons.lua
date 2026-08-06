-- Macro icon picker
-- Replaces Blizzard's MacroPopupFrame (the "name + icon" dialog opened by the
-- New / Change-Icon buttons) with a pfUI-native picker driven by
-- IconDataProviderMixin, so the full spell + item + loose icon set is
-- available instead of the stock spell-only list. Saving goes through
-- C_Macro.CreateMacro / C_Macro.EditMacro, which take the icon as a texture
-- string -- so arbitrary icons (including index-less INV_* item icons) persist
-- on both the modern (Turtle/Octo) and stock-vanilla macro UIs. The surrounding
-- MacroFrame (list + body editor) is Blizzard's, already skinned elsewhere.
if not C_Macro or not C_Macro.CreateMacro then return end
pfUI:RegisterModule("macroicons", function ()
  HookAddonOrVariable("Blizzard_MacroUI", function()
    local QUESTION_MARK = "INTERFACE\\ICONS\\INV_MISC_QUESTIONMARK"

    local ICON_GRID_COLS = 10
    local ICON_GRID_ROWS = 8
    local ICON_BTN_SIZE  = 36
    local ICON_BTN_PAD   = 6

    -- Shared picker state (forward-declared so the grid/filter closures below
    -- can capture them before RefreshIconGrid is assigned).
    local provider = nil
    local selectedIconPath = QUESTION_MARK
    local currentFilter = "all"
    local searchText = ""
    local filtered = nil  -- provider indices matching the search, or nil when empty
    local RefreshIconGrid, RebuildFilter

    local function EnsureProvider()
      if not provider then
        -- Spellbook extra type leads with class-relevant spell/talent icons.
        provider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook)
      end
    end

    -- ============================================================
    -- Popup frame
    -- ============================================================

    local picker = CreateFrame("Frame", "pfMacroIconPicker", UIParent)
    picker:SetFrameStrata("DIALOG")
    picker:SetSize(472, 484)
    -- Starts anchored to the right of the macro panel (re-anchored at open
    -- once the skin's backdrop exists); dragging pins it in place after.
    picker:SetPoint("BOTTOMLEFT", MacroFrame, "BOTTOMRIGHT", 8, 0)
    picker:Hide()
    CreateBackdrop(picker, nil, nil, .9)
    CreateBackdropShadow(picker)
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", function() this:StartMoving() end)
    picker:SetScript("OnDragStop", function()
      this:StopMovingOrSizing()
      this.userMoved = true
    end)

    picker.nameLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    picker.nameLabel:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -20)
    picker.nameLabel:SetText(MACRO_POPUP_TEXT)

    picker.editbox = CreateFrame("EditBox", "pfMacroIconPickerName", picker, "InputBoxTemplate")
    picker.editbox:SetSize(280, 20)
    picker.editbox:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -38)
    picker.editbox:SetAutoFocus(false)
    picker.editbox:SetMaxLetters(16)
    CreateBackdrop(picker.editbox)

    picker.selectedPreview = CreateFrame("Frame", nil, picker)
    picker.selectedPreview:SetSize(42, 42)
    picker.selectedPreview:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -14, -30)
    CreateBackdrop(picker.selectedPreview)
    picker.selectedPreview.tex = picker.selectedPreview:CreateTexture(nil, "ARTWORK")
    picker.selectedPreview.tex:SetAllPoints(picker.selectedPreview)
    picker.selectedPreview.tex:SetTexCoord(.08, .92, .08, .92)

    picker.selectedLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    picker.selectedLabel:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -14, -14)
    picker.selectedLabel:SetText(ICON_SELECTION_TITLE_CURRENT)
    picker.selectedLabel:SetTextColor(1, 0.82, 0)

    picker.iconLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    picker.iconLabel:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -86)
    picker.iconLabel:SetText(MACRO_POPUP_CHOOSE_ICON)

    -- Icon grid + scroll
    local iconScroll = CreateFrame("ScrollFrame", "pfMacroIconScroll", picker, "FauxScrollFrameTemplate")
    iconScroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -116)
    iconScroll:SetWidth(ICON_GRID_COLS * (ICON_BTN_SIZE + ICON_BTN_PAD) - ICON_BTN_PAD)
    iconScroll:SetHeight(ICON_GRID_ROWS * (ICON_BTN_SIZE + ICON_BTN_PAD) - ICON_BTN_PAD)

    local scrollbar = _G["pfMacroIconScrollScrollBar"]
    scrollbar:ClearAllPoints()
    scrollbar:SetPoint("TOPLEFT", iconScroll, "TOPRIGHT", 8, -16)
    scrollbar:SetPoint("BOTTOMLEFT", iconScroll, "BOTTOMRIGHT", 8, 16)
    SkinScrollbar(scrollbar)

    -- Filter dropdown: All / Spells / Items
    local filterDropdown = CreateFrame("Frame", "pfMacroIconFilter", picker, "UIDropDownMenuTemplate")
    filterDropdown:SetPoint("TOPRIGHT", picker, "TOPRIGHT", 0, -80)
    local function ApplyFilter(value)
      currentFilter = value
      UIDropDownMenu_SetSelectedValue(filterDropdown, value)
      if provider then
        if value == "spells" then provider:SetIconTypes({ IconDataProviderIconType.Spell })
        elseif value == "items" then provider:SetIconTypes({ IconDataProviderIconType.Item })
        else provider:SetIconTypes(nil) end
        RebuildFilter()
        RefreshIconGrid()
      end
    end
    UIDropDownMenu_Initialize(filterDropdown, function()
      local info
      info = {}; info.text = ICON_FILTER_ALL; info.value = "all"
      info.func = function() ApplyFilter("all") end
      info.checked = currentFilter == "all"
      UIDropDownMenu_AddButton(info)
      info = {}; info.text = ICON_FILTER_SPELL; info.value = "spells"
      info.func = function() ApplyFilter("spells") end
      info.checked = currentFilter == "spells"
      UIDropDownMenu_AddButton(info)
      info = {}; info.text = ICON_FILTER_ITEM; info.value = "items"
      info.func = function() ApplyFilter("items") end
      info.checked = currentFilter == "items"
      UIDropDownMenu_AddButton(info)
    end)
    UIDropDownMenu_SetWidth(120, filterDropdown)
    UIDropDownMenu_SetSelectedValue(filterDropdown, "all")
    SkinDropDown(filterDropdown)

    local iconButtons = {}
    for r = 1, ICON_GRID_ROWS do
      for c = 1, ICON_GRID_COLS do
        local i = (r - 1) * ICON_GRID_COLS + c
        local btn = CreateFrame("Button", nil, picker)
        btn:SetSize(ICON_BTN_SIZE, ICON_BTN_SIZE)
        btn:SetPoint("TOPLEFT", iconScroll, "TOPLEFT", (c-1) * (ICON_BTN_SIZE + ICON_BTN_PAD), -(r-1) * (ICON_BTN_SIZE + ICON_BTN_PAD))
        CreateBackdrop(btn)
        btn.texture = btn:CreateTexture(nil, "ARTWORK")
        btn.texture:SetAllPoints(btn)
        btn.texture:SetTexCoord(.08, .92, .08, .92)
        btn:SetScript("OnClick", function()
          if this.iconIndex and provider then
            local path = provider:GetIconByIndex(this.iconIndex)
            if path then selectedIconPath = path end
            RefreshIconGrid()
          end
        end)
        btn:SetScript("OnEnter", function()
          if not this.iconIndex or not provider then return end
          local path = provider:GetIconByIndex(this.iconIndex)
          if type(path) == "string" then
            local name = string.gsub(path, "^.-INTERFACE\\\\ICONS\\\\", "")
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(name)
            GameTooltip:Show()
          end
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
        iconButtons[i] = btn
      end
    end

    -- Normalize a texture to an uppercase basename so selection matching
    -- works across sources: GetMacroInfo returns "Interface\Icons\<name>"
    -- while provider paths are uppercase-prefixed for base icons and
    -- mixed-case for spellbook extras.
    local function IconKey(path)
      if type(path) ~= "string" then return path end
      return string.gsub(string.upper(path), "^.*[\\/]", "")
    end

    -- Rebuild the search-filtered index list (provider indices whose icon
    -- basename contains the search text); nil when the search box is empty.
    function RebuildFilter()
      EnsureProvider()
      if searchText == "" then
        filtered = nil
        return
      end
      filtered = {}
      for i = 1, provider:GetNumIcons() do
        local path = provider:GetIconByIndex(i)
        if type(path) == "string" and string.find(IconKey(path), searchText, 1, true) then
          table.insert(filtered, i)
        end
      end
    end

    function RefreshIconGrid()
      EnsureProvider()
      local numIcons = filtered and table.getn(filtered) or provider:GetNumIcons()
      local numRows = math.ceil(numIcons / ICON_GRID_COLS)
      FauxScrollFrame_Update(iconScroll, numRows, ICON_GRID_ROWS, ICON_BTN_SIZE + ICON_BTN_PAD)
      local offset = FauxScrollFrame_GetOffset(iconScroll)
      for i = 1, ICON_GRID_ROWS * ICON_GRID_COLS do
        local listIdx = i + offset * ICON_GRID_COLS
        local btn = iconButtons[i]
        if listIdx <= numIcons then
          btn:Show()
          local providerIdx = filtered and filtered[listIdx] or listIdx
          btn.iconIndex = providerIdx
          local path = provider:GetIconByIndex(providerIdx)
          btn.texture:SetTexture(path)
          if IconKey(path) == IconKey(selectedIconPath) then
            btn.backdrop:SetBackdropBorderColor(1, 0.82, 0, 1)
          else
            btn.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
          end
        else
          btn:Hide()
          btn.iconIndex = nil
        end
      end
      picker.selectedPreview.tex:SetTexture(selectedIconPath)
    end

    iconScroll:SetScript("OnVerticalScroll", function()
      FauxScrollFrame_OnVerticalScroll(ICON_BTN_SIZE + ICON_BTN_PAD, function() RefreshIconGrid() end)
    end)

    -- ============================================================
    -- Open / save
    -- ============================================================

    -- Blizzard's popup disables these while it is open; mirror that so the
    -- underlying frame can't be double-driven, then let MacroFrame_Update
    -- restore the correct states on close.
    local function SetMacroButtons(enabled)
      local m = enabled and "Enable" or "Disable"
      MacroNewButton[m](MacroNewButton)
      MacroEditButton[m](MacroEditButton)
      MacroDeleteButton[m](MacroDeleteButton)
    end

    local function OpenMacroPopup(mode)
      if mode == "edit" and MacroFrame.selectedMacro then
        picker.mode = "edit"
        local name, texture = GetMacroInfo(MacroFrame.selectedMacro)
        picker.editbox:SetText(name or "")
        selectedIconPath = texture or QUESTION_MARK
      else
        picker.mode = "new"
        picker.editbox:SetText("")
        selectedIconPath = QUESTION_MARK
      end
      picker.search:SetText("")
      if not picker.userMoved then
        picker:ClearAllPoints()
        picker:SetPoint("BOTTOMLEFT", MacroFrame.backdrop or MacroFrame, "BOTTOMRIGHT", 8, 0)
      end
      SetMacroButtons(false)
      picker:Show()
      picker.editbox:SetFocus()
      RefreshIconGrid()
    end

    local function SaveMacroPopup()
      local text = strtrim(picker.editbox:GetText())
      if text == "" then return end

      if picker.mode == "edit" and MacroFrame.selectedMacro then
        C_Macro.EditMacro(MacroFrame.selectedMacro, text, selectedIconPath, nil)
        MacroFrame_SelectMacro(MacroFrame.selectedMacro)
      else
        local idx = C_Macro.CreateMacro(text, selectedIconPath, nil, (MacroFrame.macroBase or 0) > 0)
        if idx then MacroFrame_SelectMacro(idx) end
      end
      picker:Hide()
    end

    picker:SetScript("OnHide", function()
      if provider then provider:Release(); provider = nil end
      MacroFrame_Update()
    end)

    picker.editbox:SetScript("OnEnterPressed", SaveMacroPopup)
    picker.editbox:SetScript("OnEscapePressed", function() picker:Hide() end)

    -- OK / Cancel
    local okay = CreateFrame("Button", "pfMacroIconPickerOkay", picker, "UIPanelButtonTemplate")
    okay:SetSize(80, 22)
    okay:SetText(OKAY)
    okay:SetScript("OnClick", SaveMacroPopup)
    SkinButton(okay)

    local cancel = CreateFrame("Button", "pfMacroIconPickerCancel", picker, "UIPanelButtonTemplate")
    cancel:SetSize(80, 22)
    cancel:SetText(CANCEL)
    cancel:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -14, 12)
    cancel:SetScript("OnClick", function() picker:Hide() end)
    SkinButton(cancel)

    -- Okay | Cancel, both anchored to the bottom-right corner.
    okay:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -6, 0)

    -- Search box (bottom-left) filters the grid by icon name.
    picker.searchLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    picker.searchLabel:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 16, 18)
    picker.searchLabel:SetText(SEARCH)

    picker.search = CreateFrame("EditBox", "pfMacroIconSearch", picker, "InputBoxTemplate")
    picker.search:SetSize(180, 20)
    picker.search:SetPoint("LEFT", picker.searchLabel, "RIGHT", 10, 0)
    picker.search:SetAutoFocus(false)
    CreateBackdrop(picker.search)
    picker.search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    picker.search:SetScript("OnTextChanged", function()
      searchText = strupper(strtrim(this:GetText()))
      RebuildFilter()
      scrollbar:SetValue(0)
      RefreshIconGrid()
    end)

    -- ============================================================
    -- Take over the New / Change-Icon buttons; retire Blizzard's popup
    -- ============================================================

    MacroNewButton:SetScript("OnClick", function()
      MacroFrame_SaveMacro()
      OpenMacroPopup("new")
    end)

    MacroEditButton:SetScript("OnClick", function()
      MacroFrame_SaveMacro()
      OpenMacroPopup("edit")
    end)

    -- Closing the macro window takes the picker with it.
    MacroFrame:HookScript("OnHide", function() picker:Hide() end)
  end)
end)
