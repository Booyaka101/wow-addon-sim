#!/usr/bin/env node
// wow-addon-visual — render an addon's UI in a browser and screenshot it.
//
// The sim loads the addon under fengari with WoW API stubs. After the
// lifecycle events fire, this tool walks the frame tree, extracts every
// visible element (frames, font strings, textures) with their positions,
// sizes, colors, and text — then renders that as HTML in a browser tab and
// takes a screenshot. You see what the player would see, without the game.
//
// Usage:
//   node wow-addon-visual.mjs <addon-dir> [--scenario login] [--output shot.png] [--golden golden.png]
//
// The screenshot can be compared against a golden baseline for regression testing.

import fs from 'node:fs';
import path from 'node:path';
import fengari from 'fengari';
const { lua, lauxlib } = fengari;

const args = process.argv.slice(2);
const addonDir = args[0];
if (!addonDir) {
    console.error('usage: node wow-addon-visual.mjs <addon-dir> [--scenario <name>] [--output <file>] [--golden <file>]');
    process.exit(2);
}

let scenario = 'login';
let outputPath = null;
let goldenPath = null;
for (let i = 1; i < args.length; i++) {
    if (args[i] === '--scenario') scenario = args[++i];
    if (args[i] === '--output') outputPath = args[++i];
    if (args[i] === '--golden') goldenPath = args[++i];
}

const log = (...a) => console.log(...a);

// ---------------------------------------------------------------------------
// shared sim infrastructure (import the preamble from wow-addon-sim)

const simPath = import.meta.dirname;
const surfacePath = path.join(simPath, 'data', 'forever-surface.json');
let surface = { globals: [], namespaces: {} };
if (fs.existsSync(surfacePath)) {
    const raw = JSON.parse(fs.readFileSync(surfacePath, 'utf8'));
    surface.globals = raw.functions || raw.globals || [];
    surface.namespaces = raw.namespaces || {};
}

