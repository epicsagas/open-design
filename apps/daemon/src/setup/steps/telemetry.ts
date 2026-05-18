import type { WizardContext } from '../wizard.js';

export async function runTelemetry(ctx: WizardContext): Promise<void> {
  const metrics = await ctx.prompter.confirm('Allow anonymous usage metrics?', false);
  const content = await ctx.prompter.confirm('Allow content analysis for improvement?', false);

  const { writeAppConfig } = await import('../../app-config.js');
  await writeAppConfig(ctx.dataDir, {
    telemetry: {
      metrics,
      content,
      artifactManifest: false,
    },
    privacyDecisionAt: Date.now(),
  });

  ctx.prompter.success('Privacy preferences saved.');
}
