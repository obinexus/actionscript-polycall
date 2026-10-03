"use strict";

// Compile AS3 with Apache Royale for Node.js -- what the `asnodec` launcher
// does, invoked directly with Java so it also works on Windows (the npm
// launcher spawns asnodec.bat without a shell, which current Node.js refuses
// with EINVAL).
//
//   node scripts/build.js            -> build/example and build/test
//   node scripts/build.js MAIN.as OUT
//
// Royale comes from the @apache-royale/royale-js dev dependency (or
// ROYALE_HOME = its royale-asjs directory); Java from JAVA_HOME or PATH.
// Exit 0 built, 1 a compile error, 77 Royale or Java missing.

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..");

function royaleHome() {
  if (process.env.ROYALE_HOME) return process.env.ROYALE_HOME;
  try {
    return path.join(path.dirname(require.resolve("@apache-royale/royale-js/package.json", { paths: [root] })), "royale-asjs");
  } catch (_) {
    return null;
  }
}

function java() {
  return process.env.JAVA_HOME ? path.join(process.env.JAVA_HOME, "bin", "java") : "java";
}

// returns {ok, summary, text} or {missing: reason}
function compile(mainFile, outDir) {
  const home = royaleHome();
  if (!home || !fs.existsSync(path.join(home, "js", "lib", "mxmlc.jar"))) {
    return { missing: "Apache Royale is not installed (npm ci installs @apache-royale/royale-js, or set ROYALE_HOME)" };
  }
  const probe = spawnSync(java(), ["-version"], { encoding: "utf8", windowsHide: true });
  if (probe.error) return { missing: `Java is not available (${java()}): ${probe.error.message}` };
  const args = ["-Dsun.io.useCanonCaches=false", "-Xms32m", "-Xmx1024m", `-Droyalecompiler=${home}`,
    `-Droyalelib=${path.join(home, "frameworks")}`, "-jar", path.join(home, "js", "lib", "mxmlc.jar"),
    "-js-output-type=node", "+configname=node",
    "-js-dynamic-access-unknown-members=true", `-source-path+=${path.join(root, "src")}`, `-js-output=${outDir}`, mainFile];
  const r = spawnSync(java(), args, { cwd: root, encoding: "utf8", windowsHide: true, maxBuffer: 64 * 1024 * 1024 });
  const text = `${r.stdout || ""}${r.stderr || ""}`;
  const summary = (text.match(/\d+ error\(s\), \d+ warning\(s\)[^\n]*/) || [""])[0];
  const javaVersion = (probe.stderr || probe.stdout || "").split("\n")[0].trim();
  const ok = !r.error && r.status === 0 && /^0 error\(s\)/.test(summary) &&
    fs.existsSync(path.join(outDir, "bin", "js-release", "index.js"));
  return { ok, summary, text, command: `java -jar royale-asjs/js/lib/mxmlc.jar -js-output-type=node ${path.relative(root, mainFile)}`,
    javaVersion, status: r.status };
}

module.exports = { compile, royaleHome };

if (require.main === module) {
  const jobs = process.argv.length > 3
    ? [[path.resolve(process.argv[2]), path.resolve(process.argv[3])]]
    : [[path.join(root, "examples", "Hello.as"), path.join(root, "build", "example")],
      [path.join(root, "tests", "TestMain.as"), path.join(root, "build", "test")]];
  for (const [main, out] of jobs) {
    const r = compile(main, out);
    if (r.missing) { console.error(`SKIP  ${r.missing}`); process.exit(77); }
    console.log(`${r.ok ? "built" : "FAILED"}: ${path.relative(root, main)} -> ${path.relative(root, out)} (${r.summary}; ${r.javaVersion})`);
    if (!r.ok) {
      console.error(r.text.split("\n").filter((l) => /error/i.test(l) && !/LoggerErrorManager/.test(l)).slice(0, 40).join("\n"));
      process.exit(1);
    }
  }
}
