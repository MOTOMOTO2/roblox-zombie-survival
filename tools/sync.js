#!/usr/bin/env node
/**
 * Live-syncs src/ into Roblox Studio with Rojo.
 *
 *   node tools/sync.js doctor     check the project and the machine, change nothing
 *   node tools/sync.js install    fetch the pinned Rojo CLI into .tools/bin
 *   node tools/sync.js plugin     install the Rojo Studio plugin for the local user
 *   node tools/sync.js serve      start the sync server (this one keeps running)
 *   node tools/sync.js sourcemap  write sourcemap.json for Luau LSP
 *   node tools/sync.js build      build a place file with Rojo instead of tools/build.js
 *
 * Rojo is resolved in this order: $ROJO_PATH, `rojo` on PATH (7.x only),
 * .tools/bin/rojo. If none of those exist, `install`/`serve` download the
 * pinned release from GitHub. Nothing is installed system-wide.
 */
const fs = require("fs");
const path = require("path");
const os = require("os");
const net = require("net");
const zlib = require("zlib");
const { spawnSync, spawn } = require("child_process");

const ROOT = path.join(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");
const TOOLS_BIN = path.join(ROOT, ".tools", "bin");
const ROJO_VERSION = "7.7.0";
const DEFAULT_PORT = 34872;
const WIN = process.platform === "win32";
const EXE = WIN ? "rojo.exe" : "rojo";

let warnings = 0;
let failures = 0;

function ok(label) {
  console.log(`ok   ${label}`);
}

function warn(label, hint) {
  warnings += 1;
  console.log(`warn ${label}${hint ? "\n     " + hint.split("\n").join("\n     ") : ""}`);
}

function fail(label, detail) {
  failures += 1;
  console.error(`FAIL ${label}${detail ? " - " + detail : ""}`);
}

// ---------------------------------------------------------------- rojo binary

function rojoVersion(exe) {
  const run = spawnSync(exe, ["--version"], { encoding: "utf8" });
  if (run.error || run.status !== 0) return null;
  const match = /(\d+)\.(\d+)\.(\d+)/.exec(run.stdout || "");
  return match ? match[0] : null;
}

// Returns { exe, version, source } or null.
function findRojo() {
  const candidates = [];
  if (process.env.ROJO_PATH) candidates.push([process.env.ROJO_PATH, "$ROJO_PATH"]);
  candidates.push([EXE, "PATH"]);
  candidates.push([path.join(TOOLS_BIN, EXE), ".tools/bin"]);
  for (const [exe, source] of candidates) {
    if (source === ".tools/bin" && !fs.existsSync(exe)) continue;
    const version = rojoVersion(exe);
    if (!version) continue;
    if (Number(version.split(".")[0]) < 7) continue; // 0.5.x speaks a different protocol
    return { exe, version, source };
  }
  return null;
}

function releaseAsset() {
  const plat = { win32: "windows", darwin: "macos", linux: "linux" }[process.platform];
  if (!plat) throw new Error(`no Rojo release for platform ${process.platform}`);
  if (process.arch !== "arm64" && process.arch !== "x64") {
    throw new Error(`no Rojo release for arch ${process.arch}`);
  }
  const arch = process.arch === "arm64" ? "aarch64" : "x86_64";
  return `rojo-${ROJO_VERSION}-${plat}-${arch}.zip`;
}

// Minimal store/deflate zip reader - the release archives hold a single binary
// and this keeps the tool dependency-free like the rest of tools/.
function unzip(buffer) {
  let eocd = -1;
  for (let i = buffer.length - 22; i >= 0 && i > buffer.length - 66000; i -= 1) {
    if (buffer.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error("not a zip file (no end-of-central-directory record)");
  const count = buffer.readUInt16LE(eocd + 10);
  let cursor = buffer.readUInt32LE(eocd + 16);
  const files = [];
  for (let i = 0; i < count; i += 1) {
    if (buffer.readUInt32LE(cursor) !== 0x02014b50) throw new Error("corrupt central directory");
    const method = buffer.readUInt16LE(cursor + 10);
    const compressedSize = buffer.readUInt32LE(cursor + 20);
    const nameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const localOffset = buffer.readUInt32LE(cursor + 42);
    const name = buffer.toString("utf8", cursor + 46, cursor + 46 + nameLength);
    cursor += 46 + nameLength + extraLength + commentLength;

    if (buffer.readUInt32LE(localOffset) !== 0x04034b50) throw new Error("corrupt local file header");
    const localNameLength = buffer.readUInt16LE(localOffset + 26);
    const localExtraLength = buffer.readUInt16LE(localOffset + 28);
    const start = localOffset + 30 + localNameLength + localExtraLength;
    const raw = buffer.subarray(start, start + compressedSize);
    if (method !== 0 && method !== 8) throw new Error(`unsupported zip compression method ${method}`);
    files.push({ name: name, data: method === 0 ? raw : zlib.inflateRawSync(raw) });
  }
  return files;
}

async function downloadRojo() {
  const asset = releaseAsset();
  const url = `https://github.com/rojo-rbx/rojo/releases/download/v${ROJO_VERSION}/${asset}`;
  console.log(`downloading ${asset}`);
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) throw new Error(`${url} responded ${response.status}`);
  const zip = Buffer.from(await response.arrayBuffer());
  const entry = unzip(zip).find((file) => path.basename(file.name) === EXE);
  if (!entry) throw new Error(`${asset} did not contain ${EXE}`);

  fs.mkdirSync(TOOLS_BIN, { recursive: true });
  const target = path.join(TOOLS_BIN, EXE);
  fs.writeFileSync(target, entry.data);
  if (!WIN) fs.chmodSync(target, 0o755);

  const version = rojoVersion(target);
  if (version !== ROJO_VERSION) {
    throw new Error(`downloaded binary reports ${version || "no version"}, expected ${ROJO_VERSION}`);
  }
  console.log(`installed Rojo ${version} to .tools/bin/${EXE}`);
  return { exe: target, version: version, source: ".tools/bin" };
}

async function requireRojo() {
  return findRojo() || downloadRojo();
}

function runRojo(rojo, args) {
  const child = spawn(rojo.exe, args, { cwd: ROOT, stdio: "inherit" });
  child.on("exit", (code) => process.exit(code === null ? 1 : code));
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => child.kill(signal));
  }
}

