#!/usr/bin/env node
/**
 * Syntax-checks every Lua source in the project.
 *
 * The game is written in Luau, but deliberately in the Lua 5.1-compatible subset
 * (no `+=`, no type annotations, no `continue`) so it can be parsed offline with
 * luaparse. That gives a real syntax gate without a Roblox install.
 */
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const ROOT = path.join(__dirname, "..");
const DIRS = ["src", "tools"];

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".lua")) out.push(full);
  }
  return out;
}

const BANNED = [
  { re: /(^|[^=~<>+\-*/%.])\+=/, msg: "compound assignment (+=) is Luau-only; use `x = x + n`" },
  { re: /^\s*continue\s*$/m, msg: "`continue` is Luau-only; restructure the loop" },
  { re: /\]\]>/, msg: "`]]>` would break the CDATA block in the generated place file" },
];

let files = [];
for (const dir of DIRS) files = files.concat(walk(path.join(ROOT, dir)));
files.sort();

let failures = 0;
for (const file of files) {
  const rel = path.relative(ROOT, file).replace(/\\/g, "/");
  const source = fs.readFileSync(file, "utf8");

  for (const rule of BANNED) {
    if (rule.re.test(source)) {
      console.error(`FAIL ${rel}: ${rule.msg}`);
      failures++;
    }
  }

  try {
    luaparse.parse(source, { luaVersion: "5.1", comments: false, scope: false });
    console.log(`ok   ${rel}`);
  } catch (err) {
    failures++;
    console.error(`FAIL ${rel}: ${err.message}`);
  }
}

console.log(`\n${files.length} Lua files checked, ${failures} problem(s).`);
process.exit(failures === 0 ? 0 : 1);
