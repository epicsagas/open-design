import type { WizardContext } from '../wizard.js';

export async function runNetwork(ctx: WizardContext): Promise<void> {
  const host = await ctx.prompter.select<string>('Bind host:', [
    { value: '127.0.0.1', label: '127.0.0.1 (localhost only)', hint: 'Recommended' },
    { value: '0.0.0.0', label: '0.0.0.0 (all interfaces)', hint: 'For LAN access' },
  ], '127.0.0.1');

  const portStr = await ctx.prompter.text('Port:', '7456');
  const port = parseInt(portStr, 10);
  if (isNaN(port) || port < 1 || port > 65535) {
    ctx.prompter.warn('Invalid port, using default 7456.');
    return;
  }

  const { writeAppConfig } = await import('../../app-config.js');
  await writeAppConfig(ctx.dataDir, { bindHost: host, port });
  ctx.prompter.success(`Network: ${host}:${port}`);
}
