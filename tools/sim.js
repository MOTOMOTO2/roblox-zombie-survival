#!/usr/bin/env node
/**
 * Runs the game's own Lua modules headlessly.
 *
 * Roblox itself is not available offline, so tools/sim/stubs.lua provides a small
 * stand-in for the engine API (Instance, Vector3, Enum, services, task, ...) and
 * tools/sim/tests.lua drives the real modules through a full boot: build the map,
 * init every service, buy and forge a gun, down and revive a player, spawn a boss
 * and phase it.
 *
 * Executed with fengari, a Lua 5.3 VM compiled to JavaScript.
 */
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const ROOT = path.join(__dirname, "..");
const SRC = path.join(ROOT, "src");
const SIM = path.join(__dirname, "sim");

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".lua")) out.push(full);
  }
  return out;
}

/** Only ModuleScripts are mountable; Scripts/LocalScripts need a real runtime. */
function mountableFiles() {
  return walk(SRC).filter((file) => {
    const base = path.basename(file);
    return !base.endsWith(".server.lua") && !base.endsWith(".client.lua");
  });
}

function longBracket(source) {
  let level = 0;
  while (source.includes("]" + "=".repeat(level) + "]")) level += 1;
  const eq = "=".repeat(level);
  return `[${eq}[\n${source}\n]${eq}]`;
}

// Build a Lua table of "Service/Folder/Module" -> source
const entries = [];
for (const file of mountableFiles()) {
  const key = path.relative(SRC, file).replace(/\\/g, "/").replace(/\.lua$/, "");
  entries.push(`  ["${key}"] = ${longBracket(fs.readFileSync(file, "utf8"))},`);
}
const sourcesChunk = `local SOURCES = {\n${entries.join("\n")}\n}\nSIM_MOUNT(SOURCES)\n`;

// Scripts and LocalScripts cannot be mounted as modules, but their source is still
// handed to Lua so the tests can run them with a fake `script` global.
const scriptEntries = [];
for (const file of walk(SRC)) {
  const base = path.basename(file);
  if (!base.endsWith(".server.lua") && !base.endsWith(".client.lua")) continue;
  const key = path
    .relative(SRC, file)
    .replace(/\\/g, "/")
    .replace(/\.(server|client)\.lua$/, "");
  scriptEntries.push(`  ["${key}"] = ${longBracket(fs.readFileSync(file, "utf8"))},`);
}
const scriptsChunk = [
  `local SCRIPT_SOURCES = {`,
  scriptEntries.join("\n"),
  `}`,
  `function SIM_SCRIPT_SOURCE(key)`,
  `\tif not SCRIPT_SOURCES[key] then error("no script source for " .. tostring(key)) end`,
  `\treturn SCRIPT_SOURCES[key]`,
  `end`,
  ``,
].join("\n");

const stubs = fs.readFileSync(path.join(SIM, "stubs.lua"), "utf8");
const tests = fs.readFileSync(path.join(SIM, "tests.lua"), "utf8");

// A controllable clock so fire-rate and cooldown logic can be tested deterministically.
const clock = `
local simTime = 1000
local realClock = os.clock
os.clock = function() return simTime end
function SIM_ADVANCE(dt) simTime = simTime + dt end
function SIM_NOW() return simTime end
`;

const program = [stubs, clock, sourcesChunk, scriptsChunk, tests].join("\n");

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const status = lauxlib.luaL_dostring(L, to_luastring(program));
if (status !== lua.LUA_OK) {
  const message = lua.lua_tojsstring(L, -1) || to_jsstring(lua.lua_tostring(L, -1) || []);
  console.error("\nsimulation error: " + message);
  process.exit(1);
}
console.log("\nsimulation finished cleanly.");
