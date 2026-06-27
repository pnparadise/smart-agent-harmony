import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { url } from '@kit.ArkTS';
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

export type AgentRuleType = 'wifiGateway' | 'wifiSsid' | 'ipv6Available' | 'ipv4Available';

export interface AgentRule {
  id: string;
  type: AgentRuleType;
  matchValue: string;
  targetTunnelId: string;
  targetTunnelName: string;
  enabled: boolean;
}

export interface SplitAppInfo {
  bundleName: string;
  label: string;
}

export interface WebBookmarkEntry {
  id: string;
  url: string;
  title: string;
  updatedAt: number;
}

export interface WebPwaEntry {
  url: string;
  startUrl: string;
  scope: string;
  display: string;
  name: string;
  manifestUrl: string;
  updatedAt: number;
}

export interface WebHistoryEntry {
  url: string;
  title: string;
  updatedAt: number;
}

const STORE_NAME = 'wg_agent';
const LOG_STORE_NAME = 'wg_agent_logs';
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
const SMART_AGENT_ENABLED_KEY = 'wg_smart_agent_enabled';
const SMART_AGENT_RULES_KEY = 'wg_smart_agent_rules';
const DOH_ENABLED_KEY = 'wg_doh_enabled';
const DOH_PROVIDER_KEY = 'wg_doh_provider';
const BROWSER_DOH_ENABLED_KEY = 'wg_browser_doh_enabled';
const BROWSER_DOH_PROVIDER_KEY = 'wg_browser_doh_provider';
const WEB_PINNED_URL_KEY = 'wg_web_pinned_url';
const WEB_LAST_URL_KEY = 'wg_web_last_url';
const WEB_SHORTCUT_URL_PREFIX = 'wg_web_shortcut_url_';
const WEB_LAST_SHORTCUT_URL_KEY = 'wg_web_last_shortcut_url';
const WEB_BOOKMARKS_KEY = 'wg_web_bookmarks';
const WEB_PWA_ENTRIES_KEY = 'wg_web_pwa_entries';
const WEB_HISTORY_KEY = 'wg_web_history';
const LOG_ENTRIES_KEY = 'wg_log_entries';
const LOG_CLEARED_AT_KEY = 'wg_log_cleared_at';
const LAST_VPN_RESTORE_AT_KEY = 'wg_last_vpn_restore_at';
const DATA_TRANSFER_NOTIFICATION_ID_KEY = 'wg_data_transfer_notification_id';
const MAX_LOG_ENTRIES = 100;
const MAX_WEB_HISTORY_ENTRIES = 80;
export const DEFAULT_DOH_PROVIDER = 'https://dns.alidns.com/dns-query';
export const DEFAULT_WEB_HOME_URL = 'about:smart-bookmarks';

export interface DohSettings {
  enabled: boolean;
  provider: string;
}

type StoreContext = common.UIAbilityContext | common.VpnExtensionContext;

export async function saveConfig(context: common.UIAbilityContext, value: string): Promise<void> {
  await saveActiveConfig(context, value);
}

export async function saveActiveConfig(context: StoreContext, value: string): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(ACTIVE_CONFIG_KEY, value);
  await store.flush();
}

export async function saveActiveTunnel(context: common.UIAbilityContext, tunnel: TunnelConfig): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(ACTIVE_CONFIG_KEY, tunnel.configText);
  await store.put(ACTIVE_TUNNEL_ID_KEY, tunnel.id);
  await store.put(ACTIVE_TUNNEL_NAME_KEY, tunnel.name);
  await store.flush();
}

export async function clearActiveTunnel(context: StoreContext): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.delete(ACTIVE_CONFIG_KEY);
  await store.delete(ACTIVE_TUNNEL_ID_KEY);
  await store.delete(ACTIVE_TUNNEL_NAME_KEY);
  await store.flush();
}

export async function loadActiveTunnelInfo(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<ActiveTunnelInfo> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
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
  return info;
}

export async function loadConfig(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<string> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  const activeValue = await store.get(ACTIVE_CONFIG_KEY, '');
  const activeConfig = activeValue as string;
  if (activeConfig.length > 0) {
    return activeConfig;
  }

  const value = await store.get(LEGACY_CONFIG_KEY, '');
  return value as string;
}

