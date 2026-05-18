import type { WizardContext } from '../wizard.js';
import { detectAgents } from '../../runtimes/detection.js';
import { AGENT_DEFS } from '../../runtimes/registry.js';

export async function runEnvDetect(ctx: WizardContext): Promise<void> {
  const results = await ctx.prompter.spinner('Detecting environment...', async () => {
    return detectAgents(ctx.flags['agent-cli-env'] as Record<string, Record<string, string>> ?? {});
  });

  const lines: string[] = [
    '── Environment ────────────────────────────',
    `  OS:          ${process.platform} ${process.arch}`,
    `  Node.js:     ${process.version}`,
  ];

  for (const agent of results) {
    const status = agent.available
      ? `✓ ${agent.version ?? 'detected'}`
      : '✗ not found';
    lines.push(`  ${agent.name.padEnd(20)} ${status}`);
  }
  lines.push('───────────────────────────────────────────');

  ctx.prompter.note('Environment', lines.join('\n'));

  // Store detection results on context for other steps
  (ctx as unknown as Record<string, unknown>)._agentResults = results;
}
