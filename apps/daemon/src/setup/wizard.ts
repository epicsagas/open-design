import type { SetupPrompter } from './prompts.js';
import { printBanner } from './banner.js';
import { runEnvDetect } from './steps/env-detect.js';
import { runAgentSelect } from './steps/agent-select.js';
import { runApiKey } from './steps/api-key.js';
import { runPluginInstall } from './steps/plugin-install.js';
import { runTelemetry } from './steps/telemetry.js';
import { runFinalize } from './steps/finalize.js';
import { runNetwork } from './steps/network.js';
import { runMedia } from './steps/media.js';
import { runMcp } from './steps/mcp.js';
import { runMemory } from './steps/memory.js';
import { runDesignSystem } from './steps/design-system.js';

export interface WizardContext {
  prompter: SetupPrompter;
  dataDir: string;
  projectRoot: string;
  selectedAgents: string[];
  flags: Record<string, unknown>;
}

export type WizardMode = 'quick' | 'advanced';

export async function runWizard(ctx: WizardContext, mode?: WizardMode): Promise<void> {
  printBanner(ctx.prompter);

  const chosenMode = mode ?? await ctx.prompter.select<WizardMode>(
    'Choose setup mode:',
    [
      { value: 'quick', label: 'Quick', hint: '5 steps — get started fast' },
      { value: 'advanced', label: 'Advanced', hint: '17 steps — full control' },
    ],
    'quick',
  );

  ctx.prompter.info(`Mode: ${chosenMode === 'quick' ? 'Quick (5 steps)' : 'Advanced (17 steps)'}`);

  // Step 1: Environment detection
  await runEnvDetect(ctx);

  // Step 2: Agent selection
  ctx.selectedAgents = await runAgentSelect(ctx);
  if (ctx.selectedAgents.length === 0) {
    ctx.prompter.warn('No agents selected. You can configure BYOK API mode later in Settings.');
  }

  // Step 3: API Key (conditional per selected agent)
  await runApiKey(ctx);

  // Step 4: Plugin install (for selected agents that support MCP)
  await runPluginInstall(ctx);

  if (chosenMode === 'advanced') {
    // Step 5: Design System + Skills
    await runDesignSystem(ctx);

    // Step 6: Network
    await runNetwork(ctx);

    // Step 7: Media Providers
    await runMedia(ctx);

    // Step 8: External MCP Client
    await runMcp(ctx);

    // Step 9: Memory / Custom Instructions
    await runMemory(ctx);

    // Steps 10-16: remaining advanced settings are deferred to Settings UI
    // (Connectors, Orbit, Language, Appearance, Desktop, Notifications, Integrations)
    ctx.prompter.info('Additional settings (Connectors, Orbit, Language, Appearance, Notifications) are available in Settings →');
  }

  // Step 5 (Quick) / Step 17 (Advanced): Telemetry
  await runTelemetry(ctx);

  // Finalization
  await runFinalize(ctx);
}
