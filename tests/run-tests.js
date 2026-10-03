"use strict";

// actionscript-polycall test harness (npm test):
//   1. compile tests/TestMain.as + src/ with Apache Royale `asnodec`
//      (AS3 -> JavaScript for Node.js, Closure release build), or use a
//      prebuilt one from AS3_POLYCALL_BUILD_DIR;
//   2. start a `polycall start` runtime, a `polycall daemon start` daemon and
//      a `polycall peer serve` C node with the C CLI;
//   3. run the compiled AS3 test against the REAL core and report its checks;
//   4. loader cases: default names, POLYCALL_LIBRARY, missing library, old /
//      ABI-2 / partial stand-in libraries (tests/fixtures/fake_core.c).
// Exit 0 = all passed, 1 = a failure, 77 = something needed was missing
// (Royale/Java, core, CLI, compiler) -- never reported as a pass.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..");
const counts = { pass: 0, fail: 0, skip: 0, blocked: 0 };
const pass = (n) => { counts.pass += 1; console.log(`PASS  ${n}`); };
const fail = (n, d) => { counts.fail += 1; console.log(`FAIL  ${n}${d ? `: ${d}` : ""}`); };
const skip = (n, r, kind = "blocked") => {
  counts.skip += 1;
  if (kind === "blocked") counts.blocked += 1;
  console.log(`SKIP  ${n} (${kind}: ${r})`);
};
const check = (c, n, d) => (c ? pass(n) : fail(n, d));
const children = [];

function cliEnv(extra = {}) {
  return { ...process.env, POLYCALL_TELEMETRY: "off", ...extra };
}

function findCli() {
  const c = process.env.POLYCALL_CLI || "polycall";
  const r = spawnSync(c, ["--version"], { encoding: "utf8", windowsHide: true, env: cliEnv() });
  return r.error || r.status !== 0 ? null : { path: c, version: r.stdout.trim() };
}

function waitForFile(file, ms = 15000) {
  const end = Date.now() + ms;
  return new Promise((resolve, reject) => {
    const tick = () => {
      try {
        const t = fs.readFileSync(file, "utf8").trim();
        if (t) return resolve(t.split(/\r?\n/)[0].trim());
      } catch (_) { /* not yet */ }
      if (Date.now() > end) return reject(new Error(`timed out waiting for ${file}`));
      setTimeout(tick, 50);
    };
    tick();
  });
}

async function startCli(cli, args, cwd, env, label) {
  const epFile = path.join(cwd, `${label}.endpoint`);
  const log = fs.openSync(path.join(cwd, `${label}.log`), "w");
  const child = spawn(cli.path, [...args, "--endpoint-file", epFile], { cwd, env, stdio: ["ignore", log, log], windowsHide: true });
  children.push(child);
  try {
    return await waitForFile(epFile);
  } catch (e) {
    throw new Error(`${label} did not start: ${e.message}\n${fs.readFileSync(path.join(cwd, `${label}.log`), "utf8")}`);
  }
}