export async function saveTunnelRuntimeStatus(context: StoreContext, status: TunnelRuntimeStatus): Promise<void> {
  const store = await getMainStoreForWrite(context);
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
    'save runtime status running=%{public}s tunnelId=%{public}s tunnelName=%{public}s tx=%{public}d rx=%{public}d updatedAt=%{public}d',
    String(running),
    tunnelId,
    tunnelName,
    txBytes,
    rxBytes,
    updatedAt
  );
}

export async function saveDataTransferNotificationId(context: StoreContext, notificationId: number): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(DATA_TRANSFER_NOTIFICATION_ID_KEY, numberValue(notificationId, 0));
  await store.flush();
}

export async function loadDataTransferNotificationId(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<number> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return await store.get(DATA_TRANSFER_NOTIFICATION_ID_KEY, 0) as number;
}

export async function clearDataTransferNotificationId(context: StoreContext): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.delete(DATA_TRANSFER_NOTIFICATION_ID_KEY);
  await store.flush();
}

export async function loadTunnelRuntimeStatus(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<TunnelRuntimeStatus> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
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
  const store = await getLogStoreForWrite(context);
  const entries = await loadAgentLogsFromLogStore(context, store);
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
  const store = await getLogStoreForLoad(context, reloadFromDisk);
  return await loadAgentLogsFromLogStore(context, store);
}

export async function clearAgentLogs(context: StoreContext): Promise<void> {
  const logStore = await getLogStoreForWrite(context);
  await logStore.put(LOG_CLEARED_AT_KEY, Date.now());
  await logStore.delete(LOG_ENTRIES_KEY);
  await logStore.flush();

  const legacyStore = await getMainStoreForWrite(context);
  await legacyStore.delete(LOG_ENTRIES_KEY);
  await legacyStore.flush();
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

export function buildSmartAgentSwitchLogEntry(
  trigger: string,
  fromTunnelName: string,
  toTunnelName: string,
  createdAt: number = Date.now()
): AgentLogEntry {
  const timestamp = numberValue(createdAt, Date.now());
  const normalizedTime = timestamp <= 0 ? Date.now() : timestamp;
  const normalizedFrom = normalizedLogTunnelName(fromTunnelName);
  const normalizedTo = normalizedTargetName(toTunnelName);
  const entry: AgentLogEntry = {
    id: createAgentLogId('smart_agent_switch', normalizedTime),
    title: '策略切换',
    subtitle: '触发：' + normalizedTriggerReason(trigger) + '，' + normalizedFrom + ' -> ' + normalizedTo,
    createdAt: normalizedTime
  };
  return entry;
}

export function createAgentRuleId(): string {
  return 'rule_' + String(Date.now()) + '_' + String(Math.floor(Math.random() * 1000000));
}

export async function loadLastVpnRestoreAt(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<number> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return await store.get(LAST_VPN_RESTORE_AT_KEY, 0) as number;
}

export async function saveLastVpnRestoreAt(context: StoreContext, value: number): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(LAST_VPN_RESTORE_AT_KEY, numberValue(value, Date.now()));
  await store.flush();
}

export async function saveAppSplitEnabled(context: StoreContext, enabled: boolean): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(APP_SPLIT_ENABLED_KEY, enabled);
  await store.flush();
}

export async function loadAppSplitEnabled(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<boolean> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return await store.get(APP_SPLIT_ENABLED_KEY, false) as boolean;
}

export async function saveSelectedSplitApps(context: StoreContext, apps: SplitAppInfo[]): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(APP_SPLIT_APPS_KEY, formatSplitAppList(apps));
  await store.flush();
}

export async function loadSelectedSplitApps(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<SplitAppInfo[]> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  const rawValue = await store.get(APP_SPLIT_APPS_KEY, '');
  return parseSplitAppList(rawValue as string);
}

export async function saveSmartAgentEnabled(context: StoreContext, enabled: boolean): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(SMART_AGENT_ENABLED_KEY, enabled);
  await store.flush();
}

export async function loadSmartAgentEnabled(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<boolean> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return await store.get(SMART_AGENT_ENABLED_KEY, false) as boolean;
}

