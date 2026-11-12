pfUI:RegisterModule("addons", function ()
  local rawborder, border = GetBorderSize()

  -- add main menu button
  local pfUIAddonButton = CreateFrame("Button", "GameMenuButtonPFUIAddOns", GameMenuFrame, "GameMenuButtonTemplate")
  pfUIAddonButton:SetPoint("TOP", 0, -32)
  pfUIAddonButton:SetText(T["AddOns"])
  pfUIAddonButton:SetScript("OnClick", function()
    pfUI.addons:Show()
    HideUIPanel(GameMenuFrame)
  end)

  local point, relativeTo, relativePoint, xOffset, yOffset = GameMenuButtonOptions:GetPoint()
  GameMenuButtonOptions:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset - 22)
  GameMenuFrame:SetHeight(GameMenuFrame:GetHeight()+22)

  -- addon window
  pfUI.addons = CreateFrame("Frame", "pfAddons", UIParent)
  pfUI.addons:SetFrameStrata("DIALOG")
  pfUI.addons:SetSize(380, 490)
  pfUI.addons:SetPoint("CENTER", 0,0)
  pfUI.addons:EnableMouseWheel(1)
  pfUI.addons:SetMovable(true)
  pfUI.addons:EnableMouse(true)
  pfUI.addons:RegisterForDrag("LeftButton")
  pfUI.addons:SetScript("OnDragStart", function() this:StartMoving() end)
  pfUI.addons:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  pfUI.addons:Hide()

  CreateBackdrop(pfUI.addons, nil, true, .75)
  CreateBackdropShadow(pfUI.addons)

  pfUI.addons:SetScript("OnHide", function()
    if this.hasChanged then
      pfUI.gui:Reload()
      this.hasChanged = nil
    end
  end)

  tinsert(UISpecialFrames,"pfAddons")

  pfUI.addons.caption = pfUI.addons:CreateFontString("Status", "LOW", "GameFontNormal")
  pfUI.addons.caption:SetFont(pfUI.font_default, C.global.font_size + 4, "OUTLINE")
  pfUI.addons.caption:SetTextColor(.2, 1, .8, 1)
  pfUI.addons.caption:SetPoint("TOP", 0, -10)
  pfUI.addons.caption:SetJustifyH("LEFT")
  pfUI.addons.caption:SetText(T["Addon List"])

  pfUI.addons.close = CreateFrame("Button", "pfBagClose", pfUI.addons)
  pfUI.addons.close:SetPoint("TOPRIGHT", -border*2,-border*2 )
  CreateBackdrop(pfUI.addons.close)
  pfUI.addons.close:SetSize(15, 15)
  pfUI.addons.close.texture = pfUI.addons.close:CreateTexture("pfBagClose")
  pfUI.addons.close.texture:SetTexture(pfUI.media["img:close"])
  pfUI.addons.close.texture:ClearAllPoints()
  pfUI.addons.close.texture:SetPoint("TOPLEFT", pfUI.addons.close, "TOPLEFT", 4, -4)
  pfUI.addons.close.texture:SetPoint("BOTTOMRIGHT", pfUI.addons.close, "BOTTOMRIGHT", -4, 4)
  pfUI.addons.close.texture:SetVertexColor(1,.25,.25,1)
  pfUI.addons.close:SetScript("OnEnter", function ()
    CreateBackdrop(pfUI.addons.close)
    pfUI.addons.close.backdrop:SetBackdropBorderColor(1,.25,.25,1)
  end)

  pfUI.addons.close:SetScript("OnLeave", function ()
    CreateBackdrop(pfUI.addons.close)
  end)

  pfUI.addons.close:SetScript("OnClick", function()
    pfUI.addons:Hide()
  end)

  -- installed addons, one entry per row of the addon list
  local addons = {}
  for i = 1, GetNumAddOns() do
    local name, title, notes = GetAddOnInfo(i)
    addons[i] = {
      index = i,
      name = name,
      title = title,
      notes = notes,
      author = GetAddOnMetadata(name, "Author"),
      version = GetAddOnMetadata(name, "Version"),
      deps = { GetAddOnDependencies(i) },                         -- required (.toc Dependencies)
      optdeps = { C_AddOns.GetAddOnOptionalDependencies(i) },     -- optional (.toc OptionalDeps)
    }
  end

  local function IsAddonEnabled(index)
    local _, _, _, enabled = GetAddOnInfo(index)
    return enabled
  end

  local function SetAddonEnabled(index, enabled)
    if enabled then
      EnableAddOn(index)
    else
      DisableAddOn(index)
    end
    pfUI.addons.hasChanged = true
  end

  -- addons profile
  local function GetSelectedAddonsList()
    local selected_addons = {}
    for i, addon in ipairs(addons) do
      if IsAddonEnabled(i) then
        table.insert(selected_addons, addon.name)
      end
    end
    return selected_addons
  end

  local selectedProfile

  local function IsSelectedProfile(profile)
    return profile == selectedProfile
  end

  local function SetAddonProfile(profile)
    -- create new profile if not existing
    if not pfUI_addon_profiles[profile] then
      pfUI_addon_profiles[profile] = GetSelectedAddonsList()
    end

    -- set dropdown to profile
    selectedProfile = profile
    pfUI.addons.profile.dropdown:GenerateMenu()

    -- load profile
    local selected = {}
    for _, name in ipairs(pfUI_addon_profiles[profile]) do
      selected[name] = true
    end

    for i, addon in ipairs(addons) do
      if selected[addon.name] and not IsAddonEnabled(i) then
        SetAddonEnabled(i, true)
      elseif not selected[addon.name] and IsAddonEnabled(i) then
        SetAddonEnabled(i, false)
      end
    end

    pfUI.addons.list.ScrollBox:ReinitializeFrames()
  end

  -- addon profiles
  pfUI.addons.profile = CreateFrame("Frame", "pfAddonListProfile", pfUI.addons)
  pfUI.addons.profile:SetScript("OnShow", function()
    pfUI_addon_profiles[T["Current"]] = GetSelectedAddonsList()
    SetAddonProfile(T["Current"])
  end)

  pfUI.addons.profile:SetPoint("TOP", pfUI.addons, "TOP", 0, -30)
  pfUI.addons.profile:SetSize(370, 30)
  CreateBackdrop(pfUI.addons.profile, nil, true)

  -- addon profile: title
  pfUI.addons.profile.caption = pfUI.addons.profile:CreateFontString("Status", "LOW", "GameFontNormal")
  pfUI.addons.profile.caption:SetFontObject(GameFontWhite)
  pfUI.addons.profile.caption:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
  pfUI.addons.profile.caption:SetPoint("LEFT", 10, 0)
  pfUI.addons.profile.caption:SetText(T["Addon Profile"])

  -- addon profile: delete
  pfUI.addons.profile.del = CreateFrame("Button", nil, pfUI.addons.profile, "UIPanelButtonTemplate")
  SkinButton(pfUI.addons.profile.del)
  pfUI.addons.profile.del:SetSize(16, 16)
  pfUI.addons.profile.del:SetPoint("RIGHT", -10, 0)
  pfUI.addons.profile.del:GetFontString():SetPoint("CENTER", 1, 0)
  pfUI.addons.profile.del:SetText("-")
  pfUI.addons.profile.del:SetTextColor(1,.5,.5,1)
  pfUI.addons.profile.del:SetScript("OnClick", function() -- TODO
    local name = selectedProfile
    if not name then return end
    CreateQuestionDialog(T["Delete profile"] .. " '|cff33ffcc" .. name .. "|r'?", function()
      pfUI_addon_profiles[name] = nil
      SetAddonProfile(T["Current"])
    end)
  end)

  -- addon profile: create
  pfUI.addons.profile.add = CreateFrame("Button", nil, pfUI.addons.profile, "UIPanelButtonTemplate")
  SkinButton(pfUI.addons.profile.add)
  pfUI.addons.profile.add:SetSize(16, 16)
  pfUI.addons.profile.add:SetPoint("RIGHT", pfUI.addons.profile.del, "LEFT", -4, 0)
  pfUI.addons.profile.add:GetFontString():SetPoint("CENTER", 1, 0)
  pfUI.addons.profile.add:SetText("+")
  pfUI.addons.profile.add:SetTextColor(.5,1,.5,1)
  pfUI.addons.profile.add:SetScript("OnClick", function()
    CreateQuestionDialog(T["Please enter a name for the new profile."],
    function()
      local profile_name = this:GetParent().input:GetText()
      local bad = string.gsub(profile_name,"([%w%s]+)","")
      if bad ~= "" then
        message("\"" .. bad .. "\" " .. T["is not allowed in profile name"])
      else
        SetAddonProfile(profile_name)
      end
    end, false, true)
  end)

  -- addon profile: dropdown
  pfUI.addons.profile.dropdown = CreateFrame("DropdownButton", nil, pfUI.addons.profile, "pfUIDropdownTemplate")
  pfUI.addons.profile.dropdown:SetPoint("RIGHT", pfUI.addons.profile.add, "LEFT", -2, 0)
  pfUI.addons.profile.dropdown:SetWidth(220)
  pfUI.addons.profile.dropdown:SetupMenu(function(dropdown, rootDescription)
    for name in pairs(pfUI_addon_profiles) do
      rootDescription:CreateRadio(name, IsSelectedProfile, SetAddonProfile, name)
    end
  end)

  local function AddDependencyLines(header, deps)
    if not deps or table.getn(deps) == 0 then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(header .. ":", .2, 1, .8)
    for _, dep in ipairs(deps) do
      if IsAddOnLoaded(dep) then
        GameTooltip:AddLine(" " .. dep, .5, 1, .5)
      elseif C_AddOns.DoesAddOnExist(dep) then
        GameTooltip:AddLine(" " .. dep, 1, .82, 0)
      else
        GameTooltip:AddLine(" " .. dep .. " (" .. ADDON_MISSING .. ")", 1, .4, .4)
      end
    end
  end

  local function RowOnEnter(self)
    local addon = self.addon
    self:SetBackdropBorderColor(1,1,1,.08)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(addon.title)
    if addon.version then
      GameTooltip:AddDoubleLine(GAME_VERSION_LABEL, addon.version, 1,1,1, .2,1,.8)
    end

    if addon.author then
      GameTooltip:AddDoubleLine(T["Author"], addon.author, 1,1,1, .2,1,.8)
    end

    GameTooltip:AddLine(addon.notes, .75,.75,.75,1)
    AddDependencyLines(T["Dependencies"], addon.deps)
    AddDependencyLines(T["Optional Dependencies"], addon.optdeps)
    GameTooltip:SetWidth(180)
    GameTooltip:Show()
  end

  local function RowOnLeave(self)
    self:SetBackdropBorderColor(1,1,1,.04)
    GameTooltip:Hide()
  end

  local function RowOnClick(self)
    self.input:Click()
  end

  local function InputOnClick(self)
    SetAddonEnabled(self:GetParent().addon.index, self:GetChecked())

    pfUI_addon_profiles[selectedProfile or T["Current"]] = GetSelectedAddonsList()
  end

  local function InitRow(row, addon)
    -- one-time setup of a pooled row
    if not row.input then
      row:SetBackdrop(pfUI.backdrop_hover)
      row:SetBackdropBorderColor(1,1,1,.04)

      row:EnableMouse(true)
      row:SetScript("OnEnter", RowOnEnter)
      row:SetScript("OnLeave", RowOnLeave)
      row:SetScript("OnClick", RowOnClick)

      -- caption
      row.caption = row:CreateFontString(nil, "LOW", "GameFontNormal")
      row.caption:SetFont(pfUI.font_default, C.global.font_size + 2, "OUTLINE")
      row.caption:SetPoint("LEFT", row, "LEFT", 2, 0)
      row.caption:SetFontObject(GameFontWhite)
      row.caption:SetJustifyH("LEFT")

      -- input field
      row.input = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
      row.input:SetNormalTexture("")
      row.input:SetPushedTexture("")
      row.input:SetHighlightTexture("")
      CreateBackdrop(row.input, nil, true)
      row.input:SetBackdropBorderColor(.3,.3,.3,1)
      row.input:SetSize(14, 14)
      row.input:SetPoint("RIGHT" , -5, 1)
      row.input:SetScript("OnClick", InputOnClick)
    end

    row.addon = addon
    row.caption:SetText(addon.title)
    row.caption:SetAlpha(IsAddOnLoaded(addon.index) and 1 or .5)
    row.input:SetChecked(IsAddonEnabled(addon.index))
  end

  -- addon list: a ScrollBox keeps rows only for the addons in view
  pfUI.addons.list = CreateFrame("Frame", "pfAddonList", pfUI.addons, "pfUIScrollBoxListTemplate")
  pfUI.addons.list:SetSize(370, 420)
  pfUI.addons.list:SetPoint("BOTTOM", 0, 5)
  CreateBackdrop(pfUI.addons.list, nil, true)

  local view = CreateScrollBoxListLinearView(5, 5, 5, 8)
  view:SetElementExtent(25)
  view:SetElementInitializer("Button", InitRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(pfUI.addons.list.ScrollBox, pfUI.addons.list.ScrollBar, view)
  pfUI.addons.list.ScrollBox:SetDataProvider(CreateDataProvider(addons))

  -- a load-on-demand addon that loads brightens its row
  pfUI.addons.list:RegisterEvent("ADDON_LOADED")
  pfUI.addons.list:SetScript("OnEvent", function(self)
    self.ScrollBox:ReinitializeFrames()
  end)

end)