// ---- 1. build ------------------------------------------------------------
function build() {
  if (process.env.AS3_POLYCALL_BUILD_DIR) {
    const dir = process.env.AS3_POLYCALL_BUILD_DIR;
    const main = path.join(dir, "test", "bin", "js-release", "index.js");
    const example = path.join(dir, "example", "bin", "js-release", "index.js");
    if (!fs.existsSync(main) || !fs.existsSync(example)) {
      return { skip: "AS3_POLYCALL_BUILD_DIR has no test/ and example/ bin/js-release/index.js" };
    }
    return { main, example, how: `prebuilt in ${dir}` };
  }
  const exe = process.env.ROYALE_ASNODEC ||
    path.join(root, "node_modules", ".bin", process.platform === "win32" ? "asnodec.cmd" : "asnodec");
  if (!process.env.ROYALE_ASNODEC && !fs.existsSync(exe)) {
    return { skip: "Apache Royale is not installed (npm ci installs @apache-royale/royale-js; it needs Java 8+)" };
  }
  const result = { how: [] };
  for (const [what, source] of [["test", "tests/TestMain.as"], ["example", "examples/Hello.as"]]) {
    const out = path.join(root, "build", what);
    const args = ["-js-dynamic-access-unknown-members=true", "-source-path+=src", `-js-output=${out}`, source];
    const r = spawnSync(exe, args, { cwd: root, encoding: "utf8", windowsHide: true, shell: process.platform === "win32" });
    const text = `${r.stdout || ""}${r.stderr || ""}`;
    const summary = (text.match(/\d+ error\(s\), \d+ warning\(s\)[^\n]*/) || [""])[0];
    if (r.error || r.status !== 0 || / [1-9]\d* error\(s\)/.test(text) || !summary) {
      if (/java|JAVA_HOME/i.test(text) && !/Error:/.test(text)) return { skip: `asnodec could not run (Java?): ${text.slice(-400)}` };
      return { error: `asnodec ${source} failed (exit ${r.status}): ` +
        text.split("\n").filter((l) => /error/i.test(l)).slice(0, 20).join("\n") };
    }
    result[what === "test" ? "main" : "example"] = path.join(out, "bin", "js-release", "index.js");
    result.how.push(`asnodec ${args.join(" ")} (${summary})`);
  }
  result.how = result.how.join("; ");
  return result;
}

// ---- fixtures --------------------------------------------------------------
function fixtures(tmp) {
  const F = path.join(tmp, "fixtures");
  const uni = path.join(F, "ünïcødé-ディレクトリ");
  fs.mkdirSync(uni, { recursive: true });
  const rc = fs.readFileSync(path.join(root, "actionscript-polycallrc"));
  fs.writeFileSync(path.join(F, "as3-polycallrc"), rc);
  fs.writeFileSync(path.join(uni, "as3-polycallrc"), rc);
  // Windows file names cannot contain '"'
  const special = process.platform === "win32" ? "it's a 'quoted' $(name)-polycallrc" : "it's a \"quoted\" $(name)-polycallrc";
  fs.writeFileSync(path.join(F, special), rc);
  fs.writeFileSync(path.join(F, "bad-polycallrc"), "this line has no equals sign\n");
  fs.writeFileSync(path.join(F, "unknown-polycallrc"), "log_level=info\nmystery_key=1\n");
  fs.writeFileSync(path.join(F, "tls-polycallrc"), "tls_enabled=true\ncert_file=/x/c.pem\nkey_file=/x/k.pem\n");
  fs.writeFileSync(path.join(F, "c2a.bin"), Buffer.from([0x43, 0, 0x74, 0x6f, 0x61, 0x73, 0x33, 0, 0xff, 0]));
  return { F, special };
}

// the compiled program requires koffi: resolve it from this repository even
// when the build lives elsewhere (AS3_POLYCALL_BUILD_DIR)
const nodePath = () => [path.join(root, "node_modules"), process.env.NODE_PATH].filter(Boolean).join(path.delimiter);

function runMain(main, env) {
  env = { ...env, NODE_PATH: nodePath() };
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [main], { cwd: root, env, stdio: ["ignore", "pipe", "inherit"], windowsHide: true });
    let rest = "";
    let summary = null;
    let fails = 0;
    const onLine = (line) => {
      if (line.startsWith("PASS  ")) pass(`[as3] ${line.slice(6)}`);
      else if (line.startsWith("FAIL  ")) { fails += 1; fail(`[as3] ${line.slice(6)}`); }
      else {
        if (/^actionscript-polycall: \d+ passed, \d+ failed$/.test(line)) summary = line;
        console.log(`# ${line}`);
      }
    };
    child.stdout.on("data", (c) => {
      rest += c.toString("utf8");
      let i;
      while ((i = rest.indexOf("\n")) >= 0) { onLine(rest.slice(0, i).replace(/\r$/, "")); rest = rest.slice(i + 1); }
    });
    child.on("close", (code) => {
      if (rest) onLine(rest);
      check(summary !== null && code === (fails ? 1 : 0), "the AS3 test ran to completion; exit status matches its checks",
        `exit ${code}, summary ${summary}`);
      resolve();
    });
  });
}

