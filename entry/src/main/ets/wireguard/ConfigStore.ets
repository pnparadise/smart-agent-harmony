import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface TunnelConfig {
  id: string;
  name: string;
  configText: string;
}

export interface ActiveTunnelInfo {
  id: string;
  name: string;
  configText: string;
}

export interface TunnelRuntimeStatus {
  running: boolean;
  tunnelId: string;
  tunnelName: string;
  txBytes: number;
  rxBytes: number;
  latestHandshakeSeconds: number;
  latestPacketSentSeconds: number;
  loss: number;
  rttMillis: number;
  updatedAt: number;
}

export interface AgentLogEntry {
  id: string;
  title: string;
  subtitle: string;
  createdAt: number;
}

export interface SplitAppInfo {
  bundleName: string;
  label: string;
}

const STORE_NAME = 'wg_agent';
const DOMAIN = 0x0001;
const TAG = 'ConfigStore';
const LEGACY_CONFIG_KEY = 'wg_quick_config';
const ACTIVE_CONFIG_KEY = 'wg_active_config';
const ACTIVE_TUNNEL_ID_KEY = 'wg_active_tunnel_id';
const ACTIVE_TUNNEL_NAME_KEY = 'wg_active_tunnel_name';
const TUNNEL_IDS_KEY = 'wg_tunnel_ids';
const TUNNEL_NAME_PREFIX = 'wg_tunnel_name_';
const TUNNEL_CONFIG_PREFIX = 'wg_tunnel_config_';
const STATUS_RUNNING_KEY = 'wg_status_running';
const STATUS_TUNNEL_ID_KEY = 'wg_status_tunnel_id';
const STATUS_TUNNEL_NAME_KEY = 'wg_status_tunnel_name';
const STATUS_TX_BYTES_KEY = 'wg_status_tx_bytes';
const STATUS_RX_BYTES_KEY = 'wg_status_rx_bytes';
const STATUS_HANDSHAKE_KEY = 'wg_status_latest_handshake_seconds';
const STATUS_PACKET_SENT_KEY = 'wg_status_latest_packet_sent_seconds';
const STATUS_LOSS_KEY = 'wg_status_loss';
const STATUS_RTT_KEY = 'wg_status_rtt_millis';
const STATUS_UPDATED_AT_KEY = 'wg_status_updated_at';
const APP_SPLIT_ENABLED_KEY = 'wg_app_split_enabled';
const APP_SPLIT_APPS_KEY = 'wg_app_split_apps';
const DOH_ENABLED_KEY = 'wg_doh_enabled';
const DOH_PROVIDER_KEY = 'wg_doh_provider';
const LOG_ENTRIES_KEY = 'wg_log_entries';
const LAST_VPN_RESTORE_AT_KEY = 'wg_last_vpn_restore_at';
const MAX_LOG_ENTRIES = 100;
export const DEFAULT_DOH_PROVIDER = 'https://dns.alidns.com/dns-query';

export interface DohSettings {
  enabled: boolean;
  provider: string;
}

type StoreContext = common.UIAbilityContext | common.VpnExtensionContext;

export async function saveConfig(context: common.UIAbilityContext, value: string): Promise<void> {
  await saveActiveConfig(context, value);
}

export async function saveActiveConfig(context: StoreContext, value: string): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  await store.put(ACTIVE_CONFIG_KEY, value);
  await store.flush();
}

export async function saveActiveTunnel(context: common.UIAbilityContext, tunnel: TunnelConfig): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  await store.put(ACTIVE_CONFIG_KEY, tunnel.configText);
  await store.put(ACTIVE_TUNNEL_ID_KEY, tunnel.id);
  await store.put(ACTIVE_TUNNEL_NAME_KEY, tunnel.name);
  await store.flush();
  hilog.info(
    DOMAIN,
    TAG,
    'save active tunnel id=%{public}s name=%{public}s configBytes=%{public}d',
    tunnel.id,
    tunnel.name,
    tunnel.configText.length
  );
}

export async function clearActiveTunnel(context: StoreContext): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  await store.delete(ACTIVE_CONFIG_KEY);
  await store.delete(ACTIVE_TUNNEL_ID_KEY);
  await store.delete(ACTIVE_TUNNEL_NAME_KEY);
  await store.flush();
}

