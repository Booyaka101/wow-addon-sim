-- Driver: fire your addon's real code paths and assert behaviour.
local function expect(cond, msg)
    if not cond then error("ASSERT FAILED: " .. msg, 0) end
end

local mainFrame
for _, fr in ipairs(FRAMES) do
    if fr.events and fr.events.PLAYER_LOGIN then mainFrame = fr break end
end
expect(mainFrame, "main frame never created")

-- 1. login fires without error
mainFrame.scripts.OnEvent(mainFrame, "PLAYER_LOGIN")
expect(#OUT >= 1, "login banner missing")

-- 2. PLAYER_ENTERING_WORLD fires without error
mainFrame.scripts.OnEvent(mainFrame, "PLAYER_ENTERING_WORLD")

-- 3. slash command works
SlashCmdList.MYADDON("test")
local sawTest = false
for _, l in ipairs(OUT) do if l:find("test output", 1, true) then sawTest = true end end
expect(sawTest, "slash test command did not produce output")

io.write("ALL CHECKS PASSED\n")
