pfUI:RegisterModule("cooldown", function ()
  -- cache values
  -- local lowcolor    = {strsplit(",", C.appearance.cd.lowcolor)}
  -- local normalcolor = {strsplit(",", C.appearance.cd.normalcolor)}
  -- local minutecolor = {strsplit(",", C.appearance.cd.minutecolor)}
  -- local hourcolor   = {strsplit(",", C.appearance.cd.hourcolor)}
  -- local daycolor    = {strsplit(",", C.appearance.cd.daycolor)}

  local function pfCooldownOnUpdate()
    -- Throttle FIRST. One of these runs per visible cooldown text, every frame,
    -- so anything above this gate is multiplied by the frame rate and by how
    -- many cooldowns are ticking.
    local now = GetTime()
    if (this.tick or 0) > now then return end
    this.tick = now + .1

    local parent = this:GetParent()
    if not parent then this:Hide() return end

    -- avoid to set cooldowns on invalid frames. The cooldown frame is stashed
    -- at creation: resolving it as _G[parent:GetName() .. "Cooldown"] built and
    -- interned that string twice per call, and this is the hottest path in the
    -- UI. The stashed reference is also the frame itself rather than a guess
    -- from its parent's name, so it holds for cooldowns named anything else.
    if this.cooldown and not this.cooldown:IsShown() then
      this:Hide()
      return
    end

    -- fix own alpha value (should be inherited, but somehow isn't always)
    if this:GetAlpha() ~= parent:GetAlpha() then
      this:SetAlpha(parent:GetAlpha())
    end

    if this.start < now then
      -- calculating remaining time as it should be
      local remaining = this.duration - (now - this.start)
      if remaining >= 0 then
        this.text:SetText(GetColoredTimeString(remaining))
      else
        this:Hide()
      end
    else
      -- I have absolutely no idea, but it works:
      -- https://github.com/Stanzilla/WoWUIBugs/issues/47
      local currentTime = time()
      local startupTime = currentTime - now
      -- just a simplification of: ((2^32) - (start * 1000)) / 1000
      local cdTime = (2 ^ 32) / 1000 - this.start
      local cdStartTime = startupTime - cdTime
      local cdEndTime = cdStartTime + this.duration
      local remaining = cdEndTime - currentTime

      if remaining >= 0 then
        this.text:SetText(GetColoredTimeString(remaining))
      else
        this:Hide()
      end
    end
  end

  local height, size
  local textcount = 0
  local function pfCreateCoolDown(cooldown, start, duration)
    textcount = textcount + 1
    local name = cooldown.GetName and cooldown:GetName() or "pfCooldown" .. textcount

    cooldown.pfCooldownText = CreateFrame("Frame", name .. "Text", cooldown:GetParent())
    cooldown.pfCooldownText.cooldown = cooldown
    cooldown.pfCooldownText:SetAllPoints(cooldown)
    cooldown.pfCooldownText:SetFrameLevel(cooldown:GetParent():GetFrameLevel() + 2)
    cooldown.pfCooldownText.text = cooldown.pfCooldownText:CreateFontString(name .. "TextString", "OVERLAY")

    if not cooldown.pfCooldownType then
      size = tonumber(C.appearance.cd.font_size_foreign)
    elseif cooldown.pfCooldownType == "BLIZZARD" then
      size = tonumber(C.appearance.cd.font_size_blizz)
    elseif cooldown.pfCooldownSize then
      size = tonumber(cooldown.pfCooldownSize)
    else
      size = tonumber(C.appearance.cd.font_size)
    end

    -- enforce dynamic font size
    if C.appearance.cd.dynamicsize == "1" and cooldown.GetParent then
      height = cooldown:GetParent() and cooldown:GetParent():GetHeight() or cooldown:GetHeight() or 0
      size = math.max((height > 0 and height * .64 or 16), size)
    end

    cooldown.pfCooldownText.text:SetFont(pfUI.media[C.appearance.cd.font], size, "OUTLINE")
    cooldown.pfCooldownText.text:SetPoint("CENTER", cooldown.pfCooldownText, "CENTER", 0, 0)
    cooldown.pfCooldownText:SetScript("OnUpdate", pfCooldownOnUpdate)
  end

  -- hook
  local function SetCooldown(this, start, duration, enable)
    -- abort on unknown frames
    if C.appearance.cd.foreign == "0" and not this.pfCooldownType then
      return
    end

    -- add support for omnicc's disable flag
    if this.noCooldownCount then
      return
    end

    -- realign cooldown frames
    local parent = this.GetParent and this:GetParent()
    if parent and parent:GetWidth() / 36 > 0 then
      this:SetScale(parent:GetWidth() / 36)
      this:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
      this:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
    end

    -- don't draw global cooldowns
    if this.pfCooldownType == "NOGCD" and duration < tonumber(C.appearance.cd.threshold) then
      start, duration = 0, 0
    end

    -- disable GCDs on non pfUI frames
    if not this.pfCooldownType and duration < tonumber(C.appearance.cd.threshold) then
      start, duration = 0, 0
    end

    -- hide animation
    if this.pfCooldownStyleAnimation == 0 then
      this:SetAlpha(0)
    elseif not this.pfCooldownStyleAnimation and C.appearance.cd.hideanim == "1" then
      this:SetAlpha(0)
    end

    -- print time as text on cooldown frames
    if ( not this.pfCooldownStyleText or this.pfCooldownStyleText == 1)
    and start > 0 and duration > 0 and (not enable or enable > 0) then
      if( not this.pfCooldownText ) then
        pfCreateCoolDown(this, start, duration)
      end

      this.pfCooldownText.start = start
      this.pfCooldownText.duration = duration
      this.pfCooldownText:Show()
    elseif(this.pfCooldownText) then
      this.pfCooldownText:Hide()
    end
  end

  -- vanilla does not have a cooldown frame type, so we hook the
  -- regular SetTimer function that each one is calling.
  hooksecurefunc("CooldownFrame_SetTimer", SetCooldown)
end)