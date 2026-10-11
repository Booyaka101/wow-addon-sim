#!/usr/bin/env node
// wow-addon-sim — run a WoW addon headlessly and report errors without the game.
//
// Loads the addon's Lua files under fengari with a WoW API stub layer generated
// from real client captures, fires the lifecycle events, and reports anything
// that throws. The point: find the error at the terminal, not mid-raid.
//
// Usage:
//   node wow-addon-sim.mjs <addon-dir> [--surface <surface.json>] [--events PLAYER_LOGIN,...]

import fs from 'node:fs';
import path from 'node:path';
import fengari from 'fengari';
const { lua, lauxlib } = fengari;

// ---------------------------------------------------------------------------
// CLI

const args = process.argv.slice(2);
const addonDir = args[0];
if (!addonDir) {
    console.error('usage: node wow-addon-sim.mjs <addon-dir> [--surface <surface.json>] [--events PLAYER_LOGIN,...]');
    process.exit(2);
}

let surfacePath = null;
let extraEvents = [];
let scenarios = [];
let strictMode = false;
for (let i = 1; i < args.length; i++) {
    if (args[i] === '--surface') surfacePath = args[++i];
    if (args[i] === '--events') extraEvents = args[++i].split(',');
    if (args[i] === '--scenario') scenarios.push(args[++i]);
    if (args[i] === '--strict') strictMode = true;
}

// ---------------------------------------------------------------------------
// surface: the real API names from captures, used for stubs AND for the
// "you called something that doesn't exist" report

let surface = { globals: [], namespaces: {} };
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Z]:)/, '$1'));
const defaultSurface = path.join(here, 'data', 'forever-surface.json');
const actualSurface = surfacePath || (fs.existsSync(defaultSurface) ? defaultSurface : null);
if (actualSurface) {
    const raw = JSON.parse(fs.readFileSync(actualSurface, 'utf8'));
    surface.globals = raw.functions || raw.globals || [];
    surface.namespaces = raw.namespaces || {};
}

const knownGlobals = new Set(surface.globals || []);
const knownNamespaces = new Set(Object.keys(surface.namespaces || {}));
const unknownCalls = new Map(); // name -> count

// ---------------------------------------------------------------------------
// Lua preamble: the WoW environment, stubbed

