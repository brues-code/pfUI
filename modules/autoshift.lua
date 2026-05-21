pfUI:RegisterModule("autoshift", "vanilla", function ()
  pfUI.autoshift = CreateFrame("Frame")
  pfUI.autoshift:RegisterEvent("UI_ERROR_MESSAGE")

  pfUI.autoshift.scanString = string.gsub(SPELL_FAILED_ONLY_SHAPESHIFT, "%%s", "(.+)")
  pfUI.autoshift.mounts = {
    -- deDE
    "^Erhöht Tempo um (.+)%%",
    -- enUS
    "^Increases speed by (.+)%%",
    -- esES
    "^Aumenta la velocidad en un (.+)%%",
    -- frFR
    "^Augmente la vitesse de (.+)%%",
    -- ruRU
    "^Скорость увеличена на (.+)%%",
    -- koKR
    "^이동 속도 (.+)%%만큼 증가",
    -- zhCN
    "^速度提高(.+)%%",
    -- turtle-wow
    "speed based on", "Slow and steady...", "Riding",
    "Lento y constante...", "Aumenta la velocidad según tu habilidad de Montar.",
    "根据您的骑行技能提高速度。", "根据骑术技能提高速度。", "又慢又稳......",
  }

  -- Form ID -> icon-path fragment of that form's buff. GetShapeshiftFormID
  -- tells us the active form directly; we still need to locate the buff in
  -- the player's array to find the bid for CancelPlayerBuff.
  --
  -- Replaces the old texture-list scan plus moonkin_scan frame: the agility
  -- buff that shares moonkin's icon no longer causes false positives because
  -- form ID 31 is only reported when the player is genuinely in Moonkin Form,
  -- regardless of what other buffs happen to be active.
  pfUI.autoshift.shapeshifts = {
    [1]  = "ability_druid_catform",       -- Cat Form
    [3]  = "ability_druid_travelform",    -- Travel Form
    [4]  = "ability_druid_aquaticform",   -- Aquatic Form
    [5]  = "ability_racial_bearform",     -- Bear Form
    [8]  = "ability_racial_bearform",     -- Dire Bear (shares texture with Bear)
    [16] = "spell_nature_spiritwolf",     -- Shaman Ghost Wolf
    [28] = "spell_shadow_shadowform",     -- Priest Shadowform
    [31] = "spell_nature_forceofnature",  -- Druid Moonkin
  }

  pfUI.autoshift.errors = { SPELL_FAILED_NOT_MOUNTED, ERR_ATTACK_MOUNTED, ERR_TAXIPLAYERALREADYMOUNTED,
    SPELL_FAILED_NOT_SHAPESHIFT, SPELL_FAILED_NO_ITEMS_WHILE_SHAPESHIFTED, SPELL_NOT_SHAPESHIFTED,
    SPELL_NOT_SHAPESHIFTED_NOSPACE, ERR_CANT_INTERACT_SHAPESHIFTED, ERR_NOT_WHILE_SHAPESHIFTED,
    ERR_NO_ITEMS_WHILE_SHAPESHIFTED, ERR_TAXIPLAYERSHAPESHIFTED,ERR_MOUNT_SHAPESHIFTED,
    ERR_EMBLEMERROR_NOTABARDGEOSET }

  pfUI.autoshift.scanner = libtipscan:GetScanner("dismount")

  pfUI.autoshift:SetScript("OnEvent", function()
    -- switch stance if required
    for stances in string.gfind(arg1, pfUI.autoshift.scanString) do
      for _, stance in pairs({ strsplit(",", stances)}) do
        CastSpellByName(string.gsub(stance,"^%s*(.-)%s*$", "%1"))
      end
    end

    -- check if we need to stand up
    if arg1 == SPELL_FAILED_NOT_STANDING then
      SitOrStand()
      return
    end

    -- scan through buffs and cancel shapeshift/mount
    for id, errorstring in pairs(pfUI.autoshift.errors) do
      if arg1 == errorstring then
        -- don't cancel form when clicking on npcs while in combat
        if arg1 == ERR_CANT_INTERACT_SHAPESHIFTED and UnitAffectingCombat("player") then
          return
        end

        -- Phase 1: mounts take priority (mount/shapeshift can't coexist in
        -- vanilla, but the original error list also covers mount-only states).
        for i = 0, 31 do
          pfUI.autoshift.scanner:SetPlayerBuff(i)
          for _, str in pairs(pfUI.autoshift.mounts) do
            if pfUI.autoshift.scanner:Find(str) then
              CancelPlayerBuff(i)
              return
            end
          end
        end

        -- Phase 2: cancel the active shapeshift if any. GetShapeshiftFormID
        -- gives us the form directly; we iterate to find its buff bid.
        local formTexture = pfUI.autoshift.shapeshifts[GetShapeshiftFormID()]
        if formTexture then
          for i = 0, 31 do
            local buff = GetPlayerBuffTexture(i)
            if buff and string.find(string.lower(buff), formTexture, 1) then
              CancelPlayerBuff(i)
              return
            end
          end
        end
      end
    end
  end)
end)
