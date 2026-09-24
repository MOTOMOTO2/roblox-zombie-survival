#!/usr/bin/env node
/**
 * Builds the Roblox files from src/ with no external tooling:
 *
 *   build/NecrotideLastStand.rbxlx  - a complete place. File > Open in Studio, hit Play.
 *   build/NecrotideLastStand.rbxmx  - a model you can drag into an existing place.
 *
 * Mapping rules (same convention Rojo uses, so rojo works too - see
 * default.project.json):
 *   src/<Service>/...        -> that Roblox service
 *   nested directories       -> Folder
 *   Foo.server.lua           -> Script
 *   Foo.client.lua           -> LocalScript
 *   Foo.lua                  -> ModuleScript
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const SRC = path.join(ROOT, "src");
const OUT = path.join(ROOT, "build");
const NAME = "NecrotideLastStand";

// Top-level directory names that are real Roblox services rather than folders.
const SERVICES = new Set([
  "Workspace",
  "Players",
  "Lighting",
  "ReplicatedFirst",
  "ReplicatedStorage",
  "ServerScriptService",
  "ServerStorage",
  "StarterGui",
  "StarterPack",
  "StarterPlayer",
  "SoundService",
  "Chat",
  "Teams",
  "TextChatService",
]);

// Container classes inside StarterPlayer.
const NESTED_CLASSES = {
  StarterPlayerScripts: "StarterPlayerScripts",
  StarterCharacterScripts: "StarterCharacterScripts",
};

let referent = 0;
function nextReferent() {
  referent += 1;
  return `RBX${referent}`;
}

function escapeText(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/** Wraps Lua source in CDATA, splitting on the only sequence that could end it. */
function cdata(source) {
  const safe = source.split("]]>").join("]]]]><![CDATA[>");
  return `<![CDATA[${safe}]]>`;
}

function indent(depth) {
  return "\t".repeat(depth);
}

function scriptItem(name, source, className, disabled, depth) {
  const lines = [];
  lines.push(`${indent(depth)}<Item class="${className}" referent="${nextReferent()}">`);
  lines.push(`${indent(depth + 1)}<Properties>`);
  lines.push(`${indent(depth + 2)}<string name="Name">${escapeText(name)}</string>`);
  lines.push(`${indent(depth + 2)}<ProtectedString name="Source">${cdata(source)}</ProtectedString>`);
  if (className !== "ModuleScript") {
    lines.push(`${indent(depth + 2)}<bool name="Disabled">${disabled ? "true" : "false"}</bool>`);
  }
  lines.push(`${indent(depth + 1)}</Properties>`);
  lines.push(`${indent(depth)}</Item>`);
  return lines.join("\n");
}

function containerItem(name, className, childrenXml, depth) {
  const lines = [];
  lines.push(`${indent(depth)}<Item class="${className}" referent="${nextReferent()}">`);
  lines.push(`${indent(depth + 1)}<Properties>`);
  lines.push(`${indent(depth + 2)}<string name="Name">${escapeText(name)}</string>`);
  lines.push(`${indent(depth + 1)}</Properties>`);
  if (childrenXml) lines.push(childrenXml);
  lines.push(`${indent(depth)}</Item>`);
  return lines.join("\n");
}

function classify(fileName) {
  if (fileName.endsWith(".server.lua")) {
    return { name: fileName.slice(0, -".server.lua".length), className: "Script" };
  }
  if (fileName.endsWith(".client.lua")) {
    return { name: fileName.slice(0, -".client.lua".length), className: "LocalScript" };
  }
  if (fileName.endsWith(".lua")) {
    return { name: fileName.slice(0, -".lua".length), className: "ModuleScript" };
  }
  return null;
}

const stats = { scripts: 0, modules: 0, folders: 0, bytes: 0 };

/** Renders the children of a directory. */
function renderDirectory(dir, depth, disabled) {
  const parts = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));

  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const className = NESTED_CLASSES[entry.name] || "Folder";
      if (className === "Folder") stats.folders += 1;
      parts.push(containerItem(entry.name, className, renderDirectory(full, depth + 1, disabled), depth));
    } else {
      const info = classify(entry.name);
      if (!info) continue;
      const source = fs.readFileSync(full, "utf8");
      stats.bytes += Buffer.byteLength(source, "utf8");
      if (info.className === "ModuleScript") stats.modules += 1;
      else stats.scripts += 1;
      parts.push(scriptItem(info.name, source, info.className, disabled, depth));
    }
  }
  return parts.join("\n");
}

function xmlDocument(body) {
  return [
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
    "\t<Meta name=\"ExplicitAutoJoints\">true</Meta>",
    "\t<External>null</External>",
    "\t<External>nil</External>",
    body,
    "</roblox>",
    "",
  ].join("\n");
}

/** The full place file: one Item per service directory in src/. */
function buildPlace() {
  const serviceDirs = fs
    .readdirSync(SRC, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  const items = [];
  for (const dirName of serviceDirs) {
    if (!SERVICES.has(dirName)) {
      throw new Error(`src/${dirName} is not a known Roblox service. Add it to SERVICES in tools/build.js.`);
    }
    const children = renderDirectory(path.join(SRC, dirName), 2, false);
    items.push(containerItem(dirName, dirName, children, 1));
  }

  // A place needs somewhere to stand before MapBuilder runs; the arena is
  // generated at runtime, so Workspace only needs to exist.
  if (!serviceDirs.includes("Workspace")) {
    items.push(containerItem("Workspace", "Workspace", "", 1));
  }
  return xmlDocument(items.join("\n"));
}

/** The drag-in model: disabled payload + installer script. */
function buildModel() {
  const payloadParts = [];
  const serviceDirs = fs
    .readdirSync(SRC, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  for (const dirName of serviceDirs) {
    if (dirName === "StarterPlayer") {
      // flatten StarterPlayer/StarterPlayerScripts -> a plain folder the
      // installer re-parents into the real StarterPlayerScripts
      const nested = path.join(SRC, dirName, "StarterPlayerScripts");
      if (fs.existsSync(nested)) {
        payloadParts.push(
          containerItem("StarterPlayerScripts", "Folder", renderDirectory(nested, 4, true), 3)
        );
      }
      continue;
    }
    payloadParts.push(containerItem(dirName, "Folder", renderDirectory(path.join(SRC, dirName), 4, true), 3));
  }

  const installerSource = fs.readFileSync(path.join(__dirname, "installer.lua"), "utf8");
  const payload = containerItem("Payload", "Folder", payloadParts.join("\n"), 2);
  const installer = scriptItem("Installer", installerSource, "Script", false, 2);
  const root = containerItem(NAME, "Folder", [payload, installer].join("\n"), 1);
  return xmlDocument(root);
}

fs.mkdirSync(OUT, { recursive: true });

const placePath = path.join(OUT, `${NAME}.rbxlx`);
const place = buildPlace();
fs.writeFileSync(placePath, place, "utf8");

referent = 0;
const modelPath = path.join(OUT, `${NAME}.rbxmx`);
const model = buildModel();
fs.writeFileSync(modelPath, model, "utf8");

console.log(`place  ${path.relative(ROOT, placePath)}  (${(place.length / 1024).toFixed(1)} KiB)`);
console.log(`model  ${path.relative(ROOT, modelPath)}  (${(model.length / 1024).toFixed(1)} KiB)`);
console.log(
  `packed ${stats.scripts} scripts, ${stats.modules} modules, ${stats.folders} folders, ${(stats.bytes / 1024).toFixed(1)} KiB of Lua`
);
