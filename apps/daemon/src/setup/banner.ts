import type { SetupPrompter } from './prompts.js';

export function printBanner(p: SetupPrompter) {
  p.banner(`
  ╔══════════════════════════════════════════╗
  ║                OPEN DESIGN               ║
  ╚══════════════════════════════════════════╝

  Welcome to Open Design Setup!
`);
}
