-- MyAddon.lua — one line describing what this does.
--
-- Long comment: why this addon exists, what problem it solves, what it does
-- NOT do (be honest about limitations). Players read this on GitHub.

-- Every WoW API call that might not exist on the Forever beta should be
-- pcall-wrapped. A signature change must degrade to silence, not error.
local function ask(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- Saved variables are available before your addon loads.
MyAddonDB = MyAddonDB or {}

-- ---------------------------------------------------------------------------
-- main frame: register events here

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- restore saved settings
        print("MyAddon loaded. /ma for commands.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- rebind things that loading screens reset
    end
end)

-- ---------------------------------------------------------------------------
-- slash commands

SLASH_MYADDON1 = "/ma"
SlashCmdList.MYADDON = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "test" then
        -- fire a test event to verify the addon works
        print("MyAddon: test output.")
    else
        print("MyAddon: /ma test")
    end
end