const PREAMBLE = `
-- error collector: any Lua error in any chunk lands here
SIM_ERRORS = {}
SIM_LOG = {}

local function sim_err(msg)
    SIM_ERRORS[#SIM_ERRORS + 1] = tostring(msg)
end

-- traceback on error
local function sim_pcall(fn, ...)
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then sim_err(err) end
    return ok
end
_G.sim_pcall = sim_pcall

-- ---------------------------------------------------------------------------
-- WoW frame system

SIM_FRAMES = {}
SIM_EVENT_SCRIPTS = {}
SIM_EVENT_HOOKS = {}

local frame_id = 0
CreateFrame = function(kind, name, parent, template)
    frame_id = frame_id + 1
    local f = {
        _kind = kind, _name = name or ("SimFrame" .. frame_id),
        _visible = false, _shown = false,
        _points = {}, _size = {w = 100, h = 100},
        _scripts = {}, _hooks = {},
        _children = {}, _textures = {}, _fonts = {},
    }
    SIM_FRAMES[#SIM_FRAMES + 1] = f

    f.Show = function(self) self._shown = true end
    f.Hide = function(self) self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.IsVisible = function(self) return self._shown end
    f.SetSize = function(self, w, h) self._size = {w = w, h = h} end
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
    f.EnableMouse = function() end
    f.SetClampedToScreen = function() end
    f.RegisterForDrag = function() end
    f.RegisterForClicks = function() end
    f.SetFrameStrata = function() end
    f.SetFrameLevel = function() end
    f.SetScale = function() end
    f.SetAlpha = function(self, a) self._alpha = a end
    f.GetAlpha = function(self) return self._alpha or 1 end
    f.StartMoving = function() end
    f.StopMovingOrSizing = function() end
    f.SetScript = function(self, name, fn) self._scripts[name] = fn end
    f.GetScript = function(self, name) return self._scripts[name] end
    f.HookScript = function(self, name, fn)
        local orig = self._scripts[name]
        self._hooks[name] = self._hooks[name] or {}
        table.insert(self._hooks[name], fn)
    end
    f.RegisterEvent = function(self, event)
        SIM_EVENT_SCRIPTS[event] = SIM_EVENT_SCRIPTS[event] or {}
        SIM_EVENT_SCRIPTS[event][self] = true
    end
    f.UnregisterEvent = function(self, event)
        if SIM_EVENT_SCRIPTS[event] then SIM_EVENT_SCRIPTS[event][self] = nil end
    end
    f.IsEventRegistered = function(self, event)
        return SIM_EVENT_SCRIPTS[event] and SIM_EVENT_SCRIPTS[event][self] or false
    end
    f.CreateTexture = function(self, ...)
        local t = { _points = {}, SetAllPoints = function() end, SetSize = function() end,
            SetTexture = function() end, SetColorTexture = function() end, SetTexCoord = function() end,
            SetVertexColor = function() end, SetDrawLayer = function() end, Show = function() end, Hide = function() end,
            SetPoint = function(...) t._points[#t._points+1] = {...} end, ClearAllPoints = function() t._points = {} end,
            GetSize = function() return 100, 100 end,
            SetBlendMode = function() end, SetDesaturated = function() end,
            SetGradient = function() end, SetMask = function() end }
        self._textures[#self._textures + 1] = t
        return t
    end
    f.CreateFontString = function(self, ...)
        -- construct first, attach methods after: closures inside a local-table
        -- initializer capture the GLOBAL fs (Lua scoping), which broke SetPoint
        -- the first time a pooled font string ever reached it (secrets sweep, 2026-10)
        local fs = { _points = {}, _text = "", _shown = false }
        fs.SetText = function(s, t) s._text = t end
        fs.GetText = function(s) return s._text end
        fs.SetFont = function() end
        fs.GetFont = function() return "SimFont.ttf", 16, "" end
        fs.SetFontObject = function() end
        fs.SetTextColor = function() end
        fs.SetJustifyH = function() end
        fs.SetJustifyV = function() end
        fs.SetPoint = function(...) fs._points[#fs._points+1] = {...} end
        fs.ClearAllPoints = function() fs._points = {} end
        fs.GetPoint = function(s, i)
            local p = s._points[i or #s._points]
            if p then return p[1], f, p[3] or "CENTER", p[4] or 0, p[5] or 0 end
            return nil
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
        fs.GetNumLines = function() return 1 end
        self._fonts[#self._fonts + 1] = fs
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
    f.SetNormalTexture = function() end
    f.SetPushedTexture = function() end
    f.SetHighlightTexture = function() end
    f.SetBackdrop = function() end
    f.SetBackdropColor = function() end
    f.SetBackdropBorderColor = function() end
    f.EnableDrawLayer = function() end

    return f
end

UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("Frame", "GameTooltip")
GameTooltip.AddLine = function(self, text) SIM_LOG[#SIM_LOG+1] = "[tooltip] " .. tostring(text) end
GameTooltip.AddDoubleLine = function(self, l, r) SIM_LOG[#SIM_LOG+1] = "[tooltip] " .. tostring(l) .. " | " .. tostring(r) end
GameTooltip.GetUnit = function(self) return "SimUnit", "target" end
GameTooltip.GetSpell = function(self) return nil end
GameTooltip.GetItem = function(self) return nil end
GameTooltip.GetAnchorType = function(self) return "ANCHOR_TOPLEFT" end
GameTooltip.SetOwner = function() end
GameTooltip.Show = function(self) end
GameTooltip.Hide = function(self) end
GameTooltip:IsShown()

-- ---------------------------------------------------------------------------
-- slash commands

SlashCmdList = {}
local function reg_slash(name)
    _G["SLASH_" .. name .. "1"] = "/" .. string.lower(name)
end

-- ---------------------------------------------------------------------------
-- WoW API stubs (generated from surface data at the JS level, injected below)

-- ---------------------------------------------------------------------------
-- utility stubs

local function safe_stub(name)
    return function(...)
        SIM_LOG[#SIM_LOG+1] = "[stub] " .. name .. "(" .. tostring(select('#', ...)) .. " args)"
        return nil
    end
end

-- some APIs need specific return shapes
local sim_clock = 1000.0
GetTime = function() return sim_clock end
GetFramerate = function() return 60 end
date = os.date
time = os.time
debugstack = function() return "" end
GetAddOnMetadata = function(addon, field) return nil end
IsAddOnLoaded = function(name) return name ~= nil end
GetNumAddOns = function() return 1 end
GetAddOnInfo = function(i) return "TestAddon", "Test", "Test", "OK", 1 end
EnableAddOn = function() end
DisableAddOn = function() end
ReloadUI = function() end
Quit = function() end
Logout = function() end

-- unit API (safe defaults)
local function stub_unit(fn)
    return function(unit, ...)
        if unit == "player" then return fn("player", ...) end
        return nil
    end
end

UnitName = function(u) return u == "player" and "SimPlayer" or "SimTarget" end
UnitExists = function(u) return u == "player" or u == "target" or u == "mouseover" end
UnitHealth = function(u) return 100 end
UnitHealthMax = function(u) return 100 end
UnitPower = function(u) return 50 end
UnitPowerMax = function(u) return 100 end
UnitPowerType = function(u) return 0, "MANA" end
UnitLevel = function(u) return 60 end
UnitClass = function(u) return "Druid", "DRUID" end
UnitRace = function(u) return "Night Elf", "NightElf" end
UnitFactionGroup = function(u) return "Alliance" end
UnitIsPlayer = function(u) return u == "player" end
UnitIsFriend = function() return true end
UnitIsEnemy = function() return false end
UnitCanAttack = function(a, b) return b ~= "player" and a == "player" end
UnitAffectingCombat = function(u) return false end
UnitIsDead = function(u) return false end
UnitIsGhost = function(u) return false end
UnitIsConnected = function(u) return true end
UnitGUID = function(u) return "Player-1234-567890" end
UnitCastingInfo = function(u) return nil end
UnitChannelInfo = function(u) return nil end
UnitBuff = function(u, i) return nil end
UnitDebuff = function(u, i) return nil end
UnitAura = function(u, i) return nil end
UnitDetailedThreatSituation = function(u, m) return 1, 50, 50, 10 end
UnitIsUnit = function(a, b) return a == b end
UnitInParty = function(u) return u == "player" end
UnitInRaid = function(u) return u == "player" end
GetNumPartyMembers = function() return 0 end
GetNumRaidMembers = function() return 0 end

-- instance / zone
GetInstanceInfo = function() return "Sim Zone", "none", 0, "Normal", 5, 0, false, 0 end
GetZoneText = function() return "Sim Zone" end
GetSubZoneText = function() return "" end
GetMinimapZoneText = function() return "Sim Zone" end
IsInInstance = function() return false, "none" end
IsInRaid = function() return false end
IsInGroup = function() return false end
InCombatLockdown = function() return false end

-- CVar
GetCVar = function(name) return nil end
GetCVarBool = function(name) return false end
SetCVar = function(name, value) SIM_LOG[#SIM_LOG+1] = "[cvar] " .. name .. " = " .. tostring(value) end

-- chat
print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    SIM_LOG[#SIM_LOG+1] = "[print] " .. table.concat(parts, " ")
end

-- string helpers Blizzard provides
strtrim = function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
strlower = string.lower
strupper = string.upper
strsplit = function(sep, str)
    local parts = {}
    for w in str:gmatch("[^" .. sep .. "]+") do parts[#parts + 1] = w end
    local up = unpack or table.unpack
    return up(parts)
end
strjoin = function(sep, ...) return table.concat({...}, sep) end
strmatch = string.match
strfind = string.find
strsub = string.sub
strrep = string.rep
strlen = string.len
strformat = string.format
BreakUpLargeNumbers = function(n) return tostring(n) end

-- color
RAID_CLASS_COLORS = {
    DRUID = { r = 1, g = 0.49, b = 0.04, colorStr = "ffff7d0a" },
    MAGE = { r = 0.41, g = 0.8, b = 0.94, colorStr = "ff69ccf0" },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
}

-- locale strings that addons commonly use
MISS = "Miss"
DODGE = "Dodge"
PARRY = "Parry"
EVADE = "Evade"
IMMUNE = "Immune"
LOW_HEALTH = "Low health!"
LOW_MANA = "Low mana!"
ENTERING_COMBAT = "Entering combat"
LEAVING_COMBAT = "Leaving combat"

-- OnUpdate ticker: the live client runs these every frame; the sim advances the
-- clock and fires every registered handler so fade/rise loops get exercised
function sim_tick_onupdate(n)
    for i = 1, n do
        sim_clock = sim_clock + 1 / 60
        local elapsed = 1 / 60
        for _, f in ipairs(SIM_FRAMES) do
            local fn = f._scripts and f._scripts["OnUpdate"]
            if fn then sim_pcall(fn, f, elapsed) end
            if f._hooks and f._hooks["OnUpdate"] then
                for _, h in ipairs(f._hooks["OnUpdate"]) do sim_pcall(h, f, elapsed) end
            end
        end
    end
end

-- event dispatch helper (JS calls into this)
function sim_fire_event(event, ...)
    local fired = 0
    -- GetCurrentEventInfo() models "the current event's payload": the dispatch
    -- context decides what it returns, exactly like the real client
    SIM_LAST_EVENT_ARGS = { ... }
    -- call all SetScript handlers
    for frame in pairs(SIM_EVENT_SCRIPTS[event] or {}) do
        local fn = frame._scripts and frame._scripts["OnEvent"]
        if fn then
            fired = fired + 1
            sim_pcall(fn, frame, event, ...)
        end
    end
    -- call all HookScript handlers
    for frame in pairs(SIM_EVENT_SCRIPTS[event] or {}) do
        if frame._hooks and frame._hooks["OnEvent"] then
            for _, fn in ipairs(frame._hooks["OnEvent"]) do
                fired = fired + 1
                sim_pcall(fn, frame, event, ...)
            end
        end
    end
    return fired
end

-- addon-loaded data
function sim_addon_loaded(name)
    sim_fire_event("ADDON_LOADED", name)
end

function sim_player_login()
    sim_fire_event("PLAYER_LOGIN")
end

function sim_player_entering_world()
    sim_fire_event("PLAYER_ENTERING_WORLD", true, true, 0)
end
`;

