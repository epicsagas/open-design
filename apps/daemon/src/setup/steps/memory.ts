import type { WizardContext } from '../wizard.js';

export async function runMemory(ctx: WizardContext): Promise<void> {
  const configure = await ctx.prompter.confirm('Configure memory/knowledge graph backend?', false);
  if (!configure) return;

  ctx.prompter.info('Memory providers can be configured later in Settings → Memory.');
  ctx.prompter.info('Run: od config set memory.provider <type>');
}
