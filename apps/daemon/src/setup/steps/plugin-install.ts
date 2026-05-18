import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import type { WizardContext } from '../wizard.js';

const execFileAsync = promisify(execFile);

export async function runPluginInstall(ctx: WizardContext): Promise<void> {
  if (ctx.selectedAgents.length === 0) return;

  for (const agentId of ctx.selectedAgents) {
    if (agentId === 'claude') {
      await installClaudeCodeMcp(ctx);
    }
    // Other agents' MCP integration can be added here later
  }
}

async function installClaudeCodeMcp(ctx: WizardContext): Promise<void> {
  const install = await ctx.prompter.confirm(
    'Install Open Design MCP server for Claude Code? (adds get_artifact, get_file, list_files, search_files)',
    true,
  );

  if (!install) {
    ctx.prompter.info('Skipped Claude Code MCP installation.');
    return;
  }

  try {
    // Find od binary path
    const odPath = process.argv[1] ?? 'od';

    await ctx.prompter.spinner('Registering MCP server with Claude Code...', async () => {
      await execFileAsync('claude', [
        'mcp', 'add',
        '--scope', 'user',
        'open-design',
        '--', odPath, 'mcp',
      ], { timeout: 15000 });
    });

    ctx.prompter.success('Claude Code MCP server registered (open-design).');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    ctx.prompter.warn(`Could not register MCP server: ${msg}`);
    ctx.prompter.info('You can register manually: claude mcp add --scope user open-design -- od mcp');
  }
}