export async function saveAgentRules(context: StoreContext, rules: AgentRule[]): Promise<void> {
  const store = await getMainStoreForWrite(context);
  const formattedRules = formatAgentRuleList(rules);
  await store.put(SMART_AGENT_RULES_KEY, formattedRules);
  await store.flush();
  hilog.info(
    DOMAIN,
    TAG,
    'save smart agent rules count=%{public}d bytes=%{public}d summary=%{public}s',
    rules.length,
    formattedRules.length,
    summarizeAgentRules(rules)
  );
}

export async function loadAgentRules(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<AgentRule[]> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  const rawValue = await store.get(SMART_AGENT_RULES_KEY, '');
  const rules = parseAgentRuleList(rawValue as string);
  hilog.info(
    DOMAIN,
    TAG,
    'load smart agent rules count=%{public}d bytes=%{public}d reload=%{public}s summary=%{public}s',
    rules.length,
    (rawValue as string).length,
    String(reloadFromDisk),
    summarizeAgentRules(rules)
  );
  return rules;
}

export async function saveDohSettings(context: StoreContext, settings: DohSettings): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(DOH_ENABLED_KEY, settings.enabled);
  await store.put(DOH_PROVIDER_KEY, normalizeDohProvider(settings.provider));
  await store.flush();
}

export async function loadDohSettings(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<DohSettings> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  const enabled = await store.get(DOH_ENABLED_KEY, true) as boolean;
  const provider = normalizeDohProvider(await store.get(DOH_PROVIDER_KEY, DEFAULT_DOH_PROVIDER) as string);
  const settings: DohSettings = {
    enabled: enabled,
    provider: provider
  };
  return settings;
}

export async function saveBrowserDohSettings(context: StoreContext, settings: DohSettings): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(BROWSER_DOH_ENABLED_KEY, settings.enabled);
  await store.put(BROWSER_DOH_PROVIDER_KEY, normalizeDohProvider(settings.provider));
  await store.flush();
}

export async function loadBrowserDohSettings(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<DohSettings> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  const legacyEnabled = await store.get(DOH_ENABLED_KEY, true) as boolean;
  const legacyProvider = normalizeDohProvider(await store.get(DOH_PROVIDER_KEY, DEFAULT_DOH_PROVIDER) as string);
  const enabled = await store.get(BROWSER_DOH_ENABLED_KEY, legacyEnabled) as boolean;
  const provider = normalizeDohProvider(
    await store.get(BROWSER_DOH_PROVIDER_KEY, legacyProvider) as string
  );
  const settings: DohSettings = {
    enabled: enabled,
    provider: provider
  };
  return settings;
}

export async function savePinnedWebUrl(context: StoreContext, url: string): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(WEB_PINNED_URL_KEY, normalizeWebUrlForStore(url));
  await store.flush();
  hilog.info(DOMAIN, TAG, 'save pinned web url');
}

export async function loadPinnedWebUrl(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<string> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return normalizeWebUrlForStore(await store.get(WEB_PINNED_URL_KEY, DEFAULT_WEB_HOME_URL) as string);
}

export async function saveWebShortcutUrl(
  context: StoreContext,
  shortcutId: string,
  url: string,
  title: string = ''
): Promise<void> {
  const normalizedUrl = normalizeWebUrlForStore(url);
  const id = normalizeShortcutId(shortcutId);
  const store = await getMainStoreForWrite(context);
  await store.put(WEB_LAST_SHORTCUT_URL_KEY, normalizedUrl);
  if (id.length > 0) {
    await store.put(WEB_SHORTCUT_URL_PREFIX + id, normalizedUrl);
  }
  const bookmarkAdded = await putWebBookmark(store, {
    id: id.length > 0 ? id : stableWebBookmarkId(normalizedUrl),
    url: normalizedUrl,
    title: title.trim().length > 0 ? title.trim() : webBookmarkTitle(normalizedUrl),
    updatedAt: Date.now()
  });
  await store.flush();
  hilog.info(DOMAIN, TAG, 'save web shortcut url id=%{public}s bookmarkAdded=%{public}s',
    id,
    String(bookmarkAdded)
  );
}

