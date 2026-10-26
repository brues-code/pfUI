pfUI:RegisterSkin("Game Menu", function ()
  StripTextures(GameMenuFrame)
  CreateBackdrop(GameMenuFrame, nil, true, .75)
  CreateBackdropShadow(GameMenuFrame)

  local menuWidth, menuHeight = GameMenuFrame:GetSize()
  GameMenuFrame:SetSize(menuWidth - 30, menuHeight + 6)

  local title = GetNoNameObject(GameMenuFrame, "FontString", "ARTWORK", MAIN_MENU)
  title:SetTextColor(1,1,1,1)
  title:ClearAllPoints()
  title:SetPoint("TOP", GameMenuFrame, "TOP", 0, 16)
  title:SetFont(pfUI.font_default, C.global.font_size + 2, "OUTLINE")

  local pfUIButton = CreateFrame("Button", "GameMenuButtonPFUI", GameMenuFrame, "GameMenuButtonTemplate")
  pfUIButton:SetPoint("TOP", 0, -10)
  pfUIButton:SetText(T["|cff33ffccpf|cffffffffUI|cffcccccc Config"])
  pfUIButton:SetScript("OnClick", function()
    pfUI.gui:Show()
    HideUIPanel(GameMenuFrame)
  end)

  local point, relativeTo, relativePoint, xOffset, yOffset = GameMenuButtonOptions:GetPoint()
  GameMenuButtonOptions:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset - 22)

  -- skin every button on the menu, including ones other addons add later
  local function SkinMenuButtons()
    for _, child in pairs({GameMenuFrame:GetChildren()}) do
      if child:GetFrameType() == "Button" and not child._pfMenuSkinned then
        SkinButton(child)
        child._pfMenuSkinned = true
      end
    end
  end

  SkinMenuButtons()
  GameMenuFrame:HookScript("OnShow", SkinMenuButtons)
end)
