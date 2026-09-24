#!/usr/bin/env node
/**
 * Verifies the build without a Roblox install.
 *
 * 1. the generated .rbxlx / .rbxmx are well-formed XML with the expected tree
 * 2. every Lua file made it into the place, byte for byte
 * 3. cross-module references actually resolve:
 *      Net.get("Name")          -> declared in Net.lua
 *      require(Shared.Module)   -> file exists
 *      S.Service.method(...)    -> that service defines the method
 *      GameConfig.Key           -> defined in GameConfig.lua
 *      weapon / enemy / tonic ids referenced by other modules exist
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const SRC = path.join(ROOT, "src");
const OUT = path.join(ROOT, "build");
const NAME = "NecrotideLastStand";

let failures = 0;
let checks = 0;

function check(ok, label, detail) {
  checks += 1;
  if (ok) {
    console.log(`ok   ${label}`);
  } else {
    failures += 1;
    console.error(`FAIL ${label}${detail ? " - " + detail : ""}`);
  }
}

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".lua")) out.push(full);
  }
  return out;
}

//------------------------------------------------------------------ XML parsing
/**
 * Minimal well-formedness scanner: tracks tag nesting, skips CDATA sections and
 * comments. Returns the tag path tree of <Item> elements.
 */
function parseRobloxXml(text, label) {
  const stack = [];
  const items = [];
  const itemStack = [];
  let i = 0;
  let root = null;

  while (i < text.length) {
    const lt = text.indexOf("<", i);
    if (lt === -1) break;

    if (text.startsWith("<![CDATA[", lt)) {
      const end = text.indexOf("]]>", lt);
      if (end === -1) throw new Error(`${label}: unterminated CDATA`);
      i = end + 3;
      continue;
    }
    if (text.startsWith("<!--", lt)) {
      const end = text.indexOf("-->", lt);
      if (end === -1) throw new Error(`${label}: unterminated comment`);
      i = end + 3;
      continue;
    }
    if (text.startsWith("<?", lt)) {
      const end = text.indexOf("?>", lt);
      i = end + 2;
      continue;
    }

    const gt = text.indexOf(">", lt);
    if (gt === -1) throw new Error(`${label}: unterminated tag`);
    const raw = text.slice(lt + 1, gt).trim();

    if (raw.startsWith("/")) {
      const name = raw.slice(1).trim();
      const open = stack.pop();
      if (open !== name) {
        throw new Error(`${label}: closing </${name}> does not match <${open}>`);
      }
      if (name === "Item") itemStack.pop();
    } else if (raw.endsWith("/")) {
      // self closing, nothing to track
    } else {
      const name = raw.split(/[\s>]/)[0];
      if (!root) root = name;
      stack.push(name);
      if (name === "Item") {
        const classMatch = raw.match(/class="([^"]+)"/);
        const node = {
          class: classMatch ? classMatch[1] : "?",
          name: null,
          parent: itemStack[itemStack.length - 1] || null,
          children: [],
        };
        if (node.parent) node.parent.children.push(node);
        items.push(node);
        itemStack.push(node);

        // the Name property is the first <string name="Name"> after the tag
        const chunk = text.slice(gt, gt + 400);
        const nameMatch = chunk.match(/<string name="Name">([^<]*)<\/string>/);
        if (nameMatch) node.name = nameMatch[1];
      }
    }
    i = gt + 1;
  }

  if (stack.length !== 0) throw new Error(`${label}: ${stack.length} unclosed tag(s): ${stack.join(", ")}`);
  if (root !== "roblox") throw new Error(`${label}: root element is <${root}>, expected <roblox>`);
  return items;
}

function pathOf(node) {
  const parts = [];
  let current = node;
  while (current) {
    parts.unshift(current.name || current.class);
    current = current.parent;
  }
  return parts.join("/");
}

//------------------------------------------------------------- place file checks
const placeFile = path.join(OUT, `${NAME}.rbxlx`);
const modelFile = path.join(OUT, `${NAME}.rbxmx`);

