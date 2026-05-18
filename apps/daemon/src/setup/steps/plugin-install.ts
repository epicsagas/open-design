import { execFile } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { promisify } from 'node:util';
import type { WizardContext } from '../wizard.js';

const execFileAsync = promisify(execFile);

const odPath = () => process.argv[1] ?? 'od';

// Agents that support MCP via their CLI's `mcp add` command.
const CLI_MCP_AGENTS: Record<string, {
  name: string;
  bin: string;
  buildArgs: (serverName: string) => string[];
  configPath?: string;
  configShape?: (odBin: string) => Record<string, unknown>;
}> = {
  claude: {
    name: 'Claude Code',
    bin: 'claude',
    buildArgs: (name) => ['mcp', 'add', '--scope', 'user', name, '--', odPath(), 'mcp'],
  },
  cursor: {
    name: 'Cursor',
    bin: 'cursor',
    // Cursor doesn't have a CLI `mcp add`; write config file instead.
    configPath: join(homedir(), '.cursor', 'mcp.json'),
    configShape: (odBin) => ({
      mcpServers: {
        'open-design': { command: odBin, args: ['mcp'] },
      },
    }),
    buildArgs: () => [],
  },
  copilot: {
    name: 'GitHub Copilot CLI',
    bin: 'github-copilot-cli',
    buildArgs: () => [],
  },
};

// ACP agents get MCP injected at spawn time by the daemon — no user action needed.
const ACP_AGENTS = new Set(['hermes', 'kimi', 'devin', 'kiro', 'kilo', 'vibe']);

export async function runPluginInstall(ctx: WizardContext): Promise<void> {
  if (ctx.selectedAgents.length === 0) return;

  const targets: string[] = [];
  const acpAgents: string[] = [];
  const manualAgents: string[] = [];

  for (const agentId of ctx.selectedAgents) {
    if (CLI_MCP_AGENTS[agentId]) {
      targets.push(agentId);
    } else if (ACP_AGENTS.has(agentId)) {
      acpAgents.push(agentId);
    } else {
      manualAgents.push(agentId);
    }
  }

  // Inform about ACP agents — no action needed
  if (acpAgents.length > 0) {
    ctx.prompter.info(
      `ACP agents (${acpAgents.join(', ')}): MCP tools are injected automatically at runtime.`,
    );
  }

  // Inform about agents that need manual config
  if (manualAgents.length > 0) {
    ctx.prompter.info(
      `For ${manualAgents.join(', ')}: add the MCP server manually via each tool's settings.`,
    );
    ctx.prompter.note('Manual MCP snippet', [
      '{',
      '  "mcpServers": {',
      `    "open-design": { "command": "${odPath()}", "args": ["mcp"] }`,
      '  }',
      '}',
    ].join('\n'));
  }

  // Install for CLI-capable targets
  if (targets.length === 0) return;

  const install = await ctx.prompter.confirm(
    `Install Open Design MCP server for ${targets.map((t) => CLI_MCP_AGENTS[t]!.name).join(', ')}?`,
    true,
  );
  if (!install) {
    ctx.prompter.info('Skipped MCP installation.');
    return;
  }

  for (const agentId of targets) {
    const def = CLI_MCP_AGENTS[agentId]!;
    if (def.configPath && def.configShape) {
      await writeMcpConfigFile(ctx, def.name, def.configPath, def.configShape(odPath()));
    } else {
      await registerViaCli(ctx, def.name, def.bin, def.buildArgs('open-design'));
    }
  }
}

async function registerViaCli(ctx: WizardContext, agentName: string, bin: string, args: string[]): Promise<void> {
  try {
    await ctx.prompter.spinner(`Registering MCP server for ${agentName}...`, async () => {
      await execFileAsync(bin, args, { timeout: 15000 });
    });
    ctx.prompter.success(`${agentName}: MCP server registered (open-design).`);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    ctx.prompter.warn(`${agentName}: CLI registration failed (${msg}). Falling back to config file.`);
    // Could add config file fallback here per agent
  }
}

async function writeMcpConfigFile(
  ctx: WizardContext,
  agentName: string,
  configPath: string,
  shape: Record<string, unknown>,
): Promise<void> {
  try {
    await ctx.prompter.spinner(`Writing MCP config for ${agentName}...`, async () => {
      let existing: Record<string, unknown> = {};
      try {
        const raw = await readFile(configPath, 'utf-8');
        existing = JSON.parse(raw);
      } catch { /* file doesn't exist yet */ }

      const merged = { ...existing, ...shape };
      if ((existing as Record<string, unknown>).mcpServers && shape.mcpServers) {
        (merged as Record<string, unknown>).mcpServers = {
          ...((existing as Record<string, Record<string, unknown>>).mcpServers ?? {}),
          ...(shape.mcpServers as Record<string, unknown>),
        };
      }

      await mkdir(join(configPath, '..'), { recursive: true });
      await writeFile(configPath, JSON.stringify(merged, null, 2) + '\n', 'utf-8');
    });
    ctx.prompter.success(`${agentName}: MCP config written to ${configPath}`);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    ctx.prompter.warn(`${agentName}: Could not write config: ${msg}`);
    ctx.prompter.info(`Manually add to ${configPath}: ${JSON.stringify(shape)}`);
  }
}
