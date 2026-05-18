import type { WizardContext } from '../wizard.js';

export async function runMcp(ctx: WizardContext): Promise<void> {
  const configure = await ctx.prompter.confirm('Configure external MCP servers?', false);
  if (!configure) return;

  ctx.prompter.info('MCP servers can be added later in Settings → External MCP Client.');
  ctx.prompter.info('Or via CLI: od mcp add <name> -- <command>');
}
