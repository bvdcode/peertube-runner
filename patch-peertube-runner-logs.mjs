import { readFileSync, writeFileSync } from "node:fs";

const targetPath = process.argv[2];

if (!targetPath) {
    throw new Error("Usage: patch-peertube-runner-logs.mjs <peertube-runner.mjs>");
}

const originalLogger = 'const logger = (0, import_pino.pino)({ level: "info" }, (0, import_pino_pretty.default)());';
const patchedLogger = `const logger = (0, import_pino.pino)({ level: "info" }, (0, import_pino_pretty.default)({ hideObject: !process.argv.includes("--verbose") }));
function getRunnerProcessOutputLines(value) {
\tif (typeof value !== "string") return [];
\tconst lines = value.split(/\\r?\\n/).map((line) => line.trim()).filter((line) => line.length > 0);
\treturn lines.slice(-40);
}
function logRunnerProcessError(err) {
\tif (!err || typeof err !== "object") return;
\tif (typeof err.message === "string" && err.message.length > 0) logger.error(\`Job error: \${err.message}\`);
\tfor (const line of getRunnerProcessOutputLines(err.stderr)) logger.error(\`Job stderr: \${line}\`);
\tfor (const line of getRunnerProcessOutputLines(err.stdout)) logger.error(\`Job stdout: \${line}\`);
}`;
const originalProcessJobError = `processJob({
\t\t\tserver,
\t\t\tjob,
\t\t\trunnerToken: server.runnerToken
\t\t}).catch((err) => {
\t\t\tlogger.error({ err }, "Cannot process job");`;
const patchedProcessJobError = `processJob({
\t\t\tserver,
\t\t\tjob,
\t\t\trunnerToken: server.runnerToken
\t\t}).catch((err) => {
\t\t\tlogRunnerProcessError(err);
\t\t\tlogger.error({ err }, "Cannot process job");`;
const source = readFileSync(targetPath, "utf8");

if (source.includes(patchedLogger) && source.includes(patchedProcessJobError)) {
    process.exit(0);
}

let patchedSource = source;

if (!patchedSource.includes(patchedLogger)) {
    if (!patchedSource.includes(originalLogger)) {
        throw new Error("Unsupported PeerTube Runner logger layout");
    }

    patchedSource = patchedSource.replace(originalLogger, patchedLogger);
}

if (!patchedSource.includes(patchedProcessJobError)) {
    if (!patchedSource.includes(originalProcessJobError)) {
        throw new Error("Unsupported PeerTube Runner process job error layout");
    }

    patchedSource = patchedSource.replace(originalProcessJobError, patchedProcessJobError);
}

if (patchedSource === source) {
    throw new Error("Unsupported PeerTube Runner logger layout");
}

writeFileSync(targetPath, patchedSource);
