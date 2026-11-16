-- /pfdll: which client DLLs pfUI can use
pfUI:RegisterModule("dllstatus", function ()
  local function Report(name, version, detected)
    if version then
      DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00" .. name .. "|r: v" .. tostring(version))
    elseif detected then
      DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00" .. name .. "|r: Detected")
    else
      DEFAULT_CHAT_FRAME:AddMessage("  |cffff0000" .. name .. "|r: Not detected")
    end
  end

  pfUI.api.RegisterSlashCommand("PFDLLSTATUS", { "/pfdll" }, function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: DLL Status Check")
    Report("ClassicAPI", CLASSIC_API_VERSION)
    Report("Nampower", GetNampowerVersion and GetNampowerVersion())
    Report("SuperWoW", SUPERWOW_VERSION)
    Report("UnitXP_SP3", nil, _G.UnitXP and pcall(UnitXP, "nop", "nop"))
  end, true)
end)