export async function loadActiveTunnelInfo(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<ActiveTunnelInfo> {
  if (reloadFromDisk) {
    await removeStoreFromCache(context);
  }

  const store = await preferences.getPreferences(context, STORE_NAME);
  const configValue = await store.get(ACTIVE_CONFIG_KEY, '');
  const legacyValue = await store.get(LEGACY_CONFIG_KEY, '');
  const idValue = await store.get(ACTIVE_TUNNEL_ID_KEY, '');
  const nameValue = await store.get(ACTIVE_TUNNEL_NAME_KEY, '');
  const activeConfig = configValue as string;
  const legacyConfig = legacyValue as string;
  const configText = activeConfig.length > 0 ? activeConfig : legacyConfig;
  const info: ActiveTunnelInfo = {
    id: idValue as string,
    name: nameValue as string,
    configText: configText
  };
  hilog.info(
    DOMAIN,
    TAG,
    'load active tunnel id=%{public}s name=%{public}s activeBytes=%{public}d legacyBytes=%{public}d selectedBytes=%{public}d',
    info.id,
    info.name,
    activeConfig.length,
    legacyConfig.length,
    info.configText.length
  );
  return info;
}

export async function loadConfig(context: StoreContext): Promise<string> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  const activeValue = await store.get(ACTIVE_CONFIG_KEY, '');
  const activeConfig = activeValue as string;
  if (activeConfig.length > 0) {
    return activeConfig;
  }

  const value = await store.get(LEGACY_CONFIG_KEY, '');
  return value as string;
}

export async function saveTunnelRuntimeStatus(context: StoreContext, status: TunnelRuntimeStatus): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  const running = status.running === true;
  const tunnelId = stringValue(status.tunnelId);
  const tunnelName = stringValue(status.tunnelName);
  const txBytes = numberValue(status.txBytes, 0);
  const rxBytes = numberValue(status.rxBytes, 0);
  const latestHandshakeSeconds = numberValue(status.latestHandshakeSeconds, -1);
  const latestPacketSentSeconds = numberValue(status.latestPacketSentSeconds, -1);
  const loss = numberValue(status.loss, 0);
  const rttMillis = numberValue(status.rttMillis, -1);
  const updatedAt = numberValue(status.updatedAt, Date.now());

  await store.put(STATUS_RUNNING_KEY, running);
  await store.put(STATUS_TUNNEL_ID_KEY, tunnelId);
  await store.put(STATUS_TUNNEL_NAME_KEY, tunnelName);
  await store.put(STATUS_TX_BYTES_KEY, txBytes);
  await store.put(STATUS_RX_BYTES_KEY, rxBytes);
  await store.put(STATUS_HANDSHAKE_KEY, latestHandshakeSeconds);
  await store.put(STATUS_PACKET_SENT_KEY, latestPacketSentSeconds);
  await store.put(STATUS_LOSS_KEY, loss);
  await store.put(STATUS_RTT_KEY, rttMillis);
  await store.put(STATUS_UPDATED_AT_KEY, updatedAt);
  await store.flush();
}

export async function loadTunnelRuntimeStatus(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<TunnelRuntimeStatus> {
  if (reloadFromDisk) {
    await removeStoreFromCache(context);
  }

  const store = await preferences.getPreferences(context, STORE_NAME);
  const status: TunnelRuntimeStatus = {
    running: await store.get(STATUS_RUNNING_KEY, false) as boolean,
    tunnelId: await store.get(STATUS_TUNNEL_ID_KEY, '') as string,
    tunnelName: await store.get(STATUS_TUNNEL_NAME_KEY, '') as string,
    txBytes: await store.get(STATUS_TX_BYTES_KEY, 0) as number,
    rxBytes: await store.get(STATUS_RX_BYTES_KEY, 0) as number,
    latestHandshakeSeconds: await store.get(STATUS_HANDSHAKE_KEY, -1) as number,
    latestPacketSentSeconds: await store.get(STATUS_PACKET_SENT_KEY, -1) as number,
    loss: await store.get(STATUS_LOSS_KEY, 0) as number,
    rttMillis: await store.get(STATUS_RTT_KEY, -1) as number,
    updatedAt: await store.get(STATUS_UPDATED_AT_KEY, 0) as number
  };
  return status;
}

export async function appendAgentLog(context: StoreContext, entry: AgentLogEntry): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  const entries = await loadAgentLogsFromStore(store);
  const normalizedEntry = normalizeAgentLogEntry(entry);
  const nextEntries: AgentLogEntry[] = [normalizedEntry];
  for (let index = 0; index < entries.length && nextEntries.length < MAX_LOG_ENTRIES; index++) {
    const existing = entries[index];
    if (existing.id !== normalizedEntry.id) {
      nextEntries.push(existing);
    }
  }

  await store.put(LOG_ENTRIES_KEY, formatAgentLogList(nextEntries));
  await store.flush();
}

