-- Macro icon picker
-- Replaces Blizzard's MacroPopupFrame (the "name + icon" dialog opened by the
-- New / Change-Icon buttons) with a pfUI-native picker driven by
-- IconDataProviderMixin, so the full spell + item + loose icon set is
-- available instead of the stock spell-only list. Saving goes through
-- C_Macro.CreateMacro / C_Macro.EditMacro, which take the icon as a texture
-- string -- so arbitrary icons (including index-less INV_* item icons) persist
-- on both the modern (Turtle/Octo) and stock-vanilla macro UIs. The surrounding
-- MacroFrame (list + body editor) is Blizzard's, already skinned elsewhere.
pfUI:RegisterModule("macroicons", function ()
  HookAddonOrVariable("Blizzard_MacroUI", function()
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

    -- Spellbook seed leads the grid with class-relevant spell/talent icons.
    local iconPicker = CreateIconPicker("pfMacroIcon", picker,
                                        IconDataProviderExtraType.Spellbook, MACRO_POPUP_TEXT)

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
        iconPicker.SetIcon(texture)
      else
        picker.mode = "new"
        picker.editbox:SetText("")
        iconPicker.SetIcon(nil)
      end
      picker.search:SetText("")
      if not picker.userMoved then
        picker:ClearAllPoints()
        picker:SetPoint("BOTTOMLEFT", MacroFrame.backdrop or MacroFrame, "BOTTOMRIGHT", 8, 0)
      end
      SetMacroButtons(false)
      picker:Show()
      picker.editbox:SetFocus()
      iconPicker.Refresh()
    end

    local function SaveMacroPopup()
      local text = picker.editbox:GetText()
      if text == "" then return end

      local icon = iconPicker.GetIcon()
      if picker.mode == "edit" and MacroFrame.selectedMacro then
        C_Macro.EditMacro(MacroFrame.selectedMacro, text, icon, nil)
        MacroFrame_SelectMacro(MacroFrame.selectedMacro)
      else
        local idx = C_Macro.CreateMacro(text, icon, nil, (MacroFrame.macroBase or 0) > 0)
        if idx then MacroFrame_SelectMacro(idx) end
      end
      picker:Hide()
    end

    picker:SetScript("OnHide", function() MacroFrame_Update() end)

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
