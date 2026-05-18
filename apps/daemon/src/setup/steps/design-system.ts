import type { WizardContext } from '../wizard.js';

export async function runDesignSystem(ctx: WizardContext): Promise<void> {
  const configure = await ctx.prompter.confirm('Configure default design system?', false);
  if (!configure) return;

  ctx.prompter.info('Design systems can be configured later in Settings → Design Systems.');
  ctx.prompter.info('Run: od config set designSystem.default <id>');
}
