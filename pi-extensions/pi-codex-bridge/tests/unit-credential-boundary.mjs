import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

const scratchRoot = join(process.cwd(), "tmp");
mkdirSync(scratchRoot, { recursive: true });

function scan(paths, credentialBytes) {
	return paths.filter((path) => readFileSync(path, "utf8").includes(credentialBytes));
}

test("settings scan detects a planted credential write", () => {
	const root = mkdtempSync(join(scratchRoot, "credential-boundary-"));
	const codexHome = join(root, "codex");
	const piHome = join(root, "pi");
	mkdirSync(codexHome);
	mkdirSync(piHome);
	const authPath = join(codexHome, "auth.json");
	const settingsPath = join(piHome, "settings.json");
	const modelsPath = join(piHome, "models.json");
	const credentialBytes = "fixture-refresh-token";
	writeFileSync(authPath, credentialBytes);
	writeFileSync(settingsPath, "{}\n");
	writeFileSync(modelsPath, "{}\n");

	const beforeAuth = statSync(authPath, { bigint: true });
	assert.deepEqual(scan([settingsPath, modelsPath], credentialBytes), []);
	const afterAuth = statSync(authPath, { bigint: true });
	assert.equal(afterAuth.size, beforeAuth.size);
	assert.equal(afterAuth.mtimeNs, beforeAuth.mtimeNs);

	writeFileSync(settingsPath, JSON.stringify({ token: credentialBytes }));
	assert.deepEqual(scan([settingsPath, modelsPath], credentialBytes), [settingsPath]);
});
