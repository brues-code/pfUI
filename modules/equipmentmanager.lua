-- Equipment Manager module
-- Backport of the 4.3.4 GearManagerDialog UI on top of ClassicAPI's
-- C_EquipmentSet.* API. Adds a 6th tab to CharacterFrame.

pfUI:RegisterModule("equipmentmanager", function()
  if not C_EquipmentSet or not C_EquipmentSet.CanUseEquipmentSets() then return end

  pfUI.equipmentmanager = pfUI.equipmentmanager or {}

  local MAX_EQUIPMENT_SETS_PER_PLAYER = 10
  local NUM_LE_EQUIPMENT_SETS_MAX_ROWS = MAX_EQUIPMENT_SETS_PER_PLAYER
  local SET_ROW_HEIGHT = 36

  local rawborder, border = GetBorderSize()
  local selectedSetID = nil
  local pendingAction = nil  -- "new" | "save" | "rename" — what the popups apply to
  local slotOverlays = {}    -- [invSlotID] = ignored-overlay texture on the character slot
  local popoutButtons = {}   -- popout arrow buttons; toggled with the EM frame

  -- Pending ignored-slot toggles per set. A slotID in this table means
  -- the effective state for that slot is FLIPPED from what's persisted.
  -- Committed when the user clicks Save; cleared when a set is deleted.
  -- Declared here (not nearer the helpers below) so the Save / Delete
  -- closures created earlier in the module can capture them as upvalues.
  local pendingIgnoredToggles = {}

  local function GetEffectiveIgnored(setID)
    local result = {}
    if not setID then return result end
    local persistent = C_EquipmentSet.GetIgnoredSlots(setID) or {}
    for _, s in ipairs(persistent) do result[s] = true end
    local pending = pendingIgnoredToggles[setID]
    if pending then
      for slotID in pairs(pending) do
        if result[slotID] then result[slotID] = nil else result[slotID] = true end
      end
    end
    return result
  end

  local function ToggleIgnoredForSet(setID, slotID)
    if not setID then return end
    pendingIgnoredToggles[setID] = pendingIgnoredToggles[setID] or {}
    if pendingIgnoredToggles[setID][slotID] then
      pendingIgnoredToggles[setID][slotID] = nil
    else
      pendingIgnoredToggles[setID][slotID] = true
    end
  end

  -- Swap a popout's chevron between closed (points away from slot) and
  -- reversed (points toward slot — indicates "flyout is open").
  local function SetPopoutReversed(popout, reversed)
    if not popout then return end
    local nc = reversed and popout.coordReversed or popout.coordNormal
    local hc = reversed and popout.coordReversedHi or popout.coordNormalHi
    popout:GetNormalTexture():SetTexCoord(unpack(nc))
    popout:GetHighlightTexture():SetTexCoord(unpack(hc))
  end

  -- Shared by the Equip button and set-row double-click.
  local function EquipSet(setID)
    if not setID then return end
    if C_EquipmentSet.EquipmentSetContainsLockedItems(setID) then
      UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT or "Locked items in set", 1, .1, .1, 1)
      return
    end
    ClearCursor()
    C_EquipmentSet.UseEquipmentSet(setID)
  end

  -- ============================================================
  -- Main content frame: opens as a sidecar to the right of CharacterFrame
  -- (matches ReputationDetailFrame's positioning pattern).
  -- ============================================================

  local frame = CreateFrame("Frame", "pfEquipmentManagerFrame", CharacterFrame)
  frame:SetWidth(220)
  frame:SetHeight(350)
  frame:SetFrameStrata("HIGH")
  frame:SetScript("OnShow", function()
    this:ClearAllPoints()
    if CharacterFrame.backdrop then
      frame:SetPoint("TOPLEFT", CharacterFrame.backdrop, "TOPRIGHT", 2*border, -2)
    else
      frame:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 0, 0)
    end
  end)
  CreateBackdrop(frame, nil, nil, .9)
  CreateBackdropShadow(frame)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -10)
  frame.title:SetText(T["Equipment Manager"] or "Equipment Manager")

  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  if SkinCloseButton then SkinCloseButton(closeBtn, frame.backdrop or frame, -6, -6) end

  -- ============================================================
  -- Toggle button on character pane (above the Hands slot)
  -- ============================================================

  local toggleBtn = CreateFrame("Button", "pfEqMgrToggleButton", PaperDollFrame)
  toggleBtn:SetWidth(28)
  toggleBtn:SetHeight(28)
  toggleBtn:SetPoint("BOTTOM", CharacterHandsSlot, "TOP", 0, 4)
  toggleBtn:SetNormalTexture("Interface\\AddOns\\pfUI\\img\\UI-GearManager-Button")
  toggleBtn:SetPushedTexture("Interface\\AddOns\\pfUI\\img\\UI-GearManager-Button-Pushed")
  toggleBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  toggleBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(T["Equipment Manager"] or "Equipment Manager")
    GameTooltip:Show()
  end)
  toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  toggleBtn:SetScript("OnClick", function()
    if frame:IsShown() then
      frame:Hide()
    else
      frame:Show()
      pfUI.equipmentmanager.Refresh()
    end
  end)

  -- ============================================================
  -- Forward declaration: OpenNamePopup is defined later, but referenced
  -- by the row context menu and the "+ New Set" row created earlier.
  -- ============================================================
  local OpenNamePopup

  -- ============================================================
  -- Equip + Save buttons (top of list area)
  -- ============================================================

  local btnEquip = CreateFrame("Button", "pfEqMgrEquip", frame, "UIPanelButtonTemplate")
  btnEquip:SetWidth(86); btnEquip:SetHeight(22); btnEquip:SetText(T["Equip"] or "Equip")
  btnEquip:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -30)
  SkinButton(btnEquip)
  btnEquip:SetScript("OnClick", function() EquipSet(selectedSetID) end)

  local btnSave = CreateFrame("Button", "pfEqMgrSave", frame, "UIPanelButtonTemplate")
  btnSave:SetWidth(86); btnSave:SetHeight(22); btnSave:SetText(T["Save"] or "Save")
  btnSave:SetPoint("LEFT", btnEquip, "RIGHT", 6, 0)
  SkinButton(btnSave)
  btnSave:SetScript("OnClick", function()
    if not selectedSetID then return end
    local name, icon = C_EquipmentSet.GetEquipmentSetInfo(selectedSetID)
    if not name then return end
    local targetID = selectedSetID
    StaticPopupDialogs["PFUI_EQMGR_SAVE_CONFIRM"] = {
      text = string.format(T["Would you like to save the equipment set '%s'?"] or "Would you like to save the equipment set '%s'?", name),
      button1 = YES, button2 = NO,
      OnAccept = function()
        -- Direct save: keep existing name + icon, commit pending ignored toggles.
        C_EquipmentSet.ClearIgnoredSlotsForSave()
        local effective = GetEffectiveIgnored(targetID)
        for slotID in pairs(effective) do
          C_EquipmentSet.IgnoreSlotForSave(slotID)
        end
        C_EquipmentSet.SaveEquipmentSet(targetID, icon)
        C_EquipmentSet.ClearIgnoredSlotsForSave()
        pendingIgnoredToggles[targetID] = nil
        pfUI.equipmentmanager.Refresh()
      end,
      timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
    }
    StaticPopup_Show("PFUI_EQMGR_SAVE_CONFIRM")
  end)

  -- ============================================================
  -- Per-row context menu (single instance, repositioned per click).
  -- Triggered by the gear icon on each set row.
  -- ============================================================

  local rowMenu = CreateFrame("Frame", "pfEqMgrRowMenu", UIParent)
  rowMenu:SetFrameStrata("DIALOG")
  rowMenu:SetWidth(140); rowMenu:SetHeight(50)
  rowMenu:Hide()
  CreateBackdrop(rowMenu, nil, nil, .95)
  CreateBackdropShadow(rowMenu)
  rowMenu:EnableMouse(true)
  rowMenu:SetScript("OnLeave", function() this:Hide() end)

  rowMenu.changeBtn = CreateFrame("Button", nil, rowMenu, "UIPanelButtonTemplate")
  rowMenu.changeBtn:SetWidth(130); rowMenu.changeBtn:SetHeight(20)
  rowMenu.changeBtn:SetPoint("TOPLEFT", rowMenu, "TOPLEFT", 5, -3)
  rowMenu.changeBtn:SetText(T["Change Name/Icon"] or "Change Name/Icon")
  SkinButton(rowMenu.changeBtn)
  rowMenu.changeBtn:SetScript("OnClick", function()
    rowMenu:Hide()
    if not rowMenu.targetSetID then return end
    local name, icon = C_EquipmentSet.GetEquipmentSetInfo(rowMenu.targetSetID)
    selectedSetID = rowMenu.targetSetID
    OpenNamePopup("save", name, icon)
  end)

  rowMenu.deleteBtn = CreateFrame("Button", nil, rowMenu, "UIPanelButtonTemplate")
  rowMenu.deleteBtn:SetWidth(130); rowMenu.deleteBtn:SetHeight(20)
  rowMenu.deleteBtn:SetPoint("TOP", rowMenu.changeBtn, "BOTTOM", 0, -2)
  rowMenu.deleteBtn:SetText(T["Delete"] or "Delete")
  SkinButton(rowMenu.deleteBtn)
  rowMenu.deleteBtn:SetScript("OnClick", function()
    rowMenu:Hide()
    if not rowMenu.targetSetID then return end
    local targetID = rowMenu.targetSetID
    local name = C_EquipmentSet.GetEquipmentSetInfo(targetID)
    StaticPopupDialogs["PFUI_EQMGR_DELETE"] = {
      text = string.format(T["Delete equipment set '%s'?"] or "Delete equipment set '%s'?", name or "?"),
      button1 = YES, button2 = NO,
      OnAccept = function()
        pendingIgnoredToggles[targetID] = nil
        C_EquipmentSet.DeleteEquipmentSet(targetID)
        if selectedSetID == targetID then selectedSetID = nil end
        pfUI.equipmentmanager.Refresh()
      end,
      timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
    }
    StaticPopup_Show("PFUI_EQMGR_DELETE")
  end)

  -- ============================================================
  -- Set list (left column)
  -- ============================================================

  local LIST_VISIBLE_ROWS = 8
  local listFrame = CreateFrame("Frame", nil, frame)
  listFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -58)
  listFrame:SetWidth(180)
  listFrame:SetHeight(SET_ROW_HEIGHT * LIST_VISIBLE_ROWS + 4)
  CreateBackdrop(listFrame, nil, nil, .75)

  local setRows = {}
  local function CreateSetRow(i)
    local row = CreateFrame("Button", nil, listFrame)
    row:SetWidth(170)
    row:SetHeight(SET_ROW_HEIGHT)
    if i == 1 then
      row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 5, -3)
    else
      row:SetPoint("TOPLEFT", setRows[i-1], "BOTTOMLEFT", 0, -2)
    end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(30)
    row.icon:SetHeight(30)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(.08, .92, .08, .92)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row.text:SetJustifyH("LEFT")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture(.3, .3, .3, .4)
    row.highlight:Hide()

    -- Gear icon (hidden by default, shown while the row is hovered).
    -- Clicking it opens the row context menu (Change Name/Icon / Delete).
    row.gear = CreateFrame("Button", nil, row)
    row.gear:SetWidth(16); row.gear:SetHeight(16)
    row.gear:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.gear.tex = row.gear:CreateTexture(nil, "ARTWORK")
    row.gear.tex:SetAllPoints(row.gear)
    row.gear.tex:SetTexture("Interface\\AddOns\\pfUI\\img\\Gear_64Grey")
    row.gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row.gear:Hide()
    row.gear:SetScript("OnClick", function()
      if not row.setID then return end
      rowMenu.targetSetID = row.setID
      rowMenu:ClearAllPoints()
      rowMenu:SetPoint("TOPLEFT", row.gear, "BOTTOMRIGHT", 0, 0)
      rowMenu:Show()
    end)

    row:SetScript("OnClick", function()
      selectedSetID = row.setID
      -- Detect double-click manually; vanilla Button has no native event.
      local now = GetTime()
      if row.lastClick and (now - row.lastClick) < 0.4 then
        row.lastClick = nil
        EquipSet(row.setID)
      else
        row.lastClick = now
      end
      pfUI.equipmentmanager.Refresh()
    end)

    row:SetScript("OnEnter", function()
      if this.setID then
        local name = C_EquipmentSet.GetEquipmentSetInfo(this.setID)
        if name then
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetEquipmentSet(name)
          GameTooltip:Show()
        end
        row.gear:Show()
      end
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
      row.gear:Hide()
    end)

    return row
  end

  for i = 1, NUM_LE_EQUIPMENT_SETS_MAX_ROWS do
    setRows[i] = CreateSetRow(i)
  end

  -- "+ New Set" pseudo-row: appears after the last set in the list,
  -- click to open the New set popup.
  local newSetRow = CreateFrame("Button", nil, listFrame)
  newSetRow:SetWidth(170); newSetRow:SetHeight(SET_ROW_HEIGHT)

  newSetRow.icon = newSetRow:CreateTexture(nil, "ARTWORK")
  newSetRow.icon:SetWidth(24); newSetRow.icon:SetHeight(24)
  newSetRow.icon:SetPoint("LEFT", newSetRow, "LEFT", 5, 0)
  newSetRow.icon:SetTexture("Interface\\AddOns\\pfUI\\img\\Character-Plus")

  newSetRow.text = newSetRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  newSetRow.text:SetPoint("LEFT", newSetRow.icon, "RIGHT", 8, 0)
  newSetRow.text:SetPoint("RIGHT", newSetRow, "RIGHT", -4, 0)
  newSetRow.text:SetJustifyH("LEFT")
  newSetRow.text:SetText(T["New Set"] or "New Set")
  newSetRow.text:SetTextColor(0.2, 1, 0.2)

  newSetRow.highlight = newSetRow:CreateTexture(nil, "BACKGROUND")
  newSetRow.highlight:SetAllPoints(newSetRow)
  newSetRow.highlight:SetTexture(.3, .3, .3, .4)
  newSetRow.highlight:Hide()
  newSetRow:SetScript("OnEnter", function() newSetRow.highlight:Show() end)
  newSetRow:SetScript("OnLeave", function() newSetRow.highlight:Hide() end)
  newSetRow:SetScript("OnClick", function() OpenNamePopup("new") end)

  -- ============================================================
  -- Helper used by the name popup (defined later)
  -- ============================================================

  local function MakeButton(name, label, parent, anchor, ax, ay, width)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(width or 70)
    b:SetHeight(22)
    b:SetText(label)
    b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", ax, ay)
    SkinButton(b)
    return b
  end

  -- Equip / Save buttons + per-row context menu replace the old bottom
  -- button stack. Delete and Change Name/Icon live in the row gear menu.

  -- ============================================================
  -- Name/icon entry popup
  -- ============================================================

  local namePopup = CreateFrame("Frame", "pfEqMgrNamePopup", UIParent)
  namePopup:SetFrameStrata("DIALOG")
  namePopup:SetWidth(472)
  namePopup:SetHeight(498)
  namePopup:SetPoint("CENTER", UIParent, "CENTER")
  namePopup:Hide()
  CreateBackdrop(namePopup, nil, nil, .9)
  CreateBackdropShadow(namePopup)
  namePopup:EnableMouse(true)
  namePopup:SetMovable(true)
  namePopup:RegisterForDrag("LeftButton")
  namePopup:SetScript("OnDragStart", function() this:StartMoving() end)
  namePopup:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  namePopup.title = namePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  namePopup.title:SetPoint("TOP", namePopup, "TOP", 0, -10)
  namePopup.title:SetText(T["Save Set"] or "Save Set")

  -- Name label + EditBox (left side)
  namePopup.nameLabel = namePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  namePopup.nameLabel:SetPoint("TOPLEFT", namePopup, "TOPLEFT", 14, -34)
  namePopup.nameLabel:SetText(T["Enter Set Name (Max 16 Characters):"] or "Enter Set Name (Max 16 Characters):")

  namePopup.editbox = CreateFrame("EditBox", "pfEqMgrNameEdit", namePopup, "InputBoxTemplate")
  namePopup.editbox:SetWidth(280)
  namePopup.editbox:SetHeight(20)
  namePopup.editbox:SetPoint("TOPLEFT", namePopup, "TOPLEFT", 14, -52)
  namePopup.editbox:SetAutoFocus(false)
  namePopup.editbox:SetMaxLetters(16)
  CreateBackdrop(namePopup.editbox)

  -- Currently Selected preview (top right)
  namePopup.selectedLabel = namePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  namePopup.selectedLabel:SetPoint("TOPRIGHT", namePopup, "TOPRIGHT", -14, -28)
  namePopup.selectedLabel:SetText(T["Currently Selected"] or "Currently Selected")
  namePopup.selectedLabel:SetTextColor(1, 0.82, 0)

  namePopup.selectedPreview = CreateFrame("Frame", nil, namePopup)
  namePopup.selectedPreview:SetWidth(42)
  namePopup.selectedPreview:SetHeight(42)
  namePopup.selectedPreview:SetPoint("TOPRIGHT", namePopup, "TOPRIGHT", -14, -44)
  CreateBackdrop(namePopup.selectedPreview)
  namePopup.selectedPreview.tex = namePopup.selectedPreview:CreateTexture(nil, "ARTWORK")
  namePopup.selectedPreview.tex:SetAllPoints(namePopup.selectedPreview)
  namePopup.selectedPreview.tex:SetTexCoord(.08, .92, .08, .92)

  -- "Choose an Icon:" label
  namePopup.iconLabel = namePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  namePopup.iconLabel:SetPoint("TOPLEFT", namePopup, "TOPLEFT", 14, -100)
  namePopup.iconLabel:SetText(T["Choose an Icon:"] or "Choose an Icon:")

  -- Icon picker: 10×8 grid of buttons + scroll
  local ICON_GRID_COLS = 10
  local ICON_GRID_ROWS = 8
  local ICON_BTN_SIZE = 36
  local ICON_BTN_PAD = 6

  local iconScroll = CreateFrame("ScrollFrame", "pfEqMgrIconScroll", namePopup, "FauxScrollFrameTemplate")
  iconScroll:SetPoint("TOPLEFT", namePopup, "TOPLEFT", 14, -130)
  iconScroll:SetWidth(ICON_GRID_COLS * (ICON_BTN_SIZE + ICON_BTN_PAD) - ICON_BTN_PAD)
  iconScroll:SetHeight(ICON_GRID_ROWS * (ICON_BTN_SIZE + ICON_BTN_PAD) - ICON_BTN_PAD)

  -- IconDataProviderMixin owns the icon DB, dedup, lazy load, and
  -- prefix handling. Init lazily on first picker open; release on hide
  -- so the shared BaseIconFilenames cache gets garbage-collected.
  -- Declared here (before the filter dropdown setup) so that closure
  -- captures pick up the local, not a global.
  local provider = nil
  -- Selection is tracked by PATH (not index) so it survives filter
  -- changes: a spell icon you picked still saves correctly even after
  -- you switch the filter to "Items" and it's no longer in the visible list.
  local QUESTION_MARK = "INTERFACE\\ICONS\\INV_MISC_QUESTIONMARK"
  local selectedIconPath = QUESTION_MARK

  local function EnsureProvider()
    if not provider then
      provider = CreateAndInitFromMixin(IconDataProviderMixin,
                                         IconDataProviderExtraType.Equipment)
    end
  end

  -- Anchor scrollbar to iconScroll's right edge so its position tracks
  -- the icon grid rather than the popup. -16/+16 vertical insets are the
  -- standard up/down arrow spacing for UIPanelScrollBarTemplate.
  local scrollbar = _G["pfEqMgrIconScrollScrollBar"]
  if scrollbar then
    scrollbar:ClearAllPoints()
    scrollbar:SetPoint("TOPLEFT", iconScroll, "TOPRIGHT", 8, -16)
    scrollbar:SetPoint("BOTTOMLEFT", iconScroll, "BOTTOMRIGHT", 8, 16)
    SkinScrollbar(scrollbar)
  end

  -- Filter dropdown: "All Icons" / "Spells" / "Items" (top right of icon area).
  local filterDropdown = CreateFrame("Frame", "pfEqMgrIconFilter", namePopup, "UIDropDownMenuTemplate")
  filterDropdown:SetPoint("TOPRIGHT", namePopup, "TOPRIGHT", 0, -94)
  local currentFilter = "all"
  local function ApplyFilter(value)
    currentFilter = value
    UIDropDownMenu_SetSelectedValue(filterDropdown, value)
    if provider then
      if value == "spells" then provider:SetIconTypes({ IconDataProviderIconType.Spell })
      elseif value == "items" then provider:SetIconTypes({ IconDataProviderIconType.Item })
      else provider:SetIconTypes(nil) end
      -- Don't reset selection — selectedIconPath persists. If the
      -- selected icon isn't in the new filter, no grid entry will be
      -- highlighted but Save will still write the chosen icon.
      pfUI.equipmentmanager.RefreshIconGrid()
    end
  end
  UIDropDownMenu_Initialize(filterDropdown, function()
    local info
    info = {}; info.text = T["All Icons"] or "All Icons"; info.value = "all"
    info.func = function() ApplyFilter("all") end
    info.checked = currentFilter == "all"
    UIDropDownMenu_AddButton(info)
    info = {}; info.text = T["Spells"] or "Spells"; info.value = "spells"
    info.func = function() ApplyFilter("spells") end
    info.checked = currentFilter == "spells"
    UIDropDownMenu_AddButton(info)
    info = {}; info.text = T["Items"] or "Items"; info.value = "items"
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
      local btn = CreateFrame("Button", nil, namePopup)
      btn:SetWidth(ICON_BTN_SIZE)
      btn:SetHeight(ICON_BTN_SIZE)
      btn:SetPoint("TOPLEFT", iconScroll, "TOPLEFT", (c-1) * (ICON_BTN_SIZE + ICON_BTN_PAD), -(r-1) * (ICON_BTN_SIZE + ICON_BTN_PAD))
      CreateBackdrop(btn)
      btn.texture = btn:CreateTexture(nil, "ARTWORK")
      btn.texture:SetAllPoints(btn)
      btn.texture:SetTexCoord(.08, .92, .08, .92)
      btn.gridIndex = i
      btn:SetScript("OnClick", function()
        if this.iconIndex and provider then
          local path = provider:GetIconByIndex(this.iconIndex)
          if path then selectedIconPath = path end
          pfUI.equipmentmanager.RefreshIconGrid()
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

  function pfUI.equipmentmanager.RefreshIconGrid()
    EnsureProvider()
    local numIcons = provider:GetNumIcons()
    local numRows = math.ceil(numIcons / ICON_GRID_COLS)
    FauxScrollFrame_Update(iconScroll, numRows, ICON_GRID_ROWS, ICON_BTN_SIZE + ICON_BTN_PAD)
    local offset = FauxScrollFrame_GetOffset(iconScroll)
    for i = 1, ICON_GRID_ROWS * ICON_GRID_COLS do
      local listIdx = i + offset * ICON_GRID_COLS
      local btn = iconButtons[i]
      if listIdx <= numIcons then
        btn:Show()
        btn.iconIndex = listIdx
        local path = provider:GetIconByIndex(listIdx)
        btn.texture:SetTexture(path)
        if path == selectedIconPath then
          btn.backdrop:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
          btn.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
        end
      else
        btn:Hide()
        btn.iconIndex = nil
      end
    end
    -- Sync the "Currently Selected" preview from the path directly so it
    -- still shows the chosen icon when filtered out of the grid.
    namePopup.selectedPreview.tex:SetTexture(selectedIconPath)
  end

  iconScroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(ICON_BTN_SIZE + ICON_BTN_PAD, function() pfUI.equipmentmanager.RefreshIconGrid() end)
  end)

  namePopup:SetScript("OnHide", function()
    if provider then provider:Release(); provider = nil end
  end)

  local btnPopupOK = MakeButton("pfEqMgrPopupOK", T["OK"] or "OK", namePopup, namePopup, 14, -340, 80)
  btnPopupOK:ClearAllPoints()
  btnPopupOK:SetPoint("BOTTOMLEFT", namePopup, "BOTTOMLEFT", 14, 12)

  local btnPopupCancel = MakeButton("pfEqMgrPopupCancel", T["Cancel"] or "Cancel", namePopup, namePopup, 0, 0, 80)
  btnPopupCancel:ClearAllPoints()
  btnPopupCancel:SetPoint("BOTTOMRIGHT", namePopup, "BOTTOMRIGHT", -14, 12)
  btnPopupCancel:SetScript("OnClick", function() namePopup:Hide() end)

  btnPopupOK:SetScript("OnClick", function()
    local name = namePopup.editbox:GetText()
    if not name or name == "" then return end
    -- Strip the prefix to match ClassicAPI's persisted short-form basenames.
    local iconForSave = string.gsub(selectedIconPath, "INTERFACE\\ICONS\\", "")
    if pendingAction == "new" then
      C_EquipmentSet.CreateEquipmentSet(name, iconForSave)
      C_EquipmentSet.ClearIgnoredSlotsForSave()
      selectedSetID = C_EquipmentSet.GetEquipmentSetID(name)
    elseif pendingAction == "save" and selectedSetID then
      -- Commit pending ignored toggles: load the effective list into
      -- ClassicAPI's session state, then SaveEquipmentSet captures it.
      C_EquipmentSet.ClearIgnoredSlotsForSave()
      local effective = GetEffectiveIgnored(selectedSetID)
      for slotID in pairs(effective) do
        C_EquipmentSet.IgnoreSlotForSave(slotID)
      end
      C_EquipmentSet.SaveEquipmentSet(selectedSetID, iconForSave)
      C_EquipmentSet.ClearIgnoredSlotsForSave()
      pendingIgnoredToggles[selectedSetID] = nil
    elseif pendingAction == "rename" and selectedSetID then
      C_EquipmentSet.ModifyEquipmentSet(selectedSetID, name)
    end
    namePopup:Hide()
    pfUI.equipmentmanager.Refresh()
  end)

  -- Assignment (not `local function`) so this fills in the forward
  -- declaration at the top of the module — closures created earlier
  -- (row gear menu, "+ New Set" row, etc.) capture the same upvalue.
  function OpenNamePopup(action, prefillName, prefillIcon)
    pendingAction = action
    namePopup.editbox:SetText(prefillName or "")
    EnsureProvider()
    if prefillIcon then
      local short = string.gsub(prefillIcon, "INTERFACE\\ICONS\\", "")
      selectedIconPath = "INTERFACE\\ICONS\\" .. strupper(short)
    else
      selectedIconPath = QUESTION_MARK
    end
    if action == "rename" then
      namePopup.title:SetText(T["Rename Set"] or "Rename Set")
      iconScroll:Hide()
      for _, b in ipairs(iconButtons) do b:Hide() end
      namePopup.iconLabel:Hide()
      namePopup.selectedLabel:Hide()
      namePopup.selectedPreview:Hide()
      filterDropdown:Hide()
    else
      namePopup.title:SetText(action == "new" and (T["Name Set"] or "Name Set") or (T["Save Set"] or "Save Set"))
      iconScroll:Show()
      namePopup.iconLabel:Show()
      namePopup.selectedLabel:Show()
      namePopup.selectedPreview:Show()
      filterDropdown:Show()
    end
    namePopup:Show()
    if action ~= "rename" then pfUI.equipmentmanager.RefreshIconGrid() end
    namePopup.editbox:SetFocus()
  end

  -- ============================================================
  -- Equipment flyout (per-slot popup)
  -- ============================================================

  local flyout = CreateFrame("Frame", "pfEqMgrFlyout", UIParent)
  flyout:SetFrameStrata("DIALOG")
  flyout:Hide()
  CreateBackdrop(flyout, nil, nil, .9)
  flyout.buttons = {}

  local FLYOUT_BTN_SIZE = 36
  local FLYOUT_COLS = 5
  -- Sentinels for the flyout's virtual entries (negative values never
  -- collide with real packed locations from GetInventoryItemsForSlot).
  local PLACEINBAGS_LOCATION = -1
  local IGNORESLOT_LOCATION = -2    -- "ignore this slot" — shown when not ignored
  local UNIGNORESLOT_LOCATION = -3  -- "un-ignore this slot" — shown when ignored

  -- Find first empty bag slot and drop the cursor item into it.
  local function UnequipToBags(invSlot)
    if not GetInventoryItemID("player", invSlot) then return end
    ClearCursor()
    PickupInventoryItem(invSlot)
    if not CursorHasItem() then return end
    for bag = 0, 4 do
      local nslots = GetContainerNumSlots(bag) or 0
      for slot = 1, nslots do
        if not C_Container.GetContainerItemID(bag, slot) then
          PickupContainerItem(bag, slot)
          return
        end
      end
    end
    ClearCursor()
    UIErrorsFrame:AddMessage(EQUIPMENT_MANAGER_BAGS_FULL or "Your bags are full.", 1, .1, .1, 1)
  end

  local function MakeFlyoutButton(i)
    local b = CreateFrame("Button", nil, flyout)
    b:SetWidth(FLYOUT_BTN_SIZE)
    b:SetHeight(FLYOUT_BTN_SIZE)
    CreateBackdrop(b)
    b.texture = b:CreateTexture(nil, "ARTWORK")
    b.texture:SetAllPoints(b)
    b.texture:SetTexCoord(.08, .92, .08, .92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      if this.specialAction == "placeInBags" then
        GameTooltip:SetText(EQUIPMENT_MANAGER_PLACE_IN_BAGS or "Place in Bags", 1, 1, 1)
      elseif this.specialAction == "ignore" then
        GameTooltip:SetText(EQUIPMENT_MANAGER_IGNORE_SLOT or "Ignore this slot", 1, 1, 1)
      elseif this.specialAction == "unignore" then
        GameTooltip:SetText(EQUIPMENT_MANAGER_UNIGNORE_SLOT or "Stop ignoring this slot", 1, 1, 1)
      elseif this.bag then
        GameTooltip:SetBagItem(this.bag, this.slot)
      elseif this.invSlot then
        GameTooltip:SetInventoryItem("player", this.invSlot)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
      if this.specialAction == "placeInBags" then
        UnequipToBags(flyout.targetInvSlot)
        flyout:Hide()
        return
      elseif this.specialAction == "ignore" or this.specialAction == "unignore" then
        ToggleIgnoredForSet(selectedSetID, flyout.targetInvSlot)
        flyout:Hide()
        pfUI.equipmentmanager.Refresh()
        return
      end
      ClearCursor()
      if this.bag then
        PickupContainerItem(this.bag, this.slot)
      elseif this.invSlot then
        PickupInventoryItem(this.invSlot)
      end
      if CursorHasItem() then
        PickupInventoryItem(flyout.targetInvSlot)
      end
      flyout:Hide()
    end)
    return b
  end

  function pfUI.equipmentmanager.ShowFlyout(slotBtn)
    -- Accept either the EM grid btn (has .slotID) or a vanilla
    -- CharacterXxxxSlot button (use GetID()).
    local invSlot = slotBtn.slotID or slotBtn:GetID()

    -- ClassicAPI's GetInventoryItemsForSlot does the eligibility filter
    -- (invType → slot compatibility, 2H/finger/trinket rules) for us;
    -- the result is `{[packedLocation] = itemLink}`.
    local items = {}
    GetInventoryItemsForSlot(invSlot, items)
    -- Skip the item currently equipped in this slot (it would be a no-op swap).
    items[invSlot + ITEM_INVENTORY_LOCATION_PLAYER] = nil

    -- Special buttons go FIRST (ignore/un-ignore, then place-in-bags),
    -- with eligible items appended after. Layout matches modern WoW.
    local ordered = {}
    if selectedSetID then
      local effective = GetEffectiveIgnored(selectedSetID)
      table.insert(ordered, effective[invSlot] and UNIGNORESLOT_LOCATION or IGNORESLOT_LOCATION)
    end
    if GetInventoryItemID("player", invSlot) then
      table.insert(ordered, PLACEINBAGS_LOCATION)
    end
    -- Eligible items, sorted by packed location for stable display.
    local itemLocations = {}
    for location in pairs(items) do
      table.insert(itemLocations, location)
    end
    table.sort(itemLocations)
    for _, location in ipairs(itemLocations) do
      table.insert(ordered, location)
    end

    flyout.targetInvSlot = invSlot
    local num = table.getn(ordered)
    while table.getn(flyout.buttons) < num do
      flyout.buttons[table.getn(flyout.buttons) + 1] = MakeFlyoutButton(table.getn(flyout.buttons) + 1)
    end
    for i, b in ipairs(flyout.buttons) do
      if i <= num then
        local location = ordered[i]
        b.specialAction = nil; b.bag = nil; b.slot = nil; b.invSlot = nil
        if location == PLACEINBAGS_LOCATION then
          b.specialAction = "placeInBags"
          b.texture:SetTexture("Interface\\AddOns\\pfUI\\img\\UI-GearManager-ItemIntoBag")
          b.count:SetText("")
        elseif location == IGNORESLOT_LOCATION then
          b.specialAction = "ignore"
          b.texture:SetTexture("Interface\\AddOns\\pfUI\\img\\UI-GearManager-LeaveItem-Opaque")
          b.count:SetText("")
        elseif location == UNIGNORESLOT_LOCATION then
          b.specialAction = "unignore"
          b.texture:SetTexture("Interface\\AddOns\\pfUI\\img\\UI-GearManager-Undo")
          b.count:SetText("")
        else
          local loc = EquipmentManager_GetLocationData(location)
          if loc.isBags then
            b.bag = loc.bag; b.slot = loc.slot
            local tex, count = GetContainerItemInfo(loc.bag, loc.slot)
            b.texture:SetTexture(tex)
            if count and count > 1 then b.count:SetText(count) else b.count:SetText("") end
          else  -- isPlayer (equipped in some other slot)
            b.invSlot = loc.slot
            b.texture:SetTexture(GetInventoryItemTexture("player", loc.slot))
            b.count:SetText("")
          end
        end
        local col = math.mod(i - 1, FLYOUT_COLS)
        local row = math.floor((i - 1) / FLYOUT_COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4 + col * (FLYOUT_BTN_SIZE + 2), -4 - row * (FLYOUT_BTN_SIZE + 2))
        b:Show()
      else
        b:Hide()
      end
    end

    if num == 0 then
      flyout:Hide()
      UIErrorsFrame:AddMessage(T["No matching items in bags"] or "No matching items in bags", 1, 1, 0, 1)
      return
    end

    local cols = math.min(num, FLYOUT_COLS)
    local rows = math.ceil(num / FLYOUT_COLS)
    flyout:SetWidth(cols * (FLYOUT_BTN_SIZE + 2) + 6)
    flyout:SetHeight(rows * (FLYOUT_BTN_SIZE + 2) + 6)
    flyout:ClearAllPoints()
    -- Anchor to the popout button so the flyout sits past it (avoids
    -- overlapping the chevron). Falls back to the slot itself for the
    -- EM grid btns which don't have a separate popout.
    local anchorBtn = slotBtn.popout or slotBtn
    if invSlot == 16 or invSlot == 17 or invSlot == 18 then
      flyout:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 4)
    else
      local centerX = (anchorBtn:GetLeft() or 0) + anchorBtn:GetWidth()/2
      if centerX > GetScreenWidth()/2 then
        flyout:SetPoint("TOPRIGHT", anchorBtn, "TOPLEFT", -4, 0)
      else
        flyout:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 4, 0)
      end
    end
    -- Reverse the chevron on the active popout, restore the previously
    -- active one (if any). flyout.currentPopout drives OnHide cleanup.
    if flyout.currentPopout and flyout.currentPopout ~= slotBtn.popout then
      SetPopoutReversed(flyout.currentPopout, false)
    end
    flyout.currentPopout = slotBtn.popout
    SetPopoutReversed(slotBtn.popout, true)
    flyout:Show()
  end

  -- Hide flyout on outside click; restore the active popout's chevron.
  flyout:SetScript("OnHide", function()
    this.targetInvSlot = nil
    if this.currentPopout then
      SetPopoutReversed(this.currentPopout, false)
      this.currentPopout = nil
    end
  end)

  -- ============================================================
  -- Alt+left-click on a character paperdoll slot → open flyout.
  -- Wraps each CharacterXxxxSlot's existing OnClick so the default
  -- behaviors (pickup / unequip / use trinket) stay intact for plain
  -- and right clicks.
  -- ============================================================

  local CHAR_SLOT_NAMES = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot",
    "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
    "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
    "RangedSlot",
  }
  -- Slot ID classification for popout positioning. Weapons sit at the
  -- bottom of the paperdoll, so their popout goes on top (chevron up).
  -- All other slots get the popout on their right side, chevron right.
  local UP_ARROW_SLOTS = { [16]=1, [17]=1, [18]=1 }
  local POPOUT_TEX = "Interface\\AddOns\\pfUI\\img\\UI-GearManager-FlyoutButton"

  for _, slotName in ipairs(CHAR_SLOT_NAMES) do
    local slot = _G["Character"..slotName]
    if slot then
      -- "Ignored" overlay rendered on top of the paperdoll slot icon.
      -- pfUI loads modules BEFORE skins (pfUI.lua:407-418), so at this
      -- point slot.backdrop doesn't exist yet — the character skin
      -- creates it later and reparents the item icon to it. A plain
      -- texture on `slot` would render BENEATH the backdrop's icon.
      -- Wrap the texture in a frame with a higher frame level so it
      -- renders above the backdrop regardless of skin-init order.
      local overlayFrame = CreateFrame("Frame", nil, slot)
      overlayFrame:SetAllPoints(slot)
      overlayFrame:SetFrameLevel(slot:GetFrameLevel() + 10)
      local overlay = overlayFrame:CreateTexture(nil, "OVERLAY")
      overlay:SetAllPoints(overlayFrame)
      overlay:SetTexture("Interface\\AddOns\\pfUI\\img\\UI-GearManager-LeaveItem-Transparent")
      overlayFrame:Hide()
      slotOverlays[slot:GetID()] = overlayFrame

      -- Popout arrow button — clicking opens the equipment flyout for
      -- this slot. Replaces the Alt+click trigger with a discoverable
      -- visual affordance matching modern WoW's paperdoll.
      local invSlot = slot:GetID()
      local popout = CreateFrame("Button", nil, slot)
      popout:SetFrameLevel(slot:GetFrameLevel() + 1)
      -- Match Blizzard's EquipmentFlyoutPopoutButtonTemplate: 16x32,
      -- anchored LEFT to slot's RIGHT (chevron points away from slot
      -- toward the flyout's opening side).
      popout:SetWidth(16); popout:SetHeight(32)
      if UP_ARROW_SLOTS[invSlot] then
        -- Weapon row: popout on TOP, vertical orientation.
        popout:SetWidth(32); popout:SetHeight(16)
        popout:SetPoint("BOTTOM", slot, "TOP", 0, 0)
      else
        -- All horizontal slots get the popout on the RIGHT edge, chevron
        -- points right. Right-column slot popouts extend slightly into
        -- the EM sidecar gutter — acceptable, matches modern UX.
        popout:SetPoint("LEFT", slot, "RIGHT", 0, 0)
      end
      popout:SetNormalTexture(POPOUT_TEX)
      popout:SetHighlightTexture(POPOUT_TEX, "ADD")
      -- Stash both texCoord variants (normal=closed, reversed=open) so
      -- SetPopoutReversed can swap between them. Reversed = swap all
      -- y-values 0↔0.5 / 0.5↔1, matching modern WoW.
      if UP_ARROW_SLOTS[invSlot] then
        -- Closed: chevron points UP (toward where the flyout will open).
        popout.coordNormal     = { 0.15625, 0.84375, 0, 0.5 }
        popout.coordReversed   = { 0.15625, 0.84375, 0.5, 0 }
        popout.coordNormalHi   = { 0.15625, 0.84375, 0.5, 1 }
        popout.coordReversedHi = { 0.15625, 0.84375, 1, 0.5 }
      else
        popout.coordNormal     = { 0.15625, 0.5, 0.84375, 0.5, 0.15625, 0, 0.84375, 0 }
        popout.coordReversed   = { 0.15625, 0, 0.84375, 0, 0.15625, 0.5, 0.84375, 0.5 }
        popout.coordNormalHi   = { 0.15625, 1, 0.84375, 1, 0.15625, 0.5, 0.84375, 0.5 }
        popout.coordReversedHi = { 0.15625, 0.5, 0.84375, 0.5, 0.15625, 1, 0.84375, 1 }
      end
      SetPopoutReversed(popout, false)
      slot.popout = popout
      popout:SetScript("OnClick", function()
        -- Toggle: if the flyout is showing for this same slot, hide it;
        -- otherwise (re)open it for the clicked slot.
        if flyout:IsShown() and flyout.targetInvSlot == invSlot then
          flyout:Hide()
        else
          pfUI.equipmentmanager.ShowFlyout(slot)
        end
      end)
      popout:Hide()
      table.insert(popoutButtons, popout)
    end
  end

  -- Tie popout visibility to the EM sidecar. They appear when the
  -- sidecar opens, hide when it closes, and the flyout closes too.
  HookScript(frame, "OnShow", function()
    for _, b in ipairs(popoutButtons) do b:Show() end
  end)
  HookScript(frame, "OnHide", function()
    for _, b in ipairs(popoutButtons) do b:Hide() end
    if flyout then flyout:Hide() end
  end)

  -- ============================================================
  -- Refresh
  -- ============================================================

  function pfUI.equipmentmanager.Refresh()
    local ids = C_EquipmentSet.GetEquipmentSetIDs() or {}
    local numSets = table.getn(ids)

    -- Auto-select the first set if none is selected (or the previously
    -- selected one was deleted). Falls through to "show equipped" only
    -- when zero sets exist.
    if numSets > 0 then
      local stillExists = false
      if selectedSetID then
        for _, id in ipairs(ids) do
          if id == selectedSetID then stillExists = true; break end
        end
      end
      if not stillExists then selectedSetID = ids[1] end
    else
      selectedSetID = nil
    end

    -- Set rows
    for i, row in ipairs(setRows) do
      if i <= numSets then
        local setID = ids[i]
        local name, icon, _, isEquipped, _, _, _, numMissing = C_EquipmentSet.GetEquipmentSetInfo(setID)
        row.setID = setID
        -- Color precedence: missing items (red) > equipped (green) > normal (white).
        local color = (numMissing and numMissing > 0) and "|cffff5555"
                      or isEquipped and "|cff33ff33" or "|cffffffff"
        row.text:SetText(color .. (name or "?") .. "|r")
        if icon then
          local full = string.find(icon, "\\") and icon or ("Interface\\Icons\\" .. icon)
          row.icon:SetTexture(full)
        else
          row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        if setID == selectedSetID then row.highlight:Show() else row.highlight:Hide() end
        row:Show()
      else
        row:Hide()
        row.setID = nil
      end
    end

    -- "+ New Set" row sits after the last real set; hide it at the cap.
    if numSets >= MAX_EQUIPMENT_SETS_PER_PLAYER then
      newSetRow:Hide()
    else
      newSetRow:ClearAllPoints()
      if numSets == 0 then
        newSetRow:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 5, -3)
      else
        newSetRow:SetPoint("TOPLEFT", setRows[numSets], "BOTTOMLEFT", 0, -2)
      end
      newSetRow:Show()
    end

    -- Update the ignored-overlay textures attached to each paperdoll
    -- slot. Uses effective state (persistent + pending toggles) so
    -- uncommitted user changes show immediately.
    local setIgnored = selectedSetID and GetEffectiveIgnored(selectedSetID) or {}
    for slotID, overlay in pairs(slotOverlays) do
      if selectedSetID and setIgnored[slotID] then overlay:Show() else overlay:Hide() end
    end

    -- Equip + Save are the only top buttons now; enable when a set is selected.
    local hasSelection = selectedSetID and true or false
    if hasSelection then btnEquip:Enable(); btnSave:Enable()
    else btnEquip:Disable(); btnSave:Disable() end
  end

  -- ============================================================
  -- Events
  -- ============================================================

  local events = CreateFrame("Frame")
  events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
  events:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
  events:RegisterEvent("EQUIPMENT_SWAP_PENDING")
  events:RegisterEvent("BAG_UPDATE_DELAYED")  -- ClassicAPI debounced; ~4x fewer refreshes than BAG_UPDATE
  events:RegisterEvent("UNIT_INVENTORY_CHANGED")
  events:SetScript("OnEvent", function()
    if not frame:IsShown() then return end
    if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
    pfUI.equipmentmanager.Refresh()
  end)

  -- Hide the sidecar + flyout when the character pane closes.
  HookScript(CharacterFrame, "OnHide", function()
    frame:Hide()
    flyout:Hide()
  end)
end)
