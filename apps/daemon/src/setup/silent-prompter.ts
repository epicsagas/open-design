import type { SetupPrompter, SelectOption } from './prompts.js';

export class SilentPrompter implements SetupPrompter {
  constructor(private flags: Record<string, unknown>) {}

  async text(message: string, defaultValue?: string): Promise<string> {
    return defaultValue ?? '';
  }

  async select<T>(message: string, options: SelectOption<T>[], initialValue?: T): Promise<T> {
    if (initialValue !== undefined) return initialValue;
    return options[0]?.value as T;
  }

  async multiselect<T>(message: string, options: SelectOption<T>[], initialValues?: T[]): Promise<T[]> {
    return initialValues ?? [];
  }

  async confirm(message: string, defaultValue?: boolean): Promise<boolean> {
    return defaultValue ?? false;
  }

  async password(message: string): Promise<string> {
    return '';
  }

  banner(text: string): void {
    process.stdout.write(text + '\n');
  }

  info(message: string): void {
    process.stdout.write(`  ${message}\n`);
  }

  success(message: string): void {
    process.stdout.write(`  ✓ ${message}\n`);
  }

  warn(message: string): void {
    process.stderr.write(`  ⚠ ${message}\n`);
  }

  error(message: string): void {
    process.stderr.write(`  ✗ ${message}\n`);
  }

  async spinner<T>(message: string, fn: () => Promise<T>): Promise<T> {
    process.stdout.write(`  > ${message}...\n`);
    return fn();
  }

  note(title: string, body: string): void {
    process.stdout.write(`── ${title} ──\n${body}\n`);
  }
}