// ---------------------------------------------------------------------------
// build the full stub environment with the captured surface

function buildStubCode() {
    const lines = [];
    // namespace tables
    for (const ns of knownNamespaces) {
        const members = surface.namespaces[ns] || [];
        lines.push(`if not ${ns} then ${ns} = {} end`);
        for (const m of members) {
            lines.push(`${ns}.${m} = ${ns}.${m} or function(...) SIM_LOG[#SIM_LOG+1] = "[stub] ${ns}.${m}()" return nil end`);
        }
    }
    // standalone globals that aren't Lua builtins
    const luaBuiltins = new Set(['print', 'pairs', 'ipairs', 'tostring', 'tonumber', 'type',
        'error', 'pcall', 'xpcall', 'select', 'unpack', 'next', 'setmetatable', 'getmetatable',
        'rawget', 'rawset', 'rawequal', 'assert', 'collectgarbage', 'gcinfo',
        'math', 'string', 'table', 'os', 'io', 'coroutine', 'package', 'debug']);
    for (const g of knownGlobals) {
        if (luaBuiltins.has(g) || g.startsWith('_')) continue;
        if (knownNamespaces.has(g)) continue;
        // only stub if it looks like a function name (CamelCase or starts lowercase with camel)
        if (/^[A-Z]/.test(g) || /^(get|set|is|has|can|do|use|find|create|register|unregister|enable|disable)/i.test(g)) {
            lines.push(`if not ${g} then ${g} = function(...) SIM_LOG[#SIM_LOG+1] = "[stub] ${g}()" return nil end end`);
        }
    }
    return lines.join('\n');
}

