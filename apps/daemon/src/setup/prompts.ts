export interface SelectOption<T> {
  value: T;
  label: string;
  hint?: string;
  disabled?: boolean;
}

export interface SetupPrompter {
  text(message: string, defaultValue?: string): Promise<string>;
  select<T>(message: string, options: SelectOption<T>[], initialValue?: T): Promise<T>;
  multiselect<T>(message: string, options: SelectOption<T>[], initialValues?: T[]): Promise<T[]>;
  confirm(message: string, defaultValue?: boolean): Promise<boolean>;
  password(message: string): Promise<string>;
  banner(text: string): void;
  info(message: string): void;
  success(message: string): void;
  warn(message: string): void;
  error(message: string): void;
  spinner<T>(message: string, fn: () => Promise<T>): Promise<T>;
  note(title: string, body: string): void;
}
