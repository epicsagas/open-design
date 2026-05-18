import type { WizardContext } from '../wizard.js';
import { findAvailablePort } from '../port-scan.js';

export async function runNetwork(ctx: WizardContext): Promise<number> {
  const defaultPort = await ctx.prompter.spinner('Scanning for available port...', () =>
    findAvailablePort(),
  );

  if (defaultPort !== 7456) {
    ctx.prompter.info(`Port 7456 is in use — found available port ${defaultPort}.`);
  }

  const host = await ctx.prompter.select<string>('Bind host:', [
    { value: '127.0.0.1', label: '127.0.0.1 (localhost only)', hint: 'Recommended' },
    { value: '0.0.0.0', label: '0.0.0.0 (all interfaces)', hint: 'For LAN access' },
  ], '127.0.0.1');

  const portStr = await ctx.prompter.text('Port:', String(defaultPort));
  const port = parseInt(portStr, 10);
  if (isNaN(port) || port < 1 || port > 65535) {
    ctx.prompter.warn(`Invalid port, using ${defaultPort}.`);
    await saveNetwork(ctx, host, defaultPort);
    return defaultPort;
  }

  await saveNetwork(ctx, host, port);
  ctx.prompter.success(`Network: ${host}:${port}`);
  return port;
}

async function saveNetwork(ctx: WizardContext, bindHost: string, port: number): Promise<void> {
  const { writeAppConfig } = await import('../../app-config.js');
  await writeAppConfig(ctx.dataDir, { bindHost, port });
}
