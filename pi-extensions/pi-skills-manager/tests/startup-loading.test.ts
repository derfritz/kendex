import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "bun:test";

const fixture = fileURLToPath(new URL("./fixtures/startup-loading.ts", import.meta.url));
for (const mode of ["resources", "visible", "disabled", "reload-visible", "registry-error", "dialog-error"]) {
  test(`startup loads only the modules needed by ${mode} sessions`, () => {
    const root = mkdtempSync(join(tmpdir(), "skills-startup-"));
    try {
      // Isolate module mocks and settings so other suites cannot hide an eager import.
      const result = spawnSync(process.execPath, ["--no-install", fixture, mode], {
        cwd: root,
        env: { PATH: process.env.PATH ?? "", HOME: root, PI_CODING_AGENT_DIR: join(root, "agent") },
        encoding: "utf8",
        timeout: 10_000,
      });
      assert.equal(result.status, 0, result.stderr);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
}
