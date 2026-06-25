pfUI:RegisterModule("castbar", function ()

  local font = C.castbar.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
  local font_size = C.castbar.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
  local rawborder, default_border = GetBorderSize("unitframes")
  local cbtexture = pfUI.media[C.appearance.castbar.texture]

  -- Helper function for castbar timer formatting
  local function FormatCastbarTime(value)
    if C.unitframes.castbardecimals == "1" then
      -- 1 decimal, round half up (matches Blizzard spellbook display)
      return string.format("%.1f", floor(value * 10 + 0.5) / 10)
    else
      -- 2 decimals (default)
      return string.format("%.2f", value)
    end
  end

  local function CreateCastbar(name, parent, unitstr, unitname)
    local cb = CreateFrame("Frame", name, parent or UIParent)

    cb:SetHeight(C.global.font_size * 1.5)
    cb:SetFrameStrata("MEDIUM")
    cb:SetFrameLevel(8)

    cb.unitstr = unitstr
    cb.unitname = unitname

    -- icon
    cb.icon = CreateFrame("Frame", nil, cb)
    cb.icon:SetPoint("TOPLEFT", 0, 0)
    cb.icon:SetHeight(16)
    cb.icon:SetWidth(16)

    cb.icon.texture = cb.icon:CreateTexture(nil, "OVERLAY")
    cb.icon.texture:SetAllPoints()
    cb.icon.texture:SetTexCoord(.08, .92, .08, .92)
    CreateBackdrop(cb.icon, default_border)

    -- statusbar
    cb.bar = CreateFrame("StatusBar", nil, cb)
    cb.bar:SetStatusBarTexture(cbtexture)
    cb.bar:ClearAllPoints()
    cb.bar:SetAllPoints(cb)
    cb.bar:SetMinMaxValues(0, 100)
    cb.bar:SetValue(20)
    local r,g,b,a = strsplit(",", C.appearance.castbar.castbarcolor)
    cb.bar:SetStatusBarColor(r,g,b,a)
    CreateBackdrop(cb.bar, default_border)
    CreateBackdropShadow(cb.bar)

    -- text left
    cb.bar.left = cb.bar:CreateFontString("Status", "DIALOG", "GameFontNormal")
    cb.bar.left:ClearAllPoints()
    cb.bar.left:SetPoint("TOPLEFT", cb.bar, "TOPLEFT", 3 + C.castbar[unitstr].txtleftoffx, C.castbar[unitstr].txtleftoffy)
    cb.bar.left:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", -3 + C.castbar[unitstr].txtleftoffx, C.castbar[unitstr].txtleftoffy)
    cb.bar.left:SetNonSpaceWrap(false)
    cb.bar.left:SetFontObject(GameFontWhite)
    cb.bar.left:SetTextColor(1,1,1,1)
    cb.bar.left:SetFont(font, font_size, "OUTLINE")
    cb.bar.left:SetJustifyH("left")

    -- text right
    cb.bar.right = cb.bar:CreateFontString("Status", "DIALOG", "GameFontNormal")
    cb.bar.right:ClearAllPoints()
    cb.bar.right:SetPoint("TOPLEFT", cb.bar, "TOPLEFT", 3 + C.castbar[unitstr].txtrightoffx, C.castbar[unitstr].txtrightoffy)
    cb.bar.right:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", -3 + C.castbar[unitstr].txtrightoffx, C.castbar[unitstr].txtrightoffy)
    cb.bar.right:SetNonSpaceWrap(false)
    cb.bar.right:SetFontObject(GameFontWhite)
    cb.bar.right:SetTextColor(1,1,1,1)
    cb.bar.right:SetFont(font, font_size, "OUTLINE")
    cb.bar.right:SetJustifyH("right")

    cb.bar.lag = cb.bar:CreateTexture(nil, "OVERLAY")
    cb.bar.lag:SetPoint("TOPRIGHT", cb.bar, "TOPRIGHT", 0, 0)
    cb.bar.lag:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", 0, 0)
    cb.bar.lag:SetTexture(1,.2,.2,.2)

    -- OnUpdate script with throttle for performance optimization
    cb:SetScript("OnUpdate", function()
      -- Throttle for performance
      if (this.tick or 0) > GetTime() then return end
      this.tick = GetTime() + 0.020 -- ~50 FPS for smooth castbar

      if this.drag and this.drag:IsShown() then
        this:SetAlpha(1)
        return
      end

      if not UnitExists(this.unitstr) then
        this:SetAlpha(0)
      end

      if this.fadeout and this:GetAlpha() > 0 then
        if this:GetAlpha() == 0 then
          this.fadeout = nil
        end

        this:SetAlpha(this:GetAlpha()-0.05)
      end

      local channel = nil
      local query = this.unitstr ~= "" and this.unitstr or this.unitname
      if not query then return end

      -- C_Spell takes a unit token; ClassicAPI's resolver also accepts GUID
      -- strings, so this.unitstr can be "player" / "target" / "focus" or a
      -- raw "0x..." GUID transparently.
      local cast, nameSubtext, texture, startTime, endTime
      local name, _, tex, startMs, endMs, _, _, _, spellID = C_Spell.UnitCastingInfo(query)
      local isChan
      if not name then
        name, _, tex, startMs, endMs, _, _, spellID = C_Spell.UnitChannelInfo(query)
        isChan = true
      end
      -- Synthetic fallback for abilities the engine treats as instant-cast but
      -- that have a meaningful wait window (e.g. Turtle WoW Steady Shot on the
      -- ranged-swing queue). Per-unit table populated by module-side hooks.
      if not name and pfUI.synthetic_casts and pfUI.synthetic_casts[query] then
        local s = pfUI.synthetic_casts[query]
        if s.endMs > GetTime() * 1000 then
          name, tex, startMs, endMs, spellID = s.name, s.icon, s.startMs, s.endMs, s.spellID
          isChan = nil
        end
      end
      if name and startMs and endMs then
        cast = name
        texture = tex
        startTime = startMs
        endTime = endMs
        if spellID and GetSpellRecField then
          nameSubtext = GetSpellRecField(spellID, "rank") or ""
        else
          nameSubtext = ""
        end
        if isChan then channel = cast end
      end

      if cast then
        local duration = endTime - startTime
        local max = duration / 1000
        local cur = GetTime() - startTime / 1000

        this:SetAlpha(1)

        local spellname = this.showname and cast and cast .. " " or ""
        local rank = this.showrank and nameSubtext and nameSubtext ~= "" and string.format("|cffaaffcc[%s]|r", nameSubtext) or ""

        if this.endTime ~= endTime then
          this.bar:SetStatusBarColor(strsplit(",", C.appearance.castbar[(channel and "channelcolor" or "castbarcolor")]))
          this.bar.left:SetText(spellname .. rank)
          this.fadeout = nil
          this.endTime = endTime

          -- set texture
          if texture and this.showicon then
            local size = this:GetHeight()
            this.icon:Show()
            this.icon:SetHeight(size)
            this.icon:SetWidth(size)
            this.icon.texture:SetTexture(texture)
            this.bar:SetPoint("TOPLEFT", this.icon, "TOPRIGHT", this.spacing, 0)
          else
            this.bar:SetPoint("TOPLEFT", this, 0, 0)
            this.icon:Hide()
          end

          if this.showlag then
            local _, _, lag = GetNetStats()
            local width = this:GetWidth() / (duration/1000) * (lag/1000)
            this.bar.lag:SetWidth(math.min(this:GetWidth(), width))
          else
            this.bar.lag:Hide()
          end
        end

        local newMax = duration / 1000
        if this.lastMax ~= newMax then
          this.bar:SetMinMaxValues(0, newMax)
          this.lastMax = newMax
        end

        if channel then
          cur = max + startTime/1000 - GetTime()
        end

        cur = cur > max and max or cur
        cur = cur < 0 and 0 or cur

        this.bar:SetValue(cur)

        if this.showtimer then
          if this.delay and this.delay > 0 then
            local delay = "|cffffaaaa" .. (channel and "-" or "+") .. FormatCastbarTime(this.delay) .. " |r "
            this.bar.right:SetText(delay .. FormatCastbarTime(cur) .. " / " .. FormatCastbarTime(max))
          else
            this.bar.right:SetText(FormatCastbarTime(cur) .. " / " .. FormatCastbarTime(max))
          end
        end

        this.fadeout = nil
      else
        this.bar:SetMinMaxValues(1,100)
        this.bar:SetValue(100)
        this.lastMax = nil
        this.fadeout = 1
        this.delay = 0
      end
    end)

    -- register for spell delay
    -- Prefer Nampower's SPELL_DELAYED_SELF (gives casterGuid + delayMs directly).
    -- Fall back to vanilla SPELLCAST_DELAYED if Nampower is not available.
    local playerarg = nil
    local function ApplyPushback(delayMs)
      if not delayMs or delayMs <= 0 or not this.endTime then return end
      this.delay = (this.delay or 0) + delayMs / 1000
      this.endTime = this.endTime + delayMs
    end

    cb:RegisterEvent("SPELL_DELAYED_SELF")
    cb:RegisterEvent(CASTBAR_EVENT_CAST_DELAY)
    cb:RegisterEvent(CASTBAR_EVENT_CHANNEL_DELAY)
    cb:RegisterEvent(CASTBAR_EVENT_CAST_START)
    cb:RegisterEvent(CASTBAR_EVENT_CHANNEL_START)
    cb:SetScript("OnEvent", function()
      if this.unitstr and not UnitIsUnit(this.unitstr, "player") then return end

      if event == "SPELL_DELAYED_SELF" then
        -- arg1=casterGuid, arg2=delayMs (Nampower, most accurate)
        ApplyPushback(arg2)

      elseif event == CASTBAR_EVENT_CAST_DELAY then
        -- SPELLCAST_DELAYED fallback intentionally removed - addon requires Nampower.
        -- Cast pushback is handled by SPELL_DELAYED_SELF above.
        return

      elseif event == CASTBAR_EVENT_CHANNEL_DELAY then
        -- SPELLCAST_CHANNEL_UPDATE fires when a channel is pushed back by damage.
        -- arg1 = new remaining time in ms. Channel ends sooner = newEndTime < this.endTime.
        if not this.endTime or not arg1 then return end
        local newEndTime = GetTime() * 1000 + arg1
        local diff = this.endTime - newEndTime  -- positive = time lost to pushback
        if diff > 50 then
          this.delay = (this.delay or 0) + diff / 1000
          this.endTime = newEndTime
        end

      elseif event == CASTBAR_EVENT_CAST_START or event == CASTBAR_EVENT_CHANNEL_START then
        playerarg = true
        this.delay = 0
      end
    end)

    cb:SetAlpha(0)
    return cb
  end

  pfUI.castbar = CreateFrame("Frame", "pfCastBar", UIParent)

  -- hide blizzard
  if C.castbar.player.hide_blizz == "1" then
    CastingBarFrame:SetScript("OnShow", function() CastingBarFrame:Hide() end)
    CastingBarFrame:UnregisterAllEvents()
    CastingBarFrame:Hide()
  end

  -- [[ pfPlayerCastbar ]] --
  if C.castbar.player.hide_pfui == "0" then
    pfUI.castbar.player = CreateCastbar("pfPlayerCastbar", UIParent, "player")
    pfUI.castbar.player.showicon = C.castbar.player.showicon == "1" and true or nil
    pfUI.castbar.player.showname = C.castbar.player.showname == "1" and true or nil
    pfUI.castbar.player.showtimer = C.castbar.player.showtimer == "1" and true or nil
    pfUI.castbar.player.showlag = C.castbar.player.showlag == "1" and true or nil
    pfUI.castbar.player.showrank = C.castbar.player.showrank == "1" and true or nil
    pfUI.castbar.player.spacing = default_border * 2 + tonumber(C.unitframes.player.pspace) * GetPerfectPixel()

    if pfUI.uf.player then
      local anchor = pfUI.uf.player.portrait:GetHeight() > pfUI.uf.player:GetHeight() and pfUI.uf.player.power or pfUI.uf.player
      local width = C.castbar.player.width ~= "-1" and C.castbar.player.width or anchor:GetWidth()
      pfUI.castbar.player:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -pfUI.castbar.player.spacing)
      pfUI.castbar.player:SetWidth(width)
    else
      local width = C.castbar.player.width ~= "-1" and C.castbar.player.width or 200
      pfUI.castbar.player:SetPoint("CENTER", 0, -200)
      pfUI.castbar.player:SetWidth(width)
    end

    if C.castbar.player.height ~= "-1" then
      pfUI.castbar.player:SetHeight(C.castbar.player.height)
    end

    UpdateMovable(pfUI.castbar.player)
  end

  -- [[ pfTargetCastbar ]] --
  if C.castbar.target.hide_pfui == "0" then
    pfUI.castbar.target = CreateCastbar("pfTargetCastbar", UIParent, "target")
    pfUI.castbar.target.showicon = C.castbar.target.showicon == "1" and true or nil
    pfUI.castbar.target.showname = C.castbar.target.showname == "1" and true or nil
    pfUI.castbar.target.showtimer = C.castbar.target.showtimer == "1" and true or nil
    pfUI.castbar.target.showlag = C.castbar.target.showlag == "1" and true or nil
    pfUI.castbar.target.showrank = C.castbar.target.showrank == "1" and true or nil
    pfUI.castbar.target.spacing = default_border * 2 + tonumber(C.unitframes.target.pspace) * GetPerfectPixel()

    if pfUI.uf.target then
      local anchor = pfUI.uf.target.portrait:GetHeight() > pfUI.uf.target:GetHeight() and pfUI.uf.target.power or pfUI.uf.target
      local width = C.castbar.target.width ~= "-1" and C.castbar.target.width or anchor:GetWidth()
      pfUI.castbar.target:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -pfUI.castbar.target.spacing)
      pfUI.castbar.target:SetWidth(width)
    else
      local width = C.castbar.target.width ~= "-1" and C.castbar.target.width or 200
      pfUI.castbar.target:SetPoint("CENTER", 0, -225)
      pfUI.castbar.target:SetWidth(width)
    end

    if C.castbar.target.height ~= "-1" then
      pfUI.castbar.target:SetHeight(C.castbar.target.height)
    end

    UpdateMovable(pfUI.castbar.target)
  end

  -- [[ pfFocusCastbar ]] --
  if C.castbar.focus.hide_pfui == "0" and pfUI.uf.focus then
    pfUI.castbar.focus = CreateCastbar("pfFocusCastbar", UIParent, "focus")
    pfUI.castbar.focus.showicon = C.castbar.focus.showicon == "1" and true or nil
    pfUI.castbar.focus.showname = C.castbar.focus.showname == "1" and true or nil
    pfUI.castbar.focus.showtimer = C.castbar.focus.showtimer == "1" and true or nil
    pfUI.castbar.focus.showlag = C.castbar.focus.showlag == "1" and true or nil
    pfUI.castbar.focus.showrank = C.castbar.focus.showrank == "1" and true or nil
    pfUI.castbar.focus.spacing = default_border * 2 + tonumber(C.unitframes.focus.pspace) * GetPerfectPixel()

    local anchor = pfUI.uf.focus.portrait:GetHeight() > pfUI.uf.focus:GetHeight() and pfUI.uf.focus.power or pfUI.uf.focus
    local width = C.castbar.focus.width ~= "-1" and C.castbar.focus.width or anchor:GetWidth()
    pfUI.castbar.focus:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -pfUI.castbar.focus.spacing)
    pfUI.castbar.focus:SetWidth(width)

    if C.castbar.focus.height ~= "-1" then
      pfUI.castbar.focus:SetHeight(C.castbar.focus.height)
    end

    -- bind castbar to the "focus" unit token; the GUID resolves at read time
    pfUI.castbar.focus.unitstr = "focus"

    UpdateMovable(pfUI.castbar.focus)
  end
end)