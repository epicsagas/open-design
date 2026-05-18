import * as clack from '@clack/prompts';
import type { SetupPrompter, SelectOption } from './prompts.js';

export class ClackPrompter implements SetupPrompter {
  text(message: string, defaultValue?: string): Promise<string> {
    return clack.text({ message, defaultValue: defaultValue ?? '' }) as Promise<string>;
  }

  async select<T>(message: string, options: SelectOption<T>[], initialValue?: T): Promise<T> {
    const clackOptions = options.map((o) => ({
      value: o.value,
      label: o.label,
      ...(o.hint !== undefined ? { hint: o.hint } : {}),
      ...(o.disabled !== undefined ? { disabled: o.disabled } : {}),
    }));
    const result = await clack.select({ message, options: clackOptions as any, initialValue });
    if (clack.isCancel(result)) {
      throw new CancelError('Selection cancelled');
    }
    return result as T;
  }

  async multiselect<T>(message: string, options: SelectOption<T>[], initialValues?: T[]): Promise<T[]> {
    const clackOptions = options.map((o) => ({
      value: o.value,
      label: o.label,
      ...(o.hint !== undefined ? { hint: o.hint } : {}),
      ...(o.disabled !== undefined ? { disabled: o.disabled } : {}),
    }));
    const clackArgs: any = {
      message,
      options: clackOptions,
      required: false,
    };
    if (initialValues !== undefined) {
      clackArgs.initialValues = initialValues;
    }
    const result = await clack.multiselect(clackArgs);
    if (clack.isCancel(result)) {
      throw new CancelError('Selection cancelled');
    }
    return result as T[];
  }

  async confirm(message: string, defaultValue?: boolean): Promise<boolean> {
    const result = await clack.confirm({ message, initialValue: defaultValue ?? false });
    if (clack.isCancel(result)) {
      throw new CancelError('Confirmation cancelled');
    }
    return result as boolean;
  }

  async password(message: string): Promise<string> {
    const result = await clack.password({ message });
    if (clack.isCancel(result)) {
      throw new CancelError('Password cancelled');
    }
    return result as string;
  }

  banner(text: string): void {
    clack.note(text, undefined);
  }

  info(message: string): void {
    clack.log.info(message);
  }

  success(message: string): void {
    clack.log.success(message);
  }

  warn(message: string): void {
    clack.log.warn(message);
  }

  error(message: string): void {
    clack.log.error(message);
  }

  async spinner<T>(message: string, fn: () => Promise<T>): Promise<T> {
    const s = clack.spinner();
    s.start(message);
    try {
      const result = await fn();
      s.stop(message);
      return result;
    } catch (err) {
      s.stop('Failed');
      throw err;
    }
  }

  note(title: string, body: string): void {
    clack.note(body, title);
  }
}

export class CancelError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CancelError';
  }
}