function probe(main, env) {
  const r = spawnSync(process.execPath, [main], { cwd: root, env: { ...env, AS3_TEST_MODE: "loader", NODE_PATH: nodePath() },
    encoding: "utf8", windowsHide: true, timeout: 60000 });
  try {
    return { ...JSON.parse(r.stdout.trim().split("\n").pop()), exit: r.status, signal: r.signal };
  } catch (_) {
    return { ok: false, unparsed: true, exit: r.status, signal: r.signal, stdout: r.stdout, stderr: r.stderr };
  }
}

function loaderTests(main, tmp) {
  const names = process.platform === "win32" ? ["polycall.dll", "libpolycall.dll"] : ["libpolycall.so.1"];
  const base = { ...process.env };
  delete base.POLYCALL_LIBRARY;
  const def = probe(main, base);
  check(def.ok && names.includes(def.path) && def.abi === 1, `default name search loads ${def.path} (${def.version})`, JSON.stringify(def));
  if (process.env.POLYCALL_LIBRARY) {
    const ex = probe(main, process.env);
    check(ex.ok && ex.path === process.env.POLYCALL_LIBRARY, `POLYCALL_LIBRARY=${process.env.POLYCALL_LIBRARY} is used first`, JSON.stringify(ex));
  }
  const ext = process.platform === "win32" ? ".dll" : process.platform === "darwin" ? ".dylib" : ".so";
  const missing = path.join(tmp, `no-such-polycall${ext}`);
  const miss = probe(main, { ...base, POLYCALL_LIBRARY: missing });
  check(!miss.ok && miss.name === "PolycallLoadError" && miss.reason === "not-found" && miss.message.includes(missing) &&
    miss.exit === 0, "missing POLYCALL_LIBRARY -> PolycallLoadError(not-found) naming the path, no crash", JSON.stringify(miss));
  const fakes = {};
  const src = path.join(__dirname, "fixtures", "fake_core.c");
  for (const cc of [process.env.CC, "cc", "gcc", "clang"].filter(Boolean)) {
    let okAll = true;
    for (const [n, defs] of Object.entries({ old: ["-DFAKE_OLD"], abi2: ["-DFAKE_ABI=2"], partial: ["-DFAKE_PARTIAL"] })) {
      const file = path.join(tmp, `fake_${n}${ext}`);
      const r = spawnSync(cc, [...defs, "-shared", ...(process.platform === "win32" ? [] : ["-fPIC"]), "-o", file, src],
        { encoding: "utf8", windowsHide: true });
      if (r.error || r.status !== 0) { okAll = false; break; }
      fakes[n] = file;
    }
    if (okAll) { console.log(`# stand-in libraries built with ${cc}`); break; }
  }
  if (!fakes.partial) {
    skip("old / ABI-2 / partial library cases", "no C compiler (CC, cc, gcc, clang) for tests/fixtures/fake_core.c");
    return;
  }
  const old = probe(main, { ...base, POLYCALL_LIBRARY: fakes.old });
  check(!old.ok && old.reason === "missing-symbol" && old.message.includes("polycall_ffi_abi_version") && old.exit === 0,
    "old 1.0 library -> PolycallLoadError(missing-symbol polycall_ffi_abi_version)", JSON.stringify(old));
  const abi2 = probe(main, { ...base, POLYCALL_LIBRARY: fakes.abi2 });
  check(!abi2.ok && abi2.reason === "abi-mismatch" && /returned 2/.test(abi2.message) && abi2.exit === 0,
    "ABI mismatch (abi_version 2) -> PolycallLoadError(abi-mismatch)", JSON.stringify(abi2));
  const partial = probe(main, { ...base, POLYCALL_LIBRARY: fakes.partial });
  check(!partial.ok && partial.reason === "missing-symbol" && partial.message.includes("polycall_peer_health") && partial.exit === 0,
    "library missing one symbol -> PolycallLoadError(missing-symbol polycall_peer_health), resolved up front", JSON.stringify(partial));
}

