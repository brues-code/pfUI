pfUI:RegisterModule("chatcopy", function ()
  EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
    if not pfUI.chat then return end

    local button = CreateFrame("Button", "pfChatCopyButton", pfUI.chat.left.panelTop)
    button:SetPoint("TOPRIGHT", 0, 0)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetWidth(16)
    button:SetHeight(16)
    button:SetAlpha(.25)
    button.icon = button:CreateTexture(nil,"BACKGROUND")
    button.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Disabled")
    button.icon:SetAllPoints()

    -- show or hide the copy box of every chat frame
    local function SetCopyMode(state)
      button.state = state

      for i=1, _G.NUM_CHAT_WINDOWS do
        local scroll = _G["ChatFrame"..i].scroll
        if scroll then
          scroll:SetShown(state)
        end
      end

      if state then
        button.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
      else
        button.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Disabled")
      end
    end

    button:SetScript("OnClick", function()
      if arg1 == "LeftButton" then
        SetCopyMode(not this.state)
      elseif arg1 == "RightButton" then
        if ChatMenu:IsShown() then
          ChatMenu:Hide()
        else
          ChatMenu:Show()
          ChatMenu:ClearAllPoints()
          ChatMenu:SetPoint("BOTTOMLEFT", this, "TOPRIGHT", 0, 0)
        end
      end
    end)

    button:SetScript("OnEnter", function()
      this:SetAlpha(1)
    end)

    button:SetScript("OnLeave", function()
      this:SetAlpha(.4)
    end)

    for i=1, _G.NUM_CHAT_WINDOWS do
      local frame = _G["ChatFrame"..i]

      -- the chat frame's messages in an edit box to copy from
      local scroll = CreateFrame("Frame", "pfChatCopy" .. i, frame, "pfUIScrollingEditBoxTemplate")
      scroll:SetAllPoints(frame)
      scroll.tex = scroll:CreateTexture(nil, "BACKGROUND")
      scroll.tex:SetColorTexture(0,0,0,.95)
      scroll.tex:SetPoint("TOPLEFT", -3, 3)
      scroll.tex:SetPoint("BOTTOMRIGHT", 3, -3)
      scroll:Hide()

      scroll:RegisterCallback("OnEscapePressed", function()
        SetCopyMode(false)
      end, scroll)

      scroll:HookScript("OnShow", function()
        -- each line in its own color, which also replaces the |r resets inside it
        local lines = {}
        for index=1, frame:GetNumMessages() do
          local text, r, g, b = frame:GetMessageInfo(index)
          if C.chat.text.copytime == "0" then
            text = pfUI.chat.StripTimestamp(text)
          end
          local color = rgbhex(r, g, b)
          table.insert(lines, color .. text:gsub("|r", color))
        end
        local text = table.concat(lines, "\n")

        scroll:SetFont(frame:GetFont())
        scroll:SetText(text)
        scroll:SetFocus()
        scroll:SetCursorPosition(#text)

        -- the edit box lays the text out in this frame's update, so scroll to
        -- the newest line after it; the caret only scrolls the focused box
        RunNextFrame(function()
          local scrollBox = scroll:GetScrollBox()
          scrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
          scrollBox:ScrollToEnd(ScrollBoxConstants.NoScrollInterpolation)
        end)
      end)

      frame.scroll = scroll
    end
  end)
end)
