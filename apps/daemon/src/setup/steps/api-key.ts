import type { WizardContext } from '../wizard.js';

const AGENT_KEY_ENV: Record<string, { env: string; label: string }[]> = {
  codex: [{ env: 'OPENAI_API_KEY', label: 'OpenAI API Key' }],
  deepseek: [{ env: 'DEEPSEEK_API_KEY', label: 'DeepSeek API Key' }],
  gemini: [{ env: 'GEMINI_API_KEY', label: 'Gemini API Key' }],
  qwen: [{ env: 'DASHSCOPE_API_KEY', label: 'DashScope API Key' }],
  qoder: [{ env: 'OPENAI_API_KEY', label: 'OpenAI API Key' }],
  opencode: [{ env: 'OPENAI_API_KEY', label: 'OpenAI API Key' }],
};

export async function runApiKey(ctx: WizardContext): Promise<void> {
  if (ctx.selectedAgents.length === 0) return;

  const agentCliEnv: Record<string, Record<string, string>> = {};

  for (const agentId of ctx.selectedAgents) {
    const keys = AGENT_KEY_ENV[agentId];
    if (!keys) continue;

    for (const { env, label } of keys) {
      const existing = process.env[env];
      if (existing) {
        ctx.prompter.info(`${label} already set in environment for ${agentId}`);
        continue;
      }

      const value = await ctx.prompter.password(`${label} for ${agentId} (leave empty to skip):`);
      if (value) {
        agentCliEnv[agentId] ??= {};
        agentCliEnv[agentId][env] = value;
      }
    }
  }

  if (Object.keys(agentCliEnv).length > 0) {
    const { writeAppConfig } = await import('../../app-config.js');
    await writeAppConfig(ctx.dataDir, { agentCliEnv });
    ctx.prompter.success('API keys saved.');
  }
}
