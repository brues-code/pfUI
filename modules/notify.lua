-- Flash the taskbar button on whispers, ready checks and battleground
-- queue pops, so they reach an alt-tabbed player. FlashClientIcon does
-- nothing while WoW is in the foreground.
pfUI:RegisterModule("notify", function ()
  if C.global.notify ~= "1" then return end

  local function Flash() FlashClientIcon() end

  pfUI.events:RegisterFrameEventAndCallback("CHAT_MSG_WHISPER", Flash)
  pfUI.events:RegisterFrameEventAndCallback("READY_CHECK", Flash)

  -- a queue pop turns a battlefield's status to "confirm"
  local popped = {}
  pfUI.events:RegisterFrameEventAndCallback("UPDATE_BATTLEFIELD_STATUS", function()
    for i = 1, MAX_BATTLEFIELD_QUEUES do
      local confirm = GetBattlefieldStatus(i) == "confirm"
      if confirm and not popped[i] then Flash() end
      popped[i] = confirm
    end
  end)
end)
