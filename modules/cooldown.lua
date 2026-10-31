pfUI:RegisterModule("cooldown", function ()
  -- The numbers are the Cooldown frame's own countdown (ClassicAPI): the
  -- engine ticks them, gated by the countdownForCooldowns cvar, and writes
  -- them through pfUI's shared formatter. pfUI only configures each frame as
  -- its timer is set.

  local function GetCooldownHeight(cooldown)
    return cooldown:GetParent() and cooldown:GetParent():GetHeight() or cooldown:GetHeight() or 0
  end

  -- sizes the numbers to the cooldown's current height; the dynamic size
  -- follows the frame, so SetCooldown calls this again whenever that height
  -- changes
  local function UpdateCountdownFont(cooldown)
    local size
    if not cooldown.pfCooldownType then
      size = tonumber(C.appearance.cd.font_size_foreign)
    elseif cooldown.pfCooldownType == "BLIZZARD" then
      size = tonumber(C.appearance.cd.font_size_blizz)
    elseif cooldown.pfCooldownSize then
      size = tonumber(cooldown.pfCooldownSize)
    else
      size = tonumber(C.appearance.cd.font_size)
    end

    local height = GetCooldownHeight(cooldown)
    cooldown.pfCountdownHeight = height

    -- enforce dynamic font size
    if C.appearance.cd.dynamicsize == "1" then
      size = math.max((height > 0 and height * .64 or 16), size)
    end

    cooldown:GetCountdownFontString():SetFont(pfUI.media[C.appearance.cd.font], size, "OUTLINE")
  end

  -- hook
  local function SetCooldown(this)
    -- 1.12's indicator Models have no countdown and keep the stock timer
    if not this:IsObjectType("Cooldown") then return end

    -- no numbers on unknown frames, nor on frames with omnicc's disable flag
    if (C.appearance.cd.foreign == "0" and not this.pfCooldownType) or this.noCooldownCount then
      this:SetHideCountdownNumbers(true)
      return
    end

    this:SetHideCountdownNumbers(this.pfCooldownStyleText == 0)

    -- no numbers for global cooldowns, except on frames that time auras
    if not this.pfCooldownType or this.pfCooldownType == "NOGCD" then
      this:SetMinimumCountdownDuration(tonumber(C.appearance.cd.threshold) * 1000)
    else
      this:SetMinimumCountdownDuration(0)
    end

    this:SetCountdownFormatter(GetCountdownFormatter())

    -- hide foreign animations; frames that set pfCooldownStyleAnimation
    -- configure their own sweep. The draw flags, not alpha, so the numbers
    -- stay visible
    if not this.pfCooldownStyleAnimation and C.appearance.cd.hideanim == "1" then
      this:SetDrawSwipe(false)
      this:SetDrawBling(false)
    end

    if GetCooldownHeight(this) ~= this.pfCountdownHeight then
      UpdateCountdownFont(this)
    end
  end

  -- hook the SetTimer function that every cooldown, Cooldown frame or
  -- stock indicator Model, is driven through.
  hooksecurefunc("CooldownFrame_SetTimer", SetCooldown)
end)
