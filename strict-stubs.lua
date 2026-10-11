-- strict-stubs.lua — API stubs that VALIDATE calls against real client behavior.
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

    local valid_scripts = get_valid_scripts(f._kind)

    -- validate and store: SetScript / HookScript REJECT unknown script names
    f.SetScript = function(self, script_name, fn)
        if not valid_scripts[script_name] then
            SIM_ERRORS[#SIM_ERRORS + 1] = string.format(
                "STRICT: %s:SetScript(%q) — %q is not a valid script for %s (has it been removed in this client?)",
                self._name, script_name or "?", script_name or "?", self._kind)
            return
        end
        self._scripts[script_name] = fn
    end

    f.HookScript = function(self, script_name, fn)
        if not valid_scripts[script_name] then
            SIM_ERRORS[#SIM_ERRORS + 1] = string.format(
                "STRICT: %s:HookScript(%q) — %q is not a valid script for %s (has it been removed in this client?)",
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
    }

    f.RegisterEvent = function(self, event)
        if not KNOWN_EVENTS[event] then
            -- don't error on unknown events — Blizzard adds new ones — but log it
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
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetSize(" .. tostring(w) .. "," .. tostring(h) .. ") — must be positive numbers"
            return
        end
        self._size = {w = w, h = h}
    end
    f.SetWidth = function(self, w) self._size.w = w end
    f.SetHeight = function(self, h) self._size.h = h end
    f.GetWidth = function(self) return self._size.w end
    f.GetHeight = function(self) return self._size.h end
    f.SetPoint = function(self, ...) self._points[#self._points + 1] = {...} end
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
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetScale(" .. tostring(s) .. ") — must be positive"
        end
    end
    f.SetAlpha = function(self, a)
        if type(a) ~= "number" or a < 0 or a > 1 then
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetAlpha(" .. tostring(a) .. ") — must be in [0,1]"
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
                SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetText(" .. type(t) .. ") — expected string or number"
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
                SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetTextColor r=" .. tostring(r) .. " — must be in [0,1]"
            end
        end
        fs.SetJustifyH = function() end
        fs.SetJustifyV = function() end
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
        return { CreateAnimation = function()
            return { SetDuration = function() end, SetTarget = function() end }
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

-- tonumber launders: the amount path has done arithmetic on tonumber(secret)
-- without error in every live version since 0.3.0.
tonumber = function(v)
    if SimSecret.is(v) then v = v.__value end
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
                    "STRICT: SetPoint(point) received a secret value — the live client rejects it with 'FontString SetPoint(): Usage:'. Recompute the position instead of reading back GetPoint from a widget that displayed secret text."
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
-- rounds, so every payload shape flows through the addon's handler — and the
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
