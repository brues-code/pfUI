pfUI:RegisterModule("autoshift", function ()
  pfUI.autoshift = CreateFrame("Frame")
  pfUI.autoshift:RegisterEvent("UI_ERROR_MESSAGE")

  pfUI.autoshift.scanString = string.gsub(SPELL_FAILED_ONLY_SHAPESHIFT, "%%s", "(.+)")

  pfUI.autoshift.errors = { SPELL_FAILED_NOT_MOUNTED, ERR_ATTACK_MOUNTED, ERR_TAXIPLAYERALREADYMOUNTED,
    SPELL_FAILED_NOT_SHAPESHIFT, SPELL_FAILED_NO_ITEMS_WHILE_SHAPESHIFTED, SPELL_NOT_SHAPESHIFTED,
    SPELL_NOT_SHAPESHIFTED_NOSPACE, ERR_CANT_INTERACT_SHAPESHIFTED, ERR_NOT_WHILE_SHAPESHIFTED,
    ERR_NO_ITEMS_WHILE_SHAPESHIFTED, ERR_TAXIPLAYERSHAPESHIFTED,ERR_MOUNT_SHAPESHIFTED,
    ERR_EMBLEMERROR_NOTABARDGEOSET }

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

        -- Mounts take priority over shapeshifts (the two can't coexist in
        -- vanilla, but the error list covers mount-only states too). Both
        -- helpers do their own engine-side aura scan and send the cancel
        -- packet directly, so no buff iteration or bid lookup is needed.
        if IsMounted() then
          Dismount()
        elseif GetShapeshiftFormID() ~= 0 then
          CancelShapeshiftForm()
        end
      end
    end
  end)
end)
