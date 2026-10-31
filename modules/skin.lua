pfUI:RegisterModule("skin", function ()
  -- durability frame
  pfUI.durability = CreateFrame("Frame", "pfDurability", UIParent)
  if pfUI.minimap then
    pfUI.durability:SetPoint("TOPLEFT", pfUI.minimap, "BOTTOMLEFT", 0, -35)
  else
    pfUI.durability:SetPoint("LEFT", UIParent, "RIGHT", -120, 120)
  end
  UpdateMovable(pfUI.durability)
  pfUI.durability:SetWidth(80)
  pfUI.durability:SetHeight(70)
  pfUI.durability:SetFrameStrata("BACKGROUND")
  DurabilityFrame:SetParent(pfUI.durability)
  DurabilityFrame:SetAllPoints(pfUI.durability)
  DurabilityFrame:SetFrameLevel(1)
  DurabilityFrame.SetPoint = function() return end

  for i = 1, UIDROPDOWNMENU_MAXLEVELS do
    CreateBackdrop(_G["DropDownList"..i.."MenuBackdrop"], nil, true, .8)
    CreateBackdropShadow(_G["DropDownList"..i.."MenuBackdrop"])

    CreateBackdrop(_G["DropDownList"..i.."Backdrop"], nil, true, .8)
    CreateBackdropShadow(_G["DropDownList"..i.."Backdrop"])
  end

  -- ClassicAPI menus that don't name a style of their own take pfUI's
  function MenuVariants.GetDefaultMenuMixin() return pfUIMenuStyleMixin end
  function MenuVariants.GetDefaultContextMenuMixin() return pfUIMenuStyleMixin end

  -- ClassicAPI menus draw their checkboxes and radios with these. Both get a
  -- pfUI box: a checked box holds a check, a selected radio a filled square.
  local function CreateSelectionBox(frame, text)
    local _, border = GetBorderSize()

    local box = frame:AttachTexture()
    frame.leftTexture1 = box
    box:SetDrawLayer("BORDER")
    box:SetPoint("LEFT")
    box:SetSize(12, 12)
    box:SetColorTexture(GetStringColorObject(C.appearance.border.color):GetRGBA())

    local inside = frame:AttachTexture()
    inside:SetDrawLayer("ARTWORK")
    inside:SetPoint("TOPLEFT", box, "TOPLEFT", border, -border)
    inside:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -border, border)
    local r, g, b = GetStringColorObject(C.appearance.border.background):GetRGB()
    inside:SetColorTexture(r, g, b, 1)

    local fontString = frame:AttachFontString()
    frame.fontString = fontString
    fontString:SetPoint("LEFT", box, "RIGHT", 6, 0)
    fontString:SetHeight(20)
    fontString:SetTextToFit(text)

    return box
  end

  function MenuVariants.CreateCheckbox(text, frame, isSelected, data)
    local box = CreateSelectionBox(frame, text)
    if isSelected(data) then
      local check = frame:AttachTexture()
      check:SetDrawLayer("OVERLAY")
      check:SetPoint("CENTER", box)
      check:SetSize(16, 16)
      check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    return box
  end

  function MenuVariants.CreateRadio(text, frame, isSelected, data)
    local box = CreateSelectionBox(frame, text)
    if isSelected(data) then
      local dot = frame:AttachTexture()
      dot:SetDrawLayer("OVERLAY")
      dot:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
      dot:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
      dot:SetColorTexture(.2, 1, .8, 1)
    end
    return box
  end

  if C.global.errors_limit == "1" then
    UIErrorsFrame:SetHeight(25)
  end

  if C.global.errors_hide == "1" then
    UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
  else
    UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
  end
end)
