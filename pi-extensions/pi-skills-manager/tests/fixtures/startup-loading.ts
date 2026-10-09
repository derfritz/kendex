import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { mock } from "bun:test";
import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";

const agentDir = process.env.PI_CODING_AGENT_DIR;
assert(agentDir);
mkdirSync(agentDir, { recursive: true });
const loaded: string[] = [];
const mode = process.argv[2];
const settings = {
  kendex: { extensionManager: { config: { "@vanillagreen/pi-skills-manager": {
    enabled: mode !== "disabled",
    hideStartupSkillsBlock: !["visible", "registry-error", "dialog-error"].includes(mode),
  } } } },
};
writeFileSync(join(agentDir, "settings.json"), JSON.stringify(settings));

let startupSkillsRendered = -1;
class MockInteractiveMode {
  session?: { resourceLoader?: { getSkills?: () => { skills: unknown[] } } };

  showLoadedResources() {
    startupSkillsRendered = this.session?.resourceLoader?.getSkills?.().skills.length ?? -1;
  }
}
mock.module("@earendil-works/pi-coding-agent", () => {
  loaded.push("host-sdk");
  return { getAgentDir: () => agentDir, InteractiveMode: MockInteractiveMode };
});
mock.module("../../extensions/skills-manager/creation.js", () => {
  loaded.push("creation");
  return { createSkillFromAnswers: async () => undefined };
});
mock.module("../../extensions/skills-manager/dialog.js", () => {
  loaded.push("dialog");
  return { showSkillsManager: async () => {
    if (mode === "dialog-error") throw new Error("dialog failed");
    return { name: "sample" };
  } };
});
mock.module("../../extensions/skills-manager/registry.js", () => {
  loaded.push("registry");
  return {
    loadSkillRegistry: async () => {
      if (mode === "registry-error") throw new Error("registry failed");
      return { skills: [] };
    },
    deleteSkill: async () => undefined,
  };
});
mock.module("../../extensions/skills-manager/toggle.js", () => {
  loaded.push("toggle");
  return { setSkillEnabled: async () => undefined };
});

const { default: skillsManager } = await import("../../extensions/skills-manager.ts");
const { clearPackageConfigCache } = await import("../../extensions/skills-manager/package-config.ts");
const commands = new Map<string, { handler: (args: string, ctx: ExtensionCommandContext) => Promise<void> }>();
const sessionHandlers: Array<(event: unknown, ctx: ExtensionContext) => unknown> = [];
const pi = {
  registerCommand(name: string, command: { handler: (args: string, ctx: ExtensionCommandContext) => Promise<void> }) {
    commands.set(name, command);
  },
  on(name: string, handler: (event: unknown, ctx: ExtensionContext) => unknown) {
    if (name === "session_start") sessionHandlers.push(handler);
  },
  events: { on: () => () => {} },
};
await skillsManager(pi as unknown as ExtensionAPI);
const needsStartupPatch = mode === "resources" || mode === "reload-visible";
assert.deepEqual(loaded, needsStartupPatch ? ["host-sdk"] : []);
const handler = commands.get("skill")?.handler;
assert(handler);

if (mode === "disabled") {
  assert(commands.has("skill:enable"));
} else {
  // Non-UI calls and command arguments must not load a menu the user cannot open.
  const inserted: string[] = [];
  const notifications: string[] = [];
  const ctx = {
    cwd: process.cwd(),
    hasUI: false,
    ui: {
      notify: (message: string) => notifications.push(message),
      pasteToEditor: (text: string) => inserted.push(text),
    },
  } as unknown as ExtensionCommandContext;
  await handler("", ctx);
  await handler("invalid-argument", { ...ctx, hasUI: true });
  assert.deepEqual(loaded, needsStartupPatch ? ["host-sdk"] : []);
  notifications.length = 0;

  if (mode === "registry-error") {
    // Registry failures retain their actionable message instead of looking like import failures.
    await handler("", { ...ctx, hasUI: true });
    assert.deepEqual(notifications, ["Failed to load skills list: registry failed"]);
  } else if (mode === "dialog-error") {
    // The dialog owns its failures; the lazy import boundary must not relabel or swallow them.
    await assert.rejects(handler("", { ...ctx, hasUI: true }), /dialog failed/);
    assert.deepEqual(notifications, []);
  } else {
    // The first interactive command still opens the manager; later commands reuse the modules.
    await handler("", { ...ctx, hasUI: true });
    assert.deepEqual(new Set(loaded.filter((name) => name !== "host-sdk")), new Set(["creation", "dialog", "registry", "toggle"]));
    assert.deepEqual(inserted, ["/skill:sample\n"]);
    const count = loaded.length;
    await handler("", { ...ctx, hasUI: true });
    assert.equal(loaded.length, count);
  }


  if (mode === "reload-visible") {
    const interactiveMode = new MockInteractiveMode();
    interactiveMode.session = { resourceLoader: { getSkills: () => ({ skills: ["sample"] }) } };
    interactiveMode.showLoadedResources();
    assert.equal(startupSkillsRendered, 0);

    // Pi keeps its patched prototype and global flags, but reloads the entrypoint.
    // Turning hiding off must therefore clear the previous extension instance's flag.
    settings.kendex.extensionManager.config["@vanillagreen/pi-skills-manager"].hideStartupSkillsBlock = false;
    writeFileSync(join(agentDir, "settings.json"), JSON.stringify(settings));
    clearPackageConfigCache();
    const { default: reloadedSkillsManager } = await import("../../extensions/skills-manager.ts?reload-visible");
    const reloadedPi = {
      registerCommand: pi.registerCommand,
      on: pi.on,
      events: pi.events,
    };
    await reloadedSkillsManager(reloadedPi as unknown as ExtensionAPI);

    interactiveMode.showLoadedResources();
    assert.equal(startupSkillsRendered, 1);
  }
}
