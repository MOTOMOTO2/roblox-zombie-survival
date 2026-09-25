#!/usr/bin/env node
/**
 * Tests the live watcher - the loop that carries pushed commits into a running
 * Studio session - against throwaway git repos in the temp directory. No
 * network, no Roblox, no Studio: it builds a bare "origin", clones it twice
 * (one clone stands in for this machine, the other for the agent pushing
 * commits) and drives tools/sync.js `pollOnce` through every outcome it
 * reports: current, pulled, blocked and offline.
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const { pollOnce } = require("./sync.js");

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

function run(cwd, args, allowFailure) {
  const result = spawnSync("git", args, { cwd: cwd, encoding: "utf8" });
  if (!allowFailure && (result.error || result.status !== 0)) {
    throw new Error(`git ${args.join(" ")} in ${cwd} failed:\n${result.stderr || result.error}`);
  }
  return result;
}

function identify(repo) {
  run(repo, ["config", "user.email", "test@example.invalid"]);
  run(repo, ["config", "user.name", "Sync Test"]);
  run(repo, ["config", "commit.gpgsign", "false"]);
}

function write(repo, file, text) {
  const full = path.join(repo, file);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, text);
}

function commit(repo, message) {
  run(repo, ["add", "-A"]);
  run(repo, ["commit", "-m", message]);
}

// bare origin + seed commit + two clones of it
function scaffold(root) {
  const origin = path.join(root, "origin.git");
  fs.mkdirSync(origin, { recursive: true });
  run(root, ["init", "--bare", "--initial-branch=main", origin]);

  const seed = path.join(root, "seed");
  fs.mkdirSync(seed, { recursive: true });
  run(seed, ["init", "--initial-branch=main"]);
  identify(seed);
  write(seed, "src/ReplicatedStorage/NecrotideShared/GameConfig.lua", "return { Wave = 1 }\n");
  write(seed, "README.md", "seed\n");
  commit(seed, "seed");
  run(seed, ["remote", "add", "origin", origin]);
  run(seed, ["push", "-u", "origin", "main"]);

  const mine = path.join(root, "mine"); // the machine running Studio
  const theirs = path.join(root, "theirs"); // the agent pushing commits
  run(root, ["clone", origin, mine]);
  run(root, ["clone", origin, theirs]);
  identify(mine);
  identify(theirs);
  return { origin: origin, mine: mine, theirs: theirs };
}

const TARGET = { branch: "main", upstream: "origin/main" };

function main() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "necrotide-sync-"));
  try {
    const repos = scaffold(root);

    // 1. nothing pushed yet
    check(pollOnce(TARGET, repos.mine).state === "current", "an idle watcher reports current");

    // 2. a pushed script change is pulled and reported as a script change
    write(repos.theirs, "src/ReplicatedStorage/NecrotideShared/GameConfig.lua", "return { Wave = 2 }\n");
    commit(repos.theirs, "buff wave 2");
    run(repos.theirs, ["push"]);
    const pulled = pollOnce(TARGET, repos.mine);
    check(pulled.state === "pulled", "a pushed commit is pulled", `state was ${pulled.state}`);
    check(pulled.behind === 1, "one commit behind is reported as one", `behind was ${pulled.behind}`);
    const applied = fs.readFileSync(
      path.join(repos.mine, "src/ReplicatedStorage/NecrotideShared/GameConfig.lua"),
      "utf8"
    );
    check(applied.includes("Wave = 2"), "the working tree Rojo watches now holds the new code");
    check(pulled.before !== pulled.after, "the pull reports the range it applied");

    // 3. straight back to quiet
    check(pollOnce(TARGET, repos.mine).state === "current", "a second poll finds nothing new");

    // 4. uncommitted local edits survive a pull (--autostash), because the
    //    person at the keyboard should not lose work to a background fetch
    write(repos.mine, "notes.txt", "my scratch notes\n");
    write(repos.theirs, "src/ReplicatedStorage/NecrotideShared/EnemyDefs.lua", "return {}\n");
    commit(repos.theirs, "add enemies");
    run(repos.theirs, ["push"]);
    const withDirt = pollOnce(TARGET, repos.mine);
    check(withDirt.state === "pulled", "a pull still happens with a dirty working tree", `state was ${withDirt.state}`);
    check(
      fs.existsSync(path.join(repos.mine, "notes.txt")) &&
        fs.readFileSync(path.join(repos.mine, "notes.txt"), "utf8").includes("scratch"),
      "uncommitted local edits are restored afterwards"
    );
    check(
      fs.existsSync(path.join(repos.mine, "src/ReplicatedStorage/NecrotideShared/EnemyDefs.lua")),
      "and the pulled file is there too"
    );

    // 5. a real conflict must stop the watcher rather than loop on the failure
    write(repos.mine, "src/ReplicatedStorage/NecrotideShared/GameConfig.lua", "return { Wave = 99 }\n");
    commit(repos.mine, "local edit that will conflict");
    write(repos.theirs, "src/ReplicatedStorage/NecrotideShared/GameConfig.lua", "return { Wave = 3 }\n");
    commit(repos.theirs, "remote edit to the same line");
    run(repos.theirs, ["push"]);
    const blocked = pollOnce(TARGET, repos.mine);
    check(blocked.state === "blocked", "a conflicting pull is reported as blocked", `state was ${blocked.state}`);
    check(Boolean(blocked.detail && blocked.detail.length), "and carries git's own explanation");
    run(repos.mine, ["rebase", "--abort"], true);

    // 6. an unreachable remote is transient, not fatal
    run(repos.mine, ["remote", "set-url", "origin", path.join(root, "does-not-exist.git")]);
    const offline = pollOnce(TARGET, repos.mine);
    check(offline.state === "offline", "an unreachable remote is reported as offline", `state was ${offline.state}`);
    check(Boolean(offline.detail && offline.detail.length), "and says why");
  } finally {
    fs.rmSync(root, { recursive: true, force: true, maxRetries: 5 });
  }

  console.log("");
  console.log(`${checks - failures}/${checks} checks passed`);
  if (failures) process.exitCode = 1;
}

main();
