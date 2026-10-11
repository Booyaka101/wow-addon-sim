-- strict-stubs.lua ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â API stubs that VALIDATE calls against real client behavior.
--
-- The sim's original stubs accepted everything (permissive). The live test proved
-- this is the wrong default: GameTooltip:HookScript("OnTooltipSetUnit", ...) was
-- accepted by the stub but crashes on the real Forever client because that script
-- doesn't exist on the Midnight tooltip system.
--
-- These stubs are STRICT: they validate argument types, script names, method
-- existence, and return shapes. An addon that passes the strict sim has a much
-- higher probability of working on the real client.

-- ---------------------------------------------------------------------------
-- valid script names per widget type (from the WoW UI source)
-- Addons can only hook/set scripts that the widget type supports.

local VALID_SCRIPTS = {
    Frame = {
        "OnLoad", "OnEvent", "OnUpdate", "OnShow", "OnHide", "OnSizeChanged",
        "OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnKeyDown", "OnKeyUp",
        "OnDragStart", "OnDragStop", "OnEnter", "OnLeave", "OnAttributeChanged",
        "OnChar", "OnTooltipCleared", "OnTooltipSetUnit", "OnTooltipSetItem",
        "OnTooltipSetSpell", "OnTooltipSetDefaultAnchor", "OnTooltipAddMoney",
        "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave",
        "OnReceiveDrag", "OnCharComposition",
    },
    Button = {
        "OnClick", "OnDoubleClick", "PostClick", "PreClick",
        -- inherits Frame scripts
        "OnLoad", "OnEvent", "OnUpdate", "OnShow", "OnHide", "OnEnter", "OnLeave",
    },
    EditBox = {
        "OnTextChanged", "OnTextSet", "OnInputLanguageChanged", "OnEditFocusGained",
        "OnEditFocusLost", "OnEnterPressed", "OnEscapePressed", "OnTabPressed",
        "OnSpacePressed", "OnArrowPressed", "OnCursorPositionChanged",
        "OnEditFocusGained", "OnEditFocusLost", "OnChar", "OnKeyDown", "OnKeyUp",
    },
    ScrollFrame = { "OnVerticalScroll", "OnHorizontalScroll", "OnScrollRangeChanged" },
    Slider = { "OnValueChanged", "OnMinMaxChanged" },
    CheckButton = { "OnClick" },
    ColorSelect = { "OnColorSelect" },
    MessageFrame = { "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave" },
    SimpleHTML = { "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave" },
    GameTooltip = {
        -- Midnight+ tooltip system: OnTooltipSetUnit may NOT be available
        "OnTooltipCleared", "OnTooltipAddMoney",
        "OnTooltipSetItem", "OnTooltipSetSpell", "OnTooltipSetDefaultAnchor",
        -- OnTooltipSetUnit is NOT in this list: it was removed in Midnight's
        -- tooltip rewrite and HookScript will error if it doesn't exist.
        -- To detect if it's available: GameTooltip:HasScript("OnTooltipSetUnit")
    },
}

-- expand: child types inherit parent scripts
local INHERITS = {
    Button = { "Frame" },
    CheckButton = { "Button", "Frame" },
    EditBox = { "Frame" },
}

local function get_valid_scripts(widget_type)
    local scripts = {}
    local function add_from(t)
        if not t then return end
        for _, s in ipairs(VALID_SCRIPTS[t] or {}) do scripts[s] = true end
        for _, parent in ipairs(INHERITS[t] or {}) do add_from(parent) end
    end
    add_from(widget_type)
    return scripts
end

-- ---------------------------------------------------------------------------
-- strict frame factory

