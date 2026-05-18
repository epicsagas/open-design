import type { WizardContext } from '../wizard.js';

export async function runMedia(ctx: WizardContext): Promise<void> {
  const configure = await ctx.prompter.confirm('Configure media providers (image/video generation)?', false);
  if (!configure) return;

  ctx.prompter.info('Media providers can be configured later in Settings → Media Providers.');
  ctx.prompter.info('Run: od config set mediaProviders.<id>.apiKey <key>');
}
