pfUI:RegisterModule("updatenotify", function ()
  if pfUI.version.string == "dev" then return end

  local alreadyshown
  local localversion  = tonumber(pfUI.version.major*10000 + pfUI.version.minor*100 + pfUI.version.fix)
  local remoteversion = tonumber(pfUI_init.updateavailable) or 0
  local loginchannels = { "BATTLEGROUND", "RAID", "GUILD" }
  local groupchannels = { "BATTLEGROUND", "RAID" }

  local ADDON_PREFIX = "pfUI-brues"

  local localbranch = "main"
  local versionmsg  = "VERSION:" .. localversion .. ":" .. localbranch

  pfUI.updater = CreateFrame("Frame")
  pfUI.updater:RegisterEvent("CHAT_MSG_ADDON")
  pfUI.updater:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.updater:RegisterEvent("PARTY_MEMBERS_CHANGED")
  pfUI.updater:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" and arg1 == ADDON_PREFIX then
      local v, rv, branch = pfUI.api.strsplit(":", arg2)
      rv = tonumber(rv)
      -- only process VERSION messages from the same branch
      -- messages without a branch tag (old versions) are ignored
      if v == "VERSION" and rv and branch == localbranch then
        if rv > localversion then
          pfUI_init.updateavailable = rv
        end
      end
    end

    if event == "PARTY_MEMBERS_CHANGED" then
      local groupsize = IsInRaid() and GetNumRaidMembers() or IsInGroup() and GetNumPartyMembers() or 0
      if ( this.group or 0 ) < groupsize then
        for _, chan in pairs(groupchannels) do
          SendAddonMessage(ADDON_PREFIX, versionmsg, chan)
        end
      end
      this.group = groupsize
    end

    if event == "PLAYER_ENTERING_WORLD" then
      if not alreadyshown and localversion < remoteversion then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(T["|cff33ffccpf|rUI: New version available! Get it at %s"], GetAddOnMetadata(pfUI.name, "X-Website") .. "/releases"))
        DEFAULT_CHAT_FRAME:AddMessage(T["|cffddddddIt's always safe to upgrade |cff33ffccpf|rUI. |cffddddddYou won't lose any of your configuration."])
        pfUI_init.updateavailable = localversion
        alreadyshown = true
      end

      for _, chan in pairs(loginchannels) do
        SendAddonMessage(ADDON_PREFIX, versionmsg, chan)
      end
    end
  end)
end)