local function strict_create_frame(kind, name, parent, template)
    local f = {
        _kind = kind or "Frame",
        _name = name or "unnamed",
        _strict = true,
        _scripts = {}, _hooks = {}, _points = {}, _size = {w = 100, h = 100},
        _shown = false, _events = {}, _fonts = {}, _textures = {}, _children = {},
    }
    SIM_FRAMES[#SIM_FRAMES + 1] = f -- so the OnUpdate ticker reaches strict frames
    f._parent = parent -- children must resolve GetParent from construction

    -- template members live frames carry (BasicFrame-style title font string,
    -- UIPanelButton-style text)
    f.TitleText = { SetText = function() end, SetTextColor = function() end }
    f.SetText = function(self, t) self._buttontext = t end
    f.GetText = function(self) return self._buttontext end
    f.Enable = function() end
    f.Disable = function() end

    local valid_scripts = get_valid_scripts(f._kind)

    -- validate and store: SetScript / HookScript REJECT unknown script names
    f.SetScript = function(self, script_name, fn)
        if not valid_scripts[script_name] then
            SIM_ERRORS[#SIM_ERRORS + 1] = string.format(
                "STRICT: %s:SetScript(%q) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â %q is not a valid script for %s (has it been removed in this client?)",
                self._name, script_name or "?", script_name or "?", self._kind)
            return
        end
        self._scripts[script_name] = fn
    end

    f.HookScript = function(self, script_name, fn)
        if not valid_scripts[script_name] then
            SIM_ERRORS[#SIM_ERRORS + 1] = string.format(
                "STRICT: %s:HookScript(%q) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â %q is not a valid script for %s (has it been removed in this client?)",
                self._name, script_name or "?", script_name or "?", self._kind)
            return
        end
        self._hooks[script_name] = self._hooks[script_name] or {}
        table.insert(self._hooks[script_name], fn)
    end

    f.GetScript = function(self, script_name)
        return self._scripts[script_name]
    end

    f.HasScript = function(self, script_name)
        return valid_scripts[script_name] ~= nil
    end

    -- RegisterEvent validates event names
    local KNOWN_EVENTS = {
        PLAYER_LOGIN = true, PLAYER_LOGOUT = true, PLAYER_ENTERING_WORLD = true,
        PLAYER_LEAVING_WORLD = true, ADDON_LOADED = true, PLAYER_REGEN_ENABLED = true,
        PLAYER_REGEN_DISABLED = true, PLAYER_TARGET_CHANGED = true,
        UPDATE_MOUSEOVER_UNIT = true, UNIT_HEALTH = true, UNIT_POWER_UPDATE = true,
        COMBAT_TEXT_UPDATE = true, UNIT_AURA = true, ZONE_CHANGED_NEW_AREA = true,
        ZONE_CHANGED = true, MINIMAP_ZONE_CHANGED = true, PLAYER_LEVEL_UP = true,
        UNIT_EXITING_VEHICLE = true, UNIT_ENTERING_VEHICLE = true, UNIT_PET = true,
        GROUP_ROSTER_UPDATE = true, PARTY_MEMBERS_CHANGED = true,
        CHAT_MSG_ADDON = true, VARIABLES_LOADED = true, PLAYER_ALIVE = true,
        PLAYER_DEAD = true, PLAYER_UNGHOST = true, CURRENCY_DISPLAY_UPDATE = true,
        QUEST_ACCEPTED = true, QUEST_COMPLETE = true, QUEST_LOG_UPDATE = true,
        BAG_UPDATE = true, BAG_UPDATE_DELAYED = true, ITEM_LOCKED = true,
        MERCHANT_SHOW = true, MERCHANT_CLOSED = true, TRADE_SHOW = true,
        PET_BATTLE_OPENING_START = true, PET_BATTLE_CLOSE = true,
        PLAYER_SPECIALIZATION_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true,
        INSPECT_READY = true, UNIT_INVENTORY_CHANGED = true,
        ITEM_SEARCH_RESULTS_UPDATED = true, COMMODITY_SEARCH_RESULTS_UPDATED = true,
        AUCTION_HOUSE_SHOW = true, AUCTION_HOUSE_CLOSED = true,
        REPLICATE_ITEM_LIST_UPDATE = true, REPLICATE_ITEM_LIST_UPDATED = true,
        COMMODITY_PRICE_UPDATED = true,
        AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = true, AUCTION_HOUSE_BROWSE_RESULTS_ADDED = true, OWNED_AUCTIONS_UPDATED = true,
    }

    f.RegisterEvent = function(self, event)
        if not KNOWN_EVENTS[event] then
            -- don't error on unknown events ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â Blizzard adds new ones ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â but log it
            SIM_LOG[#SIM_LOG + 1] = "[strict] unknown event registered: " .. tostring(event) .. " (may be new in this client)"
        end
        self._events[event] = true
        SIM_EVENT_SCRIPTS[event] = SIM_EVENT_SCRIPTS[event] or {}
        SIM_EVENT_SCRIPTS[event][self] = true
    end

    -- standard frame methods (non-validating for speed, these are stable)
    f.UnregisterEvent = function(self, event) self._events[event] = nil end
    f.IsEventRegistered = function(self, event) return self._events[event] or false end
    f.Show = function(self) self._shown = true end
    f.Hide = function(self) self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.IsVisible = function(self) return self._shown end
    f.SetSize = function(self, w, h)
        if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetSize(" .. tostring(w) .. "," .. tostring(h) .. ") ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â must be positive numbers"
            return
        end
        self._size = {w = w, h = h}
    end
    f.SetWidth = function(self, w) self._size.w = w end
    f.SetHeight = function(self, h) self._size.h = h end
    f.GetWidth = function(self) return self._size.w end
    f.GetHeight = function(self) return self._size.h end
    f.SetPoint = function(self, ...) self._points[#self._points + 1] = {...} end
    f.SetAllPoints = function(self) self._points[#self._points + 1] = { "ALL" } end
    f.SetShown = function(self, v) if v then self._shown = true else self._shown = false end end
    f.ClearAllPoints = function(self) self._points = {} end
    f.GetPoint = function(self, i)
        local p = self._points[i or #self._points]
        if p then return p[1], self, p[3] or "CENTER", p[4] or 0, p[5] or 0 end
        return nil
    end
    f.GetNumPoints = function(self) return #self._points end
    f.SetMovable = function() end
    f.EnableMouse = function(self, ...) self._mouse = ... end
    f.SetClampedToScreen = function() end
    f.RegisterForDrag = function() end
    f.RegisterForClicks = function() end
    f.SetFrameStrata = function() end
    f.SetFrameLevel = function() end
    f.SetScale = function(self, s)
        if type(s) ~= "number" or s <= 0 then
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetScale(" .. tostring(s) .. ") ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â must be positive"
        end
    end
    f.SetAlpha = function(self, a)
        if type(a) ~= "number" or a < 0 or a > 1 then
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetAlpha(" .. tostring(a) .. ") ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â must be in [0,1]"
        end
        self._alpha = a
    end
    f.GetAlpha = function(self) return self._alpha or 1 end
    f.StartMoving = function() end
    f.StopMovingOrSizing = function() end
    f.SetNormalTexture = function() end
    f.SetPushedTexture = function() end
    f.SetHighlightTexture = function() end
    f.SetBackdrop = function() end
    f.SetBackdropColor = function() end
    f.SetBackdropBorderColor = function() end
    f.EnableDrawLayer = function() end
    f.SetID = function(self, id) self._id = id end
    f.GetID = function(self) return self._id end
    f.SetParent = function(self, p) self._parent = p end
    f.GetParent = function(self) return self._parent end
    f.GetName = function(self) return self._name end
    f.GetFrameType = function(self) return self._kind end
    f.IsObjectType = function(self, t) return self._kind == t end
    f.GetEffectiveScale = function(self) return 1 end
    f.GetScale = function(self) return 1 end
    f.IsMouseOver = function(self) return false end
    f.GetCenter = function(self) return 0, 0 end
    f.GetRect = function(self) return 0, 0, self._size.w, self._size.h end
    f.IsShown = function(self) return self._shown end
    f.CreateTexture = function(self)
        return { SetAllPoints = function() end, SetSize = function() end,
            SetTexture = function() end, SetColorTexture = function() end,
            SetTexCoord = function() end, SetVertexColor = function() end,
            SetDrawLayer = function() end, Show = function() end, Hide = function() end,
            SetPoint = function() end, ClearAllPoints = function() end,
            SetBlendMode = function() end, SetDesaturated = function() end }
    end
    f.CreateFontString = function(self)
        local fs = { _text = "", _shown = false, _points = {} }
        fs.SetText = function(s, t)
            if type(t) ~= "string" and type(t) ~= "number" then
                SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetText(" .. type(t) .. ") ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â expected string or number"
            end
            -- SimSecret is defined later in this file; resolved at call time.
            -- A marked value stores its display text: SetText is the display sink.
            s._text = (SimSecret and SimSecret.display(t)) or tostring(t or "")
        end
        fs.GetText = function(s) return s._text end
        fs.SetFont = function() end
        fs.GetFont = function() return "Font.ttf", 16, "" end
        fs.SetFontObject = function() end
        fs.SetTextColor = function(s, r, g, b, a)
            if type(r) ~= "number" or r < 0 or r > 1 then
                SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetTextColor r=" .. tostring(r) .. " ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â must be in [0,1]"
            end
        end
        fs.SetJustifyH = function() end
        fs.SetJustifyV = function() end
        fs.SetShown = function(s, v) if v then s._shown = true else s._shown = false end end
        fs.SetPoint = function(...) fs._points[#fs._points + 1] = {...} end
        fs.ClearAllPoints = function() fs._points = {} end
        fs.GetPoint = function(s, i)
            local p = s._points[i or #s._points]
            if p then return p[1], f, p[3] or "CENTER", p[4] or 0, p[5] or 0 end
        end
        fs.SetSize = function() end
        fs.SetWidth = function() end
        fs.SetHeight = function() end
        fs.Show = function(s) s._shown = true end
        fs.Hide = function(s) s._shown = false end
        fs.SetAlpha = function() end
        fs.SetShadowColor = function() end
        fs.SetShadowOffset = function() end
        fs.SetSpacing = function() end
        fs.SetAllPoints = function() end
        fs.SetWordWrap = function() end
        fs.SetMaxLines = function() end
        fs.GetStringWidth = function() return 100 end
        fs.GetStringHeight = function() return 20 end
        return fs
    end
    f.CreateAnimationGroup = function(self)
        return { Play = function() end, Stop = function() end, SetScript = function() end,
            CreateAnimation = function()
                return { SetDuration = function() end, SetTarget = function() end,
                    SetOrder = function() end, SetFromAlpha = function() end,
                    SetToAlpha = function() end, SetOffset = function() end,
                    SetSmoothing = function() end }
            end }
    end

    return f
end

-- install strict CreateFrame
StrictCreateFrame = strict_create_frame

-- strict GameTooltip: does NOT list OnTooltipSetUnit as hookable
-- (matches the Midnight+ tooltip system behavior on Forever build 70338)
StrictGameTooltip = strict_create_frame("GameTooltip", "GameTooltip")
StrictGameTooltip.AddLine = function(self, text)
    SIM_LOG[#SIM_LOG + 1] = "[tooltip] " .. tostring(text)
end
StrictGameTooltip.AddDoubleLine = function(self, l, r)
    SIM_LOG[#SIM_LOG + 1] = "[tooltip] " .. tostring(l) .. " | " .. tostring(r)
end
StrictGameTooltip.GetUnit = function(self) return "SimUnit", "target" end
StrictGameTooltip.GetSpell = function(self) return nil end
StrictGameTooltip.GetItem = function(self) return nil end
StrictGameTooltip.SetOwner = function() end

-- ---------------------------------------------------------------------------
-- secret-value emulation (strict mode)
-- Reproduces the live client's secret marker semantics, verified in game on
-- Forever build 70338 across ClearCombatText 0.3.1-0.3.5:
--   arithmetic on a secret        -> ERRORS here, exactly like live
--   tostring(secret)              -> allowed, result KEEPS the marker
--   tonumber(secret)              -> launders to a clean number
--   secret .. x                   -> allowed (wiki-blessed), result keeps the marker
--   secret == nil / ~= nil        -> allowed (documented nil-check)
--   SetText(secret-marked string) -> allowed (display is a sanctioned sink)
--   type(secret)                  -> reports the underlying type, like live
-- Two live behaviors Lua 5.1 cannot intercept on tables and stay the linter's
-- job (wow-secret-lint WSL004/WSL002 model them statically):
--   #secret                       -> errors in game; raw length here
--   secret OP value (compare)     -> errors in game; silent inequality here

local rawtostring, rawtonumber, rawtype = tostring, tonumber, type

SimSecret = {}

local SECRET_META = {}
SECRET_META.__index = nil
function SECRET_META.__tostring(s) return s.__display end
function SECRET_META.__concat(a, b)
    local l = SimSecret.is(a) and a.__display or rawtostring(a)
    local r = SimSecret.is(b) and b.__display or rawtostring(b)
    return SimSecret.mark(l .. r)
end
local function secret_arith()
    error("attempt to perform arithmetic on a secret value", 2)
end
SECRET_META.__add = secret_arith
SECRET_META.__sub = secret_arith
SECRET_META.__mul = secret_arith
SECRET_META.__div = secret_arith
SECRET_META.__mod = secret_arith
SECRET_META.__pow = secret_arith
SECRET_META.__unm = secret_arith

function SimSecret.mark(value, display)
    return setmetatable({ __value = value, __display = rawtostring(display or value) }, SECRET_META)
end
function SimSecret.is(v)
    return rawtype(v) == "table" and getmetatable(v) == SECRET_META
end

function issecretvalue(v) return SimSecret.is(v) end

-- tostring keeps the marker: the 0.3.4 crash was comparing tostring(secret)
-- against "", which errors in game while the call itself is sanctioned.
tostring = function(v)
    local r = rawtostring(v)
    if SimSecret.is(v) then return SimSecret.mark(r, r) end
    return r
end

-- tonumber launders only secret STRINGS (conversion builds a clean value); a
-- secret NUMBER rides through unchanged (live-proven: consolidate's sum came
-- back secret and arithmetic killed the addon)
tonumber = function(v)
    if SimSecret.is(v) then
        local inner = v.__value
        if rawtype(inner) ~= "string" then return v end
        v = inner
    end
    return rawtonumber(v)
end

-- type spoofs like the live client: type(secretString) == "string" there.
type = function(v)
    if SimSecret.is(v) then return rawtype(v.__value) end
    return rawtype(v)
end

-- display sink accounting: count SetText calls that carried a marked value, and
-- store the display text like the live client renders it
function SimSecret.display(v)
    if SimSecret.is(v) then return v.__display end
    return nil
end
SIM_SECRET_RENDERS = 0
-- a widget that displayed secret text carries the marker, and its getters hand
-- marked values back (live-proven: GetPoint returned <secret string> after
-- SetText(secret), and passing that into SetPoint raised a usage error)
local function track_fontstring(fs)
    local raw = fs.SetText
    local rawGetPoint = fs.GetPoint
    local rawGetText = fs.GetText
    local rawSetPoint = fs.SetPoint
    local tainted = false
    fs.SetText = function(s, text)
        if SimSecret.is(text) then
            SIM_SECRET_RENDERS = SIM_SECRET_RENDERS + 1
            tainted = true
            return raw(s, text.__display)
        end
        return raw(s, text)
    end
    if rawGetPoint then
        fs.GetPoint = function(s, i)
            local point, rel, relPoint, x, y = rawGetPoint(s, i)
            if tainted then
                return SimSecret.mark(point or "CENTER"), rel,
                    SimSecret.mark(relPoint or "CENTER"), SimSecret.mark(x or 0), SimSecret.mark(y or 0)
            end
            return point, rel, relPoint, x, y
        end
    end
    if rawGetText then
        fs.GetText = function(s)
            local t = rawGetText(s)
            if tainted then return SimSecret.mark(t or "") end
            return t
        end
    end
    if rawSetPoint then
        fs.SetPoint = function(s, point, ...)
            if SimSecret.is(point) then
                SIM_ERRORS[#SIM_ERRORS + 1] =
                    "STRICT: SetPoint(point) received a secret value ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â the live client rejects it with 'FontString SetPoint(): Usage:'. Recompute the position instead of reading back GetPoint from a widget that displayed secret text."
            end
            return rawSetPoint(s, point, ...)
        end
    end
end
local strict_cf_inner = StrictCreateFrame
StrictCreateFrame = function(...)
    local f = strict_cf_inner(...)
    if f and f.CreateFontString then
        local raw_cfs = f.CreateFontString
        f.CreateFontString = function(self, ...)
            local fs = raw_cfs(self, ...)
            if fs then track_fontstring(fs) end
            return fs
        end
    end
    return f
end
-- UIParent comes from the permissive layer and never passes through the strict
-- factory, so its font strings need the same wrapping
if UIParent and UIParent.CreateFontString then
    local raw_cfs = UIParent.CreateFontString
    UIParent.CreateFontString = function(self, ...)
        local fs = raw_cfs(self, ...)
        if fs then track_fontstring(fs) end
        return fs
    end
end

-- C_CombatText with a rotating payload queue: the shapes seen in live play.
-- Strict mode only: the permissive stub layer leaves C_CombatText nil, which
-- is why the sim never exercised any of this before (see GAPS.md).
local PAYLOADS = {
    function() return SimSecret.mark(1234) end,                     -- number secret
    function() return SimSecret.mark("Krol Blade") end,             -- string secret
    function() return nil, SimSecret.mark(50), SimSecret.mark(75) end, -- absorb shape (a2/a3)
    function() return "plain clean string" end,                     -- clean payload
    function() return 42 end,                                       -- clean number
    function() return nil end,                                      -- empty event
}
local payload_by_mtype = {}
C_CombatText = {
    GetCurrentEventInfo = function()
        -- per-dispatch rotation: every event type cycles through every payload
        -- shape, so repeats on the same type exercise consolidation arithmetic
        local m = (SIM_LAST_EVENT_ARGS or {})[1]
        local key = m ~= nil and tostring(m) or "?"
        local ix = (payload_by_mtype[key] or 0) + 1
        payload_by_mtype[key] = ix
        return PAYLOADS[((ix - 1) % #PAYLOADS) + 1]()
    end,
    SetActiveUnit = function() return true end,
}

-- secrets sweep: fire COMBAT_TEXT_UPDATE across known types, unknown types and
-- rounds, so every payload shape flows through the addon's handler ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â and the
-- same payload repeats on the same type often enough to hit consolidation.
function sim_run_secret_sweep()
    local mtypes = {
        "PERIODIC_HEAL", "DAMAGE", "ABSORB_DAMAGED", "SPELL_CAST", "MISS",
        "SOME_NEW_UNKNOWNTYPE", "ANOTHER_UNKNOWN",
    }
    for round = 1, #PAYLOADS + 2 do
        for _, mtype in ipairs(mtypes) do
            sim_fire_event("COMBAT_TEXT_UPDATE", mtype)
        end
    end
    print("  [secrets] sweep done: " .. SIM_SECRET_RENDERS .. " marked value(s) rendered through SetText")
end

-- ---------------------------------------------------------------------------
-- Auction House emulation (strict mode): forever-layout replicate data
-- The live client's GetReplicateItemInfo returns [3]=count, [10]=buyout,
-- [17]=itemID, [18]=loaded ÃƒÆ’Ã‚Â¯Ãƒâ€šÃ‚Â¿Ãƒâ€šÃ‚Â½ positions Auctionator reads on this build.
C_AuctionHouse = C_AuctionHouse or {}
local SIM_AH_ROWS = {}
SimAH = { seed = {} }

function SimAH.populate(rows) SIM_AH_ROWS = rows end
function SimAH.clear() SIM_AH_ROWS = {} end

C_AuctionHouse.ReplicateItems = function()
    SIM_AH_ROWS = {}
    for i, r in ipairs(SimAH.seed) do
        SIM_AH_ROWS[i] = { itemID = r.itemID, count = r.count, buyout = r.buyout }
    end
    -- the client delivers the list asynchronously, then fires the event
    C_Timer.After(0.2, function() sim_fire_event("REPLICATE_ITEM_LIST_UPDATE") end)
    return true
end
C_AuctionHouse.GetNumReplicateItems = function() return #SIM_AH_ROWS end
C_AuctionHouse.GetReplicateItemInfo = function(i)
    local r = SIM_AH_ROWS[i]
    if not r then return nil end
    return nil, nil, r.count, nil, nil, nil, nil, nil, nil, r.buyout,
           nil, nil, nil, nil, nil, nil, r.itemID, true
end
C_AuctionHouse.GetReplicateItemLink = function(i)
    local r = SIM_AH_ROWS[i]
    if not r then return nil end
    return ("|cffffffff|Hitem:%d::::::::120::::|h[Sim Item %d]|h|r"):format(r.itemID, r.itemID)
end
C_AuctionHouse.IsThrottledMessageSystemReady = function() return true end

-- C_Timer.After must actually run: addons prefer it over manual OnUpdate timers,
-- and a no-op stub silently kills every scheduled callback (found by the ah scan)
C_Timer = C_Timer or {}
local sim_timers = {}
C_Timer.After = function(sec, fn)
    sim_timers[#sim_timers + 1] = { due = GetTime() + (sec or 0), fn = fn }
end
C_Timer.NewTicker = function(sec, fn)
    local t = { sec = sec or 0, due = GetTime() + (sec or 0), fn = fn, repeating = true }
    t.Cancel = function(self) self.cancelled = true end
    sim_timers[#sim_timers + 1] = t
    return t
end
local raw_sim_tick = sim_tick_onupdate
sim_tick_onupdate = function(n)
    for i = 1, n do
        raw_sim_tick(1)
        for j = #sim_timers, 1, -1 do
            local t = sim_timers[j]
            if t.cancelled then
                table.remove(sim_timers, j)
            elseif GetTime() >= t.due then
                table.remove(sim_timers, j)
                if t.repeating then t.due = GetTime() + t.sec; sim_timers[#sim_timers + 1] = t end
                sim_pcall(t.fn)
            end
        end
    end
end


function sim_run_ah_scan()
    -- seed a small market: 6 listings across 3 items, sane prices
    SimAH.seed = {
        { itemID = 1529, count = 1, buyout = 500000 },
        { itemID = 1529, count = 5, buyout = 2600000 },
        { itemID = 4338, count = 20, buyout = 800000 },
        { itemID = 4338, count = 1, buyout = 39000 },
        { itemID = 3827, count = 1, buyout = 150000 },
        { itemID = 3827, count = 10, buyout = 2000000 },
    }
    -- pass 1: another addon already delivered the replicate list (the
    -- Auctionator race) - the addon must harvest without its own request.
    -- A watch rule is set first so the scan also drives the search path
    -- (rebuildWatch -> searchListing -> SendSearchQuery, sorts validated).
    if SlashCmdList and SlashCmdList["FOREVERSNIPER"] then
        SlashCmdList["FOREVERSNIPER"]("watch Sim4338 20g")
    end
    SimAH.itemRows = {
        { auctionID = 9001, buyoutAmount = 2000000, quantity = 1, itemKey = { itemID = 4338 } },
        { auctionID = 9002, buyoutAmount = 5200000, quantity = 5, itemKey = { itemID = 1529 } },
    }
    SimAH.commodityRows = {
        { unitPrice = 39000, quantity = 40 },
    }
    SimAH.populate(SimAH.seed)
    sim_fire_event("AUCTION_HOUSE_SHOW")
    for i = 1, 80 do sim_tick_onupdate(10) end
    sim_fire_event("AUCTION_HOUSE_CLOSED")
    -- pass 2: nothing present; after the polite window the addon must fetch
    SimAH.clear()
    sim_fire_event("AUCTION_HOUSE_SHOW")
    for i = 1, 250 do sim_tick_onupdate(10) end
    sim_fire_event("AUCTION_HOUSE_CLOSED")
    local learned = 0
    if ForeverSniperDB and ForeverSniperDB.book then
        for _ in pairs(ForeverSniperDB.book) do learned = learned + 1 end
    end
    if learned == 0 then
        SIM_ERRORS[#SIM_ERRORS + 1] = "AH SCAN: the price book did not fill - item learning is broken"
    end
    local internal = ForeverSniperDB and ForeverSniperDB.errors or {}
    for _, e in ipairs(internal) do
        SIM_ERRORS[#SIM_ERRORS + 1] = "addon err(" .. tostring(e.domain) .. "): " .. tostring(e.err)
    end
    print("  [ah] scan complete: " .. learned .. " item(s) learned, " .. #internal .. " internal error(s)")
end

-- browse emulation: the live market feed (price-sorted, aggregated per item)
SimAH.browseRows = {}
C_AuctionHouse.GetBrowseResults = function() return SimAH.browseRows end
C_AuctionHouse.HasFullBrowseResults = function() return true end
C_AuctionHouse.RequestMoreBrowseResults = function() end
C_AuctionHouse.SendBrowseQuery = function(q)
    C_Timer.After(0.1, function() sim_fire_event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
    return true
end

-- pass 3 of the ah scenario: the live browse sweep must learn and snipe
function sim_run_browse_sweep()
    SimAH.browseRows = {
        { itemKey = { itemID = 1529 }, minPrice = 500000, totalQuantity = 12 },
        { itemKey = { itemID = 4338 }, minPrice = 5000000, totalQuantity = 50 },
        { itemKey = { itemID = 3827 }, minPrice = 200000, totalQuantity = 8  },
        { itemKey = { itemID = 7777 }, minPrice = 5000000, totalQuantity = 10 }, -- uncached item
    }
    local live = C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults() or nil
    print("  [browse] seeded " .. #SimAH.browseRows .. " rows; GetBrowseResults returns "
        .. (live and #live or "nil") .. " (same table: " .. tostring(live == SimAH.browseRows) .. ")")
    SimAHFrame:Show()
    -- own an auction above the learned market: the undercut guard must fire
    SimOwnedAuctions[1] = {
        itemKey = { itemID = 4338 }, itemLink = nil,
        buyoutAmount = 800000000, quantity = 20, -- 4000g/unit: above ANY plausible median
    }
    sim_fire_event("AUCTION_HOUSE_SHOW")
    for i = 1, 210 do sim_tick_onupdate(10) end -- ~35s: sweeps arm AND the 30s undercut poll lands
    if SimAHFrame.BrowseResultsFrame:IsShown() then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: the auto tab-switch did not leave the Browse page"
    end
    -- someone lists 4338 at a fifth of market; a gray-quality item at a deal
    -- price; and a flooded market deal - only the first may alert
    SimAH.browseRows[2].minPrice = 1500000 -- the deal drop: 15g vs 50g market (70% off)
    SimAH.browseRows[4].minPrice = 1500000 -- the uncached item drops too: defers, then fires
    SimAH.browseRows[#SimAH.browseRows + 1] =
        { itemKey = { itemID = 828 }, minPrice = 5000, totalQuantity = 5 }    -- gray: gated
    SimAH.browseRows[#SimAH.browseRows + 1] =
        { itemKey = { itemID = 3827 }, minPrice = 20000, totalQuantity = 9000 } -- flooded: gated
    SimAH.browseRows[#SimAH.browseRows + 1] =
        { itemKey = { itemID = 5555 }, minPrice = 45000, totalQuantity = 30 }  -- under vendor: VENDOR deal
    SimAH.browseRows[#SimAH.browseRows + 1] =
        { itemKey = { itemID = 7777 }, minPrice = 5000, totalQuantity = 10 }  -- deal, uncached first (deferred)
    SimAH.browseRows[#SimAH.browseRows + 1] =
        { itemKey = { itemID = 9999 }, minPrice = 5000, totalQuantity = 4 }  -- deal BUT non-stackable: must stay silent
    for i = 1, 40 do sim_tick_onupdate(10) end -- next sweep must catch it
    -- click the alerted popup row: exercises searchListing -> SendSearchQuery
    -- (sorts validation) and the keyed result readers via printPending
    for _, fr in ipairs(SIM_FRAMES) do
        if fr.itemID ~= nil and fr._scripts and fr._scripts.OnClick then
            sim_pcall(fr._scripts.OnClick, fr)
            break
        end
    end
    for i = 1, 10 do sim_tick_onupdate(10) end -- let the search results land
-- a flip sold: the mail arrives, the mint must count it as REALIZED
    SimMailbox[1] = { itemName = "Sim4338", quantity = 50, sale = 260000000, deposit = 500000, cut = 13000000 }
-- toggle the deal feed: rows must build, fill and hide without errors;
    -- with a seeded bag, the SELL button must post at the learned market
    SimBags[0][1] = { id = 4338, count = 50 }
    SimBags[0][2] = { id = 5555, count = 30 }
    SimBags[0][3] = { id = 7777, count = 10 }
    SimBags[0][4] = { id = 9999, count = 4 }
    SimBags[0][5] = { id = 3827, count = 900 }
    if SlashCmdList and SlashCmdList["FOREVERSNIPER"] then
        SlashCmdList["FOREVERSNIPER"]("feed")
        for i = 1, 5 do sim_tick_onupdate(10) end
        for _, fr in ipairs(SIM_FRAMES) do
            if fr.fs and fr.fs._text == "SELL" and fr._scripts and fr._scripts.OnClick then
                sim_pcall(fr._scripts.OnClick, fr)
                break
            end
        end
        for i = 1, 3 do sim_tick_onupdate(10) end
        SlashCmdList["FOREVERSNIPER"]("feed")
        -- seed bags + a paid position BEFORE portfolio reads them
        SimBags[0] = SimBags[0] or {}
        SimBags[0][1] = SimBags[0][1] or { id = 4338, count = 50 }
        local ba = ForeverSniperDB.boughtAt
        if ba == nil then
            -- cannot happen after the unifier, but be safe
            ba = {}
            ForeverSniperDB.boughtAt = ba
        end
        ba[4338] = { t = os.time() - 60, price = 3000000 }
        SlashCmdList["FOREVERSNIPER"]("portfolio")
        SlashCmdList["FOREVERSNIPER"]("relist")
        for i = 1, 90 do sim_tick_onupdate(10) end -- paced: ~1s per holding
        SlashCmdList["FOREVERSNIPER"]("cancel")
        for i = 1, 10 do sim_tick_onupdate(10) end -- let the query + event land
        SlashCmdList["FOREVERSNIPER"]("why")
        SlashCmdList["FOREVERSNIPER"]("options")
        for i = 1, 3 do sim_tick_onupdate(10) end
        SlashCmdList["FOREVERSNIPER"]("options")
    end
    local undercuts = (ForeverSniperDB and ForeverSniperDB.stats and ForeverSniperDB.stats.undercuts) or 0
    if undercuts == 0 then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: the undercut guard did not fire on the overpriced listing"
    end
    if #SimPosted == 0 then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: the SELL button did not post the flip"
    end
    sim_fire_event("AUCTION_HOUSE_CLOSED")
    local internal = ForeverSniperDB and ForeverSniperDB.errors or {}
    for _, e in ipairs(internal) do
        SIM_ERRORS[#SIM_ERRORS + 1] = "addon err(" .. tostring(e.domain) .. "): " .. tostring(e.err)
    end
    local kinds = {}
    for _, a in ipairs((ForeverSniperDB and ForeverSniperDB.alerts) or {}) do
        kinds[#kinds + 1] = a.kind .. ":" .. tostring(a.id)
    end
    local joined = table.concat(kinds, ",")
    print("  [browse] alert kinds fired: " .. joined)
    local deals = (ForeverSniperDB and ForeverSniperDB.stats and ForeverSniperDB.stats.deals) or 0
    if not (joined:match("market:4338") or joined:match("watch:4338")) then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: neither the market deal nor the watch hit fired for 4338"
    end
    if not joined:match("vendor:5555") then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: the vendor flip did not fire"
    end
    if joined:match("market:9999") then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: the non-stackable MARKET deal fired - stackables-only mode broken"
    end
    if not joined:match("vendor:9999") then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: the non-stackable VENDOR flip did not fire - guaranteed profit must alert"
    end
    if joined:match(":828") then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: the gray item must be gated out"
    end
    local vendorDeals = (ForeverSniperDB and ForeverSniperDB.stats and ForeverSniperDB.stats.vendorDeals) or 0
    if vendorDeals ~= 2 then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: vendor flip count wrong (" .. vendorDeals .. ", expected 2: stackable + non-stackable)"
    end
    print("  [browse] sweep done: " .. deals .. " deal(s) fired (" .. vendorDeals .. " vendor)")

    -- the mailbox mint: the sold-auction mail must be counted as REALIZED.
    -- Runs last: the CLOSED event above triggers the scan synchronously.
    local sawPortfolio = false
    for _, l in ipairs(SIM_LOG) do
        if tostring(l):find("holdings", 1, true) then sawPortfolio = true break end
    end
    if not sawPortfolio then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: /fsn portfolio printed nothing"
    end
    local sales = (ForeverSniperDB and ForeverSniperDB.stats and ForeverSniperDB.stats.sales) or 0
    if sales == 0 then
        SIM_ERRORS[#SIM_ERRORS + 1] = "BROWSE SWEEP: the mailbox mint missed the sold-auction mail"
    end
end

-- search-contract enforcement: this client validates sorts entries by field
-- name (sortOrder, reverseSort - NOT reverse) and keys every result reader
-- (GetNumItemSearchResults(itemKey), GetItemSearchResultInfo(itemKey, index),
-- GetCommoditySearchResultInfo(itemID, index)). Live-proven via Auctionator
-- usage strings and the "Current Field: [reverseSort]" error.
SimAH.itemRows = {}
SimAH.commodityRows = {}

local function validSorts(sorts)
    if sorts == nil then return true end
    if type(sorts) ~= "table" then return false, "sorts must be a table" end
    for i, s in ipairs(sorts) do
        if type(s) ~= "table" then return false, "sorts[" .. i .. "] must be a table" end
        if type(s.sortOrder) ~= "number" then
            return false, "sorts[" .. i .. "].sortOrder must be a number (Enum.AuctionHouseSortOrder)"
        end
        for k in pairs(s) do
            if k ~= "sortOrder" and k ~= "reverseSort" then
                return false, "sorts[" .. i .. "] has unknown field '" .. k ..
                    "' (this client validates by name: sortOrder, reverseSort)"
            end
        end
    end
    return true
end

C_AuctionHouse.MakeItemKey = function(id) return { itemID = id } end
C_AuctionHouse.SendSearchQuery = function(key, sorts, separate)
    local ok, msg = validSorts(sorts)
    if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: SendSearchQuery: " .. msg end
    SimAH.searchKey = key
    C_Timer.After(0.1, function() sim_fire_event("ITEM_SEARCH_RESULTS_UPDATED") end)
    return true
end
local rawBrowseQuery = C_AuctionHouse.SendBrowseQuery
C_AuctionHouse.SendBrowseQuery = function(q)
    local ok, msg = validSorts(q and q.sorts)
    if not ok then SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: SendBrowseQuery: " .. msg end
    return rawBrowseQuery(q)
end
C_AuctionHouse.GetNumItemSearchResults = function(key)
    if type(key) ~= "table" then
        SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: GetNumItemSearchResults(itemKey) - this client requires the key"
        return 0
    end
    return #SimAH.itemRows
end
C_AuctionHouse.GetItemSearchResultInfo = function(key, i)
    if type(key) ~= "table" then
        SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: GetItemSearchResultInfo(itemKey, index) - this client requires the key"
        return nil
    end
    return SimAH.itemRows[i or 1]
end
C_AuctionHouse.GetCommoditySearchResultInfo = function(itemID, i)
    if type(itemID) ~= "number" then
        SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: GetCommoditySearchResultInfo(itemID, index) - this client requires the item id"
        return nil
    end
    return SimAH.commodityRows[i or 1]
end

-- GetItemInfo: name resolution for watch-by-name rules (sim items are named
-- "Sim<itemID>") and quality for the listability gate. SimItemQuality maps
-- item ids to rarities; missing ids are uncommon (1).
SimItemQuality = { [828] = 0 }
SimItemVendor = { [5555] = 60000, [9999] = 30000 }
GetItemInfo = function(idOrLink)
    local id = type(idOrLink) == "number" and idOrLink or tonumber(tostring(idOrLink):match("item:(%d+)") or "")
    if id == nil then return nil end
    return "Sim" .. id, nil, SimItemQuality[id] or 1, 40, nil, nil, nil, nil, nil, tostring(id),
        SimItemVendor[id] or 0
end

-- Enum.AuctionHouseSortOrder: the live client exposes Name and Price keys
-- (Auctionator references both); values are validated as numbers only
Enum = Enum or {}
Enum.AuctionHouseSortOrder = Enum.AuctionHouseSortOrder or {
    Bid = 0, Buyout = 1, Price = 1, Name = 2, Quantity = 3, TimeLeft = 4,
}

-- C_Timer.NewTimer: one-shot timers (toast auto-hide)
C_Timer.NewTimer = function(sec, fn)
    local t = { sec = sec or 0, due = GetTime() + (sec or 0), fn = fn }
    t.Cancel = function(self) self.cancelled = true end
    sim_timers[#sim_timers + 1] = t
    return t
end

-- bag + posting emulation: the relist assistant path
SimBags = { [0] = {} } -- bag -> slot -> { id, count }
C_Container = C_Container or {}
C_Container.GetContainerNumSlots = function(bag)
    return SimBags[bag] and #SimBags[bag] or 0
end
C_Container.GetContainerItemID = function(bag, slot)
    local it = SimBags[bag] and SimBags[bag][slot]
    return it and it.id or nil
end
C_Container.GetContainerItemInfo = function(bag, slot)
    local it = SimBags[bag] and SimBags[bag][slot]
    if not it then return nil end
    return { itemID = it.id, stackCount = it.count }
end
ItemLocation = ItemLocation or {}
ItemLocation.CreateFromBagAndSlot = function(bag, slot)
    if SimBags[bag] and SimBags[bag][slot] then
        return { bag = bag, slot = slot }
    end
    return nil
end
C_AuctionHouse.IsSellItemValid = function(loc) return loc ~= nil end
C_AuctionHouse.GetAvailablePostCount = function(loc)
    if loc == nil then return 0 end
    local it = SimBags[loc.bag] and SimBags[loc.bag][loc.slot]
    return it and it.count or 0
end
SimPosted = {}
C_AuctionHouse.PostItem = function(loc, duration, quantity, buyout)
    if loc == nil or type(duration) ~= "number" or type(quantity) ~= "number" or type(buyout) ~= "number"
        or quantity <= 0 or buyout <= 0 then
        SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: PostItem bad args (loc/duration/quantity/buyout)"
        return false
    end
    local it = SimBags[loc.bag] and SimBags[loc.bag][loc.slot]
    SimPosted[#SimPosted + 1] = { id = it and it.id, quantity = quantity, buyout = buyout, duration = duration }
    SIM_LOG[#SIM_LOG + 1] = "[posted] item " .. tostring(it and it.id) .. " x" .. quantity .. " for " .. buyout
    return true
end
C_AuctionHouse.PostCommodity = function(loc, duration, quantity, unitPrice)
    if loc == nil or type(quantity) ~= "number" or type(unitPrice) ~= "number" or unitPrice <= 0 then
        SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: PostCommodity bad args"
        return false
    end
    local it = SimBags[loc.bag] and SimBags[loc.bag][loc.slot]
    SimPosted[#SimPosted + 1] = { id = it and it.id, quantity = quantity, unit = unitPrice, duration = duration }
    SIM_LOG[#SIM_LOG + 1] = "[posted] commodity " .. tostring(it and it.id) .. " x" .. quantity .. " at " .. unitPrice
    return true
end
C_AuctionHouse.GetItemCommodityStatus = function(id) return false end

-- uncached item info: these return nil from GetItemInfo until loaded;
-- RequestLoadItemDataByID moves them into the known set (async cache model)
SimUncached = { [7777] = true }
local rawGetItemInfo = GetItemInfo
GetItemInfo = function(idOrLink)
  local id = type(idOrLink) == "number" and idOrLink or tonumber(tostring(idOrLink):match("item:(%d+)") or "")
  if id and SimUncached[id] then return nil end
  return rawGetItemInfo(idOrLink)
end
C_Item = C_Item or {}
C_Item.RequestLoadItemDataByID = function(id)
  if id and SimUncached[id] then SimUncached[id] = nil end
end

-- AuctionHouseFrame emulation: opens on the Browse page (tab 1) like the
-- live client; clicking another tab switches the display mode away from it
SimAHFrame = StrictCreateFrame("Frame", "AuctionHouseFrame", UIParent)
AuctionHouseFrame = SimAHFrame -- the addon resolves the global by name
SimAHFrame:SetPoint("CENTER")
SimAHFrame.BrowseResultsFrame = StrictCreateFrame("Frame", nil, SimAHFrame)
SimAHFrame.BrowseResultsFrame:SetAllPoints()
SimAHFrame.BrowseResultsFrame:Show()
SimAHFrame.Tabs = {}
local simTabNames = { "Browse", "Bids", "Auctions" }
for i, name in ipairs(simTabNames) do
  local t = StrictCreateFrame("Button", "SimAHTab" .. i, SimAHFrame)
  t._text = name
  t:IsShown() -- no-op
  t._enabled = true
  t.Click = function(self)
    -- any non-first tab clears the browse display
    if self._tabIndex ~= 1 then
      SimAHFrame.BrowseResultsFrame:Hide()
      SIM_LOG[#SIM_LOG + 1] = "[ah] tab switched: " .. tostring(self._text)
    else
      SimAHFrame.BrowseResultsFrame:Show()
    end
  end
  t._tabIndex = i
  SimAHFrame.Tabs[i] = t
end

-- C_Item by-ID oracles + the stackable model: max stack 20 by default,
-- SimMaxStack overrides per item id (1 = non-stackable gear-like)
SimMaxStack = { [1529] = 1, [9999] = 1 }
local rawCItemGetItemInfo = GetItemInfo
C_Item = C_Item or {}
C_Item.GetItemNameByID = function(id)
  local info = rawCItemGetItemInfo and nil
  -- names come from the existing GetItemInfo stub; uncached stays nil
  local ok, n = pcall(rawCItemGetItemInfo, id)
  if ok and type(n) == "string" then return n end
  return nil
end
C_Item.GetItemQualityByID = function(id)
  local ok, _, _, q = pcall(rawCItemGetItemInfo, id)
  if ok and type(q) == "number" then return q end
  return nil
end
C_Item.GetItemIconByID = function(id)
  local ok, _, _, _, _, _, _, _, _, ic = pcall(rawCItemGetItemInfo, id)
  if ok and type(ic) == "string" then return ic end
  return nil
end
C_Item.GetItemMaxStackSizeByID = function(id)
  if id == nil then return nil end
  if SimUncached[id] then return nil end
  return SimMaxStack[id] or 20
end

-- owned auctions emulation: the undercut guard's data source
SimOwnedAuctions = {}
C_AuctionHouse.QueryOwnedAuctions = function()
    C_Timer.After(0.1, function() sim_fire_event("OWNED_AUCTIONS_UPDATED") end)
    return true
end
C_AuctionHouse.GetNumOwnedAuctions = function() return #SimOwnedAuctions end
C_AuctionHouse.GetOwnedAuctionInfo = function(i)
    return SimOwnedAuctions[i]
end

-- auction-sale mail emulation: the mailbox mint's data source
SimMailbox = {}
GetInboxNumItems = function() return #SimMailbox end
GetInboxInvoiceInfo = function(i)
    local m = SimMailbox[i]
    if not m then return nil end
    return "seller", m.itemName, m.quantity, m.sale, m.deposit, m.cut
end

-- cancel emulation: the cancel cannon's action
SimCancels = {}
C_AuctionHouse.CancelAuction = function(auctionID)
    if type(auctionID) ~= "number" then
        SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: CancelAuction(auctionID) needs the numeric id"
        return false
    end
    SimCancels[#SimCancels + 1] = auctionID
    SIM_LOG[#SIM_LOG + 1] = "[canceled] auction " .. auctionID
    return true
end
