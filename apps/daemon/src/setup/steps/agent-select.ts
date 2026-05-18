import type { WizardContext } from '../wizard.js';
import { AGENT_DEFS } from '../../runtimes/registry.js';
import type { DetectedAgent } from '../../runtimes/types.js';
import type { SelectOption } from '../prompts.js';

export async function runAgentSelect(ctx: WizardContext): Promise<string[]> {
  const agentResults = (ctx as unknown as Record<string, unknown>)._agentResults as DetectedAgent[] | undefined;
  const available = new Map<string, DetectedAgent>();
  if (agentResults) {
    for (const a of agentResults) {
      if (a.available) available.set(a.id, a);
    }
  }

  const options: SelectOption<string>[] = AGENT_DEFS.map((def) => {
    const detected = available.get(def.id);
    return {
      value: def.id,
      label: def.name,
      hint: detected
        ? `✓ detected${detected.version ? ` (${detected.version})` : ''}`
        : '✗ not found',
      disabled: !detected,
    };
  });

  const defaultSelected = AGENT_DEFS
    .filter((def) => available.has(def.id))
    .map((def) => def.id);

  if (defaultSelected.length === 0) {
    ctx.prompter.warn('No local agents detected. You can use BYOK API mode from Settings.');
    return [];
  }

  const selected = await ctx.prompter.multiselect<string>(
    'Select agents to configure:',
    options,
    defaultSelected,
  );

  return selected;
}