// read the addon TOC
function readToc(dir) {
    const tocFile = fs.readdirSync(dir).find(f => f.toLowerCase().endsWith('.toc'));
    if (!tocFile) throw new Error(`no .toc in ${dir}`);
    const tocText = fs.readFileSync(path.join(dir, tocFile), 'utf8');
    const files = [];
    const meta = {};
    for (const line of tocText.split('\n')) {
        const t = line.trim();
        if (t.startsWith('##')) {
            const m = t.match(/^##\s*(\w+):\s*(.*)/);
            if (m) meta[m[1]] = m[2];
        } else if (t && !t.startsWith('#')) {
            files.push(t.replace(/\\/g, '/'));
        }
    }
    return { meta, files, tocFile };
}

// ---------------------------------------------------------------------------
// the Lua program: sim preamble (from wow-addon-sim) + addon + layout walker

// We reuse the sim's approach but add a layout extraction function at the end
const WALKER = `
-- walk the frame tree and collect layout data as a JSON-ready table
function sim_walk_layout()
    local layout = {}

    local function walk_frame(f, depth)
        if not f then return end
        local entry = {
            name = f._name or "unnamed",
            kind = f._kind or "Frame",
            shown = f._shown or false,
            depth = depth,
            x = 0, y = 0, w = 0, h = 0,
            alpha = f._alpha or 1,
            text = nil, textR = 1, textG = 1, textB = 1,
            children = {},
        }

        -- position from the first anchor point
        if f._points and #f._points > 0 then
            local p = f._points[1]
            entry.x = p[4] or p[2] or 0
            entry.y = p[5] or p[3] or 0
        end

        -- size
        if f._size then
            entry.w = f._size.w or 0
            entry.h = f._size.h or 0
        end

        -- font strings (text elements) — include ALL, even hidden ones (marked)
        if f._fonts then
            for i, fs in ipairs(f._fonts) do
                if fs._text and #fs._text > 0 then
                    local fsEntry = {
                        name = "text_" .. i,
                        kind = "FontString",
                        shown = fs._shown ~= false,
                        depth = depth + 1,
                        x = 0, y = 0,
                        w = string.len(fs._text) * 8,
                        h = 16,
                        alpha = fs._alpha or 1,
                        text = fs._text,
                    }
                    -- get position from the font string's own anchor points
                    if fs._points and #fs._points > 0 then
                        local fp = fs._points[1]
                        fsEntry.x = fp[4] or fp[2] or 0
                        fsEntry.y = fp[5] or fp[3] or 0
                    end
                    entry.children[#entry.children + 1] = fsEntry
                end
            end
        end

        -- textures
        if f._textures then
            for i = 1, #f._textures do
                entry.children[#entry.children + 1] = {
                    name = "texture_" .. i,
                    kind = "Texture",
                    shown = true,
                    depth = depth + 1,
                    x = 0, y = 0, w = entry.w, h = entry.h,
                    alpha = 0.3,
                    text = nil,
                }
            end
        end

        return entry
    end

    for i, f in ipairs(SIM_FRAMES) do
        local entry = walk_frame(f, 0)
        if entry then layout[#layout + 1] = entry end
    end

    return layout
end

-- serialize the layout as a simple string we can parse from JS
function sim_layout_json()
    local layout = sim_walk_layout()
    local parts = {}
    for i, entry in ipairs(layout) do
        local s = string.format(
            '{"name":"%s","kind":"%s","shown":%s,"x":%d,"y":%d,"w":%d,"h":%d,"alpha":%.2f',
            entry.name or "?", entry.kind or "?",
            tostring(entry.shown), entry.x or 0, entry.y or 0,
            entry.w or 0, entry.h or 0, entry.alpha or 1
        )
        if entry.text then
            s = s .. string.format(',"text":"%s"', tostring(entry.text):gsub('"', '\\\\"'))
        end
        if #entry.children > 0 then
            s = s .. ',"children":['
            for j, c in ipairs(entry.children) do
                if j > 1 then s = s .. ',' end
                s = s .. string.format(
                    '{"name":"%s","kind":"%s","text":"%s","x":%d,"y":%d,"w":%d,"h":%d}',
                    c.name or "?", c.kind or "?",
                    tostring(c.text or ""):gsub('"', '\\\\"'),
                    c.x or 0, c.y or 0, c.w or 0, c.h or 0
                )
            end
            s = s .. ']'
        end
        s = s .. '}'
        parts[#parts + 1] = s
    end
    return '[' .. table.concat(parts, ',') .. ']'
end
`;

// ---------------------------------------------------------------------------
// build the program (reuse the sim's preamble structure)

const toc = readToc(addonDir);
log(`\nwow-addon-visual: ${toc.meta.Title || path.basename(addonDir)}`);
log(`  Scenario: ${scenario}`);

// build the full program using the sim's wow-addon-sim.mjs preamble
// (we extract it from the sim file)
const simSource = fs.readFileSync(path.join(simPath, 'wow-addon-sim.mjs'), 'utf8');
const preambleMatch = simSource.match(/const PREAMBLE = `([\s\S]*?)`;/);
if (!preambleMatch) throw new Error('could not extract preamble from wow-addon-sim.mjs');
const PREAMBLE = preambleMatch[1];

// build stub code from surface
const knownNamespaces = new Set(Object.keys(surface.namespaces || {}));
const stubLines = [];
for (const ns of knownNamespaces) {
    const members = surface.namespaces[ns] || [];
    stubLines.push(`if not ${ns} then ${ns} = {} end`);
    for (const m of members) {
        stubLines.push(`${ns}.${m} = ${ns}.${m} or function(...) return nil end`);
    }
}
for (const g of (surface.globals || [])) {
    if (/^[A-Z]/.test(g) && !knownNamespaces.has(g)) {
        stubLines.push(`if not ${g} then ${g} = function(...) return nil end end`);
    }
}

const fullProgram = PREAMBLE + '\n' + stubLines.join('\n') + '\n' + WALKER;

// ---------------------------------------------------------------------------
// run the sim

const L = lua.lua_newstate();
fengari.lualib.luaL_openlibs(L);

let status = lauxlib.luaL_dostring(L, fengari.to_luastring(fullProgram));
if (status !== lua.LUA_OK) {
    const err = lua.lua_tostring(L, -1);
    log(`STUB ERROR: ${err ? fengari.to_jsstring(err) : '?'}`);
    process.exit(1);
}

// load addon files
for (const file of toc.files) {
    const fp = path.join(addonDir, file);
    if (!fs.existsSync(fp)) continue;
    const code = fs.readFileSync(fp, 'utf8');
    const wrapped = 'sim_pcall(function()\n' + code + '\nend)';
    status = lauxlib.luaL_dostring(L, fengari.to_luastring(wrapped));
    if (status !== lua.LUA_OK) {
        log(`LOAD ERROR in ${file}: ${lua.lua_tostring(L, -1) ? fengari.to_jsstring(lua.lua_tostring(L, -1)) : '?'}`);
        process.exit(1);
    }
}

// fire events based on scenario
const SCENARIOS = {
    login: ['sim_addon_loaded', 'sim_player_login', 'sim_player_entering_world'],
    combat: ['sim_addon_loaded', 'sim_player_login', 'sim_player_entering_world'],
    arena: ['sim_addon_loaded', 'sim_player_login', 'sim_player_entering_world'],
};
const funcs = SCENARIOS[scenario] || SCENARIOS.login;
for (const fn of funcs) {
    lua.lua_getglobal(L, fengari.to_luastring(fn));
    if (fn === 'sim_addon_loaded') lua.lua_pushstring(L, fengari.to_luastring(toc.meta.Title || ''));
    lua.lua_pcall(L, fn === 'sim_addon_loaded' ? 1 : 0, 0, 0);
}

// fire the addon's test command if it has one (produces visible output)
for (const cmd of ['test', 'anchor']) {
    lua.lua_getglobal(L, fengari.to_luastring('SlashCmdList'));
    if (lua.lua_istable(L, -1)) {
        // find the slash table for this addon
        lua.lua_pushnil(L);
        while (lua.lua_next(L, -2) !== 0) {
            const key = lua.lua_tostring(L, -2);
            const keyStr = key ? fengari.to_jsstring(key) : '';
            if (lua.lua_isfunction(L, -1)) {
                lua.lua_pushstring(L, fengari.to_luastring(cmd));
                lua.lua_pcall(L, 1, 0, 0);
                break;
            }
            lua.lua_pop(L, 1);
        }
    }
    lua.lua_pop(L, 1);
}

// also try calling any registered test function directly
lua.lua_getglobal(L, fengari.to_luastring('sim_pcall'));
if (lua.lua_isfunction(L, -1)) {
    // try ClearCombatText test
    lua.lua_getglobal(L, fengari.to_luastring('SlashCmdList'));
    if (lua.lua_istable(L, -1)) {
        for (const table of ['CLEARCOMBATTEXT', 'WHYHIDDEN']) {
            lua.lua_getfield(L, -1, table);
            if (lua.lua_isfunction(L, -1)) {
                lua.lua_pushstring(L, fengari.to_luastring('test'));
                lua.lua_pcall(L, 1, 0, 0);
                log(`  Fired /${table.toLowerCase()} test`);
            } else {
                lua.lua_pop(L, 1);
            }
        }
    }
    lua.lua_pop(L, 1);
}
lua.lua_pop(L, 1);

// extract the layout
lua.lua_getglobal(L, fengari.to_luastring('sim_layout_json'));
status = lua.lua_pcall(L, 0, 1, 0);
if (status !== lua.LUA_OK) {
    log('LAYOUT ERROR');
    process.exit(1);
}
const layoutJson = lua.lua_tostring(L, -1);
const layoutStr = layoutJson ? fengari.to_jsstring(layoutJson) : '[]';
let layout;
try { layout = JSON.parse(layoutStr); } catch { layout = []; }

log(`  Frames: ${layout.length}`);

// ---------------------------------------------------------------------------
// render as HTML

function renderHTML(layout) {
    const els = [];
    for (const f of layout) {
        if (!f.shown) continue;
        const style = `
            position: absolute;
            left: ${(400 + f.x).toFixed(0)}px;
            top: ${(300 - f.y).toFixed(0)}px;
            width: ${Math.max(f.w, 10)}px;
            height: ${Math.max(f.h, 4)}px;
            opacity: ${f.alpha};
            ${f.kind === 'FontString' || f.text ? 'color: #fff; font-size: 14px; font-family: sans-serif;' : 'border: 1px solid rgba(100,150,255,0.3); background: rgba(40,44,52,0.8);'}
        `;
        const text = f.text ? `<span style="color:#fff;padding:2px 6px;">${f.text}</span>` : '';
        els.push(`<div style="${style}" title="${f.name} (${f.kind})">${text}</div>`);
        if (f.children) {
            for (const c of f.children) {
                if (!c.text) continue;
                // use the child's own x/y if it has anchor points, else offset from parent
                const cx = 400 + (f.x || 0) + (c.x || 0);
                const cy = 300 - (f.y || 0) - (c.y || 0) + 20;
                els.push(`<div style="position:absolute;left:${cx.toFixed(0)}px;top:${cy.toFixed(0)}px;color:${c.kind === 'FontString' ? '#ffd200' : '#888'};font-size:13px;font-family:sans-serif;opacity:${c.shown ? 0.95 : 0.4};${c.shown ? '' : 'text-decoration:line-through;'}">${c.text}</div>`);
            }
        }
    }
    return `<!DOCTYPE html>
<html><head><style>
body { margin:0; background:#1a1a2e; width:800px; height:600px; overflow:hidden; }
.grid { position:absolute; inset:0; background:
    linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px);
    background-size: 20px 20px; }
.label { position:fixed; top:4px; left:8px; color:#666; font:11px monospace; }
</style></head><body>
<div class="grid"></div>
<div class="label">${toc.meta.Title || path.basename(addonDir)} — ${scenario} — ${new Date().toISOString().slice(0,16)}</div>
${els.join('\n')}
</body></html>`;
}

const html = renderHTML(layout);

// ---------------------------------------------------------------------------
// render in browser via CDP and screenshot

const htmlPath = outputPath || path.join(process.env.TEMP || '/tmp', `addon-visual-${Date.now()}.html`);
fs.writeFileSync(htmlPath, html);
const pngPath = htmlPath.replace('.html', '.png');

try {
    const resp = await fetch(`http://127.0.0.1:9222/json/new?file:///${htmlPath.replace(/\\/g, '/')}`, { method: 'PUT' });
    await resp.json();
    await new Promise(r => setTimeout(r, 3000));

    const { connectByUrl } = await import('file:///C:/Users/cbosc/.claude/skills/cdp-chrome/cdp.mjs');
    const c = await connectByUrl('file:///');
    await c.sleep(2000);
    const shot = await c.screenshot();
    fs.writeFileSync(pngPath, Buffer.from(shot, 'base64'));
    await c.close();
    log(`  Screenshot: ${pngPath} (${Math.round(fs.statSync(pngPath).size / 1024)} KB)`);
} catch (e) {
    log(`  Browser not available (${e.message.slice(0, 50)}); HTML written to ${htmlPath}`);
    log(`  Open in any browser to see the visual layout`);
}

// ---------------------------------------------------------------------------
// golden comparison

if (goldenPath && fs.existsSync(goldenPath) && fs.existsSync(pngPath)) {
    const golden = fs.readFileSync(goldenPath);
    const current = fs.readFileSync(pngPath);
    if (golden.equals(current)) {
        log('  ✓ MATCHES golden baseline');
    } else {
        log('  ✗ DIFFERS from golden baseline');
        process.exitCode = 1;
    }
} else if (goldenPath && !fs.existsSync(goldenPath)) {
    log(`  Golden baseline not found at ${goldenPath}`);
    log(`  Save the current screenshot as the baseline:`);
    log(`    cp ${pngPath} ${goldenPath}`);
}

log('\n  Done.');
