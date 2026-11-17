/** CliperX Widget API 1, 2, 3 and 4. Compile to a standalone widget.js before packing. */
interface WidgetContext {
  now: string;
  settings: Record<string, string>;
  state: Record<string, unknown>;
  data: Record<string, any>;
  errors: Record<string, string>;
  /** API 3 capability snapshots and subscriptions. */
  power?: { mode: 'automatic' | 'manual' | 'off'; active: boolean; running: number;
    lidEnabled: boolean; lidActive: boolean; authorizing: boolean; error: string; helperAvailable: boolean };
  music?: { title: string; artist: string; isPlaying: boolean };
  agent?: { count: number; running: number; unread: number };
  metrics?: { cpuPercent: number; memoryUsedBytes: number; memoryTotalBytes: number; downloadMBps: number; uploadMBps: number };
  /** API 2. Only metadata crosses into scripts. Material text stays in native UI. */
  contextPack?: { count: number; imageCount: number; hasConversation: boolean; estimatedTokens: number; shortened: number; unavailable: number };
  textProcessing?: { appleAvailable: boolean; actionTitle?: string; busy?: boolean };
  aiUsage?: {
    status: 'ready' | 'stale' | 'unavailable';
    provider?: 'codex' | 'claude';
    updatedAt?: string;
    error?: string;
    windows?: { label: string; usedPercent: number; resetsAt?: string; windowMinutes?: number }[];
  };
  /** API 2. The shared native basket owns its content and paste actions. */
  collectionBasket?: { count: number; autoCollect: boolean; isOpen: boolean; isPasting: boolean };
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
  primaryAction?: string;
}
type WidgetEffect = { type: 'power.setMode'; value: 'automatic' | 'manual' | 'off' }
  | { type: 'power.toggleLid'; value: '' }
  | { type: 'openURL' | 'clipboard.write'; value: string }
  | { type: 'context.prepare' | 'text.process' | 'aiUsage.refresh' | 'basket.open' | 'music.playPause' | 'music.previous' | 'music.next' | 'agent.open'; value: '' };
declare function defineWidget(definition: {
  render(context: WidgetContext): WidgetView;
  onAction?(action: string, context: WidgetContext): { state?: Record<string, unknown>; effects?: WidgetEffect[] };
}): void;

interface WidgetPresentation {
  card: 'standard' | 'metric' | 'music' | 'basket' | 'agent' | 'ccswitch';
  workspace?: 'context' | 'text' | 'basket' | 'agent';
  metric?: 'cpu' | 'memory' | 'network' | 'battery' | 'disk' | 'clock';
  multipleInstances?: boolean;
}

interface WidgetPermissions {
  network?: string[];
  openURL?: boolean;
  clipboardWrite?: boolean;
  systemMetrics?: boolean;
  contextPreparation?: boolean;
  textProcessing?: boolean;
  aiUsage?: boolean;
  collectionBasket?: boolean;
  musicControl?: boolean;
  agentConversations?: boolean;
  providerConfiguration?: boolean;
  powerManagement?: boolean;
}
interface WidgetCatalogMetadata {
  category?: 'clipboard' | 'ai' | 'productivity' | 'system' | 'other';
  tags?: string[];
  screenshots?: string[];
  readme?: string;
  changelog?: string;
  minAppVersion?: string;
  feedbackURL?: string;
}

/** API 4. The native host owns input selection, task parameters and execution. */
interface WidgetTaskDefinition {
  input: { types: ('text' | 'image')[]; minItems: number; maxItems: number };
  parameters: { key: string; title: string; default: string; required?: boolean }[];
  prompt: string;
  output: { format: 'markdown' };
}
interface WidgetManifest {
  id: string;
  name: string;
  version: string;
  apiVersion: 1 | 2 | 3 | 4;
  author: string;
  description: string;
  license: string;
  symbol: string;
  sizes: ('small' | 'wide')[];
  refreshSeconds: number;
  permissions: WidgetPermissions;
  settings?: { key: string; title: string; default: string }[];
  sources?: Record<string, { url: string }>;
  presentation?: WidgetPresentation;
  subscriptions?: ('metrics' | 'music' | 'agent' | 'context' | 'text' | 'basket' | 'power')[];
  task?: WidgetTaskDefinition;
}
