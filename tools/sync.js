#!/usr/bin/env node
/**
 * Live-syncs src/ into Roblox Studio with Rojo.
 *
 *   node tools/sync.js doctor     check the project and the machine, change nothing
 *   node tools/sync.js install    fetch the pinned Rojo CLI into .tools/bin
 *   node tools/sync.js plugin     install the Rojo Studio plugin for the local user
 *   node tools/sync.js serve      start the sync server (this one keeps running)
 *   node tools/sync.js live       serve + auto-pull new commits into Studio (keeps running)
 *   node tools/sync.js pull       git pull, so a running server streams the new code
 *   node tools/sync.js syncback   pull scripts out of a .rbxl back into src/
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
const MAC = process.platform === "darwin";
const EXE = WIN ? "rojo.exe" : "rojo";
const MIN_NODE = 18; // global fetch(), used to download the pinned Rojo

let warnings = 0;
let failures = 0;

function nodeMajor() {
  return Number(process.versions.node.split(".")[0]);
}

function requireNode() {
  if (nodeMajor() >= MIN_NODE) return;
  console.error(
    `this tool needs Node ${MIN_NODE} or newer (found ${process.versions.node}).\n` +
      (MAC
        ? "on macOS: `brew install node`, or download the LTS installer from https://nodejs.org"
        : "download the LTS installer from https://nodejs.org")
  );
  process.exit(1);
}

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

// Gatekeeper refuses to exec anything carrying com.apple.quarantine. Node's
// fetch does not set it, but a hand-downloaded release does, and the resulting
// "cannot be opened" dialog is a dead end. Clearing it is a no-op otherwise.
function quarantined(file) {
  if (!MAC || !fs.existsSync(file)) return false;
  const run = spawnSync("xattr", ["-p", "com.apple.quarantine", file], { encoding: "utf8" });
  return run.status === 0;
}

function clearQuarantine(file) {
  if (!quarantined(file)) return false;
  return spawnSync("xattr", ["-d", "com.apple.quarantine", file]).status === 0;
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
  clearQuarantine(target);

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

// Path of the Studio app, if it is where the installer puts it.
function studioApp() {
  const candidates = MAC
    ? ["/Applications/RobloxStudio.app", path.join(os.homedir(), "Applications", "RobloxStudio.app")]
    : WIN
      ? [path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "Roblox", "Versions")]
      : [];
  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

function git(args, cwd) {
  const run = spawnSync("git", args, { cwd: cwd || ROOT, encoding: "utf8" });
  if (run.error || run.status !== 0) return null;
  return (run.stdout || "").trim();
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

function checkGit() {
  if (!git(["rev-parse", "--git-dir"])) {
    warn("this folder is not a git clone", "you can still sync; you just cannot `npm run pull` new commits");
    return;
  }
  const branch = git(["rev-parse", "--abbrev-ref", "HEAD"]) || "?";
  const remote = git(["remote", "get-url", "origin"]);
  if (!remote) {
    warn(`on branch ${branch} with no "origin" remote`, "`npm run pull` needs one to fetch commits from");
    return;
  }
  ok(`git clone of ${remote} on branch ${branch}`);

  const upstream = git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]);
  if (!upstream) {
    warn(`branch ${branch} is not tracking a remote branch`, `\`git branch --set-upstream-to origin/${branch}\``);
    return;
  }
  // Deliberately no network fetch here: doctor is meant to be instant and to
  // work offline. This reports what the last fetch already knows.
  const counts = git(["rev-list", "--left-right", "--count", `${upstream}...HEAD`]);
  const [behind, ahead] = (counts || "0\t0").split(/\s+/).map(Number);
  if (behind) warn(`${behind} commit(s) waiting on ${upstream}`, "`npm run pull` to take them into Studio");
  else ok(`up to date with ${upstream} as of the last fetch`);
  if (ahead) ok(`${ahead} local commit(s) not pushed yet`);

  const dirty = git(["status", "--porcelain"]);
  if (dirty) warn(`${dirty.split("\n").length} uncommitted change(s)`, "`npm run pull` stashes and restores them for you");
}

async function doctor() {
  console.log("-- project");
  checkProject();

  console.log("-- machine");
  const platform = { win32: "Windows", darwin: "macOS", linux: "Linux" }[process.platform] || process.platform;
  if (nodeMajor() >= MIN_NODE) ok(`Node ${process.versions.node} on ${platform} (${process.arch})`);
  else fail(`Node ${MIN_NODE}+`, `found ${process.versions.node} on ${platform}`);

  const studio = studioApp();
  if (studio) ok(`Roblox Studio found (${studio})`);
  else if (MAC || WIN) warn("Roblox Studio not found in the usual place", "install it from https://create.roblox.com, or ignore this if it lives elsewhere");

  console.log("-- tooling");
  const rojo = findRojo();
  if (rojo) {
    ok(`Rojo ${rojo.version} (${rojo.source})`);
    if (rojo.version !== ROJO_VERSION) {
      warn(`Rojo ${rojo.version} is not the pinned ${ROJO_VERSION}`, `it is used as-is; rokit.toml pins ${ROJO_VERSION}`);
    }
    if (quarantined(rojo.exe)) {
      warn("macOS has quarantined the Rojo binary", `\`xattr -d com.apple.quarantine ${rojo.exe}\` - or delete .tools/ and run \`npm run sync:install\``);
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

  console.log("-- collaboration");
  checkGit();

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
  console.log("next: `npm run live` (sync + auto-pull), or `npm run sync` for sync alone.");
  console.log("then, in Studio: Plugins > Rojo > Connect");
}

// ------------------------------------------------------------------ commands

// Lists what a range of commits did to src/, the only part of a pull that
// Studio can show. Returns how many script files changed.
function reportScripts(before, after, indent, cwd) {
  const prefix = indent || "";
  const files = git(["diff", "--name-only", `${before}..${after}`], cwd) || "";
  const changed = files ? files.split("\n") : [];
  const scripts = changed.filter((file) => /^src\/.*\.luau?$/.test(file));
  console.log(`${prefix}${changed.length} file(s) changed, ${scripts.length} of them scripts:`);
  for (const file of scripts.slice(0, 20)) console.log(`${prefix}  ${file}`);
  if (scripts.length > 20) console.log(`${prefix}  ... and ${scripts.length - 20} more`);
  return scripts.length;
}

// `git pull` with the working tree protected. A Rojo server watching src/ picks
// the new files up on its own, so this is the whole "get Claude's edits into my
// Studio" step - no restart, no reconnect. `live` does it for you on a timer.
function pull() {
  if (!git(["rev-parse", "--git-dir"])) {
    console.error("not a git clone - nothing to pull");
    process.exitCode = 1;
    return;
  }
  const before = git(["rev-parse", "HEAD"]);
  const run = spawnSync("git", ["pull", "--rebase", "--autostash"], { cwd: ROOT, stdio: "inherit" });
  if (run.status !== 0) {
    console.error("\ngit pull failed. Resolve the conflict above, then run it again.");
    process.exitCode = run.status || 1;
    return;
  }
  const after = git(["rev-parse", "HEAD"]);
  if (before === after) {
    console.log("already up to date - nothing new to sync");
    return;
  }
  console.log("");
  const scripts = reportScripts(before, after);
  console.log(
    scripts
      ? "\na running `npm run sync` has already pushed these into Studio. Press Play to try them."
      : "\nno script changes, so Studio will not show anything new."
  );
}

// ----------------------------------------------------------------- live mode

const DEFAULT_INTERVAL = 15; // seconds between fetches

function stamp() {
  return new Date().toTimeString().slice(0, 8);
}

function say(line) {
  console.log(`${stamp()} live  ${line}`);
}

const SAY_INDENT = " ".repeat(stamp().length) + " live  ";

function argValue(args, flag, fallback) {
  const index = args.indexOf(flag);
  const value = index >= 0 ? args[index + 1] : null;
  if (value && !value.startsWith("--")) return value;
  return fallback;
}

// The branch `live` may fast-forward, or null - with the reason already printed,
// because serving without the watcher is still useful.
function liveTarget() {
  if (!git(["rev-parse", "--git-dir"])) {
    say("this folder is not a git clone, so there is nothing to watch - serving files only");
    return null;
  }
  const branch = git(["rev-parse", "--abbrev-ref", "HEAD"]) || "?";
  if (!git(["remote", "get-url", "origin"])) {
    say(`no "origin" remote to watch - serving files only`);
    return null;
  }
  const upstream = git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]);
  if (!upstream) {
    say(`branch ${branch} tracks no remote branch - serving files only`);
    say(`  fix: git branch --set-upstream-to origin/${branch}`);
    return null;
  }
  return { branch: branch, upstream: upstream };
}

// One poll: fetch, then fast-forward if the remote moved.
//   current  nothing new
//   pulled   commits applied; Rojo's file watcher takes it from here
//   offline  the remote was unreachable - transient, keep polling
//   blocked  a rebase or stash conflict; a human has to step in, so the caller
//            stops polling instead of reprinting the same failure forever
function pollOnce(target, cwd) {
  const dir = cwd || ROOT;
  const fetched = spawnSync("git", ["fetch", "--quiet"], { cwd: dir, encoding: "utf8" });
  if (fetched.error || fetched.status !== 0) {
    const detail = (fetched.stderr || "").trim() || (fetched.error && fetched.error.message) || "git fetch failed";
    return { state: "offline", detail: detail };
  }
  const behind = Number(git(["rev-list", "--count", `HEAD..${target.upstream}`], dir) || "0");
  if (!behind) return { state: "current" };

  const before = git(["rev-parse", "HEAD"], dir);
  const pulled = spawnSync("git", ["pull", "--rebase", "--autostash"], { cwd: dir, encoding: "utf8" });
  if (pulled.status !== 0) {
    return { state: "blocked", detail: `${pulled.stdout || ""}${pulled.stderr || ""}`.trim() };
  }
  return { state: "pulled", behind: behind, before: before, after: git(["rev-parse", "HEAD"], dir) };
}

// `serve` plus a git watcher, in one window. Commits pushed to the tracked
// branch are pulled and handed to the running Rojo server, which streams them
// into the open Studio session - so an agent that cannot reach this machine
// still lands its edits in the place, hands-free.
async function live(args) {
  const rojo = await requireRojo();
  const port = argPort(args);
  const asked = argValue(args, "--interval", process.env.ROJO_PULL_INTERVAL || DEFAULT_INTERVAL);
  const seconds = Math.max(5, Number(asked) || DEFAULT_INTERVAL);
  const target = liveTarget();

  console.log(`Rojo ${rojo.version} (${rojo.source}) serving NECROTIDE: LAST STAND on port ${port}`);
  console.log("in Studio: Plugins > Rojo > Connect. Leave this running while you edit.");
  if (target) console.log(`watching ${target.upstream} every ${seconds}s - new commits go straight into Studio`);
  console.log("");

  let stopped = false;
  let timer = null;
  const child = spawn(rojo.exe, ["serve", "default.project.json", "--port", port], { cwd: ROOT, stdio: "inherit" });
  child.on("exit", (code) => {
    stopped = true;
    if (timer) clearTimeout(timer);
    process.exit(code === null ? 1 : code);
  });
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => {
      stopped = true;
      if (timer) clearTimeout(timer);
      child.kill(signal);
    });
  }

  if (!target) return;

  let lastOffline = null;
  const tick = () => {
    if (stopped) return;
    const result = pollOnce(target);
    if (result.state === "pulled") {
      say(`pulled ${result.behind} commit(s) from ${target.upstream}`);
      const scripts = reportScripts(result.before, result.after, SAY_INDENT);
      say(scripts ? "Rojo is pushing them into Studio now" : "no script changes, so Studio will not show anything new");
      lastOffline = null;
    } else if (result.state === "offline") {
      // Print a given failure once, not once per interval.
      if (result.detail !== lastOffline) {
        say(`cannot reach ${target.upstream.split("/")[0]}, still trying: ${result.detail.split("\n")[0]}`);
        lastOffline = result.detail;
      }
    } else if (result.state === "blocked") {
      say("git pull needs a hand - the watcher is stopping, Rojo keeps serving");
      console.log(result.detail);
      say("sort it out in another terminal, then restart `npm run live`");
      return;
    } else {
      lastOffline = null;
    }
    timer = setTimeout(tick, seconds * 1000);
  };
  timer = setTimeout(tick, seconds * 1000);
}

function argPort(args) {
  const index = args.indexOf("--port");
  if (index >= 0 && args[index + 1]) return args[index + 1];
  return String(process.env.ROJO_PORT || DEFAULT_PORT);
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] && !args[0].startsWith("--") ? args[0] : "serve";

  if (command === "doctor") return doctor();
  if (command === "pull") return pull();

  requireNode();

  if (command === "live") return live(args);

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
  if (command === "syncback") {
    // The reverse direction: take a place you have been editing inside Studio
    // and write its scripts back over src/. Only the containers mapped in
    // default.project.json are touched; Workspace and Lighting are marked
    // $ignoreUnknownInstances, so hand-built geometry is not serialised.
    const input = args.slice(1).find((arg) => !arg.startsWith("--"));
    if (!input) {
      const guesses = fs
        .readdirSync(ROOT)
        .filter((name) => /\.rbxlx?$/.test(name))
        .map((name) => `  node tools/sync.js syncback ${name}`);
      console.error("syncback needs the place file to read, e.g.\n  node tools/sync.js syncback place.rbxl");
      if (guesses.length) console.error(`\nfound in this folder:\n${guesses.join("\n")}`);
      process.exitCode = 1;
      return;
    }
    if (!fs.existsSync(path.resolve(ROOT, input))) {
      console.error(`${input} does not exist - save the place from Studio first (File > Save As)`);
      process.exitCode = 1;
      return;
    }
    const write = args.includes("--write");
    console.log(
      write
        ? `writing ${input} back over src/ - Rojo will ask you to confirm; commit first if you have not`
        : `dry run: what ${input} would change in src/. Re-run with --write to apply.`
    );
    const flags = ["syncback", "default.project.json", "--input", input, "--list"];
    if (!write) flags.push("--dry-run");
    return runRojo(rojo, flags);
  }
  if (command === "serve") {
    const port = argPort(args);
    console.log(`Rojo ${rojo.version} (${rojo.source}) serving NECROTIDE: LAST STAND on port ${port}`);
    console.log("in Studio: Plugins > Rojo > Connect. Leave this running while you edit.");
    return runRojo(rojo, ["serve", "default.project.json", "--port", port]);
  }

  console.error(`unknown command "${command}" - try: doctor, install, plugin, serve, live, pull, syncback, sourcemap, build`);
  process.exitCode = 1;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = { pollOnce: pollOnce, reportScripts: reportScripts, liveTarget: liveTarget, findRojo: findRojo };
