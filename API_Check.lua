do
  -- ClassicAPI dependency gate.
  --
  -- Which TOC the client opened already answers "is ClassicAPI here?". Whenever
  -- the DLL is loaded it redirects the read of `pfUI\pfUI.toc` to
  -- `pfUI_Turtle.toc` (Turtle clients) or `pfUI_ClassicAPI.toc` (everything
  -- else). Reaching this file from the plain `pfUI.toc` therefore means
  -- ClassicAPI is absent -- and that TOC deliberately loads nothing but this
  -- file, so there is nothing to disable, only a notice to show.
  --
  -- The flavor TOCs still need a version gate of their own: the redirect has
  -- existed since ClassicAPI v1.11.0, well below the API surface pfUI relies
  -- on. There pfUI does load, and will throw wherever it reaches for something
  -- the installed DLL doesn't have yet -- the popup names the cause so those
  -- errors aren't a mystery.
  local PFUI_CLASSIC_API_MIN     = 11301  -- (X*10000 + Y*100 + Z)
  local PFUI_CLASSIC_API_LATEST  = PFUI_CLASSIC_API_MIN
  local PFUI_CLASSIC_API_WEBSITE = "https://github.com/brues-code/ClassicAPI"
  local PFUI_CLASSIC_API_LATEST_URL = PFUI_CLASSIC_API_WEBSITE .. "/releases/latest"
  local function FormatVersion(packed)
    local x = math.floor(packed / 10000)
    local y = math.floor(math.mod(packed, 10000) / 100)
    local z = math.mod(packed, 100)
    return string.format("v%d.%d.%d", x, y, z)
  end

  local headline, detail
  if not CLASSIC_API_VERSION then
    headline = "|cff33ffccpf|cffffffffUI|r has been disabled."
    detail = "The ClassicAPI DLL isn't loaded. Download the latest release from:"
  elseif CLASSIC_API_VERSION < PFUI_CLASSIC_API_MIN then
    headline = "|cff33ffccpf|cffffffffUI|r cannot run on this ClassicAPI."
    detail = "ClassicAPI " .. FormatVersion(PFUI_CLASSIC_API_MIN) .. " or newer is required -- any errors alongside this one are the APIs it is missing. Download the latest release from:"
  end

  if detail then
    local function ShowRequiredPopup()
      StaticPopupDialogs["PFUI_CLASSICAPI_REQUIRED"] = {
        text = headline .. "\n\n" .. detail,
        button1 = OKAY,
        hasEditBox = 1,
        editBoxWidth = 280,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
        OnShow = function()
          local editBox = getglobal(this:GetName().."EditBox")
          if editBox then
            editBox:SetText(PFUI_CLASSIC_API_LATEST_URL)
            editBox:HighlightText()
            editBox:SetFocus()
          end
        end,
      }
      StaticPopup_Show("PFUI_CLASSICAPI_REQUIRED")
      DEFAULT_CHAT_FRAME:AddMessage(
        headline .. " " .. detail .. " " .. PFUI_CLASSIC_API_LATEST_URL,
        1, 0.3, 0.3
      )
    end
    local loginFrame = CreateFrame("Frame")
    loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    loginFrame:SetScript("OnEvent", function()
      loginFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
      ShowRequiredPopup()
    end)
  elseif CLASSIC_API_VERSION < PFUI_CLASSIC_API_LATEST then
    EventUtil.ContinueOnPlayerLogin(function()
      C_Timer.After(8, function()
        DEFAULT_CHAT_FRAME:AddMessage(
          "|cff33ffccpf|rUI: ClassicAPI " .. FormatVersion(PFUI_CLASSIC_API_LATEST) .. " is available — " .. PFUI_CLASSIC_API_LATEST_URL,
          1, 0.85, 0.3
        )
      end)
    end)
  end
end
