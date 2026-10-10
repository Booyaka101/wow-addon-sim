const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib } = fengari;

const here = __dirname;
const read = (p) => fs.readFileSync(path.join(here, p), 'utf8');
const prelude = read('prelude.lua');
const addon = fs.readFileSync(path.join(here, '..', '..', 'MyAddon.lua'), 'utf8');
const driver = read('driver.lua');

const program = prelude + '\ndo\n' + addon + '\nend\n' + driver;
const L = lua.lua_newstate();
fengari.lualib.luaL_openlibs(L);
const status = lauxlib.luaL_dostring(L, fengari.to_luastring(program));
if (status !== lua.LUA_OK) {
  const err = lua.lua_tostring(L, -1);
  console.log('HARNESS FAILED:', err ? fengari.to_jsstring(err) : 'unknown');
  process.exit(1);
}
