/**
 * kendex Pi Skills Manager.
 *
 * A polished /skill manager view for browsing, previewing, inserting, creating,
 * editing, renaming, deleting, and enabling/disabling Pi skills.
 */

import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { INSTALL_SYMBOL, STARTUP_HIDE_ENABLED_SYMBOL } from "./skills-manager/constants.js";
import { installSettingsCacheRefresh, recordProjectTrust } from "./skills-manager/package-config.js";
import { settingBoolean, updatePackageConfig } from "./skills-manager/settings.js";
import type { SkillEntry } from "./skills-manager/types.js";

function errorMessage(error: unknown): string {
	const message = error instanceof Error ? error.message : String(error);
	return message.length > 180 ? `${message.slice(0, 179)}…` : message;
}

function insertNativeSkillCommand(ctx: ExtensionContext, skill: SkillEntry): void {
	ctx.ui.pasteToEditor(`/skill:${skill.name}\n`);
}

type StartupModule = typeof import("./skills-manager/startup.js");
let startupModule: StartupModule | undefined;

function setStartupHideEnabled(enabled: boolean): void {
	(globalThis as unknown as Record<PropertyKey, unknown>)[STARTUP_HIDE_ENABLED_SYMBOL] = enabled;
}

async function configureStartupSkillsBlock(cwd = process.cwd()): Promise<void> {
	const hideSkills = settingBoolean("enabled", true, cwd) && settingBoolean("hideStartupSkillsBlock", true, cwd);
	setStartupHideEnabled(hideSkills);
	if (!hideSkills) return;
	startupModule ??= await import("./skills-manager/startup.js");
	startupModule.patchInteractiveModeStartupSkillsBlock();
}

export default async function skillsManager(pi: ExtensionAPI): Promise<void> {
	const guard = pi as unknown as Record<PropertyKey, unknown>;
	if (guard[INSTALL_SYMBOL]) return;
	guard[INSTALL_SYMBOL] = true;

	await configureStartupSkillsBlock();

	const enabledAtLoad = settingBoolean("enabled", true);

	if (!enabledAtLoad) {
		const enableRecovery = async (ctx: ExtensionCommandContext) => {
			updatePackageConfig(ctx.cwd, { enabled: true });
			ctx.ui.notify("Skills Manager enabled. Reloading...", "info");
			await ctx.reload();
		};
		pi.registerCommand("skill", {
			description: "Skills manager recovery command.",
			handler: async (args, ctx) => {
				if (args.trim().toLowerCase() !== "enable") {
					ctx.ui.notify("Skills Manager is disabled. Run /skill:enable, then /reload.", "warning");
					return;
				}
				await enableRecovery(ctx);
			},
		});
		pi.registerCommand("skill:enable", {
			description: "Re-enable the skills manager",
			handler: async (_args, ctx) => enableRecovery(ctx),
		});
		return;
	}

	// The inventory is loaded when /skill opens the manager and dropped when it
	// closes, so a session that never opens it, headless or not, holds none.
	async function prepareSession(ctx: ExtensionContext): Promise<void> {
		recordProjectTrust(ctx);
		await configureStartupSkillsBlock(ctx.cwd);
	}

	pi.registerCommand("skill", {
		description: "Pi skills manager view. Native skills remain /skill:name.",
		handler: async (args, ctx) => {
			const rawArgs = args.trim();
			const trimmed = rawArgs.toLowerCase();
			if (trimmed === "enable") {
				updatePackageConfig(ctx.cwd, { enabled: true });
				ctx.ui.notify("Skills Manager already enabled.", "info");
				return;
			}
			if (trimmed === "disable") {
				updatePackageConfig(ctx.cwd, { enabled: false });
				ctx.ui.notify("Skills Manager disabled. Run /reload to unload commands/hooks.", "info");
				return;
			}
			if (rawArgs) {
				ctx.ui.notify("Use /skill:name for native skill invocation, or /skill with no arguments for the manager.", "warning");
				return;
			}
			if (!ctx.hasUI) {
				ctx.ui.notify("/skill manager requires interactive mode", "warning");
				return;
			}
			let modules;
			try {
				modules = await Promise.all([
					import("./skills-manager/creation.js"),
					import("./skills-manager/dialog.js"),
					import("./skills-manager/registry.js"),
					import("./skills-manager/toggle.js"),
				]);
			} catch (error) {
				ctx.ui.notify(`Failed to load skills manager: ${errorMessage(error)}`, "error");
				return;
			}
			const [{ createSkillFromAnswers }, { showSkillsManager }, { deleteSkill, loadSkillRegistry }, { setSkillEnabled }] = modules;
			let registry;
			try {
				registry = await loadSkillRegistry(ctx.cwd);
			} catch (error) {
				ctx.ui.notify(`Failed to load skills list: ${errorMessage(error)}`, "error");
				return;
			}
			const selection = await showSkillsManager(ctx, registry, {
				onCreate: async (answers, signal) => await createSkillFromAnswers(ctx, answers, { thinkingLevel: pi.getThinkingLevel(), signal }),
				onDelete: async (skill) => await deleteSkill(ctx, skill),
				onToggle: async (skill, enabled) => await setSkillEnabled(ctx.cwd, skill, enabled),
				onRefresh: async () => await loadSkillRegistry(ctx.cwd),
			});
			if (selection) insertNativeSkillCommand(ctx, selection);
		},
	});

	installSettingsCacheRefresh(pi);
	pi.on("session_start", async (_event, ctx) => { await prepareSession(ctx); });
}