// -------------------------------------------------------------------- checks

function pluginDir() {
  if (WIN) {
    const local = process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local");
    return path.join(local, "Roblox", "Plugins");
  }
  if (process.platform === "darwin") return path.join(os.homedir(), "Documents", "Roblox", "Plugins");
  return null; // Studio is Windows/macOS only
}

function portFree(port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port: port });
    socket.setTimeout(700);
    const done = (free) => {
      socket.destroy();
      resolve(free);
    };
    socket.on("connect", () => done(false));
    socket.on("timeout", () => done(true));
    socket.on("error", () => done(true));
  });
}

function checkProject() {
  let project;
  try {
    project = JSON.parse(fs.readFileSync(PROJECT, "utf8"));
  } catch (error) {
    fail("default.project.json parses", error.message);
    return;
  }
  ok(`default.project.json parses (project "${project.name}")`);

  if (project.tree && project.tree.$className === "DataModel") {
    ok("project root is a DataModel, so it syncs into a place");
  } else {
    fail("project root is a DataModel", 'tree.$className must be "DataModel" for `rojo serve`');
  }

  const mapped = [];
  (function collect(node, trail) {
    if (!node || typeof node !== "object") return;
    if (typeof node.$path === "string") mapped.push([trail.join("."), node.$path]);
    for (const key of Object.keys(node)) {
      if (!key.startsWith("$")) collect(node[key], trail.concat(key));
    }
  })(project.tree, []);

  if (!mapped.length) fail("project maps at least one directory", "no $path entries found");
  for (const pair of mapped) {
    const label = `${pair[0]} <- ${pair[1]}`;
    if (fs.existsSync(path.join(ROOT, pair[1]))) ok(label);
    else fail(label, "path does not exist");
  }

  // Two files that collapse to the same instance name would fight each other on
  // every sync, so catch it here rather than in Studio.
  const seen = new Map();
  let scripts = 0;
  (function walk(dir) {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (!/\.luau?$/.test(entry.name)) continue;
      scripts += 1;
      const stem = entry.name.replace(/\.(server|client)?\.?luau?$/, "");
      const key = path.dirname(full).toLowerCase() + "\u0000" + stem.toLowerCase();
      const clash = seen.get(key);
      if (clash) {
        fail(`one instance named "${stem}"`, `${path.relative(ROOT, clash)} and ${path.relative(ROOT, full)} both sync to it`);
      }
      seen.set(key, full);
    }
  })(path.join(ROOT, "src"));

  if (scripts > 0) ok(`${scripts} source files under src/`);
  else fail("src/ contains source files", "nothing to sync");
}

