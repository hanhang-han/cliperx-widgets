/** CliperX Widget API 1 and 2. Compile to a standalone widget.js before packing. */
interface WidgetContext {
  now: string;
  settings: Record<string, string>;
  state: Record<string, unknown>;
  data: Record<string, any>;
  errors: Record<string, string>;
  metrics?: { cpuPercent: number; memoryUsedBytes: number; memoryTotalBytes: number; downloadMBps: number; uploadMBps: number };
  /** API 2. Only metadata crosses into scripts. Material text stays in native UI. */
  contextPack?: { count: number; estimatedTokens: number; shortened: number; unavailable: number };
  textProcessing?: { appleAvailable: boolean };
  aiUsage?: {
    status: 'ready' | 'stale' | 'unavailable';
    provider?: 'codex' | 'claude';
    updatedAt?: string;
    error?: string;
    windows?: { label: string; usedPercent: number; resetsAt?: string; windowMinutes?: number }[];
  };
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
type WidgetEffect = { type: 'openURL' | 'clipboard.write'; value: string }
  | { type: 'context.prepare' | 'text.process' | 'aiUsage.refresh'; value: '' };
declare function defineWidget(definition: {
  render(context: WidgetContext): WidgetView;
  onAction?(action: string, context: WidgetContext): { state?: Record<string, unknown>; effects?: WidgetEffect[] };
}): void;
