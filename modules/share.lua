pfUI:RegisterModule("share", function ()
  -- Profile sharing rides ClassicAPI's C_EncodingUtil:
  --   export:  diff vs defaults -> SerializeCBOR -> CompressString (zlib)
  --            -> EncodeBase64, prefixed with the format magic
  --   import:  the reverse, into a plain table — no loadstring, so a
  --            pasted profile can't execute code
  -- The Decode/Encode button converts between the transport blob and an
  -- editable JSON view of the same table.
  local MAGIC = "!pf1!"

  -- Deep-diff `tbl` against `default`, keeping only changed or added
  -- values. `ignored` keys are skipped at the top level only (matches the
  -- old serializer: "position"/"disabled" when Ignore Layout is checked).
  -- Returns nil when nothing differs.
  local function DiffConfig(tbl, default, ignored)
    local diff = nil
    for k, v in pairs(tbl) do
      if not ( ignored and ignored[k] ) then
        local dv = default and default[k]
        if type(v) == "table" then
          local sub = DiffConfig(v, type(dv) == "table" and dv or nil)
          if sub then
            diff = diff or {}
            diff[k] = sub
          end
        elseif v ~= dv and ( type(v) == "string" or type(v) == "number" or type(v) == "boolean" ) then
          diff = diff or {}
          diff[k] = v
        end
      end
    end
    return diff
  end

  -- EditBoxes don't soft-wrap one giant unbroken line; chunk the blob.
  local function wrap(str, width)
    local out = {}
    for i = 1, strlen(str), width do
      table.insert(out, strsub(str, i, i + width - 1))
    end
    return table.concat(out, "\n")
  end

  local function Encode(tbl)
    return MAGIC .. wrap(C_EncodingUtil.EncodeBase64(
      C_EncodingUtil.CompressString(
        C_EncodingUtil.SerializeCBOR(tbl))), 92)
  end

  local function Decode(text)
    if not text then return nil end
    text = gsub(text, "%s", "")
    if strsub(text, 1, strlen(MAGIC)) ~= MAGIC then return nil end
    local ok, result = pcall(function()
      return C_EncodingUtil.DeserializeCBOR(
        C_EncodingUtil.DecompressString(
          C_EncodingUtil.DecodeBase64(strsub(text, strlen(MAGIC) + 1))))
    end)
    if ok and type(result) == "table" then return result end
    return nil
  end

  local function DecodeJSON(text)
    if not text or gsub(text, "%s", "") == "" then return nil end
    local ok, result = pcall(function()
      return C_EncodingUtil.DeserializeJSON(text)
    end)
    if ok and type(result) == "table" then return result end
    return nil
  end

  -- Legacy import (pre-!pf1! exports): base64 -> LZW -> Lua source
  -- "pfUI_config = {...}". The base64 layer is standard and handled by
  -- C_EncodingUtil.DecodeBase64; only the custom LZW format needs the old
  -- Lua decoder. Import-only — new exports always use the CBOR pipeline.
  local function decompress(input)
    -- based on Rochet2's lzw compression
    if type(input) ~= "string" or strlen(input) < 1 then
      return nil
    end

    local control = strsub(input, 1, 1)
    if control == "u" then
      return strsub(input, 2)
    elseif control ~= "c" then
      return nil
    end
    input = strsub(input, 2)
    local len = strlen(input)

    if len < 2 then
      return nil
    end

    local dict = {}
    for i = 0, 255 do
      local ic, iic = strchar(i), strchar(i, 0)
      dict[iic] = ic
    end

    local a, b = 0, 1

    local result = {}
    local n = 1
    local last = strsub(input, 1, 2)
    result[n] = dict[last]
    n = n+1
    for i = 3, len, 2 do
      local code = strsub(input, i, i+1)
      local lastStr = dict[last]
      if not lastStr then
        return nil
      end
      local toAdd = dict[code]
      if toAdd then
        result[n] = toAdd
        n = n+1
        local str = lastStr..strsub(toAdd, 1, 1)
        if a >= 256 then
          a, b = 0, b+1
          if b >= 256 then
            dict = {}
            b = 1
          end
        end
        dict[strchar(a,b)] = str
        a = a+1
      else
        local str = lastStr..strsub(lastStr, 1, 1)
        result[n] = str
        n = n+1
        if a >= 256 then
          a, b = 0, b+1
          if b >= 256 then
            dict = {}
            b = 1
          end
        end
        dict[strchar(a,b)] = str
        a = a+1
      end
      last = code
    end
    return table.concat(result)
  end

  local function DecodeLegacy(text)
    if not text or gsub(text, "%s", "") == "" then return nil end

    -- encoded blob? peel base64 + LZW down to Lua source. Raw (already
    -- decoded) source pastes are accepted as-is.
    local source = text
    local stripped = gsub(text, "%s", "")
    local ok, decoded = pcall(function()
      return C_EncodingUtil.DecodeBase64(stripped)
    end)
    if ok and decoded then
      local decompressed = decompress(decoded)
      if decompressed then source = decompressed end
    end

    local chunk = loadstring(source)
    if not chunk then return nil end

    -- Sandbox the chunk: an empty environment means it can assign its
    -- config table but can't reach any global or API function — a legacy
    -- profile string is data, never code.
    local sandbox = {}
    setfenv(chunk, sandbox)
    if not pcall(chunk) then return nil end
    if type(sandbox.pfUI_config) == "table" then return sandbox.pfUI_config end
    return nil
  end

  do -- Window
    local f = CreateFrame("Frame", "pfShare", UIParent)
    f:Hide()
    f:SetPoint("CENTER", 0, 0)
    f:SetWidth(580)
    f:SetHeight(420)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")

    f:SetScript("OnShow", function()
      if pfUI.gui and pfUI.gui:IsShown() then
        f.hadGUI = true
        pfUI.gui:Hide()
      else
        f.hadGUI = nil
      end
    end)

    f:SetScript("OnHide", function()
      if f.hadGUI then
        pfUI.gui:Show()
      end
    end)

    CreateBackdrop(f, nil, true, 0.8)
    CreateBackdropShadow(f)
    table.insert(UISpecialFrames, "pfShare")

    do -- Edit Box
      f.scroll = pfUI.api.CreateScrollFrame("pfShareScroll", f)
      f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
      f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 50)
      f.scroll:SetWidth(560)
      f.scroll:SetHeight(400)

      f.scroll.backdrop = CreateFrame("Frame", "pfShareScrollBackdrop", f.scroll)
      f.scroll.backdrop:SetFrameLevel(1)
      f.scroll.backdrop:SetPoint("TOPLEFT", f.scroll, "TOPLEFT", -5, 5)
      f.scroll.backdrop:SetPoint("BOTTOMRIGHT", f.scroll, "BOTTOMRIGHT", 5, -5)
      pfUI.api.CreateBackdrop(f.scroll.backdrop, nil, true)

      f.scroll.text = CreateFrame("EditBox", "pfShareEditBox", f.scroll)
      f.scroll.text.bg = f.scroll.text:CreateTexture(nil, "OVERLAY")
      f.scroll.text.bg:SetAllPoints(f.scroll.text)
      f.scroll.text.bg:SetTexture(1,1,1,.05)
      f.scroll.text:SetMultiLine(true)
      f.scroll.text:SetWidth(560)
      f.scroll.text:SetHeight(400)
      f.scroll.text:SetAllPoints(f.scroll)
      f.scroll.text:SetTextInsets(15,15,15,15)
      f.scroll.text:SetFont(pfUI.media["font:RobotoMono.ttf"], 9)
      f.scroll.text:SetAutoFocus(false)
      f.scroll.text:SetJustifyH("LEFT")
      f.scroll.text:SetScript("OnEscapePressed", function() this:ClearFocus() end)
      f.scroll.text:SetScript("OnTextChanged", function()
        this:GetParent():UpdateScrollChildRect()
        this:GetParent():UpdateScrollState()

        local text = this:GetText()
        local blob = Decode(text)
        local json = not blob and DecodeJSON(text) or nil
        local legacy = not blob and not json and DecodeLegacy(text) or nil

        if blob or json or legacy then
          f.loadButton:Enable()
          f.loadButton.text:SetTextColor(.5,1,.5,1)
        else
          f.loadButton:Disable()
          f.loadButton.text:SetTextColor(1,.5,.5,1)
        end

        if blob or legacy then
          -- decoding a legacy string yields the JSON view; re-encoding it
          -- from there produces a new-format blob (migration path)
          f.readButton:Enable()
          f.readButton.text:SetText(T["Decode"])
          f.readButton.func = function()
            local current = f.scroll.text:GetText()
            local config = Decode(current) or DecodeLegacy(current)
            if config then
              f.scroll.text:SetText(C_EncodingUtil.SerializeJSON(config))
            end
          end
        elseif json then
          f.readButton:Enable()
          f.readButton.text:SetText(T["Encode"])
          f.readButton.func = function()
            local config = DecodeJSON(f.scroll.text:GetText())
            if config then
              f.scroll.text:SetText(Encode(config))
            end
          end
        else
          f.readButton:Disable()
          f.readButton.text:SetText(T["N/A"])
        end
      end)
      f.scroll:SetScrollChild(f.scroll.text)
    end

    do -- button: close
      f.closeButton = CreateFrame("Button", "pfShareClose", f)
      f.closeButton:SetPoint("TOPRIGHT", -5, -5)
      f.closeButton:SetHeight(12)
      f.closeButton:SetWidth(12)
      f.closeButton.texture = f.closeButton:CreateTexture("pfQuestionDialogCloseTex")
      f.closeButton.texture:SetTexture(pfUI.media["img:close"])
      f.closeButton.texture:ClearAllPoints()
      f.closeButton.texture:SetAllPoints(f.closeButton)
      f.closeButton.texture:SetVertexColor(1,.25,.25,1)
      pfUI.api.SkinButton(f.closeButton, 1, .5, .5)
      f.closeButton:SetScript("OnClick", function()
       this:GetParent():Hide()
      end)
    end

    do -- checkbox: ignore positions
      f.ignorePosition = CreateFrame("CheckButton", "pfShareIgnorePosition", f, "UICheckButtonTemplate")
      f.ignorePosition:SetNormalTexture("")
      f.ignorePosition:SetPushedTexture("")
      f.ignorePosition:SetHighlightTexture("")
      CreateBackdrop(f.ignorePosition, nil, true)
      f.ignorePosition:SetWidth(14)
      f.ignorePosition:SetHeight(14)
      f.ignorePosition:SetPoint("BOTTOMLEFT", 10, 10)

      f.ignorePositionCaption = f.ignorePosition:CreateFontString("Status", "LOW", "GameFontNormal")
      f.ignorePositionCaption:SetFont(pfUI.font_default, C.global.font_size + 2, "OUTLINE")
      f.ignorePositionCaption:SetPoint("LEFT", f.ignorePosition, "RIGHT", 5, 0)
      f.ignorePositionCaption:SetFontObject(GameFontWhite)
      f.ignorePositionCaption:SetJustifyH("LEFT")
      f.ignorePositionCaption:SetText(T["Ignore Layout"])
    end


    do -- button: load
      f.loadButton = CreateFrame("Button", "pfShareLoad", f)
      pfUI.api.SkinButton(f.loadButton)
      f.loadButton:SetPoint("BOTTOMRIGHT", -5, 5)
      f.loadButton:SetWidth(75)
      f.loadButton:SetHeight(25)
      f.loadButton.text = f.loadButton:CreateFontString("Caption", "LOW", "GameFontWhite")
      f.loadButton.text:SetAllPoints(f.loadButton)
      f.loadButton.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
      f.loadButton.text:SetText(T["Import"])
      f.loadButton:SetScript("OnClick", function()
        local text = f.scroll.text:GetText()
        local config = Decode(text) or DecodeJSON(text) or DecodeLegacy(text)
        if not config then return end

        _G.pfUI_config = config
        C = _G.pfUI_config
        pfUI:LoadConfig()

        -- Skip firstrun wizard when importing a shared profile
        -- The imported config is a complete setup, no wizard needed
        if pfUI.firstrun and pfUI.firstrun.steps then
          for _, step in pairs(pfUI.firstrun.steps) do
            pfUI_init[step.name] = true
          end
        end

        CreateQuestionDialog(T["Some settings need to reload the UI to take effect.\nDo you want to reloadUI now?"], ReloadUI)
      end)
    end

    do -- button: read
      f.readButton = CreateFrame("Button", "pfShareDecode", f)
      pfUI.api.SkinButton(f.readButton)
      f.readButton:SetPoint("RIGHT", f.loadButton, "LEFT", -10, 0)
      f.readButton:SetWidth(75)
      f.readButton:SetHeight(25)
      f.readButton.text = f.readButton:CreateFontString("Caption", "LOW", "GameFontWhite")
      f.readButton.text:SetAllPoints(f.readButton)
      f.readButton.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
      f.readButton.text:SetText(T["N/A"])
      f.readButton:SetScript("OnClick", function()
        this.func()
      end)
    end

    do -- button: export
      f.exportButton = CreateFrame("Button", "pfShareExport", f)
      pfUI.api.SkinButton(f.exportButton)
      f.exportButton:SetPoint("RIGHT", f.readButton, "LEFT", -10, 0)
      f.exportButton:SetWidth(75)
      f.exportButton:SetHeight(25)
      f.exportButton.text = f.exportButton:CreateFontString("Caption", "LOW", "GameFontWhite")
      f.exportButton.text:SetAllPoints(f.exportButton)
      f.exportButton.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
      f.exportButton.text:SetText(T["Export"])
      f.exportButton:SetScript("OnClick", function()
        -- generate a default config
        local myconfig = CopyTable(pfUI_config)
        _G.pfUI_config = {}
        pfUI:LoadConfig()
        local defconfig = CopyTable(pfUI_config)

        -- restore config and references
        _G.pfUI_config = CopyTable(myconfig)
        C = _G.pfUI_config

        local ignored = {}
        ignored["position"] = f.ignorePosition:GetChecked()
        ignored["disabled"] = f.ignorePosition:GetChecked()

        local encoded = Encode(DiffConfig(myconfig, defconfig, ignored) or {})
        f.scroll.text:SetText(encoded)
        f.scroll.text.value = encoded
        f.scroll:SetVerticalScroll(0)
      end)
    end

    _G.SLASH_PFEXPORT1, _G.SLASH_PFEXPORT2, _G.SLASH_PFEXPORT3 = "/export", "/import", "/share"
    function SlashCmdList.PFEXPORT(msg, editbox)
      f:Show()
    end
  end
end)