async function doctor() {
  console.log("-- project");
  checkProject();

  console.log("-- tooling");
  const rojo = findRojo();
  if (rojo) {
    ok(`Rojo ${rojo.version} (${rojo.source})`);
    if (rojo.version !== ROJO_VERSION) {
      warn(`Rojo ${rojo.version} is not the pinned ${ROJO_VERSION}`, `it is used as-is; rokit.toml pins ${ROJO_VERSION}`);
    }
  } else {
    warn("no Rojo CLI found", `\`npm run sync:install\` downloads Rojo ${ROJO_VERSION} into .tools/bin - nothing system-wide`);
  }

  const dir = pluginDir();
  if (!dir) {
    warn("Roblox Studio does not run on this platform", "run the sync server on the machine that has Studio");
  } else if (!fs.existsSync(dir)) {
    warn(`Studio plugin folder is missing (${dir})`, "run `npm run sync:plugin`, then restart Studio");
  } else {
    const installed = fs.readdirSync(dir).find((name) => /rojo/i.test(name));
    if (installed) ok(`Rojo Studio plugin installed (${installed})`);
    else warn("Rojo Studio plugin is not installed", "run `npm run sync:plugin`, then restart Studio");
  }

  console.log("-- network");
  const port = Number(process.env.ROJO_PORT || DEFAULT_PORT);
  if (await portFree(port)) {
    ok(`port ${port} is free`);
  } else {
    warn(`port ${port} is already in use`, `stop the other Rojo server, or run \`npm run sync -- --port ${port + 1}\``);
  }

  console.log("");
  console.log(`${failures} failed, ${warnings} warnings`);
  if (failures) {
    process.exitCode = 1;
    return;
  }
  console.log("next: `npm run sync`, then in Studio: Plugins > Rojo > Connect");
}

// ------------------------------------------------------------------ commands

function argPort(args) {
  const index = args.indexOf("--port");
  if (index >= 0 && args[index + 1]) return args[index + 1];
  return String(process.env.ROJO_PORT || DEFAULT_PORT);
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] && !args[0].startsWith("--") ? args[0] : "serve";

  if (command === "doctor") return doctor();

  if (command === "install") {
    const found = findRojo();
    if (found) {
      console.log(`Rojo ${found.version} already available (${found.source})`);
      return;
    }
    await downloadRojo();
    return;
  }

  const rojo = await requireRojo();

  if (command === "plugin") {
    console.log("installing the Rojo Studio plugin for the current user - restart Studio afterwards");
    return runRojo(rojo, ["plugin", "install"]);
  }
  if (command === "sourcemap") {
    return runRojo(rojo, ["sourcemap", "default.project.json", "--output", "sourcemap.json"].concat(args.slice(1)));
  }
  if (command === "build") {
    // Deliberately not build/NecrotideLastStand.rbxlx: that one is the checked-in
    // artifact from tools/build.js, and clobbering it with a second generator
    // makes for noisy diffs.
    const out = args[1] && !args[1].startsWith("--") ? args[1] : "build/rojo/NecrotideLastStand.rbxlx";
    fs.mkdirSync(path.dirname(path.join(ROOT, out)), { recursive: true });
    return runRojo(rojo, ["build", "default.project.json", "--output", out]);
  }
  if (command === "serve") {
    const port = argPort(args);
    console.log(`Rojo ${rojo.version} (${rojo.source}) serving NECROTIDE: LAST STAND on port ${port}`);
    console.log("in Studio: Plugins > Rojo > Connect. Leave this running while you edit.");
    return runRojo(rojo, ["serve", "default.project.json", "--port", port]);
  }

  console.error(`unknown command "${command}" - try: doctor, install, plugin, serve, sourcemap, build`);
  process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