// ---------------------------------------------------------------------------
// read the addon

function readToc(dir) {
    const tocFile = fs.readdirSync(dir).find(f => f.toLowerCase().endsWith('.toc'));
    if (!tocFile) throw new Error(`no .toc file in ${dir}`);
    const tocPath = path.join(dir, tocFile);
    const tocText = fs.readFileSync(tocPath, 'utf8');
    const files = [];
    const meta = {};
    for (const line of tocText.split('\n')) {
        const trimmed = line.trim();
        if (trimmed.startsWith('##')) {
            const m = trimmed.match(/^##\s*(\w+):\s*(.*)/);
            if (m) meta[m[1]] = m[2];
        } else if (trimmed && !trimmed.startsWith('#')) {
            files.push(trimmed.replace(/\\/g, '/'));
        }
    }
    return { meta, files, dir, tocFile };
}

// ---------------------------------------------------------------------------
// scenario system: named gameplay states that fire a realistic event sequence

const SCENARIOS = {
    login: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD'],
    combat: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_DISABLED',
             'UNIT_COMBAT', 'COMBAT_TEXT_UPDATE', 'UNIT_HEALTH', 'UNIT_POWER_UPDATE'],
    arena: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'ZONE_CHANGED_NEW_AREA',
            'PLAYER_REGEN_DISABLED', 'COMBAT_TEXT_UPDATE', 'UNIT_HEALTH'],
    target: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_TARGET_CHANGED',
             'UPDATE_MOUSEOVER_UNIT', 'UNIT_AURA'],
    zone: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'ZONE_CHANGED_NEW_AREA',
           'ZONE_CHANGED', 'MINIMAP_ZONE_CHANGED', 'PLAYER_ENTERING_WORLD'],
    group: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'GROUP_ROSTER_UPDATE',
            'PARTY_MEMBERS_CHANGED', 'UNIT_HEALTH', 'UNIT_POWER_UPDATE'],
    logout: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_LEAVING_WORLD', 'PLAYER_LOGOUT'],
    secrets: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'COMBAT_TEXT_UPDATE'],
    ah: ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'AH_SCAN', 'BROWSE_SWEEP'],
};

