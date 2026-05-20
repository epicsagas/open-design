import type { WizardContext } from '../wizard.js';
import { writeAppConfig } from '../../app-config.js';

export async function runFinalize(ctx: WizardContext): Promise<void> {
  ctx.prompter.info('Finalizing setup...');

  // Save onboarding completed + primary agent
  const primaryAgent = ctx.selectedAgents[0] ?? null;
  await writeAppConfig(ctx.dataDir, {
    onboardingCompleted: true,
    agentId: primaryAgent,
  });

  ctx.prompter.success('Configuration saved.');

  // Try to start the daemon and health-check
  const shouldStart = await ctx.prompter.select<string>('Ready to launch:', [
    { value: 'browser', label: 'Open in Browser', hint: 'Start daemon + open browser' },
    { value: 'later', label: 'Later', hint: 'Start manually with `od`' },
  ], 'browser');

  if (shouldStart === 'browser') {
    await startAndOpen(ctx);
  } else {
    printSummary(ctx, null);
  }
}

async function startAndOpen(ctx: WizardContext): Promise<void> {
  try {
    const { startServer } = await import('../../server.js');
    const { openBrowser } = await import('../../browser-open.js');
    const { readAppConfig } = await import('../../app-config.js');

    const savedConfig = await readAppConfig(ctx.dataDir);
    const port = ctx.resolvedPort
      ?? (typeof ctx.flags['port'] === 'string' ? parseInt(ctx.flags['port'], 10) : undefined)
      ?? savedConfig.port
      ?? 7456;
    ctx.resolvedPort = port;
    const host = typeof ctx.flags['bind'] === 'string'
      ? ctx.flags['bind']
      : (savedConfig.bindHost ?? '127.0.0.1');

    const url = await startServer({ port, host, returnServer: false }) as unknown as string;

    // Health check
    const resp = await fetch(`${url}/api/health`);
    if (!resp.ok) throw new Error(`Health check failed: ${resp.status}`);

    ctx.prompter.success(`Daemon is healthy (${resp.status} OK)`);

    printSummary(ctx, url);

    openBrowser(url);
    // Let the browser open, then exit
    setTimeout(() => process.exit(0), 1000);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    ctx.prompter.warn(`Could not start daemon: ${msg}`);
    printSummary(ctx, null);
    process.exit(0);
  }
}

function printSummary(ctx: WizardContext, url: string | null): void {
  const primaryAgent = ctx.selectedAgents[0] ?? 'none';
  ctx.prompter.note(
    'Setup Complete',
    [
      `  Agent:      ${primaryAgent}`,
      `  Port:       ${ctx.resolvedPort ?? (typeof ctx.flags['port'] === 'string' ? ctx.flags['port'] : '7456')}`,
      `  Data:       ${ctx.dataDir}`,
      '',
      url ? `  → ${url}` : '  Start with: od',
      '',
      '  Next steps:',
      '    od              — start daemon + browser',
      '    od status       — check daemon health',
      '    od config list  — view all settings',
    ].join('\n'),
  );
}