check(fs.existsSync(placeFile), "place file exists");
check(fs.existsSync(modelFile), "model file exists");
if (!fs.existsSync(placeFile) || !fs.existsSync(modelFile)) {
  console.error("\nRun `npm run build` first.");
  process.exit(1);
}

const placeText = fs.readFileSync(placeFile, "utf8");
const modelText = fs.readFileSync(modelFile, "utf8");

let placeItems = [];
let modelItems = [];
try {
  placeItems = parseRobloxXml(placeText, "rbxlx");
  check(true, "rbxlx is well-formed XML");
} catch (err) {
  check(false, "rbxlx is well-formed XML", err.message);
}
try {
  modelItems = parseRobloxXml(modelText, "rbxmx");
  check(true, "rbxmx is well-formed XML");
} catch (err) {
  check(false, "rbxmx is well-formed XML", err.message);
}

const placePaths = new Set(placeItems.map(pathOf));
const REQUIRED_PATHS = [
  "ReplicatedStorage/NecrotideShared/GameConfig",
  "ReplicatedStorage/NecrotideShared/Net",
  "ReplicatedStorage/NecrotideShared/WeaponDefs",
  "ReplicatedStorage/NecrotideShared/EnemyDefs",
  "ReplicatedStorage/NecrotideShared/TonicDefs",
  "ReplicatedStorage/NecrotideShared/PowerupDefs",
  "ReplicatedStorage/NecrotideShared/Util",
  "ServerScriptService/Bootstrap",
  "ServerScriptService/Services/MapBuilder",
  "ServerScriptService/Services/WaveService",
  "ServerScriptService/Services/EnemyService",
  "ServerScriptService/Services/Combat",
  "ServerScriptService/Services/Loadout",
  "ServerScriptService/Services/Economy",
  "ServerScriptService/Services/PlayerService",
  "ServerScriptService/Services/BarrierService",
  "ServerScriptService/Services/StationService",
  "ServerScriptService/Services/PowerupService",
  "StarterPlayer/StarterPlayerScripts/ClientMain",
  "StarterPlayer/StarterPlayerScripts/Modules/Hud",
  "StarterPlayer/StarterPlayerScripts/Modules/Effects",
];
for (const required of REQUIRED_PATHS) {
  check(placePaths.has(required), `place contains ${required}`);
}

// class sanity
const byPath = new Map(placeItems.map((node) => [pathOf(node), node]));
check(byPath.get("ServerScriptService/Bootstrap").class === "Script", "Bootstrap is a Script");
check(
  byPath.get("StarterPlayer/StarterPlayerScripts/ClientMain").class === "LocalScript",
  "ClientMain is a LocalScript"
);
check(
  byPath.get("ReplicatedStorage/NecrotideShared/GameConfig").class === "ModuleScript",
  "GameConfig is a ModuleScript"
);
check(placeItems.some((n) => n.class === "Workspace"), "place declares Workspace");

// model file: payload disabled, installer requireable, Boot script enabled
const modelTree = new Map(modelItems.map((node) => [pathOf(node), node]));
const installerNode = modelTree.get(`${NAME}/Installer`);
check(
  installerNode !== undefined && installerNode.class === "ModuleScript",
  "model Installer is a ModuleScript (runnable from the Command Bar)",
  installerNode && installerNode.class
);
const bootNode = modelTree.get(`${NAME}/Boot`);
check(bootNode !== undefined && bootNode.class === "Script", "model has a Boot script");
const bootMatch = modelText.match(
  /<string name="Name">Boot<\/string>[\s\S]*?<bool name="Disabled">(\w+)<\/bool>/
);
check(bootMatch && bootMatch[1] === "false", "model Boot script is enabled");
check(
  modelText.includes(`require(workspace.${NAME}.Installer)`),
  "model documents the Command Bar install line"
);
check(
  modelTree.has(`${NAME}/Payload/ReplicatedStorage/NecrotideShared/GameConfig`),
  "model payload carries the shared modules"
);
check(modelTree.has(`${NAME}/Payload/StarterPlayerScripts/ClientMain`), "model payload carries the client");
const bootstrapInModel = modelText.match(
  /<string name="Name">Bootstrap<\/string>[\s\S]*?<bool name="Disabled">(\w+)<\/bool>/
);
check(bootstrapInModel && bootstrapInModel[1] === "true", "model payload Bootstrap is disabled until installed");