function getScenarioEvents(name) {
    if (SCENARIOS[name]) return SCENARIOS[name];
    // treat as comma-separated event names
    return name.split(',').map(e => e.trim());
}

// ---------------------------------------------------------------------------
// run

const toc = readToc(addonDir);
console.log(`\nwow-addon-sim: ${toc.meta.Title || path.basename(addonDir)} v${toc.meta.Version || '?'}`);
console.log(`  TOC: ${toc.tocFile} (${toc.meta.Interface || 'no interface'})`);
console.log(`  Files: ${toc.files.join(', ')}`);
console.log(`  Surface: ${actualSurface ? path.basename(actualSurface) : 'none (minimal stubs only)'} (${knownGlobals.size} globals, ${knownNamespaces.size} namespaces)`);

const stubCode = buildStubCode();
let fullProgram = PREAMBLE + '\n' + stubCode + '\n';

// if --strict: append strict stubs that override permissive ones
if (strictMode) {
    const strictPath = path.join(here, 'strict-stubs.lua');
    if (fs.existsSync(strictPath)) {
        const strictCode = fs.readFileSync(strictPath, 'utf8');
        fullProgram += '\n' + strictCode + '\n' + `
-- swap in strict versions
CreateFrame = StrictCreateFrame
GameTooltip = StrictGameTooltip
`;
        console.log('  Mode: STRICT (validates script names, argument types, API contracts)');
    }
}

const L = lua.lua_newstate();
fengari.lualib.luaL_openlibs(L);

// load the preamble + stubs
let status = lauxlib.luaL_dostring(L, fengari.to_luastring(fullProgram));
if (status !== lua.LUA_OK) {
    const err = lua.lua_tostring(L, -1);
    console.error('STUB LAYER ERROR:', safeJsString(L, -1) || 'unknown');
    process.exit(1);
}