export async function loadAgentLogs(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<AgentLogEntry[]> {
  if (reloadFromDisk) {
    await removeStoreFromCache(context);
  }

  const store = await preferences.getPreferences(context, STORE_NAME);
  return await loadAgentLogsFromStore(store);
}

export async function clearAgentLogs(context: StoreContext): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  await store.delete(LOG_ENTRIES_KEY);
  await store.flush();
}

export function buildVpnRestartLogEntry(tunnelName: string, createdAt: number = Date.now()): AgentLogEntry {
  const timestamp = numberValue(createdAt, Date.now());
  const normalizedTime = timestamp <= 0 ? Date.now() : timestamp;
  const entry: AgentLogEntry = {
    id: createAgentLogId('vpn_restart', normalizedTime),
    title: 'vpn重启',
    subtitle: '拉起隧道：' + normalizedLogTunnelName(tunnelName),
    createdAt: normalizedTime
  };
  return entry;
}

export async function loadLastVpnRestoreAt(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<number> {
  if (reloadFromDisk) {
    await removeStoreFromCache(context);
  }

  const store = await preferences.getPreferences(context, STORE_NAME);
  return await store.get(LAST_VPN_RESTORE_AT_KEY, 0) as number;
}

export async function saveLastVpnRestoreAt(context: StoreContext, value: number): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  await store.put(LAST_VPN_RESTORE_AT_KEY, numberValue(value, Date.now()));
  await store.flush();
}

export async function saveAppSplitEnabled(context: StoreContext, enabled: boolean): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  await store.put(APP_SPLIT_ENABLED_KEY, enabled);
  await store.flush();
  hilog.info(DOMAIN, TAG, 'save app split enabled=%{public}s', String(enabled));
}

export async function loadAppSplitEnabled(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<boolean> {
  if (reloadFromDisk) {
    await removeStoreFromCache(context);
  }

  const store = await preferences.getPreferences(context, STORE_NAME);
  const enabled = await store.get(APP_SPLIT_ENABLED_KEY, false) as boolean;
  hilog.info(DOMAIN, TAG, 'load app split enabled=%{public}s', String(enabled));
  return enabled;
}

export async function saveSelectedSplitApps(context: StoreContext, apps: SplitAppInfo[]): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  await store.put(APP_SPLIT_APPS_KEY, formatSplitAppList(apps));
  await store.flush();
  hilog.info(DOMAIN, TAG, 'save selected split apps count=%{public}d', apps.length);
}

export async function loadSelectedSplitApps(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<SplitAppInfo[]> {
  if (reloadFromDisk) {
    await removeStoreFromCache(context);
  }

  const store = await preferences.getPreferences(context, STORE_NAME);
  const rawValue = await store.get(APP_SPLIT_APPS_KEY, '');
  const apps = parseSplitAppList(rawValue as string);
  hilog.info(DOMAIN, TAG, 'load selected split apps count=%{public}d', apps.length);
  return apps;
}

export async function saveDohSettings(context: StoreContext, settings: DohSettings): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  await store.put(DOH_ENABLED_KEY, settings.enabled);
  await store.put(DOH_PROVIDER_KEY, normalizeDohProvider(settings.provider));
  await store.flush();
  hilog.info(
    DOMAIN,
    TAG,
    'save doh settings enabled=%{public}s provider=%{public}s',
    String(settings.enabled),
    normalizeDohProvider(settings.provider)
  );
}