export async function saveWebShortcutMapping(
  context: StoreContext,
  shortcutId: string,
  url: string
): Promise<void> {
  const normalizedUrl = normalizeWebUrlForStore(url);
  const id = normalizeShortcutId(shortcutId);
  const store = await getMainStoreForWrite(context);
  await store.put(WEB_LAST_SHORTCUT_URL_KEY, normalizedUrl);
  if (id.length > 0) {
    await store.put(WEB_SHORTCUT_URL_PREFIX + id, normalizedUrl);
  }
  await store.flush();
  hilog.info(DOMAIN, TAG, 'save web shortcut mapping id=%{public}s', id);
}

export async function loadWebShortcutUrl(
  context: StoreContext,
  shortcutId: string,
  reloadFromDisk: boolean = false
): Promise<string> {
  const id = normalizeShortcutId(shortcutId);
  if (id.length === 0) {
    return '';
  }

  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return normalizeWebUrlForStore(await store.get(WEB_SHORTCUT_URL_PREFIX + id, '') as string);
}

export async function hasWebShortcutMapping(
  context: StoreContext,
  shortcutId: string,
  reloadFromDisk: boolean = false
): Promise<boolean> {
  return (await loadWebShortcutUrl(context, shortcutId, reloadFromDisk)).length > 0;
}

export async function loadLastWebShortcutUrl(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<string> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return normalizeWebUrlForStore(await store.get(WEB_LAST_SHORTCUT_URL_KEY, '') as string);
}

export async function saveWebBookmark(
  context: StoreContext,
  url: string,
  title: string = '',
  bookmarkId: string = ''
): Promise<boolean> {
  const normalizedUrl = normalizeWebUrlForStore(url);
  if (!isWebBookmarkUrl(normalizedUrl)) {
    return false;
  }

  const id = normalizeShortcutId(bookmarkId);
  const store = await getMainStoreForWrite(context);
  if (id.length > 0) {
    await store.put(WEB_LAST_SHORTCUT_URL_KEY, normalizedUrl);
    await store.put(WEB_SHORTCUT_URL_PREFIX + id, normalizedUrl);
  }
  const added = await putWebBookmark(store, {
    id: id.length > 0 ? id : stableWebBookmarkId(normalizedUrl),
    url: normalizedUrl,
    title: title.trim().length > 0 ? title.trim() : webBookmarkTitle(normalizedUrl),
    updatedAt: Date.now()
  });
  if (added || id.length > 0) {
    await store.flush();
  }
  hilog.info(DOMAIN, TAG, 'save web bookmark added=%{public}s', String(added));
  return added;
}

export async function loadWebBookmarks(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<WebBookmarkEntry[]> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return parseWebBookmarks(await store.get(WEB_BOOKMARKS_KEY, '') as string);
}

export async function saveWebPwaEntry(context: StoreContext, entry: WebPwaEntry): Promise<void> {
  const normalized = normalizeWebPwaEntry(entry);
  if (normalized.url.length === 0 || normalized.startUrl.length === 0 || normalized.scope.length === 0 ||
    normalized.name.length === 0) {
    return;
  }

  const store = await getMainStoreForWrite(context);
  const entries = parseWebPwaEntries(await store.get(WEB_PWA_ENTRIES_KEY, '') as string);
  const next: WebPwaEntry[] = [normalized];
  for (let index = 0; index < entries.length; index++) {
    const existing = entries[index];
    if (existing.url !== normalized.url && existing.startUrl !== normalized.startUrl) {
      next.push(existing);
    }
  }
  await store.put(WEB_PWA_ENTRIES_KEY, JSON.stringify(next));
  await store.flush();
}

export async function loadWebPwaEntry(
  context: StoreContext,
  url: string,
  reloadFromDisk: boolean = false
): Promise<WebPwaEntry | undefined> {
  const normalizedUrl = normalizeWebUrlForStore(url);
  if (normalizedUrl.length === 0) {
    return undefined;
  }
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  const entries = parseWebPwaEntries(await store.get(WEB_PWA_ENTRIES_KEY, '') as string);
  for (let index = 0; index < entries.length; index++) {
    const entry = entries[index];
    if (entry.url === normalizedUrl || entry.startUrl === normalizedUrl ||
      (entry.scope.length > 0 && normalizedUrl.startsWith(entry.scope))) {
      return entry;
    }
  }
  return undefined;
}

