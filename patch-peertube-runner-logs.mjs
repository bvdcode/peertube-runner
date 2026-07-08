import { readFileSync, writeFileSync } from "node:fs";

const targetPath = process.argv[2];

if (!targetPath) {
    throw new Error("Usage: patch-peertube-runner-logs.mjs <peertube-runner.mjs>");
}

const originalLogger = 'const logger = (0, import_pino.pino)({ level: "info" }, (0, import_pino_pretty.default)());';
const patchedLogger = 'const logger = (0, import_pino.pino)({ level: "info" }, (0, import_pino_pretty.default)({ hideObject: !process.argv.includes("--verbose") }));';
const source = readFileSync(targetPath, "utf8");

if (source.includes(patchedLogger)) {
    process.exit(0);
}

if (!source.includes(originalLogger)) {
    throw new Error("Unsupported PeerTube Runner logger layout");
}

writeFileSync(targetPath, source.replace(originalLogger, patchedLogger));