// load each addon file
let hadErrors = false;
for (const file of toc.files) {
    const filePath = path.join(addonDir, file);
    if (!fs.existsSync(filePath)) {
        console.error(`  MISSING: ${file}`);
        hadErrors = true;
        continue;
    }
    const code = fs.readFileSync(filePath, 'utf8');
    // wrap in a vararg function so `...` works at file scope (WoW addons get (name, nsTable))
    // pcall catches errors without crashing the sim
    const wrapped = `sim_pcall(function(...) ${code} end, ${JSON.stringify(toc.meta.Title || path.basename(addonDir))}, nil)`;
    status = lauxlib.luaL_dostring(L, fengari.to_luastring(wrapped));
    if (status !== lua.LUA_OK) {
        const err = lua.lua_tostring(L, -1);
        console.error(`  LOAD ERROR in ${file}: ${safeJsString(L, -1) || 'unknown'}`);
        hadErrors = true;
    }
}

// fire lifecycle events (plus scenarios)
let events;
if (scenarios.length > 0) {
    events = scenarios.flatMap(s => getScenarioEvents(s));
    console.log(`  Scenarios: ${scenarios.join(', ')} (${events.length} events)`);
} else {
    events = ['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', ...extraEvents];
}
for (const ev of events) {
    // the AH scan replaces the pseudo-event with a full open->scan->learn pass
    if (scenarios.includes('ah') && ev === 'AH_SCAN') {
        lua.lua_getglobal(L, fengari.to_luastring('sim_run_ah_scan'));
        const as = lua.lua_pcall(L, 0, 0, 0);
        if (as !== lua.LUA_OK) {
            console.error(`  DISPATCH ERROR (ah scan): ${safeJsString(L, -1) || 'unknown'}`);
            hadErrors = true;
        }
        continue;
    }
    if (scenarios.includes('ah') && ev === 'BROWSE_SWEEP') {
        lua.lua_getglobal(L, fengari.to_luastring('sim_run_browse_sweep'));
        const bs = lua.lua_pcall(L, 0, 0, 0);
        if (bs !== lua.LUA_OK) {
            console.error(`  DISPATCH ERROR (browse sweep): ${safeJsString(L, -1) || 'unknown'}`);
            hadErrors = true;
        }
        continue;
    }
    // the secrets sweep replaces the bare event with a full marked-payload pass
    if (scenarios.includes('secrets') && ev === 'COMBAT_TEXT_UPDATE') {
        lua.lua_getglobal(L, fengari.to_luastring('sim_run_secret_sweep'));
        const ss = lua.lua_pcall(L, 0, 0, 0);
        if (ss !== lua.LUA_OK) {
            console.error(`  DISPATCH ERROR (secrets sweep): ${safeJsString(L, -1) || 'unknown'}`);
            hadErrors = true;
        }
        continue;
    }
    lua.lua_getglobal(L, fengari.to_luastring(
        ev === 'ADDON_LOADED' ? 'sim_addon_loaded'
        : ev === 'PLAYER_LOGIN' ? 'sim_player_login'
        : 'sim_player_entering_world'
    ));
    if (ev === 'ADDON_LOADED') lua.lua_pushstring(L, fengari.to_luastring(toc.meta.Title || path.basename(addonDir)));
    const callStatus = lua.lua_pcall(L, ev === 'ADDON_LOADED' ? 1 : 0, 0, 0);
    if (callStatus !== lua.LUA_OK) {
        console.error(`  EVENT ERROR (${ev}): ${safeJsString(L, -1) || 'unknown'}`);
        hadErrors = true;
    } else {
        // also fire through the generic event dispatcher for events we don't
        // have dedicated helpers for (they go through sim_fire_event)
        if (!['ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD'].includes(ev)) {
            lua.lua_getglobal(L, fengari.to_luastring('sim_fire_event'));
            lua.lua_pushstring(L, fengari.to_luastring(ev));
            const s2 = lua.lua_pcall(L, 1, 0, 0);
            if (s2 !== lua.LUA_OK) {
                console.error(`  DISPATCH ERROR (${ev}): ${safeJsString(L, -1) || 'unknown'}`);
                hadErrors = true;
            }
        }
    }
}