export async function saveWebHistoryUrl(context: StoreContext, url: string, title: string = ''): Promise<void> {
  const normalizedUrl = normalizeWebUrlForStore(url);
  const comparableUrl = normalizeWebHistoryComparableUrl(normalizedUrl);
  if (comparableUrl.length === 0) {
    return;
  }

  const store = await getMainStoreForWrite(context);
  const entries = parseWebHistoryEntries(await store.get(WEB_HISTORY_KEY, '') as string);
  const normalizedTitle = title.trim();
  const next: WebHistoryEntry[] = [{
    url: normalizedUrl,
    title: normalizedTitle,
    updatedAt: Date.now()
  }];
  for (let index = 0; index < entries.length && next.length < MAX_WEB_HISTORY_ENTRIES; index++) {
    const entry = entries[index];
    if (normalizeWebHistoryComparableUrl(entry.url) !== comparableUrl) {
      next.push(entry);
    }
  }
  await store.put(WEB_HISTORY_KEY, JSON.stringify(next));
  await store.flush();
}

export async function loadWebHistory(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<WebHistoryEntry[]> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  return parseWebHistoryEntries(await store.get(WEB_HISTORY_KEY, '') as string);
}

export async function deleteWebHistoryUrl(context: StoreContext, url: string): Promise<void> {
  const normalizedUrl = normalizeWebUrlForStore(url);
  const comparableUrl = normalizeWebHistoryComparableUrl(normalizedUrl);
  if (comparableUrl.length === 0) {
    return;
  }

  const store = await getMainStoreForWrite(context);
  const entries = parseWebHistoryEntries(await store.get(WEB_HISTORY_KEY, '') as string);
  const next: WebHistoryEntry[] = [];
  for (let index = 0; index < entries.length; index++) {
    const entry = entries[index];
    if (normalizeWebHistoryComparableUrl(entry.url) !== comparableUrl) {
      next.push(entry);
    }
  }
  await store.put(WEB_HISTORY_KEY, JSON.stringify(next));
  await store.flush();
}

export async function deleteWebBookmark(
  context: StoreContext,
  bookmarkId: string,
  url: string = ''
): Promise<void> {
  const id = normalizeShortcutId(bookmarkId);
  const normalizedUrl = normalizeWebUrlForStore(url);
  if (id.length === 0 && normalizedUrl.length === 0) {
    return;
  }

  const store = await getMainStoreForWrite(context);
  const bookmarks = parseWebBookmarks(await store.get(WEB_BOOKMARKS_KEY, '') as string);
  const next: WebBookmarkEntry[] = [];
  for (let index = 0; index < bookmarks.length; index++) {
    const bookmark = bookmarks[index];
    if ((id.length > 0 && bookmark.id === id) || (normalizedUrl.length > 0 && bookmark.url === normalizedUrl)) {
      continue;
    }
    next.push(bookmark);
  }
  await store.put(WEB_BOOKMARKS_KEY, JSON.stringify(next));
  await store.flush();
  hilog.info(DOMAIN, TAG, 'delete web bookmark id=%{public}s', id);
}

export async function saveLastWebUrl(context: StoreContext, url: string): Promise<void> {
  const store = await getMainStoreForWrite(context);
  await store.put(WEB_LAST_URL_KEY, normalizeWebUrlForStore(url));
  await store.flush();
}

export async function loadLastWebUrl(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<string> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
  const lastUrl = normalizeWebUrlForStore(await store.get(WEB_LAST_URL_KEY, '') as string);
  if (lastUrl.length > 0) {
    return lastUrl;
  }
  return await loadPinnedWebUrl(context, false);
}

async function removeStoreFromCache(context: StoreContext): Promise<void> {
  await removePreferencesStoreFromCache(context, STORE_NAME);
}

async function removeLogStoreFromCache(context: StoreContext): Promise<void> {
  await removePreferencesStoreFromCache(context, LOG_STORE_NAME);
}