async function main() {
  const b = build();
  if (b.skip) { skip("compile the AS3 test (Apache Royale asnodec)", b.skip); return; }
  if (b.error) { fail("compile the AS3 test (Apache Royale asnodec)", b.error); return; }
  pass(`compile the AS3 binding + test: ${b.how}`);
  try {
    require.resolve("koffi", { paths: [root] });
  } catch (_) {
    skip("AS3 tests against the real core", "koffi is not installed (npm ci)");
    return;
  }
  const cli = findCli();
  if (!cli) { skip("AS3 tests against the real core", "the polycall CLI was not found (set POLYCALL_CLI)"); return; }
  const base = process.env.AS3_POLYCALL_TMP || os.tmpdir();
  fs.mkdirSync(base, { recursive: true });
  const tmp = fs.mkdtempSync(path.join(base, "as3-polycall-"));
  const { F, special } = fixtures(tmp);
  const token = `as3-${process.pid}-${Date.now()}`;
  const env = cliEnv({ POLYCALL_DEV_TOKEN: token });
  let daemonStop = null;
  try {
    const runtime = await startCli(cli, ["start", "--endpoint", "127.0.0.1:0"], tmp, cliEnv(), "runtime");
    fs.writeFileSync(path.join(tmp, "Polycallfile"), "log_level=info\n");
    const stateDir = path.join(tmp, "daemon-state");
    const d = spawnSync(cli.path, ["--format", "json", "daemon", "start", "--endpoint", "127.0.0.1:0", "--state-dir", stateDir,
      path.join(tmp, "Polycallfile")], { cwd: tmp, env, encoding: "utf8", windowsHide: true, timeout: 30000 });
    const doc = JSON.parse(d.stdout);
    if (!doc.ok) throw new Error(`polycall daemon start: ${d.stdout} ${d.stderr}`);
    daemonStop = () => spawnSync(cli.path, ["daemon", "stop", "--force", "--state-dir", stateDir, path.join(tmp, "Polycallfile")],
      { cwd: tmp, env, encoding: "utf8", windowsHide: true, timeout: 60000 });
    const cnode = await startCli(cli, ["peer", "serve", "--node-id", "cnode", "--endpoint", "127.0.0.1:0"], tmp, env, "cnode");
    console.log(`# CLI ${cli.path} (${cli.version}); runtime ${runtime}, daemon ${doc.data.endpoint}, C node ${cnode}`);
    await runMain(b.main, {
      ...process.env, POLYCALL_TELEMETRY: "off", POLYCALL_DEV_TOKEN: token, POLYCALL_CLI: cli.path,
      QA_RUNTIME: runtime, QA_DAEMON: doc.data.endpoint, QA_CNODE: cnode, QA_FIXTURES: F, QA_SPECIAL: special,
      QA_TOKEN: token, QA_TAG: `${process.pid}-${Date.now()}`
    });
    loaderTests(b.main, tmp);
    const ex = spawnSync(process.execPath, [b.example], { cwd: root, env: { ...env, NODE_PATH: nodePath() },
      encoding: "utf8", windowsHide: true, timeout: 60000 });
    check(ex.status === 0 && /valid for running/.test(ex.stdout) &&
      /as3-outbox sent 'hello from ActionScript' as m-1/.test(ex.stdout),
    "examples/Hello.as (compiled by asnodec) validates actionscript-polycallrc and exchanges a message", ex.stdout + ex.stderr);
  } finally {
    if (daemonStop) {
      const r = daemonStop();
      check(r.status === 0, "polycall daemon stop", `${r.status} ${r.stdout} ${r.stderr}`);
    }
    for (const c of children) if (c.exitCode === null) c.kill();
  }
}

main().catch((e) => fail("actionscript-polycall tests", e.stack || e.message)).finally(() => {
  // informational, not counted: this harness tests the Node.js (Royale) target only
  console.log("# not tested here: an Adobe/HARMAN AIR or Flash Player runtime (proprietary; its licence terms must be " +
    "accepted) and an AIR Native Extension, the AIR route to C -- see README");
  console.log(`--- actionscript-polycall: ${counts.pass} passed, ${counts.fail} failed, ${counts.skip} skipped ---`);
  process.exitCode = counts.fail ? 1 : counts.blocked ? 77 : 0;
});