// tick OnUpdate handlers after the events: fade/rise loops must survive too
lua.lua_getglobal(L, fengari.to_luastring('sim_tick_onupdate'));
lua.lua_pushnumber(L, 120); // two seconds of frames
const tickStatus = lua.lua_pcall(L, 1, 0, 0);
if (tickStatus !== lua.LUA_OK) {
    console.error(`  TICK ERROR (onupdate): ${safeJsString(L, -1) || 'unknown'}`);
    hadErrors = true;
}

// after the addon loads and events fire, load the injector and perf modules
const injectorPath = path.join(here, 'event-injector.lua');
const perfPath = path.join(here, 'perf-instrument.lua');

if (fs.existsSync(injectorPath)) {
    const injectorCode = fs.readFileSync(injectorPath, 'utf8');
    const iStatus = lauxlib.luaL_dostring(L, fengari.to_luastring(injectorCode));
    if (iStatus !== lua.LUA_OK) {
        console.error('  INJECTOR: failed to load (non-fatal)');
    }
}

if (fs.existsSync(perfPath)) {
    const perfCode = fs.readFileSync(perfPath, 'utf8');
    const pStatus = lauxlib.luaL_dostring(L, fengari.to_luastring(perfCode));
    if (pStatus !== lua.LUA_OK) {
        console.error('  PERF: failed to load (non-fatal)');
    }
}

// data-rich scenarios that exercise actual addon logic
const DATA_SCENARIOS = {
    combat_burst: () => {
        // simulate a 23-event combat sequence with real data
        lua.lua_getglobal(L, fengari.to_luastring('sim_inject_units'));
        lua.lua_pcall(L, 0, 0, 0);
        lua.lua_getglobal(L, fengari.to_luastring('sim_combat_sequence'));
        lua.lua_pcall(L, 0, 0, 0);
    },
    arena_restricted: () => {
        // enter an arena with restrictions active — WhyHidden's main case
        lua.lua_getglobal(L, fengari.to_luastring('sim_enable_restrictions'));
        lua.lua_pcall(L, 0, 0, 0);
        lua.lua_getglobal(L, fengari.to_luastring('sim_enter_arena'));
        lua.lua_pcall(L, 0, 0, 0);
        lua.lua_getglobal(L, fengari.to_luastring('sim_inject_units'));
        lua.lua_pcall(L, 0, 0, 0);
        // fire a player login to re-check restrictions in the new context
        lua.lua_getglobal(L, fengari.to_luastring('sim_player_login'));
        lua.lua_pcall(L, 0, 0, 0);
    },
    raid_healing: () => {
        // simulate healing in a raid with restrictions
        lua.lua_getglobal(L, fengari.to_luastring('sim_enable_restrictions'));
        lua.lua_pcall(L, 0, 0, 0);
        lua.lua_getglobal(L, fengari.to_luastring('sim_enter_raid'));
        lua.lua_pcall(L, 0, 0, 0);
        lua.lua_getglobal(L, fengari.to_luastring('sim_inject_units'));
        lua.lua_pcall(L, 0, 0, 0);
        // fire a healing-focused event sequence
        for (const mtype of ['ENTERING_COMBAT', 'HEAL', 'HEAL_CRIT', 'PERIODICHEAL', 'ABSORB', 'HEAL', 'HEAL_CRIT']) {
            lua.lua_getglobal(L, fengari.to_luastring('sim_combat_event'));
            lua.lua_pushstring(L, fengari.to_luastring(mtype));
            lua.lua_pcall(L, 1, 0, 0);
        }
    },
};

// after the standard events, run any data scenarios
for (const s of scenarios) {
    if (DATA_SCENARIOS[s]) {
        console.log(`  Running data scenario: ${s}`);
        DATA_SCENARIOS[s]();
    }
}

