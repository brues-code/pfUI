do
  -- ClassicAPI dependency check.
  -- pfUI relies pervasively on the modern C_* / SuperWoW / nameplate / focus
  -- API surface that ClassicAPI polyfills, so presence is required.
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
  if not CLASSIC_API_VERSION or CLASSIC_API_VERSION < PFUI_CLASSIC_API_MIN then
    local minVersion = FormatVersion(PFUI_CLASSIC_API_MIN)
    pfUI_disabled = true
    pfUI_locale = {}
    pfUI_profiles = {}
    pfUI_translation = {}

    -- ClassicAPI is required. Rather than let the ~140 files that follow flood
    -- errors as they load, stand up an inert stub so everything no-ops:
    --   * modules/skins register their body into a no-op, so it never runs;
    --   * the setfenv'd api/lib files run inside `env`, where CreateFrame and
    --     any missing global (C_*, SuperWoW, ...) resolve to a null object --
    --     so no real frames or live OnUpdate/OnEvent handlers get created and
    --     missing API calls just return null instead of erroring.
    local null  -- forward declaration so the metamethods can return it
    local nullmt = {
      __index = function() return null end,
      __newindex = function() end,
      __call = function() return null end,
      __concat = function() return "" end,
      __tostring = function() return "" end,
    }
    for _, op in ipairs({ "__add","__sub","__mul","__div","__mod","__pow","__unm" }) do
      nullmt[op] = function() return null end
    end
    for _, op in ipairs({ "__lt","__le","__eq" }) do nullmt[op] = function() return false end end
    null = setmetatable({}, nullmt)

    local realG = getfenv(0)
    pfUI = setmetatable({}, { __index = function() return null end })
    pfUI.env = setmetatable({}, {
      __index = function(_, k)
        if k == "CreateFrame" then return function() return null end end
        local v = realG[k]
        if v ~= nil then return v end
        return null
      end,
    })
    function pfUI:RegisterModule(_, _, _) end
    function pfUI:RegisterSkin(_, _, _) end
    function pfUI:GetEnvironment() return pfUI.env end
    local detail
    if not CLASSIC_API_VERSION then
      detail = "The ClassicAPI DLL isn't loaded. The |cff33ffcc!!!ClassicAPI|r addon ships bundled with it -- delete your |cff33ffcc!!!ClassicAPI|r folder and install the latest release from:"
    else
      detail = "ClassicAPI " .. minVersion .. " or newer is required. Delete your |cff33ffcc!!!ClassicAPI|r folder and reinstall the latest release from:"
    end

    local function ShowRequiredPopup()
      StaticPopupDialogs["PFUI_CLASSICAPI_REQUIRED"] = {
        text = "|cff33ffccpf|cffffffffUI|r has been disabled.\n\n" .. detail,
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
        "|cff33ffccpf|cffffffffUI|r disabled: " .. detail .. " " .. PFUI_CLASSIC_API_LATEST_URL,
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
