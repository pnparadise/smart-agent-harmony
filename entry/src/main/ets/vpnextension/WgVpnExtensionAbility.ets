import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { buffer } from '@kit.ArkTS';
import { connection, vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ActiveTunnelInfo,
  appendAgentLog,
  buildVpnNativeFailureLogEntry,
  buildSmartAgentSwitchLogEntry,
  buildVpnRestartLogEntry,
  DEFAULT_DOH_PROVIDER,
  hasActiveTunnelSelection,
  isVpnKeepAliveEnabled,
  loadAppSplitEnabled,
  loadActiveTunnelInfo,
  loadDohSettings,
  loadVpnKeepAliveSettings,
  loadSelectedSplitApps,
  loadSmartAgentEnabled,
  saveTunnelRuntimeStatus,
  SplitAppInfo,
  TunnelRuntimeStatus,
  VpnKeepAliveSettings
} from '../wireguard/ConfigStore';
import { SmartAgentDecision, SmartAgentStrategy } from '../wireguard/SmartAgentStrategy';
import {
  hasIPv4,
  hasIPv6,
  parseCidr,
  parseWireGuardConfig,
  ParsedCidr,
  WireGuardConfig
} from '../wireguard/WireGuardConfig';
import { NativeTunnel, TunnelStats } from '../wireguard/NativeTunnel';
import { updateVpnDataTransferNotification } from '../wireguard/VpnBackgroundTask';
import { queryVpnNetworkAvailable } from '../wireguard/VpnNetworkMonitor';

const DOMAIN = 0x0001;
const TAG = 'WgVpnExtension';
const VPN_INTERFACE = 'vpn-tun';
const BUNDLE_NAME = 'com.smart.agent';
const FORCE_HANDSHAKE_DEBOUNCE_MS = 1500;
const DATA_TRANSFER_NOTIFICATION_INTERVAL_MS = 5000;
const RUNTIME_STATUS_PUBLISH_INTERVAL_MS = 3000;
const NATIVE_TUNNEL_HEALTH_INTERVAL_MS = 250;
const WANT_ACTION_RESTORE = 'restore';
const WANT_ACTION_NETWORK_LOST = 'networkLost';
const DOH_RESOLVE_TIMEOUT_MS = 8000;

interface DnsJsonAnswer {
  data?: string;
  type?: number;
}

interface DnsJsonResponse {
  Answer?: DnsJsonAnswer[];
}

interface LoggedVpnConfig extends vpnExtension.VpnConfig {
  trustedApplications?: string[];
  blockedApplications?: string[];
}

interface DesiredVpnState {
  activeInfo: ActiveTunnelInfo;
  appSplitEnabled: boolean;
  selectedSplitApps: SplitAppInfo[];
  smartAgentEnabled: boolean;
  decisionSummary: string;
  fingerprint: string;
}

