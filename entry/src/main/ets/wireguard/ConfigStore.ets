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
  hilog.info(
    DOMAIN,
    TAG,
    'save runtime status running=%{public}s id=%{public}s name=%{public}s tx=%{public}s rx=%{public}s handshake=%{public}s packetSent=%{public}s rtt=%{public}s updatedAt=%{public}s',
    String(running),
    tunnelId,
    tunnelName,
    String(txBytes),
    String(rxBytes),
    String(latestHandshakeSeconds),
    String(latestPacketSentSeconds),
    String(rttMillis),
    String(updatedAt)
  );
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
  hilog.info(
    DOMAIN,
    TAG,
    'load runtime status running=%{public}s id=%{public}s name=%{public}s tx=%{public}s rx=%{public}s handshake=%{public}s packetSent=%{public}s rtt=%{public}s updatedAt=%{public}s',
    String(status.running),
    status.tunnelId,
    status.tunnelName,
    String(status.txBytes),
    String(status.rxBytes),
    String(status.latestHandshakeSeconds),
    String(status.latestPacketSentSeconds),
    String(status.rttMillis),
    String(status.updatedAt)
  );
  return status;
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
