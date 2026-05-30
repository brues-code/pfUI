-- Equipment Manager module
-- Backport of the 4.3.4 GearManagerDialog UI on top of ClassicAPI's
-- C_EquipmentSet.* API. Adds a 6th tab to CharacterFrame.

pfUI:RegisterModule("equipmentmanager", function()
  if not C_EquipmentSet or not C_EquipmentSet.CanUseEquipmentSets() then return end

  pfUI.equipmentmanager = pfUI.equipmentmanager or {}

  local MAX_EQUIPMENT_SETS_PER_PLAYER = 10
  local NUM_LE_EQUIPMENT_SETS_MAX_ROWS = MAX_EQUIPMENT_SETS_PER_PLAYER
  local SET_ROW_HEIGHT = 36
  local SLOT_SIZE = 36

  local SLOTS = {
    { id = 1,  name = "HeadSlot" },
    { id = 2,  name = "NeckSlot" },
    { id = 3,  name = "ShoulderSlot" },
    { id = 15, name = "BackSlot" },
    { id = 5,  name = "ChestSlot" },
    { id = 4,  name = "ShirtSlot" },
    { id = 19, name = "TabardSlot" },
    { id = 9,  name = "WristSlot" },
    { id = 10, name = "HandsSlot" },
    { id = 6,  name = "WaistSlot" },
    { id = 7,  name = "LegsSlot" },
    { id = 8,  name = "FeetSlot" },
    { id = 11, name = "Finger0Slot" },
    { id = 12, name = "Finger1Slot" },
    { id = 13, name = "Trinket0Slot" },
    { id = 14, name = "Trinket1Slot" },
    { id = 16, name = "MainHandSlot" },
    { id = 17, name = "SecondaryHandSlot" },
    { id = 18, name = "RangedSlot" },
  }

  local rawborder, border = GetBorderSize()
  local selectedSetID = nil
  local pendingAction = nil  -- "new" | "save" | "rename" — what the popups apply to

  -- ============================================================
  -- Main content frame: opens as a sidecar to the right of CharacterFrame
  -- (matches ReputationDetailFrame's positioning pattern).
  -- ============================================================

  local frame = CreateFrame("Frame", "pfEquipmentManagerFrame", CharacterFrame)
  frame:SetWidth(380)
  frame:SetHeight(380)
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
  toggleBtn:SetWidth(20)
  toggleBtn:SetHeight(20)
  toggleBtn:SetPoint("BOTTOM", CharacterHandsSlot, "TOP", 0, 4)
  CreateBackdrop(toggleBtn)
  toggleBtn.texture = toggleBtn:CreateTexture(nil, "ARTWORK")
  toggleBtn.texture:SetAllPoints(toggleBtn)
  toggleBtn.texture:SetTexCoord(.08, .92, .08, .92)
  toggleBtn.texture:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
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
  -- Set list (left column)
  -- ============================================================

  local LIST_VISIBLE_ROWS = 6
  local listFrame = CreateFrame("Frame", nil, frame)
  listFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -30)
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
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture(.3, .3, .3, .4)
    row.highlight:Hide()

    row:SetScript("OnClick", function()
      selectedSetID = row.setID
      pfUI.equipmentmanager.Refresh()
    end)

    return row
  end

  for i = 1, NUM_LE_EQUIPMENT_SETS_MAX_ROWS do
    setRows[i] = CreateSetRow(i)
  end

  -- ============================================================
  -- Slot grid (right column)
  -- ============================================================

  local slotGrid = CreateFrame("Frame", nil, frame)
  slotGrid:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 12, 0)
  slotGrid:SetWidth(4 * (SLOT_SIZE + 4))
  slotGrid:SetHeight(5 * (SLOT_SIZE + 4))

  local slotButtons = {}
  for idx, slot in ipairs(SLOTS) do
    local col = math.mod(idx - 1, 4)
    local row = math.floor((idx - 1) / 4)
    local btn = CreateFrame("Button", "pfEqMgrSlot"..slot.id, slotGrid)
    btn:SetWidth(SLOT_SIZE)
    btn:SetHeight(SLOT_SIZE)
    btn:SetPoint("TOPLEFT", slotGrid, "TOPLEFT", col * (SLOT_SIZE + 4), -row * (SLOT_SIZE + 4))
    btn.slotID = slot.id
    btn.slotName = slot.name
    local _, emptyTex = GetInventorySlotInfo(strupper(slot.name))
    btn.emptyTexture = emptyTex

    CreateBackdrop(btn)
    btn.texture = btn:CreateTexture(nil, "ARTWORK")
    btn.texture:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    btn.texture:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn.texture:SetTexCoord(.08, .92, .08, .92)

    -- "Ignored" overlay (X mark when slot is in ignored list)
    btn.ignoredOverlay = btn:CreateTexture(nil, "OVERLAY")
    btn.ignoredOverlay:SetAllPoints(btn.texture)
    btn.ignoredOverlay:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    btn.ignoredOverlay:SetVertexColor(1, 0.3, 0.3, 0.85)
    btn.ignoredOverlay:Hide()

    -- Missing indicator (red border tint)
    btn.missingFlag = false

    btn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      if this.itemID then
        GameTooltip:SetHyperlink("item:"..this.itemID..":0:0:0")
      else
        GameTooltip:SetText(_G[strupper(this.slotName)] or this.slotName)
      end
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function()
      if arg1 == "RightButton" then
        -- Toggle ignored state for the selected set (or session toggles
        -- for the next save when no set is selected).
        if selectedSetID then
          local ignored = C_EquipmentSet.GetIgnoredSlots(selectedSetID) or {}
          local isIgnored = false
          for _, s in ipairs(ignored) do if s == this.slotID then isIgnored = true; break end end
          -- Per-set ignored state isn't directly mutable via ClassicAPI;
          -- session toggles + Save is the documented workflow. We toggle
          -- the session state and prompt the user to Save.
          if isIgnored then C_EquipmentSet.UnignoreSlotForSave(this.slotID)
          else C_EquipmentSet.IgnoreSlotForSave(this.slotID) end
          UIErrorsFrame:AddMessage(
            (T["Slot ignored toggled — click Save to update set"] or "Slot ignored toggled — click Save to update set"),
            1, 1, 0, 1)
        else
          if C_EquipmentSet.IsSlotIgnoredForSave(this.slotID) then
            C_EquipmentSet.UnignoreSlotForSave(this.slotID)
          else
            C_EquipmentSet.IgnoreSlotForSave(this.slotID)
          end
          pfUI.equipmentmanager.Refresh()
        end
      else
        pfUI.equipmentmanager.ShowFlyout(this)
      end
    end)

    slotButtons[slot.id] = btn
  end

  -- ============================================================
  -- Action buttons row (below set list)
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

  -- Anchor button stack from the frame's bottom so it stays in place
  -- regardless of how many set rows are visible above.
  local btnDelete = CreateFrame("Button", "pfEqMgrDelete", frame, "UIPanelButtonTemplate")
  btnDelete:SetWidth(116); btnDelete:SetHeight(22); btnDelete:SetText(T["Delete"] or "Delete")
  btnDelete:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
  SkinButton(btnDelete)

  local btnEquip = CreateFrame("Button", "pfEqMgrEquip", frame, "UIPanelButtonTemplate")
  btnEquip:SetWidth(55); btnEquip:SetHeight(22); btnEquip:SetText(T["Equip"] or "Equip")
  btnEquip:SetPoint("BOTTOMLEFT", btnDelete, "TOPLEFT", 0, 4)
  SkinButton(btnEquip)

  local btnRename = CreateFrame("Button", "pfEqMgrRename", frame, "UIPanelButtonTemplate")
  btnRename:SetWidth(55); btnRename:SetHeight(22); btnRename:SetText(T["Rename"] or "Rename")
  btnRename:SetPoint("LEFT", btnEquip, "RIGHT", 6, 0)
  SkinButton(btnRename)

  local btnNew = CreateFrame("Button", "pfEqMgrNew", frame, "UIPanelButtonTemplate")
  btnNew:SetWidth(55); btnNew:SetHeight(22); btnNew:SetText(T["New"] or "New")
  btnNew:SetPoint("BOTTOMLEFT", btnEquip, "TOPLEFT", 0, 4)
  SkinButton(btnNew)

  local btnSave = CreateFrame("Button", "pfEqMgrSave", frame, "UIPanelButtonTemplate")
  btnSave:SetWidth(55); btnSave:SetHeight(22); btnSave:SetText(T["Save"] or "Save")
  btnSave:SetPoint("LEFT", btnNew, "RIGHT", 6, 0)
  SkinButton(btnSave)

  -- ============================================================
  -- Name/icon entry popup
  -- ============================================================

  local namePopup = CreateFrame("Frame", "pfEqMgrNamePopup", UIParent)
  namePopup:SetFrameStrata("DIALOG")
  namePopup:SetWidth(260)
  namePopup:SetHeight(330)
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
  namePopup.title:SetText(T["Name Set"] or "Name Set")

  namePopup.editbox = CreateFrame("EditBox", "pfEqMgrNameEdit", namePopup, "InputBoxTemplate")
  namePopup.editbox:SetWidth(220)
  namePopup.editbox:SetHeight(20)
  namePopup.editbox:SetPoint("TOP", namePopup, "TOP", 0, -32)
  namePopup.editbox:SetAutoFocus(false)
  namePopup.editbox:SetMaxLetters(32)
  CreateBackdrop(namePopup.editbox)

  namePopup.iconLabel = namePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  namePopup.iconLabel:SetPoint("TOPLEFT", namePopup, "TOPLEFT", 14, -62)
  namePopup.iconLabel:SetText(T["Icon"] or "Icon")

  -- Icon picker: 5×5 grid of buttons + scroll
  local ICON_GRID_COLS = 5
  local ICON_GRID_ROWS = 5
  local ICON_BTN_SIZE = 36
  local ICON_BTN_PAD = 6

  local iconScroll = CreateFrame("ScrollFrame", "pfEqMgrIconScroll", namePopup, "FauxScrollFrameTemplate")
  iconScroll:SetPoint("TOPLEFT", namePopup, "TOPLEFT", 14, -78)
  iconScroll:SetWidth(ICON_GRID_COLS * (ICON_BTN_SIZE + ICON_BTN_PAD) - ICON_BTN_PAD)
  iconScroll:SetHeight(ICON_GRID_ROWS * (ICON_BTN_SIZE + ICON_BTN_PAD) - ICON_BTN_PAD)
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
  -- IconDataProviderMixin owns the icon DB, dedup, lazy load, and
  -- prefix handling. Init lazily on first picker open; release on hide
  -- so the shared BaseIconFilenames cache gets garbage-collected.
  local provider = nil
  local selectedIconIdx = 1

  local function EnsureProvider()
    if not provider then
      provider = CreateAndInitFromMixin(IconDataProviderMixin,
                                         IconDataProviderExtraType.Equipment)
    end
  end

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
        if this.iconIndex then
          selectedIconIdx = this.iconIndex
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
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
        btn.texture:SetTexture(provider:GetIconByIndex(listIdx))
        if listIdx == selectedIconIdx then
          btn.backdrop:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
          btn.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
        end
      else
        btn:Hide()
        btn.iconIndex = nil
      end
    end
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
    local iconForSave = provider and provider:GetIconForSaving(selectedIconIdx) or "INV_MISC_QUESTIONMARK"
    if pendingAction == "new" then
      C_EquipmentSet.CreateEquipmentSet(name, iconForSave)
      C_EquipmentSet.ClearIgnoredSlotsForSave()
      selectedSetID = C_EquipmentSet.GetEquipmentSetID(name)
    elseif pendingAction == "save" and selectedSetID then
      C_EquipmentSet.SaveEquipmentSet(selectedSetID, iconForSave)
      C_EquipmentSet.ClearIgnoredSlotsForSave()
    elseif pendingAction == "rename" and selectedSetID then
      C_EquipmentSet.ModifyEquipmentSet(selectedSetID, name)
    end
    namePopup:Hide()
    pfUI.equipmentmanager.Refresh()
  end)

  local function OpenNamePopup(action, prefillName, prefillIcon)
    pendingAction = action
    namePopup.editbox:SetText(prefillName or "")
    EnsureProvider()
    if prefillIcon then
      -- Stored icons are short-form basenames; GetIconByIndex returns
      -- the full "INTERFACE\\ICONS\\X" path, so reconstruct before lookup.
      local short = string.gsub(prefillIcon, "INTERFACE\\ICONS\\", "")
      selectedIconIdx = provider:GetIndexOfIcon("INTERFACE\\ICONS\\" .. strupper(short)) or 1
    else
      selectedIconIdx = 1
    end
    if action == "rename" then
      namePopup.title:SetText(T["Rename Set"] or "Rename Set")
      iconScroll:Hide()
      for _, b in ipairs(iconButtons) do b:Hide() end
      namePopup.iconLabel:Hide()
    else
      namePopup.title:SetText(action == "new" and (T["Name Set"] or "Name Set") or (T["Save Set"] or "Save Set"))
      iconScroll:Show()
      namePopup.iconLabel:Show()
      pfUI.equipmentmanager.RefreshIconGrid()
    end
    namePopup:Show()
    namePopup.editbox:SetFocus()
  end

  -- Wire main action buttons
  btnNew:SetScript("OnClick", function() OpenNamePopup("new") end)
  btnSave:SetScript("OnClick", function()
    if not selectedSetID then OpenNamePopup("new"); return end
    local name, icon = C_EquipmentSet.GetEquipmentSetInfo(selectedSetID)
    OpenNamePopup("save", name, icon)
  end)
  btnRename:SetScript("OnClick", function()
    if not selectedSetID then return end
    local name = C_EquipmentSet.GetEquipmentSetInfo(selectedSetID)
    OpenNamePopup("rename", name)
  end)
  btnDelete:SetScript("OnClick", function()
    if not selectedSetID then return end
    local name = C_EquipmentSet.GetEquipmentSetInfo(selectedSetID)
    StaticPopupDialogs["PFUI_EQMGR_DELETE"] = {
      text = string.format(T["Delete equipment set '%s'?"] or "Delete equipment set '%s'?", name or "?"),
      button1 = YES, button2 = NO,
      OnAccept = function()
        C_EquipmentSet.DeleteEquipmentSet(selectedSetID)
        selectedSetID = nil
        pfUI.equipmentmanager.Refresh()
      end,
      timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
    }
    StaticPopup_Show("PFUI_EQMGR_DELETE")
  end)
  btnEquip:SetScript("OnClick", function()
    if not selectedSetID then return end
    if C_EquipmentSet.EquipmentSetContainsLockedItems(selectedSetID) then
      UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT or "Locked items in set", 1, .1, .1, 1)
      return
    end
    ClearCursor()
    C_EquipmentSet.UseEquipmentSet(selectedSetID)
  end)

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
      if this.bag then
        GameTooltip:SetBagItem(this.bag, this.slot)
      elseif this.invSlot then
        GameTooltip:SetInventoryItem("player", this.invSlot)
      end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
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
    local invSlot = slotBtn.slotID

    -- ClassicAPI's GetInventoryItemsForSlot does the eligibility filter
    -- (invType → slot compatibility, 2H/finger/trinket rules) for us;
    -- the result is `{[packedLocation] = itemLink}`.
    local items = {}
    GetInventoryItemsForSlot(invSlot, items)
    -- Skip the item currently equipped in this slot (it would be a no-op swap).
    items[invSlot + ITEM_INVENTORY_LOCATION_PLAYER] = nil

    -- Collect into an ordered list (sorted by packed location for stable display).
    local ordered = {}
    for location in pairs(items) do
      table.insert(ordered, location)
    end
    table.sort(ordered)

    flyout.targetInvSlot = invSlot
    local num = table.getn(ordered)
    while table.getn(flyout.buttons) < num do
      flyout.buttons[table.getn(flyout.buttons) + 1] = MakeFlyoutButton(table.getn(flyout.buttons) + 1)
    end
    for i, b in ipairs(flyout.buttons) do
      if i <= num then
        local loc = EquipmentManager_GetLocationData(ordered[i])
        if loc.isBags then
          b.bag = loc.bag; b.slot = loc.slot; b.invSlot = nil
          local tex, count = GetContainerItemInfo(loc.bag, loc.slot)
          b.texture:SetTexture(tex)
          if count and count > 1 then b.count:SetText(count) else b.count:SetText("") end
        else  -- isPlayer (equipped in some other slot)
          b.bag = nil; b.slot = nil; b.invSlot = loc.slot
          b.texture:SetTexture(GetInventoryItemTexture("player", loc.slot))
          b.count:SetText("")
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
    flyout:SetPoint("TOPLEFT", slotBtn, "TOPRIGHT", 4, 0)
    flyout:Show()
  end

  -- Hide flyout on outside click
  flyout:SetScript("OnHide", function() this.targetInvSlot = nil end)

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

    -- Slot grid: if a set is selected, show that set's composition;
    -- otherwise show currently equipped items.
    local setItemIDs = selectedSetID and (C_EquipmentSet.GetItemIDs(selectedSetID) or {}) or nil
    local setIgnored = {}
    if selectedSetID then
      local ig = C_EquipmentSet.GetIgnoredSlots(selectedSetID) or {}
      for _, s in ipairs(ig) do setIgnored[s] = true end
    end

    for _, slot in ipairs(SLOTS) do
      local btn = slotButtons[slot.id]
      local itemID
      if setItemIDs then itemID = setItemIDs[slot.id] end
      if not itemID then itemID = GetInventoryItemID and GetInventoryItemID("player", slot.id) end

      btn.itemID = itemID
      if itemID then
        btn.texture:SetTexture(C_Item.GetItemIconByID(itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.texture:SetTexCoord(.08, .92, .08, .92)
      else
        btn.texture:SetTexture(btn.emptyTexture)
        -- Paperdoll slot textures have generous transparent padding around
        -- the silhouette; crop in so the icon visually fills the slot.
        btn.texture:SetTexCoord(0.075, 0.925, 0.075, 0.925)
      end

      -- Ignored state: set-specific (saved) or session toggle (when no set)
      local isIgnored = setItemIDs and setIgnored[slot.id]
        or (not selectedSetID and C_EquipmentSet.IsSlotIgnoredForSave(slot.id))
      if isIgnored then btn.ignoredOverlay:Show() else btn.ignoredOverlay:Hide() end

      -- Missing item (set has slot but item not resolved): red border
      if selectedSetID and setItemIDs and not setItemIDs[slot.id] and not isIgnored then
        local locations = C_EquipmentSet.GetItemLocations(selectedSetID) or {}
        if not locations[slot.id] then
          btn.backdrop:SetBackdropBorderColor(0.9, 0.2, 0.2, 1)
        else
          btn.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
        end
      else
        btn.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
      end
    end

    -- Button enable state
    local hasSelection = selectedSetID and true or false
    if hasSelection then
      btnSave:Enable(); btnEquip:Enable(); btnRename:Enable(); btnDelete:Enable()
    else
      btnSave:Disable(); btnEquip:Disable(); btnRename:Disable(); btnDelete:Disable()
    end
    if numSets >= MAX_EQUIPMENT_SETS_PER_PLAYER then btnNew:Disable() else btnNew:Enable() end
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