//---------------------------------------------------- source embedded correctly
const luaFiles = walk(SRC);
for (const file of luaFiles) {
  const rel = path.relative(SRC, file).replace(/\\/g, "/");
  const source = fs.readFileSync(file, "utf8");
  check(placeText.includes(source), `place embeds ${rel} verbatim`);
}
const cdataOpens = (placeText.match(/<!\[CDATA\[/g) || []).length;
const cdataCloses = (placeText.match(/\]\]>/g) || []).length;
check(
  cdataOpens === cdataCloses && cdataOpens === luaFiles.length,
  `CDATA blocks balanced (${cdataOpens} open / ${cdataCloses} close for ${luaFiles.length} files)`
);

//-------------------------------------------------------- cross-module checks
const sharedDir = path.join(SRC, "ReplicatedStorage", "NecrotideShared");
const servicesDir = path.join(SRC, "ServerScriptService", "Services");

const netSource = fs.readFileSync(path.join(sharedDir, "Net.lua"), "utf8");
const declaredRemotes = new Set(
  [...netSource.matchAll(/^\t"([A-Za-z]+)",$/gm)].map((match) => match[1])
);
check(declaredRemotes.size >= 15, `Net declares remotes (${declaredRemotes.size})`);

const sharedModules = new Set(
  fs.readdirSync(sharedDir).filter((f) => f.endsWith(".lua")).map((f) => f.slice(0, -4))
);

const serviceSources = new Map();
for (const file of fs.readdirSync(servicesDir)) {
  if (file.endsWith(".lua")) {
    serviceSources.set(file.slice(0, -4), fs.readFileSync(path.join(servicesDir, file), "utf8"));
  }
}

const configSource = fs.readFileSync(path.join(sharedDir, "GameConfig.lua"), "utf8");
const configKeys = new Set([...configSource.matchAll(/^GameConfig\.(\w+)\s*=/gm)].map((m) => m[1]));

const usedRemotes = new Set();
let badRemotes = [];
let badRequires = [];
let badServiceCalls = [];
let badConfigKeys = [];