// after all events, run layout validation
if (fs.existsSync(path.join(here, 'layout-validator.lua'))) {
    const validatorCode = fs.readFileSync(path.join(here, 'layout-validator.lua'), 'utf8');
    status = lauxlib.luaL_dostring(L, fengari.to_luastring(validatorCode));
    if (status === lua.LUA_OK) {
        lua.lua_getglobal(L, fengari.to_luastring('sim_validate_layout'));
        const vStatus = lua.lua_pcall(L, 0, 2, 0);
        if (vStatus === lua.LUA_OK) {
            const errCount = lua.lua_tonumber(L, -2);
            if (errCount > 0) {
                lua.lua_getglobal(L, fengari.to_luastring('sim_layout_errors_json'));
                lua.lua_pcall(L, 0, 1, 0);
                const errsJson = lua.lua_tostring(L, -1);
                const errs = JSON.parse(errsJson ? (() => { try { return fengari.to_jsstring(errsJson); } catch { return '[]'; } })() : '[]');
                errs.forEach(e => console.error(`  LAYOUT: ${e}`));
                hadErrors = true;
            } else {
                console.log('  Layout: valid (all structural checks passed)');
            }
        } else {
            console.error(`  LAYOUT: validator itself errored: ${safeJsString(L, -1)}`);
        }
        lua.lua_pop(L, 2);
    } else {
        const verr = lua.lua_tostring(L, -1);
        console.error(`  LAYOUT: validator failed to load: ${verr ? (() => { try { return fengari.to_jsstring(verr); } catch { return 'non-utf8'; } })() : 'unknown'}`);
    }
}

// performance report and budget check
{
    lua.lua_getglobal(L, fengari.to_luastring('sim_perf_report'));
    const prStatus = lua.lua_pcall(L, 0, 1, 0);
    if (prStatus === lua.LUA_OK) {
        const report = safeJsString(L, -1);
        console.log(`  Perf: ${report.replace(/\n/g, ' | ')}`);
        lua.lua_pop(L, 1);
    }
    lua.lua_getglobal(L, fengari.to_luastring('sim_check_performance'));
    const pcStatus = lua.lua_pcall(L, 0, 2, 0);
    if (pcStatus === lua.LUA_OK) {
        const issueCount = lua.lua_tonumber(L, -2);
        if (issueCount > 0) {
            // get the issues
            lua.lua_getglobal(L, fengari.to_luastring('sim_perf_report'));
            // just report the count; the issues are in the table
            console.error(`  PERF: ${issueCount} budget concern(s) — run with --verbose for details`);
            hadErrors = true;
        }
    }
    lua.lua_pop(L, 2);
}

// collect errors
function safeJsString(L, index) {
    try {
        const t = lua.lua_tostring(L, index);
        return t ? fengari.to_jsstring(t) : '';
    } catch {
        return '(non-utf8)';
    }
}

function getTableLength(L, index) {
    let count = 0;
    lua.lua_pushnil(L);
    while (lua.lua_next(L, index - 1) !== 0) {
        count++;
        lua.lua_pop(L, 1);
    }
    return count;
}

lua.lua_getglobal(L, fengari.to_luastring('SIM_ERRORS'));
const errCount = getTableLength(L, -1);
const errTexts = [];
lua.lua_pushnil(L);
while (lua.lua_next(L, -2) !== 0) {
    errTexts.push(safeJsString(L, -1));
    lua.lua_pop(L, 1);
}
lua.lua_pop(L, 1);
errTexts.forEach(e => console.error(`  ERROR: ${e}`));
if (errTexts.length > 0) hadErrors = true;

// collect the stub call log (first 30)
lua.lua_getglobal(L, fengari.to_luastring('SIM_LOG'));
const logTexts = [];
lua.lua_pushnil(L);
while (lua.lua_next(L, -2) !== 0) {
    logTexts.push(safeJsString(L, -1));
    lua.lua_pop(L, 1);
}
lua.lua_pop(L, 1);
const logLines = logTexts.slice(-40); // the TAIL: late-scenario output matters most

console.log(`\n  Log (${logTexts.length} entries, last ${logLines.length}):`);
logLines.forEach(l => console.log(`    ${l}`));

if (hadErrors) {
    console.log(`\n  RESULT: ${errTexts.length > 0 ? errTexts.length : 'some'} error(s) found`);
    process.exit(1);
} else {
    console.log('\n  RESULT: CLEAN — no errors on load or lifecycle events');
    process.exit(0);
}