async function removePreferencesStoreFromCache(context: StoreContext, storeName: string): Promise<void> {
  try {
    await preferences.removePreferencesFromCache(context, storeName);
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

function normalizeWebUrlForStore(value: string): string {
  return stringValue(value).trim();
}

function normalizeWebHistoryComparableUrl(value: string): string {
  const normalized = normalizeWebUrlForStore(value);
  if (!isWebBookmarkUrl(normalized)) {
    return '';
  }
  try {
    const parsed = url.URL.parseURL(normalized);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return '';
    }
    if (parsed.hostname.trim().length === 0) {
      return '';
    }
    return parsed.toString();
  } catch (err) {
    return normalized;
  }
}

function normalizeShortcutId(value: string): string {
  return stringValue(value).trim();
}

function isWebBookmarkUrl(value: string): boolean {
  const normalized = normalizeWebUrlForStore(value);
  return normalized.startsWith('http://') || normalized.startsWith('https://');
}

async function putWebBookmark(store: preferences.Preferences, entry: WebBookmarkEntry): Promise<boolean> {
  const normalizedUrl = normalizeWebUrlForStore(entry.url);
  if (!isWebBookmarkUrl(normalizedUrl)) {
    return false;
  }

  const normalizedEntry: WebBookmarkEntry = {
    id: entry.id.length > 0 ? entry.id : stableWebBookmarkId(normalizedUrl),
    url: normalizedUrl,
    title: entry.title.trim().length > 0 ? entry.title.trim() : webBookmarkTitle(normalizedUrl),
    updatedAt: entry.updatedAt > 0 ? entry.updatedAt : Date.now()
  };
  const bookmarks = parseWebBookmarks(await store.get(WEB_BOOKMARKS_KEY, '') as string);
  for (let index = 0; index < bookmarks.length; index++) {
    const bookmark = bookmarks[index];
    if (bookmark.url === normalizedEntry.url || bookmark.id === normalizedEntry.id) {
      return false;
    }
  }
  const next: WebBookmarkEntry[] = [];
  for (let index = 0; index < bookmarks.length; index++) {
    next.push(bookmarks[index]);
  }
  next.push(normalizedEntry);
  await store.put(WEB_BOOKMARKS_KEY, JSON.stringify(next));
  return true;
}

function parseWebBookmarks(value: string): WebBookmarkEntry[] {
  try {
    const parsed = JSON.parse(value) as WebBookmarkEntry[];
    if (!Array.isArray(parsed)) {
      return [];
    }
    const result: WebBookmarkEntry[] = [];
    for (let index = 0; index < parsed.length; index++) {
      const item = parsed[index] as WebBookmarkEntry;
      const url = normalizeWebUrlForStore(item.url);
      if (url.length === 0) {
        continue;
      }
      let id = normalizeShortcutId(item.id).length > 0 ? normalizeShortcutId(item.id) : stableWebBookmarkId(url);
      for (let resultIndex = 0; resultIndex < result.length; resultIndex++) {
        if (result[resultIndex].id === id && result[resultIndex].url !== url) {
          id = stableWebBookmarkId(url);
          break;
        }
      }
      result.push({
        id: id,
        url: url,
        title: stringValue(item.title).trim().length > 0 ? stringValue(item.title).trim() : webBookmarkTitle(url),
        updatedAt: typeof item.updatedAt === 'number' && !isNaN(item.updatedAt) ? item.updatedAt : 0
      });
    }
    return result;
  } catch (err) {
    return [];
  }
}

function normalizeWebPwaEntry(entry: WebPwaEntry): WebPwaEntry {
  return {
    url: normalizeWebUrlForStore(entry.url),
    startUrl: normalizeWebUrlForStore(entry.startUrl),
    scope: normalizeWebUrlForStore(entry.scope),
    display: stringValue(entry.display).trim().toLowerCase(),
    name: stringValue(entry.name).trim(),
    manifestUrl: normalizeWebUrlForStore(entry.manifestUrl),
    updatedAt: typeof entry.updatedAt === 'number' && !isNaN(entry.updatedAt) && entry.updatedAt > 0 ?
      entry.updatedAt : Date.now()
  };
}

function parseWebPwaEntries(value: string): WebPwaEntry[] {
  try {
    const parsed = JSON.parse(value) as WebPwaEntry[];
    if (!Array.isArray(parsed)) {
      return [];
    }
    const result: WebPwaEntry[] = [];
    for (let index = 0; index < parsed.length; index++) {
      const entry = normalizeWebPwaEntry(parsed[index] as WebPwaEntry);
      if (entry.url.length === 0 || entry.startUrl.length === 0 || entry.scope.length === 0 ||
        entry.name.length === 0) {
        continue;
      }
      result.push(entry);
    }
    return result;
  } catch (err) {
    return [];
  }
}

function parseWebHistoryEntries(value: string): WebHistoryEntry[] {
  try {
    const parsed = JSON.parse(value) as WebHistoryEntry[];
    if (!Array.isArray(parsed)) {
      return [];
    }
    const result: WebHistoryEntry[] = [];
    for (let index = 0; index < parsed.length; index++) {
      const item = parsed[index] as WebHistoryEntry;
      const normalizedUrl = normalizeWebUrlForStore(item.url);
      const comparableUrl = normalizeWebHistoryComparableUrl(normalizedUrl);
      if (comparableUrl.length === 0) {
        continue;
      }
      if (result.some((entry: WebHistoryEntry) => {
        return normalizeWebHistoryComparableUrl(entry.url) === comparableUrl;
      })) {
        continue;
      }
      result.push({
        url: normalizedUrl,
        title: stringValue(item.title).trim(),
        updatedAt: typeof item.updatedAt === 'number' && !isNaN(item.updatedAt) ? item.updatedAt : 0
      });
      if (result.length >= MAX_WEB_HISTORY_ENTRIES) {
        break;
      }
    }
    return result;
  } catch (err) {
    return [];
  }
}

function webBookmarkTitle(url: string): string {
  const marker = '://';
  const schemeIndex = url.indexOf(marker);
  if (schemeIndex < 0) {
    return url;
  }
  const start = schemeIndex + marker.length;
  const slashIndex = url.indexOf('/', start);
  const host = slashIndex >= 0 ? url.substring(start, slashIndex) : url.substring(start);
  const atIndex = host.lastIndexOf('@');
  return atIndex >= 0 ? host.substring(atIndex + 1) : host;
}

function stableWebBookmarkId(url: string): string {
  let hash = 2166136261;
  for (let index = 0; index < url.length; index++) {
    hash ^= url.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return 'web_' + (hash >>> 0).toString(16);
}

export function createTunnelId(): string {
  return 'tun_' + String(Date.now()) + '_' + String(Math.floor(Math.random() * 1000000));
}

export async function loadTunnels(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<TunnelConfig[]> {
  const store = await getMainStoreForLoad(context, reloadFromDisk);
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
  const store = await getMainStoreForWrite(context);
  const idsValue = await store.get(TUNNEL_IDS_KEY, '');
  const ids = parseIdList(idsValue as string);
  await saveTunnelToStore(store, tunnel, ids);
}

export async function deleteTunnel(context: common.UIAbilityContext, tunnelId: string): Promise<void> {
  const store = await getMainStoreForWrite(context);
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

async function getMainStoreForWrite(context: StoreContext): Promise<preferences.Preferences> {
  // UIAbility and VpnExtensionAbility both mutate the same preferences file.
  // Reload before writes so a stale cached instance does not flush older values
  // back to disk and overwrite recently saved settings from the other context.
  return await reloadMainStore(context);
}

async function getMainStoreForLoad(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<preferences.Preferences> {
  if (reloadFromDisk) {
    return await reloadMainStore(context);
  }
  return await getMainStore(context);
}

async function getLogStoreForLoad(
  context: StoreContext,
  reloadFromDisk: boolean = false
): Promise<preferences.Preferences> {
  if (reloadFromDisk) {
    return await reloadLogStore(context);
  }
  return await getLogStore(context);
}

async function getLogStoreForWrite(context: StoreContext): Promise<preferences.Preferences> {
  return await reloadLogStore(context);
}

async function getMainStore(context: StoreContext): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context, STORE_NAME);
}

async function getLogStore(context: StoreContext): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context, LOG_STORE_NAME);
}

async function reloadMainStore(context: StoreContext): Promise<preferences.Preferences> {
  await removeStoreFromCache(context);
  return await getMainStore(context);
}

async function reloadLogStore(context: StoreContext): Promise<preferences.Preferences> {
  await removeLogStoreFromCache(context);
  return await getLogStore(context);
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

function formatAgentRuleList(rules: AgentRule[]): string {
  const lines: string[] = [];
  for (let index = 0; index < rules.length; index++) {
    const rule = normalizeAgentRule(rules[index]);
    if (rule.id.length > 0) {
      lines.push(
        encodeURIComponent(rule.id) + '\t' +
        encodeURIComponent(rule.type) + '\t' +
        encodeURIComponent(rule.matchValue) + '\t' +
        encodeURIComponent(rule.targetTunnelId) + '\t' +
        encodeURIComponent(rule.targetTunnelName) + '\t' +
        String(rule.enabled)
      );
    }
  }
  return lines.join('\n');
}

function parseAgentRuleList(rawValue: string): AgentRule[] {
  if (rawValue.length === 0) {
    return [];
  }

  const lines = rawValue.split('\n');
  const rules: AgentRule[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    if (line.length === 0) {
      continue;
    }

    const parts = line.split('\t');
    if (parts.length < 6) {
      continue;
    }

    try {
      const rule: AgentRule = {
        id: decodeURIComponent(parts[0]),
        type: normalizeAgentRuleType(decodeURIComponent(parts[1])),
        matchValue: decodeURIComponent(parts[2]),
        targetTunnelId: decodeURIComponent(parts[3]),
        targetTunnelName: decodeURIComponent(parts[4]),
        enabled: parts[5] === 'true'
      };
      const normalized = normalizeAgentRule(rule);
      if (normalized.id.length > 0) {
        rules.push(normalized);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'parse smart agent rule failed: %{public}s', formatUnknownError(err));
    }
  }
  return rules;
}

function normalizeAgentRule(rule: AgentRule): AgentRule {
  const normalized: AgentRule = {
    id: stringValue(rule.id),
    type: normalizeAgentRuleType(rule.type),
    matchValue: stringValue(rule.matchValue).trim(),
    targetTunnelId: stringValue(rule.targetTunnelId),
    targetTunnelName: stringValue(rule.targetTunnelName).trim(),
    enabled: rule.enabled === true
  };
  return normalized;
}

function normalizeAgentRuleType(value: string): AgentRuleType {
  if (value === 'wifiSsid') {
    return 'wifiSsid';
  }
  if (value === 'ipv6Available') {
    return 'ipv6Available';
  }
  if (value === 'ipv4Available') {
    return 'ipv4Available';
  }
  return 'wifiGateway';
}

function summarizeAgentRules(rules: AgentRule[]): string {
  if (rules.length === 0) {
    return '<empty>';
  }

  const parts: string[] = [];
  for (let index = 0; index < rules.length; index++) {
    const rule = normalizeAgentRule(rules[index]);
    parts.push(
      shortRuleId(rule.id) + ':' +
      rule.type + ':' +
      shortRuleValue(rule.matchValue) + ':' +
      shortRuleValue(rule.targetTunnelId.length > 0 ? rule.targetTunnelId : 'direct') + ':' +
      (rule.enabled ? 'on' : 'off')
    );
  }
  return parts.join('|');
}

function shortRuleId(ruleId: string): string {
  const normalized = stringValue(ruleId);
  if (normalized.length <= 8) {
    return normalized;
  }
  return normalized.substring(normalized.length - 8);
}

function shortRuleValue(value: string): string {
  const normalized = stringValue(value).trim();
  if (normalized.length === 0) {
    return '-';
  }
  if (normalized.length <= 24) {
    return normalized;
  }
  return normalized.substring(0, 24) + '...';
}

async function loadAgentLogsFromStore(store: preferences.Preferences): Promise<AgentLogEntry[]> {
  const rawValue = await store.get(LOG_ENTRIES_KEY, '');
  return parseAgentLogList(rawValue as string);
}

async function loadAgentLogsFromLogStore(
  context: StoreContext,
  logStore: preferences.Preferences
): Promise<AgentLogEntry[]> {
  const clearedAt = await logStore.get(LOG_CLEARED_AT_KEY, 0) as number;
  const entries = await loadAgentLogsFromStore(logStore);
  if (entries.length > 0 || clearedAt > 0) {
    return entries;
  }

  const legacyStore = await getMainStore(context);
  return await loadAgentLogsFromStore(legacyStore);
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

function normalizedTargetName(tunnelName: string): string {
  const normalized = tunnelName.trim();
  if (normalized.length > 0) {
    return normalized;
  }
  return '直连';
}

function normalizedTriggerReason(trigger: string): string {
  const normalized = trigger.trim();
  if (normalized.length > 0) {
    return normalized;
  }
  return '网络变化';
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