export default class WgVpnExtensionAbility extends VpnExtensionAbility {
  private vpnConnection?: vpnExtension.VpnConnection;
  private netConnection?: connection.NetConnection;
  private tunnelHandle: number = 0;
  private activeTunnelId: string = '';
  private activeTunnelName: string = '';
  private runningConfigFingerprint: string = '';
  private restartQueue: Promise<void> = Promise.resolve();
  private restartRequestCount: number = 0;
  private lastForceHandshakeAt: number = 0;
  private dataTransferNotificationTimer: number = -1;
  private runtimeStatusPublishTimer: number = -1;
  private nativeTunnelHealthTimer: number = -1;
  private lastNotifiedTxBytes: number = -1;
  private lastNotifiedRxBytes: number = -1;
  private lastLoggedTunReadPackets: number = -1;
  private lastLoggedTunDroppedPackets: number = -1;
  private lastLoggedUdpReadPackets: number = -1;
  private networkStrategyInFlight: boolean = false;
  private nativeTunnelDeathLogged: boolean = false;
  private nativeTunnelRecoveryInFlight: boolean = false;
  private lastRecoveredLostNetId: number = -1;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'WgVpnExtension onCreate');
    this.restartWireGuard('onCreate', false).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'start failed: %{public}s', this.formatError(err));
      this.cleanup().catch((cleanupErr: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'cleanup after start failure failed: %{public}s', this.formatError(cleanupErr));
      });
    });
  }

  onRequest(want: Want, startId: number): void {
    hilog.info(DOMAIN, TAG, 'WgVpnExtension onRequest startId=%{public}d ability=%{public}s', startId, want.abilityName ?? '');
    if (this.isNetworkLostWant(want)) {
      this.recoverVpnNetwork(want);
      return;
    }
    if (this.isRestoreWant(want)) {
      if (this.restartRequestCount > 0 || this.nativeTunnelRecoveryInFlight) {
        hilog.info(
          DOMAIN,
          TAG,
          'skip restore request, recovery pending pendingRestarts=%{public}d nativeRecovery=%{public}s',
          this.restartRequestCount,
          String(this.nativeTunnelRecoveryInFlight)
        );
        return;
      }
      if (this.tunnelHandle !== 0 && queryVpnNetworkAvailable() !== false) {
        this.publishRuntimeStatus(true, true).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'publish restore status failed: %{public}s', this.formatError(err));
        });
        hilog.info(DOMAIN, TAG, 'skip restore request, vpn network and native handle available');
        return;
      }
      if (this.tunnelHandle !== 0) {
        hilog.warn(DOMAIN, TAG, 'restore request detected missing vpn network, rebuild native handle=%{public}d', this.tunnelHandle);
      }
    }

    this.restartWireGuard('onRequest', true).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'restart failed: %{public}s', this.formatError(err));
      this.cleanup().catch((cleanupErr: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'cleanup after restart failure failed: %{public}s', this.formatError(cleanupErr));
      });
    });
  }

  private recoverVpnNetwork(want: Want): void {
    const lostNetId = this.wantNumber(want, 'lostNetId');
    if (this.restartRequestCount > 0 || this.nativeTunnelRecoveryInFlight ||
      (lostNetId >= 0 && lostNetId === this.lastRecoveredLostNetId)) {
      hilog.info(
        DOMAIN,
        TAG,
        'skip vpn network recovery lostNetId=%{public}d pendingRestarts=%{public}d nativeRecovery=%{public}s',
        lostNetId,
        this.restartRequestCount,
        String(this.nativeTunnelRecoveryInFlight)
      );
      return;
    }
    this.restartWireGuard('vpn-network-lost:' + String(lostNetId), true).then(() => {
      if (lostNetId >= 0) {
        this.lastRecoveredLostNetId = lostNetId;
      }
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'vpn network recovery failed: %{public}s', this.formatError(err));
      this.cleanup().catch((cleanupErr: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'cleanup after vpn network recovery failed: %{public}s', this.formatError(cleanupErr));
      });
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'WgVpnExtension onDestroy');
    this.cleanup(false).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'cleanup on destroy failed: %{public}s', this.formatError(err));
    });
  }

  private async restartWireGuard(
    reason: string,
    cleanupFirst: boolean,
    desiredState?: DesiredVpnState
  ): Promise<void> {
    this.restartRequestCount++;
    const task = this.restartQueue.then(() => {
      return this.doRestartWireGuard(reason, cleanupFirst, desiredState);
    });
    this.restartQueue = task.catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restart queue task failed: %{public}s', this.formatError(err));
    });
    try {
      await task;
    } finally {
      this.restartRequestCount--;
    }
  }

  private async doRestartWireGuard(
    reason: string,
    cleanupFirst: boolean,
    desiredState?: DesiredVpnState
  ): Promise<void> {
    const effectiveDesiredState = desiredState === undefined ? await this.resolveDesiredVpnState() : desiredState;
    hilog.info(
      DOMAIN,
      TAG,
      'restartWireGuard reason=%{public}s cleanupFirst=%{public}s handle=%{public}d activeId=%{public}s desiredId=%{public}s',
      reason,
      String(cleanupFirst),
      this.tunnelHandle,
      this.activeTunnelId,
      effectiveDesiredState.activeInfo.id
    );
    if (this.canReuseRunningTunnel(effectiveDesiredState)) {
      this.activeTunnelId = effectiveDesiredState.activeInfo.id;
      this.activeTunnelName = effectiveDesiredState.activeInfo.name;
      hilog.info(DOMAIN, TAG, 'skip restart, running vpn config unchanged reason=%{public}s', reason);
      await this.publishRuntimeStatus(true, true);
      return;
    }
    if (cleanupFirst || this.tunnelHandle !== 0 || this.vpnConnection !== undefined) {
      await this.cleanup(false);
    }
    await this.startWireGuard(effectiveDesiredState);
  }

  private async startWireGuard(desiredState?: DesiredVpnState): Promise<void> {
    hilog.info(DOMAIN, TAG, 'WgVpnExtension startWireGuard begin');

    const desired = desiredState === undefined ? await this.resolveDesiredVpnState() : desiredState;
    const activeInfo = desired.activeInfo;
    this.activeTunnelId = activeInfo.id;
    this.activeTunnelName = activeInfo.name;
    hilog.info(
      DOMAIN,
      TAG,
      'active tunnel resolved id=%{public}s name=%{public}s configBytes=%{public}d',
      this.activeTunnelId,
      this.activeTunnelName,
      activeInfo.configText.length
    );
    hilog.info(
      DOMAIN,
      TAG,
      'desired state smartAgentEnabled=%{public}s decision=%{public}s',
      String(desired.smartAgentEnabled),
      desired.decisionSummary
    );
    if (activeInfo.configText.length === 0) {
      hilog.info(DOMAIN, TAG, 'skip tunnel start, no active config after strategy decision');
      this.startNetworkObserver();
      await this.publishRuntimeStatus(false, false);
      return;
    }

    const rawConfig = activeInfo.configText;
    hilog.info(DOMAIN, TAG, 'config resolved, bytes=%{public}d', rawConfig.length);

    const config = parseWireGuardConfig(rawConfig);
    hilog.info(
      DOMAIN,
      TAG,
      'config parsed, addresses=%{public}d routes=%{public}d dns=%{public}d mtu=%{public}d',
      config.iface.addresses.length,
      config.peer.allowedIPs.length,
      config.iface.dns.length,
      config.iface.mtu
    );
    hilog.info(DOMAIN, TAG, 'interface addresses=%{public}s', config.iface.addresses.join(','));
    hilog.info(DOMAIN, TAG, 'interface dns=%{public}s', config.iface.dns.join(','));
    hilog.info(DOMAIN, TAG, 'peer allowedIPs=%{public}s', config.peer.allowedIPs.join(','));
    hilog.info(
      DOMAIN,
      TAG,
      'peer endpoint host=%{public}s port=%{public}d keepalive=%{public}d',
      config.peer.endpointHost,
      config.peer.endpointPort,
      config.peer.persistentKeepalive
    );

    this.vpnConnection = vpnExtension.createVpnConnection(this.context);
    hilog.info(DOMAIN, TAG, 'vpn connection created');

    const endpointHost = await this.resolveEndpointHost(config.peer.endpointHost);
    hilog.info(
      DOMAIN,
      TAG,
      'endpoint resolved original=%{public}s selected=%{public}s',
      config.peer.endpointHost,
      endpointHost
    );

    this.tunnelHandle = NativeTunnel.create(config, endpointHost);
    hilog.info(DOMAIN, TAG, 'native tunnel created, handle=%{public}d', this.tunnelHandle);

    try {
      const socketFd = NativeTunnel.getSocketFd(this.tunnelHandle);
      hilog.info(DOMAIN, TAG, 'native socket fd=%{public}d', socketFd);

      await this.vpnConnection.protect(socketFd);
      hilog.info(DOMAIN, TAG, 'native socket protected');

      const vpnConfig = this.buildVpnConfig(config, desired.appSplitEnabled, desired.selectedSplitApps);
      const vpnMtu = vpnConfig.mtu === undefined ? 0 : vpnConfig.mtu;
      const loggedVpnConfig = vpnConfig as LoggedVpnConfig;
      const trustedApplications =
        loggedVpnConfig.trustedApplications === undefined ? [] : loggedVpnConfig.trustedApplications;
      hilog.info(
        DOMAIN,
        TAG,
        'vpn config built, addresses=%{public}d routes=%{public}d dns=%{public}d mtu=%{public}d ipv4=%{public}s ipv6=%{public}s appSplit=%{public}s trustedApps=%{public}d',
        vpnConfig.addresses.length,
        vpnConfig.routes === undefined ? 0 : vpnConfig.routes.length,
        vpnConfig.dnsAddresses === undefined ? 0 : vpnConfig.dnsAddresses.length,
        vpnMtu,
        String(vpnConfig.isIPv4Accepted),
        String(vpnConfig.isIPv6Accepted),
        String(desired.appSplitEnabled),
        trustedApplications.length
      );
      this.logVpnConfigDetails(vpnConfig);

      const tunFd = await this.vpnConnection.create(vpnConfig);
      hilog.info(DOMAIN, TAG, 'vpn tun created, fd=%{public}d', tunFd);

      NativeTunnel.start(this.tunnelHandle, tunFd);
      hilog.info(DOMAIN, TAG, 'WgVpnExtension native tunnel started');
      this.runningConfigFingerprint = desired.fingerprint;
      this.nativeTunnelDeathLogged = false;
      this.appendVpnRestartLog(this.activeTunnelName, Date.now());
      this.startNetworkObserver();
      this.startDataTransferNotificationUpdates();
      this.startRuntimeStatusPublishUpdates();
      this.startNativeTunnelHealthMonitor();
      this.publishRuntimeStatus(true, true).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'publish initial runtime status failed: %{public}s', this.formatError(err));
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'start stage failed: %{public}s', this.formatError(error));
      await this.cleanup();
      throw new Error('Failed to start WireGuard tunnel: ' + this.formatError(error));
    }
    hilog.info(DOMAIN, TAG, 'WgVpnExtension WireGuard tunnel started');
  }

  private appendVpnRestartLog(tunnelName: string, createdAt: number): void {
    appendAgentLog(
      this.context as common.VpnExtensionContext,
      buildVpnRestartLogEntry(tunnelName, createdAt)
    ).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'append vpn restart log failed: %{public}s', this.formatError(err));
    });
  }

  private appendSmartAgentSwitchLog(trigger: string, fromTunnelName: string, toTunnelName: string): void {
    if (fromTunnelName.trim() === toTunnelName.trim()) {
      return;
    }
    appendAgentLog(
      this.context as common.VpnExtensionContext,
      buildSmartAgentSwitchLogEntry(trigger, fromTunnelName, toTunnelName, Date.now())
    ).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'append smart agent switch log failed: %{public}s', this.formatError(err));
    });
  }

  private async resolveDesiredVpnState(): Promise<DesiredVpnState> {
    const activeInfo = await this.resolveActiveTunnelInfo();
    const appSplitEnabled = await loadAppSplitEnabled(this.context as common.VpnExtensionContext, true);
    const selectedSplitApps = await loadSelectedSplitApps(this.context as common.VpnExtensionContext, true);
    return {
      activeInfo: activeInfo,
      appSplitEnabled: appSplitEnabled,
      selectedSplitApps: selectedSplitApps,
      smartAgentEnabled: false,
      decisionSummary: 'manual active tunnel',
      fingerprint: this.buildVpnStateFingerprint(activeInfo, appSplitEnabled, selectedSplitApps)
    };
  }

  private async resolveDesiredVpnStateForDecision(decision: SmartAgentDecision): Promise<DesiredVpnState> {
    const appSplitEnabled = await loadAppSplitEnabled(this.context as common.VpnExtensionContext, true);
    const selectedSplitApps = await loadSelectedSplitApps(this.context as common.VpnExtensionContext, true);
    return {
      activeInfo: decision.selectedActiveInfo,
      appSplitEnabled: appSplitEnabled,
      selectedSplitApps: selectedSplitApps,
      smartAgentEnabled: true,
      decisionSummary: decision.summary,
      fingerprint: this.buildVpnStateFingerprint(decision.selectedActiveInfo, appSplitEnabled, selectedSplitApps)
    };
  }

  private canReuseRunningTunnel(desiredState: DesiredVpnState): boolean {
    return this.tunnelHandle !== 0 &&
      this.vpnConnection !== undefined &&
      this.isCurrentNativeTunnelAlive() &&
      this.runningConfigFingerprint.length > 0 &&
      this.runningConfigFingerprint === desiredState.fingerprint;
  }

  private isCurrentNativeTunnelAlive(): boolean {
    if (this.tunnelHandle === 0) {
      return false;
    }
    try {
      return NativeTunnel.isAlive(this.tunnelHandle);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'native tunnel alive query failed: %{public}s', this.formatError(error));
      return false;
    }
  }

  private buildVpnStateFingerprint(
    activeInfo: ActiveTunnelInfo,
    appSplitEnabled: boolean,
    selectedSplitApps: SplitAppInfo[]
  ): string {
    return this.joinFingerprintParts([
      activeInfo.configText,
      String(appSplitEnabled),
      this.normalizedSplitBundleNames(selectedSplitApps).join(',')
    ]);
  }

  private normalizedSplitBundleNames(apps: SplitAppInfo[]): string[] {
    const bundleNames: string[] = [];
    for (let index = 0; index < apps.length; index++) {
      const bundleName = apps[index].bundleName.trim();
      if (bundleName.length > 0 && !this.hasBundleName(bundleNames, bundleName)) {
        bundleNames.push(bundleName);
      }
    }
    bundleNames.sort();
    return bundleNames;
  }

  private joinFingerprintParts(parts: string[]): string {
    const encodedParts: string[] = [];
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      encodedParts.push(String(part.length) + ':' + part);
    }
    return encodedParts.join('|');
  }

  private async resolveActiveTunnelInfo(): Promise<ActiveTunnelInfo> {
    const activeInfo = await loadActiveTunnelInfo(this.context as common.VpnExtensionContext, true);
    if (hasActiveTunnelSelection(activeInfo)) {
      hilog.info(DOMAIN, TAG, 'using active tunnel config id=%{public}s name=%{public}s', activeInfo.id, activeInfo.name);
      return activeInfo;
    }

    const emptyInfo: ActiveTunnelInfo = {
      id: '',
      name: '',
      configText: ''
    };
    hilog.info(DOMAIN, TAG, 'no active tunnel selected, keep direct connection');
    return emptyInfo;
  }

  private async resolveSmartAgentDecision(): Promise<SmartAgentDecision> {
    const strategy = new SmartAgentStrategy(this.context as common.VpnExtensionContext);
    return await strategy.resolveDecision();
  }

  private async resolveEndpointHost(host: string): Promise<string> {
    const normalized = host.trim();
    if (this.isIpAddress(normalized)) {
      return normalized;
    }

    const dohResolved = await this.resolveEndpointHostViaDoh(normalized);
    if (dohResolved.length > 0) {
      return dohResolved;
    }

    const addresses = await connection.getAddressesByName(normalized);
    if (addresses.length === 0) {
      throw new Error('endpoint did not resolve: ' + normalized);
    }

    for (let index = 0; index < addresses.length; index++) {
      const address = addresses[index].address;
      if (address.length > 0 && address.indexOf(':') < 0) {
        return address;
      }
    }
    return addresses[0].address;
  }

  private async resolveEndpointHostViaDoh(host: string): Promise<string> {
    const settings = await loadDohSettings(this.context as common.VpnExtensionContext, true);
    if (!settings.enabled) {
      return '';
    }

    const provider = this.normalizeDohProvider(settings.provider);
    if (provider.length === 0) {
      return '';
    }

    const ipv4 = await this.queryDohAddress(provider, host, 'A');
    if (ipv4.length > 0) {
      hilog.info(DOMAIN, TAG, 'endpoint doh resolved host=%{public}s type=A value=%{public}s', host, ipv4);
      return ipv4;
    }

    const ipv6 = await this.queryDohAddress(provider, host, 'AAAA');
    if (ipv6.length > 0) {
      hilog.info(DOMAIN, TAG, 'endpoint doh resolved host=%{public}s type=AAAA value=%{public}s', host, ipv6);
      return ipv6;
    }

    return '';
  }

  private async queryDohAddress(provider: string, host: string, recordType: string): Promise<string> {
    const request = http.createHttp();
    const requestUrl = provider + '?name=' + encodeURIComponent(host) + '&type=' + encodeURIComponent(recordType);
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: true,
        readTimeout: DOH_RESOLVE_TIMEOUT_MS,
        connectTimeout: DOH_RESOLVE_TIMEOUT_MS,
        header: {
          Accept: 'application/dns-json, application/json, text/plain, */*'
        }
      };
      const response = await request.request(requestUrl, options);
      if (response.responseCode < http.ResponseCode.OK || response.responseCode >= 300 ||
        response.resultType !== http.HttpDataType.ARRAY_BUFFER) {
        return '';
      }
      const text = buffer.from(new Uint8Array(response.result as ArrayBuffer)).toString('utf8');
      const payload = JSON.parse(text) as DnsJsonResponse;
      if (!Array.isArray(payload.Answer)) {
        return '';
      }
      for (let index = 0; index < payload.Answer.length; index++) {
        const answer = payload.Answer[index];
        if (answer === undefined || answer.data === undefined || answer.type === undefined) {
          continue;
        }
        if ((recordType === 'A' && answer.type === 1) || (recordType === 'AAAA' && answer.type === 28)) {
          const value = answer.data.trim();
          if (value.length > 0) {
            return value;
          }
        }
      }
      return '';
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'endpoint doh query failed host=%{public}s type=%{public}s error=%{public}s',
        host, recordType, this.formatError(error));
      return '';
    } finally {
      request.destroy();
    }
  }

  private normalizeDohProvider(value: string): string {
    const provider = value.trim();
    if (provider.length === 0) {
      return DEFAULT_DOH_PROVIDER;
    }
    return provider;
  }

  private isIpAddress(value: string): boolean {
    if (value.indexOf(':') >= 0) {
      return true;
    }
    const parts = value.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      if (part.length === 0 || part.length > 3) {
        return false;
      }
      const parsed = Number(part);
      if (!Number.isInteger(parsed) || parsed < 0 || parsed > 255) {
        return false;
      }
    }
    return true;
  }

  private buildVpnConfig(
    config: WireGuardConfig,
    appSplitEnabled: boolean,
    selectedSplitApps: SplitAppInfo[]
  ): vpnExtension.VpnConfig {
    const ipv4Accepted = hasIPv4(config);
    const ipv6Accepted = hasIPv6(config);
    const addresses: vpnExtension.LinkAddress[] = config.iface.addresses.map((value: string) => {
      const parsed: ParsedCidr = parseCidr(value);
      return this.buildLinkAddress(parsed);
    });

    const routes: vpnExtension.RouteInfo[] = config.peer.allowedIPs
      .map((value: string) => parseCidr(value))
      .filter((parsed: ParsedCidr) => (parsed.family === 1 && ipv4Accepted) || (parsed.family === 2 && ipv6Accepted))
      .map((parsed: ParsedCidr) => this.buildRoute(parsed, addresses));

    const vpnConfig: vpnExtension.VpnConfig = {
      addresses: addresses,
      routes: routes,
      dnsAddresses: config.iface.dns,
      mtu: config.iface.mtu,
      isIPv4Accepted: ipv4Accepted,
      isIPv6Accepted: ipv6Accepted,
      isInternal: false,
      isBlocking: false
    };
    const trustedApplications = this.splitAppBundleNames(selectedSplitApps);
    if (appSplitEnabled && trustedApplications.length > 0) {
      vpnConfig.trustedApplications = trustedApplications;
    } else if (appSplitEnabled) {
      hilog.warn(DOMAIN, TAG, 'app split enabled but no selected apps, vpn runs in global mode');
    }
    return vpnConfig;
  }

  private splitAppBundleNames(apps: SplitAppInfo[]): string[] {
    const bundleNames: string[] = [];
    for (let index = 0; index < apps.length; index++) {
      const bundleName = apps[index].bundleName;
      if (bundleName.length > 0 && !this.hasBundleName(bundleNames, bundleName)) {
        bundleNames.push(bundleName);
      }
    }
    if (!this.hasBundleName(bundleNames, BUNDLE_NAME)) {
      bundleNames.push(BUNDLE_NAME);
    }
    return bundleNames;
  }

  private hasBundleName(bundleNames: string[], bundleName: string): boolean {
    for (let index = 0; index < bundleNames.length; index++) {
      if (bundleNames[index] === bundleName) {
        return true;
      }
    }
    return false;
  }

  private buildNetAddress(address: string, family: number): connection.NetAddress {
    const netAddress: connection.NetAddress = {
      address: address,
      family: family,
      port: 0
    };
    return netAddress;
  }

  private buildLinkAddress(parsed: ParsedCidr): vpnExtension.LinkAddress {
    const linkAddress: vpnExtension.LinkAddress = {
      address: this.buildNetAddress(parsed.address, parsed.family),
      prefixLength: parsed.prefixLength
    };
    return linkAddress;
  }

  private buildRoute(parsed: ParsedCidr, addresses: vpnExtension.LinkAddress[]): vpnExtension.RouteInfo {
    const gateway = this.findGatewayAddress(parsed.family, addresses);
    const route: vpnExtension.RouteInfo = {
      'interface': VPN_INTERFACE,
      destination: this.buildLinkAddress(parsed),
      gateway: this.buildNetAddress(gateway, parsed.family),
      hasGateway: true,
      isDefaultRoute: parsed.prefixLength === 0
    };
    return route;
  }

  private findGatewayAddress(family: number, addresses: vpnExtension.LinkAddress[]): string {
    for (let index = 0; index < addresses.length; index++) {
      const address = addresses[index].address;
      if (address.family === family && address.address.length > 0) {
        return address.address;
      }
    }
    return family === 1 ? '0.0.0.0' : '::';
  }

  private logVpnConfigDetails(vpnConfig: vpnExtension.VpnConfig): void {
    const loggedConfig = vpnConfig as LoggedVpnConfig;
    const addresses = vpnConfig.addresses
      .map((value: vpnExtension.LinkAddress) => this.formatLinkAddress(value))
      .join(',');
    const routes = (vpnConfig.routes === undefined ? [] : vpnConfig.routes)
      .map((value: vpnExtension.RouteInfo) => this.formatRoute(value))
      .join(',');
    const dns = vpnConfig.dnsAddresses === undefined ? '' : vpnConfig.dnsAddresses.join(',');
    hilog.info(DOMAIN, TAG, 'vpn config detail addresses=%{public}s', addresses);
    hilog.info(DOMAIN, TAG, 'vpn config detail routes=%{public}s', routes);
    hilog.info(DOMAIN, TAG, 'vpn config detail dns=%{public}s', dns);
    hilog.error(
      DOMAIN,
      TAG,
      'VPNCONFIG addresses=%{public}s routes=%{public}s dns=%{public}s ipv4=%{public}s ipv6=%{public}s trustedApplications=%{public}s blockedApplications=%{public}s',
      this.formatEmptyList(addresses),
      this.formatEmptyList(routes),
      this.formatEmptyList(dns),
      String(vpnConfig.isIPv4Accepted),
      String(vpnConfig.isIPv6Accepted),
      this.formatApplicationList(loggedConfig.trustedApplications),
      this.formatApplicationList(loggedConfig.blockedApplications)
    );
    hilog.info(
      DOMAIN,
      TAG,
      'vpn config detail trustedApplications=%{public}s',
      this.formatApplicationList(loggedConfig.trustedApplications)
    );
    hilog.info(
      DOMAIN,
      TAG,
      'vpn config detail blockedApplications=%{public}s',
      this.formatApplicationList(loggedConfig.blockedApplications)
    );
  }

  private formatLinkAddress(value: vpnExtension.LinkAddress): string {
    return value.address.address + '/' + String(value.prefixLength);
  }

  private formatRoute(value: vpnExtension.RouteInfo): string {
    return this.formatLinkAddress(value.destination) +
      ',gateway=' + value.gateway.address +
      ',hasGateway=' + String(value.hasGateway) +
      ',default=' + String(value.isDefaultRoute);
  }

  private formatApplicationList(applications: string[] | undefined): string {
    if (applications === undefined || applications.length === 0) {
      return '<none>';
    }
    return applications.join(',');
  }

  private formatEmptyList(value: string): string {
    if (value.length === 0) {
      return '<none>';
    }
    return value;
  }

  private async cleanup(publishStopped: boolean = true): Promise<void> {
    hilog.info(
      DOMAIN,
      TAG,
      'WgVpnExtension cleanup begin handle=%{public}d hasConnection=%{public}s activeId=%{public}s publishStopped=%{public}s',
      this.tunnelHandle,
      String(this.vpnConnection !== undefined),
      this.activeTunnelId,
      String(publishStopped)
    );
    this.stopNetworkObserver();
    this.stopDataTransferNotificationUpdates();
    this.stopRuntimeStatusPublishUpdates();
    this.stopNativeTunnelHealthMonitor();
    this.lastForceHandshakeAt = 0;
    this.runningConfigFingerprint = '';
    this.nativeTunnelDeathLogged = false;

    if (this.tunnelHandle !== 0) {
      hilog.info(DOMAIN, TAG, 'WgVpnExtension stopping native tunnel');
      NativeTunnel.stop(this.tunnelHandle);
      this.tunnelHandle = 0;
    }

    if (publishStopped) {
      this.publishRuntimeStatus(false, false).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'publish stopped status failed: %{public}s', this.formatError(err));
      });
    }

    if (this.vpnConnection !== undefined) {
      const connectionToDestroy = this.vpnConnection;
      this.vpnConnection = undefined;
      await connectionToDestroy.destroy().catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'destroy failed: %{public}s', this.formatError(err));
      });
    }

    hilog.info(DOMAIN, TAG, 'WgVpnExtension cleanup end');
  }

  private resetDataTransferNotificationState(): void {
    this.lastNotifiedTxBytes = -1;
    this.lastNotifiedRxBytes = -1;
  }

  private startDataTransferNotificationUpdates(): void {
    this.stopDataTransferNotificationUpdates();
    this.dataTransferNotificationTimer = setInterval(() => {
      this.updateDataTransferNotification().catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'dataTransfer notification update failed: %{public}s', this.formatError(err));
      });
    }, DATA_TRANSFER_NOTIFICATION_INTERVAL_MS);
  }

  private stopDataTransferNotificationUpdates(): void {
    if (this.dataTransferNotificationTimer >= 0) {
      clearInterval(this.dataTransferNotificationTimer);
      this.dataTransferNotificationTimer = -1;
    }
    this.resetDataTransferNotificationState();
  }

  private startRuntimeStatusPublishUpdates(): void {
    this.stopRuntimeStatusPublishUpdates();
    this.runtimeStatusPublishTimer = setInterval(() => {
      this.publishRuntimeStatus(this.tunnelHandle !== 0, true).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'periodic runtime status publish failed: %{public}s', this.formatError(err));
      });
    }, RUNTIME_STATUS_PUBLISH_INTERVAL_MS);
  }

  private stopRuntimeStatusPublishUpdates(): void {
    if (this.runtimeStatusPublishTimer >= 0) {
      clearInterval(this.runtimeStatusPublishTimer);
      this.runtimeStatusPublishTimer = -1;
    }
  }

  private startNativeTunnelHealthMonitor(): void {
    this.stopNativeTunnelHealthMonitor();
    this.nativeTunnelHealthTimer = setInterval(() => {
      this.checkNativeTunnelHealth().catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'native tunnel health check failed: %{public}s', this.formatError(err));
      });
    }, NATIVE_TUNNEL_HEALTH_INTERVAL_MS);
  }

  private stopNativeTunnelHealthMonitor(): void {
    if (this.nativeTunnelHealthTimer < 0) {
      return;
    }
    clearInterval(this.nativeTunnelHealthTimer);
    this.nativeTunnelHealthTimer = -1;
  }

  private async checkNativeTunnelHealth(): Promise<void> {
    const handle = this.tunnelHandle;
    if (handle === 0 || this.nativeTunnelRecoveryInFlight) {
      return;
    }
    let alive = false;
    try {
      alive = NativeTunnel.isAlive(handle);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'native tunnel health query failed: %{public}s', this.formatError(error));
    }
    if (alive) {
      return;
    }
    let stats: TunnelStats | undefined = undefined;
    try {
      stats = NativeTunnel.stats(handle);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'native tunnel failure stats unavailable: %{public}s', this.formatError(error));
    }
    await this.handleDeadNativeTunnel('nativeHealthMonitor', stats, handle);
  }

  private async updateDataTransferNotification(): Promise<void> {
    if (this.tunnelHandle === 0) {
      return;
    }

    const stats = NativeTunnel.stats(this.tunnelHandle);
    if (!this.isNativeTunnelAlive(stats)) {
      await this.handleDeadNativeTunnel('dataTransferNotification', stats);
      return;
    }
    this.logNativePacketStats(stats);
    const txBytes = stats.txBytes;
    const rxBytes = stats.rxBytes;
    this.lastNotifiedTxBytes = txBytes;
    this.lastNotifiedRxBytes = rxBytes;
    await updateVpnDataTransferNotification(
      this.context as common.VpnExtensionContext,
      this.activeTunnelName,
      txBytes,
      rxBytes
    );
  }

  private startNetworkObserver(): void {
    if (this.netConnection !== undefined) {
      return;
    }

    try {
      const netConnection = connection.createNetConnection();
      netConnection.on('netAvailable', (netHandle: connection.NetHandle) => {
        this.handleNetworkChanged('netAvailable', netHandle).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'handle netAvailable failed: %{public}s', this.formatError(err));
        });
      });
      netConnection.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
        this.handleNetworkChanged('netCapabilitiesChange', info.netHandle).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'handle netCapabilitiesChange failed: %{public}s', this.formatError(err));
        });
      });
      netConnection.on('netLost', (netHandle: connection.NetHandle) => {
        hilog.info(DOMAIN, TAG, 'network lost netId=%{public}d', netHandle.netId);
        this.handleNetworkChanged('netLost', netHandle).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'handle netLost failed: %{public}s', this.formatError(err));
        });
      });
      netConnection.register((err: BusinessError) => {
        if (err !== undefined && err.code !== 0) {
          hilog.warn(DOMAIN, TAG, 'network observer register failed: %{public}s', this.formatError(err));
          return;
        }
        hilog.info(DOMAIN, TAG, 'network observer registered');
      });
      this.netConnection = netConnection;
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'start network observer failed: %{public}s', this.formatError(error));
    }
  }

  private stopNetworkObserver(): void {
    const netConnection = this.netConnection;
    if (netConnection === undefined) {
      return;
    }
    this.netConnection = undefined;
    try {
      netConnection.unregister((err: BusinessError) => {
        if (err !== undefined && err.code !== 0) {
          hilog.warn(DOMAIN, TAG, 'network observer unregister failed: %{public}s', this.formatError(err));
          return;
        }
        hilog.info(DOMAIN, TAG, 'network observer unregistered');
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'stop network observer failed: %{public}s', this.formatError(error));
    }
  }

  private async handleNetworkChanged(reason: string, netHandle: connection.NetHandle): Promise<void> {
    hilog.info(DOMAIN, TAG, 'network changed reason=%{public}s netId=%{public}d', reason, netHandle.netId);
    const smartAgentEnabled = await loadSmartAgentEnabled(this.context as common.VpnExtensionContext, true);
    if (!smartAgentEnabled) {
      this.forceHandshake(reason);
      return;
    }
    const decision = await this.resolveSmartAgentDecision();
    await this.applySmartAgentDecision(reason, decision);
  }

  private async applySmartAgentDecision(reason: string, decision: SmartAgentDecision): Promise<void> {
    if (this.networkStrategyInFlight) {
      hilog.info(DOMAIN, TAG, 'skip smart agent reevaluate while in flight reason=%{public}s', reason);
      return;
    }

    this.networkStrategyInFlight = true;
    try {
      hilog.info(
        DOMAIN,
        TAG,
        'smart agent decision reason=%{public}s mode=%{public}s summary=%{public}s selectedId=%{public}s handle=%{public}d',
        reason,
        decision.matchSource,
        decision.summary,
        decision.selectedActiveInfo.id,
        this.tunnelHandle
      );

      if (!decision.shouldConnectVpn) {
        if (this.tunnelHandle !== 0 || this.vpnConnection !== undefined) {
          this.appendSmartAgentSwitchLog(reason, this.activeTunnelName, '');
          await this.cleanupTunnelOnly();
        } else {
          await this.publishRuntimeStatus(false, false);
        }
        return;
      }

      const desiredState = await this.resolveDesiredVpnStateForDecision(decision);
      if (this.canReuseRunningTunnel(desiredState)) {
        this.activeTunnelId = desiredState.activeInfo.id;
        this.activeTunnelName = desiredState.activeInfo.name;
        this.forceHandshake(reason);
        await this.publishRuntimeStatus(true, true);
        return;
      }

      this.appendSmartAgentSwitchLog(reason, this.activeTunnelName, desiredState.activeInfo.name);
      await this.restartWireGuard('network:' + reason, true, desiredState);
    } finally {
      this.networkStrategyInFlight = false;
    }
  }

  private async cleanupTunnelOnly(): Promise<void> {
    hilog.info(
      DOMAIN,
      TAG,
      'cleanup tunnel only begin handle=%{public}d hasConnection=%{public}s',
      this.tunnelHandle,
      String(this.vpnConnection !== undefined)
    );
    this.stopDataTransferNotificationUpdates();
    this.stopRuntimeStatusPublishUpdates();
    this.stopNativeTunnelHealthMonitor();
    this.lastForceHandshakeAt = 0;
    this.runningConfigFingerprint = '';
    this.activeTunnelId = '';
    this.activeTunnelName = '';

    if (this.tunnelHandle !== 0) {
      NativeTunnel.stop(this.tunnelHandle);
      this.tunnelHandle = 0;
    }

    if (this.vpnConnection !== undefined) {
      const connectionToDestroy = this.vpnConnection;
      this.vpnConnection = undefined;
      await connectionToDestroy.destroy().catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'destroy in cleanupTunnelOnly failed: %{public}s', this.formatError(err));
      });
    }

    await this.publishRuntimeStatus(false, false);
    hilog.info(DOMAIN, TAG, 'cleanup tunnel only end');
  }

  private forceHandshake(reason: string): void {
    if (this.tunnelHandle === 0) {
      return;
    }

    const now = Date.now();
    if (now - this.lastForceHandshakeAt < FORCE_HANDSHAKE_DEBOUNCE_MS) {
      return;
    }
    this.lastForceHandshakeAt = now;

    try {
      NativeTunnel.forceHandshake(this.tunnelHandle);
      hilog.info(DOMAIN, TAG, 'force handshake requested reason=%{public}s handle=%{public}d', reason, this.tunnelHandle);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'force handshake failed reason=%{public}s error=%{public}s', reason, this.formatError(error));
    }
  }

  private async publishRuntimeStatus(running: boolean, includeStats: boolean): Promise<void> {
    let txBytes = 0;
    let rxBytes = 0;
    let latestHandshakeSeconds = -1;
    let latestPacketSentSeconds = -1;
    let loss = 0;
    let rttMillis = -1;
    if (running && includeStats && this.tunnelHandle !== 0) {
      try {
        const stats = NativeTunnel.stats(this.tunnelHandle);
        if (!this.isNativeTunnelAlive(stats)) {
          await this.handleDeadNativeTunnel('publishRuntimeStatus', stats);
          return;
        } else {
          txBytes = stats.txBytes;
          rxBytes = stats.rxBytes;
          latestHandshakeSeconds = stats.latestHandshakeSeconds;
          latestPacketSentSeconds = stats.latestPacketSentSeconds;
          loss = stats.loss;
          rttMillis = stats.rttMillis;
          this.logNativePacketStats(stats);
        }
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'read native stats failed: %{public}s', this.formatError(error));
      }
    }
    if (running && (txBytes !== this.lastNotifiedTxBytes || rxBytes !== this.lastNotifiedRxBytes)) {
      this.lastNotifiedTxBytes = txBytes;
      this.lastNotifiedRxBytes = rxBytes;
      updateVpnDataTransferNotification(
        this.context as common.VpnExtensionContext,
        this.activeTunnelName,
        txBytes,
        rxBytes
      ).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'publish dataTransfer notification update failed: %{public}s', this.formatError(err));
      });
    }

    const status: TunnelRuntimeStatus = {
      running: running,
      tunnelId: this.activeTunnelId,
      tunnelName: this.activeTunnelName,
      txBytes: txBytes,
      rxBytes: rxBytes,
      latestHandshakeSeconds: latestHandshakeSeconds,
      latestPacketSentSeconds: latestPacketSentSeconds,
      loss: loss,
      rttMillis: rttMillis,
      nativeWorkerExitCode: 0,
      nativeLastError: '',
      nativeLastEvent: '',
      nativeLastWorker: '',
      nativeLastErrorAtSeconds: -1,
      nativeLastTickSeconds: -1,
      nativeTunReadLast: '',
      nativeTunWriteLast: '',
      updatedAt: Date.now()
    };
    if (includeStats && this.tunnelHandle !== 0) {
      try {
        const diagnosticStats = NativeTunnel.stats(this.tunnelHandle);
        status.nativeWorkerExitCode = diagnosticStats.workerExitCode;
        status.nativeLastError = diagnosticStats.lastError;
        status.nativeLastEvent = diagnosticStats.lastEvent;
        status.nativeLastWorker = diagnosticStats.lastWorker;
        status.nativeLastErrorAtSeconds = diagnosticStats.lastErrorAtSeconds;
        status.nativeLastTickSeconds = diagnosticStats.lastTickSeconds;
        status.nativeTunReadLast = diagnosticStats.tunReadLast;
        status.nativeTunWriteLast = diagnosticStats.tunWriteLast;
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'read native diagnostic stats failed: %{public}s', this.formatError(error));
      }
    }
    await saveTunnelRuntimeStatus(this.context as common.VpnExtensionContext, status);
  }

  private logNativePacketStats(stats: TunnelStats): void {
    if (stats.tunReadPackets === this.lastLoggedTunReadPackets &&
      stats.tunDroppedPackets === this.lastLoggedTunDroppedPackets &&
      stats.udpReadPackets === this.lastLoggedUdpReadPackets) {
      return;
    }

    this.lastLoggedTunReadPackets = stats.tunReadPackets;
    this.lastLoggedTunDroppedPackets = stats.tunDroppedPackets;
    this.lastLoggedUdpReadPackets = stats.udpReadPackets;
  }

  private isNativeTunnelAlive(stats: TunnelStats): boolean {
    if (!stats.running) {
      return false;
    }
    if (!stats.tunWorkerAlive || !stats.udpWorkerAlive) {
      return false;
    }
    return true;
  }

  private async handleDeadNativeTunnel(
    reason: string,
    stats: TunnelStats | undefined,
    detectedHandle: number = this.tunnelHandle
  ): Promise<void> {
    if (detectedHandle === 0 || detectedHandle !== this.tunnelHandle || this.nativeTunnelRecoveryInFlight) {
      return;
    }
    this.nativeTunnelRecoveryInFlight = true;
    if (!this.nativeTunnelDeathLogged) {
      hilog.error(
        DOMAIN,
        TAG,
        'WgVpnExtension native tunnel dead reason=%{public}s handle=%{public}d running=%{public}s tunAlive=%{public}s udpAlive=%{public}s exitCode=%{public}d lastWorker=%{public}s lastEvent=%{public}s lastError=%{public}s lastTickSeconds=%{public}s',
        reason,
        this.tunnelHandle,
        String(stats === undefined ? false : stats.running),
        String(stats === undefined ? false : stats.tunWorkerAlive),
        String(stats === undefined ? false : stats.udpWorkerAlive),
        stats === undefined ? 0 : stats.workerExitCode,
        stats === undefined ? '' : stats.lastWorker,
        stats === undefined ? 'stats_unavailable' : stats.lastEvent,
        stats === undefined ? '' : stats.lastError,
        stats === undefined ? '-1' : stats.lastTickSeconds.toFixed(3)
      );
      appendAgentLog(
        this.context as common.VpnExtensionContext,
        buildVpnNativeFailureLogEntry(
          this.activeTunnelName,
          reason,
          stats === undefined ? 0 : stats.workerExitCode,
          stats === undefined ? '' : stats.lastWorker,
          stats === undefined ? 'stats_unavailable' : stats.lastEvent,
          stats === undefined ? '' : stats.lastError,
          Date.now()
        )
      ).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'append native failure log failed: %{public}s', this.formatError(err));
      });
      this.nativeTunnelDeathLogged = true;
    }
    try {
      const settings: VpnKeepAliveSettings = await loadVpnKeepAliveSettings(
        this.context as common.VpnExtensionContext,
        true
      );
      if (!isVpnKeepAliveEnabled(settings)) {
        await this.cleanup(false);
        await this.publishRuntimeStatus(false, false);
        return;
      }
      hilog.warn(
        DOMAIN,
        TAG,
        'self-heal native tunnel reason=%{public}s pip=%{public}s inApp=%{public}s',
        reason,
        String(settings.pictureInPictureEnabled),
        String(settings.inAppEnabled)
      );
      await this.restartWireGuard('native-death:' + reason, true);
    } finally {
      this.nativeTunnelRecoveryInFlight = false;
    }
  }

  private isRestoreWant(want: Want): boolean {
    return this.wantAction(want) === WANT_ACTION_RESTORE;
  }

  private isNetworkLostWant(want: Want): boolean {
    return this.wantAction(want) === WANT_ACTION_NETWORK_LOST;
  }

  private wantAction(want: Want): string {
    const parameters = want.parameters;
    if (parameters === undefined) {
      return '';
    }
    const action = parameters.action;
    if (typeof action === 'string') {
      return action;
    }
    return '';
  }

  private wantNumber(want: Want, key: string): number {
    const parameters = want.parameters;
    if (parameters === undefined) {
      return -1;
    }
    const value = parameters[key];
    if (typeof value === 'number') {
      return value;
    }
    return -1;
  }

  private formatError(error: BusinessError): string {
    const message = error.message ?? '';
    if (message.length > 0) {
      return 'code=' + String(error.code) + ', message=' + message;
    }
    return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
  }
}