export async function loadDohSettings(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<DohSettings> {
  if (reloadFromDisk) {
    await removeStoreFromCache(context);
  }

  const store = await preferences.getPreferences(context, STORE_NAME);
  const enabled = await store.get(DOH_ENABLED_KEY, true) as boolean;
  const provider = normalizeDohProvider(await store.get(DOH_PROVIDER_KEY, DEFAULT_DOH_PROVIDER) as string);
  const settings: DohSettings = {
    enabled: enabled,
    provider: provider
  };
  hilog.info(
    DOMAIN,
    TAG,
    'load doh settings enabled=%{public}s provider=%{public}s',
    String(settings.enabled),
    settings.provider
  );
  return settings;
}

async function removeStoreFromCache(context: StoreContext): Promise<void> {
  try {
    await preferences.removePreferencesFromCache(context, STORE_NAME);
    hilog.info(DOMAIN, TAG, 'preferences cache removed store=%{public}s', STORE_NAME);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'remove preferences cache failed: %{public}s', formatUnknownError(err));
  }
}

function normalizeDohProvider(value: string): string {
  const provider = value.trim();
  if (provider.length === 0) {
    return DEFAULT_DOH_PROVIDER;
  }
  return provider;
}

export function createTunnelId(): string {
  return 'tun_' + String(Date.now()) + '_' + String(Math.floor(Math.random() * 1000000));
}

export async function loadTunnels(context: common.UIAbilityContext): Promise<TunnelConfig[]> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  const idsValue = await store.get(TUNNEL_IDS_KEY, '');
  const ids = parseIdList(idsValue as string);
  if (ids.length === 0) {
    const legacyValue = await store.get(LEGACY_CONFIG_KEY, '');
    const legacyConfig = legacyValue as string;
    if (legacyConfig.length === 0) {
      return [];
    }

    const migratedTunnel: TunnelConfig = {
      id: createTunnelId(),
      name: 'Tunnel 1',
      configText: legacyConfig
    };
    await saveTunnelToStore(store, migratedTunnel, ids);
    return [migratedTunnel];
  }

  const tunnels: TunnelConfig[] = [];
  for (let index = 0; index < ids.length; index++) {
    const id = ids[index];
    const nameValue = await store.get(TUNNEL_NAME_PREFIX + id, 'Tunnel');
    const configValue = await store.get(TUNNEL_CONFIG_PREFIX + id, '');
    const tunnel: TunnelConfig = {
      id: id,
      name: nameValue as string,
      configText: configValue as string
    };
    tunnels.push(tunnel);
  }
  return tunnels;
}

export async function saveTunnel(context: common.UIAbilityContext, tunnel: TunnelConfig): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  const idsValue = await store.get(TUNNEL_IDS_KEY, '');
  const ids = parseIdList(idsValue as string);
  await saveTunnelToStore(store, tunnel, ids);
}

export async function deleteTunnel(context: common.UIAbilityContext, tunnelId: string): Promise<void> {
  const store = await preferences.getPreferences(context, STORE_NAME);
  const idsValue = await store.get(TUNNEL_IDS_KEY, '');
  const ids = parseIdList(idsValue as string);
  const nextIds: string[] = [];
  for (let index = 0; index < ids.length; index++) {
    if (ids[index] !== tunnelId) {
      nextIds.push(ids[index]);
    }
  }

  await store.put(TUNNEL_IDS_KEY, nextIds.join(','));
  await store.delete(TUNNEL_NAME_PREFIX + tunnelId);
  await store.delete(TUNNEL_CONFIG_PREFIX + tunnelId);
  await store.flush();
}

function parseIdList(rawValue: string): string[] {
  if (rawValue.length === 0) {
    return [];
  }

  const rawIds = rawValue.split(',');
  const ids: string[] = [];
  for (let index = 0; index < rawIds.length; index++) {
    const id = rawIds[index];
    if (id.length > 0) {
      ids.push(id);
    }
  }
  return ids;
}

function formatSplitAppList(apps: SplitAppInfo[]): string {
  const lines: string[] = [];
  for (let index = 0; index < apps.length; index++) {
    const app = apps[index];
    if (app.bundleName.length > 0) {
      lines.push(encodeURIComponent(app.bundleName) + '\t' + encodeURIComponent(app.label));
    }
  }
  return lines.join('\n');
}