for (const file of luaFiles) {
  const rel = path.relative(SRC, file).replace(/\\/g, "/");
  const source = fs.readFileSync(file, "utf8");

  for (const match of source.matchAll(/Net\.get\("([^"]+)"\)/g)) {
    usedRemotes.add(match[1]);
    if (!declaredRemotes.has(match[1])) badRemotes.push(`${rel}: ${match[1]}`);
  }

  for (const match of source.matchAll(/require\(Shared\.(\w+)\)/g)) {
    if (!sharedModules.has(match[1])) badRequires.push(`${rel}: Shared.${match[1]}`);
  }

  for (const match of source.matchAll(/\bS\.(\w+)\.(\w+)\s*\(/g)) {
    const [, service, method] = match;
    if (service === "Map" || service === "MapBuilder") continue;
    const target = serviceSources.get(service);
    if (!target) {
      badServiceCalls.push(`${rel}: unknown service S.${service}`);
      continue;
    }
    const defined =
      new RegExp(`function\\s+${service}\\.${method}\\s*\\(`).test(target) ||
      new RegExp(`${service}\\.${method}\\s*=\\s*function`).test(target);
    if (!defined) badServiceCalls.push(`${rel}: S.${service}.${method} is not defined in ${service}.lua`);
  }

  for (const match of source.matchAll(/\bGameConfig\.(\w+)\b/g)) {
    if (!configKeys.has(match[1]) && match[1] !== "init") badConfigKeys.push(`${rel}: GameConfig.${match[1]}`);
  }
}

check(badRemotes.length === 0, "every Net.get name is declared", badRemotes.join("; "));
check(badRequires.length === 0, "every require(Shared.X) resolves", badRequires.join("; "));
check(badServiceCalls.length === 0, "every S.Service.method exists", badServiceCalls.slice(0, 8).join("; "));
check(badConfigKeys.length === 0, "every GameConfig key exists", [...new Set(badConfigKeys)].join("; "));

const unusedRemotes = [...declaredRemotes].filter((name) => !usedRemotes.has(name));
if (unusedRemotes.length > 0) {
  console.log(`note declared but unused remotes: ${unusedRemotes.join(", ")}`);
}

//----------------------------------------------------------- content id checks
const weaponSource = fs.readFileSync(path.join(sharedDir, "WeaponDefs.lua"), "utf8");
const weaponIds = new Set([...weaponSource.matchAll(/^\t\tid = "(\w+)",$/gm)].map((m) => m[1]));
const enemySource = fs.readFileSync(path.join(sharedDir, "EnemyDefs.lua"), "utf8");
const enemyIds = new Set([...enemySource.matchAll(/^\t\tid = "(\w+)",$/gm)].map((m) => m[1]));
const tonicSource = fs.readFileSync(path.join(sharedDir, "TonicDefs.lua"), "utf8");
const tonicIds = new Set([...tonicSource.matchAll(/^\t\tid = "(\w+)",$/gm)].map((m) => m[1]));

check(weaponIds.size >= 10, `weapon roster size ${weaponIds.size}`);
check(enemyIds.size >= 5, `enemy roster size ${enemyIds.size}`);
check(tonicIds.size >= 5, `tonic roster size ${tonicIds.size}`);

const mapSource = fs.readFileSync(path.join(servicesDir, "MapBuilder.lua"), "utf8");
const badWallBuys = [...mapSource.matchAll(/weapon = "(\w+)"/g)].map((m) => m[1]).filter((id) => !weaponIds.has(id));
check(badWallBuys.length === 0, "every Armory Rack weapon id exists", badWallBuys.join(", "));
// an Armory Rack for a crate-only weapon would be unpriceable
const wallBuyIds = [...mapSource.matchAll(/weapon = "(\w+)"/g)].map((m) => m[1]);
const unpriced = wallBuyIds.filter((id) => {
  const block = weaponSource.split(`id = "${id}"`)[1] || "";
  const upToNext = block.split("\n\t},")[0];
  return /wallCost = nil/.test(upToNext) || !/wallCost = \d+/.test(upToNext);
});
check(unpriced.length === 0, "every Armory Rack weapon has a wall price", unpriced.join(", "));

const badTonicSpots = [...mapSource.matchAll(/tonic = "(\w+)"/g)].map((m) => m[1]).filter((id) => !tonicIds.has(id));
check(badTonicSpots.length === 0, "every Tonic Still id exists", badTonicSpots.join(", "));

const summonTargets = [...enemySource.matchAll(/enemy = "(\w+)"/g)].map((m) => m[1]).filter((id) => !enemyIds.has(id));
check(summonTargets.length === 0, "every boss summon references a real enemy", summonTargets.join(", "));

const startingWeapon = weaponSource.match(/StartingWeapon = "(\w+)"/);
check(startingWeapon && weaponIds.has(startingWeapon[1]), "starting weapon id exists");

// every weapon must have an Overforge variant, otherwise the machine is a dud
const weaponBlocks = weaponSource.split(/\n\t\{\n/).slice(1);
const missingUpgrades = weaponBlocks
  .filter((block) => !block.includes("upgrade = {"))
  .map((block) => (block.match(/id = "(\w+)"/) || [])[1]);
check(missingUpgrades.length === 0, "every weapon has an Overforge upgrade", missingUpgrades.join(", "));

console.log(`\n${checks} checks, ${failures} failure(s).`);
process.exit(failures === 0 ? 0 : 1);
