/** CliperX Widget API 1. Compile TypeScript to a standalone widget.js before packing. */
interface WidgetContext {
  now: string;
  settings: Record<string, string>;
  state: Record<string, unknown>;
  data: Record<string, any>;
  errors: Record<string, string>;
  metrics?: { cpuPercent: number; memoryUsedBytes: number; memoryTotalBytes: number; downloadMBps: number; uploadMBps: number };
}
interface WidgetView {
  title: string;
  value: string;
  subtitle?: string;
  symbol?: string;
  progress?: number;
  series?: number[];
  countdownTo?: string;
  details?: { label: string; value: string }[];
  actions?: { id: string; title: string }[];
}
interface WidgetEffect { type: 'openURL' | 'clipboard.write'; value: string }
declare function defineWidget(definition: {
  render(context: WidgetContext): WidgetView;
  onAction?(action: string, context: WidgetContext): { state?: Record<string, unknown>; effects?: WidgetEffect[] };
}): void;