function parseSplitAppList(rawValue: string): SplitAppInfo[] {
  if (rawValue.length === 0) {
    return [];
  }

  const lines = rawValue.split('\n');
  const apps: SplitAppInfo[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    if (line.length === 0) {
      continue;
    }

    const parts = line.split('\t');
    if (parts.length < 1 || parts[0].length === 0) {
      continue;
    }

    try {
      const bundleName = decodeURIComponent(parts[0]);
      const label = parts.length > 1 ? decodeURIComponent(parts[1]) : bundleName;
      const app: SplitAppInfo = {
        bundleName: bundleName,
        label: label.length > 0 ? label : bundleName
      };
      apps.push(app);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'parse selected split app failed: %{public}s', formatUnknownError(err));
    }
  }
  return apps;
}

async function loadAgentLogsFromStore(store: preferences.Preferences): Promise<AgentLogEntry[]> {
  const rawValue = await store.get(LOG_ENTRIES_KEY, '');
  return parseAgentLogList(rawValue as string);
}

function formatAgentLogList(entries: AgentLogEntry[]): string {
  const lines: string[] = [];
  for (let index = 0; index < entries.length; index++) {
    const entry = normalizeAgentLogEntry(entries[index]);
    if (entry.id.length > 0 && entry.title.length > 0) {
      lines.push(
        encodeURIComponent(entry.id) + '\t' +
        encodeURIComponent(entry.title) + '\t' +
        encodeURIComponent(entry.subtitle) + '\t' +
        String(entry.createdAt)
      );
    }
  }
  return lines.join('\n');
}

function parseAgentLogList(rawValue: string): AgentLogEntry[] {
  if (rawValue.length === 0) {
    return [];
  }

  const lines = rawValue.split('\n');
  const entries: AgentLogEntry[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    if (line.length === 0 || entries.length >= MAX_LOG_ENTRIES) {
      continue;
    }

    const parts = line.split('\t');
    if (parts.length < 4) {
      continue;
    }

    try {
      const entry: AgentLogEntry = {
        id: decodeURIComponent(parts[0]),
        title: decodeURIComponent(parts[1]),
        subtitle: decodeURIComponent(parts[2]),
        createdAt: Number(parts[3])
      };
      const normalized = normalizeAgentLogEntry(entry);
      if (normalized.id.length > 0 && normalized.title.length > 0) {
        entries.push(normalized);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'parse agent log failed: %{public}s', formatUnknownError(err));
    }
  }
  return entries;
}

function normalizeAgentLogEntry(entry: AgentLogEntry): AgentLogEntry {
  const createdAt = numberValue(entry.createdAt, Date.now());
  const normalized: AgentLogEntry = {
    id: stringValue(entry.id),
    title: stringValue(entry.title),
    subtitle: stringValue(entry.subtitle),
    createdAt: createdAt <= 0 ? Date.now() : createdAt
  };
  return normalized;
}

function createAgentLogId(prefix: string, createdAt: number): string {
  return prefix + '_' + String(createdAt) + '_' + String(Math.floor(Math.random() * 1000000));
}

function normalizedLogTunnelName(tunnelName: string): string {
  const normalized = tunnelName.trim();
  if (normalized.length > 0) {
    return normalized;
  }
  return '未知隧道';
}

async function saveTunnelToStore(store: preferences.Preferences, tunnel: TunnelConfig, ids: string[]): Promise<void> {
  const nextIds: string[] = [];
  let found = false;
  for (let index = 0; index < ids.length; index++) {
    const id = ids[index];
    nextIds.push(id);
    if (id === tunnel.id) {
      found = true;
    }
  }

  if (!found) {
    nextIds.push(tunnel.id);
  }

  await store.put(TUNNEL_IDS_KEY, nextIds.join(','));
  await store.put(TUNNEL_NAME_PREFIX + tunnel.id, tunnel.name);
  await store.put(TUNNEL_CONFIG_PREFIX + tunnel.id, tunnel.configText);
  await store.flush();
}

function stringValue(value: string | undefined): string {
  if (value === undefined) {
    return '';
  }
  return value;
}

function numberValue(value: number | undefined, fallback: number): number {
  if (value === undefined || Number.isNaN(value)) {
    return fallback;
  }
  return value;
}

function formatUnknownError(err: Object): string {
  const error = err as Error;
  if (error.message !== undefined && error.message.length > 0) {
    return error.message;
  }
  return JSON.stringify(err);
}
