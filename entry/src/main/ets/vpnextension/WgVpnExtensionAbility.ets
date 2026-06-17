import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connection, vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ActiveTunnelInfo,
  appendAgentLog,
  buildVpnRestartLogEntry,
  loadAppSplitEnabled,
  loadActiveTunnelInfo,
  loadConfig,
  loadSelectedSplitApps,
  saveTunnelRuntimeStatus,
  SplitAppInfo,
  TunnelRuntimeStatus
} from '../wireguard/ConfigStore';
import {
  hasIPv4,
  hasIPv6,
  parseCidr,
  parseWireGuardConfig,
  ParsedCidr,
  WireGuardConfig
} from '../wireguard/WireGuardConfig';
import { NativeTunnel } from '../wireguard/NativeTunnel';
import { updateVpnDataTransferNotification } from '../wireguard/VpnBackgroundTask';

const DOMAIN = 0x0001;
const TAG = 'WgVpnExtension';
const VPN_INTERFACE = 'vpn-tun';
const BUNDLE_NAME = 'com.smart.agent';
const FORCE_HANDSHAKE_DEBOUNCE_MS = 1500;
const DATA_TRANSFER_NOTIFICATION_INTERVAL_MS = 1000;
const WANT_ACTION_REFRESH_STATUS = 'refreshStatus';
const WANT_ACTION_RESTORE = 'restore';

interface LoggedVpnConfig extends vpnExtension.VpnConfig {
  trustedApplications?: string[];
  blockedApplications?: string[];
}

export default class WgVpnExtensionAbility extends VpnExtensionAbility {
  private vpnConnection?: vpnExtension.VpnConnection;
  private netConnection?: connection.NetConnection;
  private tunnelHandle: number = 0;
  private activeTunnelId: string = '';
  private activeTunnelName: string = '';
  private restartQueue: Promise<void> = Promise.resolve();
  private lastForceHandshakeAt: number = 0;
  private dataTransferNotificationTimer: number = -1;
  private lastNotifiedTxBytes: number = -1;
  private lastNotifiedRxBytes: number = -1;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    if (this.isRefreshStatusWant(want)) {
      this.publishRuntimeStatus(false, false).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'publish cold refresh status failed: %{public}s', this.formatError(err));
      });
      return;
    }

    this.restartWireGuard('onCreate', false).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'start failed: %{public}s', this.formatError(err));
      this.cleanup().catch((cleanupErr: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'cleanup after start failure failed: %{public}s', this.formatError(cleanupErr));
      });
    });
  }

  onRequest(want: Want, startId: number): void {
    hilog.info(DOMAIN, TAG, 'onRequest startId=%{public}d ability=%{public}s', startId, want.abilityName ?? '');
    if (this.isRefreshStatusWant(want)) {
      this.publishRuntimeStatus(this.tunnelHandle !== 0, true).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'publish requested runtime status failed: %{public}s', this.formatError(err));
      });
      return;
    }

    if (this.isRestoreWant(want) && this.tunnelHandle !== 0) {
      this.publishRuntimeStatus(true, true).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'publish restore status failed: %{public}s', this.formatError(err));
      });
      return;
    }

    this.restartWireGuard('onRequest', true).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'restart failed: %{public}s', this.formatError(err));
      this.cleanup().catch((cleanupErr: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'cleanup after restart failure failed: %{public}s', this.formatError(cleanupErr));
      });
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.cleanup(false).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'cleanup on destroy failed: %{public}s', this.formatError(err));
    });
  }

  private async restartWireGuard(reason: string, cleanupFirst: boolean): Promise<void> {
    const task = this.restartQueue.then(() => {
      return this.doRestartWireGuard(reason, cleanupFirst);
    });
    this.restartQueue = task.catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restart queue task failed: %{public}s', this.formatError(err));
    });
    await task;
  }

  private async doRestartWireGuard(reason: string, cleanupFirst: boolean): Promise<void> {
    hilog.info(
      DOMAIN,
      TAG,
      'restartWireGuard reason=%{public}s cleanupFirst=%{public}s handle=%{public}d activeId=%{public}s',
      reason,
      String(cleanupFirst),
      this.tunnelHandle,
      this.activeTunnelId
    );
    if (cleanupFirst || this.tunnelHandle !== 0 || this.vpnConnection !== undefined) {
      await this.cleanup(false);
    }
    await this.startWireGuard();
  }

  private async startWireGuard(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'startWireGuard begin');

    const activeInfo = await this.resolveActiveTunnelInfo();
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

      const appSplitEnabled = await loadAppSplitEnabled(this.context as common.VpnExtensionContext, true);
      const selectedSplitApps = await loadSelectedSplitApps(this.context as common.VpnExtensionContext, true);
      const vpnConfig = this.buildVpnConfig(config, appSplitEnabled, selectedSplitApps);
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
        String(appSplitEnabled),
        trustedApplications.length
      );
      this.logVpnConfigDetails(vpnConfig);

      const tunFd = await this.vpnConnection.create(vpnConfig);
      hilog.info(DOMAIN, TAG, 'vpn tun created, fd=%{public}d', tunFd);

      NativeTunnel.start(this.tunnelHandle, tunFd);
      hilog.info(DOMAIN, TAG, 'native tunnel started');
      this.appendVpnRestartLog(this.activeTunnelName, Date.now());
      this.startNetworkObserver();
      this.startDataTransferNotificationUpdates();
      this.publishRuntimeStatus(true, false).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'publish initial runtime status failed: %{public}s', this.formatError(err));
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'start stage failed: %{public}s', this.formatError(error));
      await this.cleanup();
      throw new Error('Failed to start WireGuard tunnel: ' + this.formatError(error));
    }
    hilog.info(DOMAIN, TAG, 'WireGuard tunnel started');
  }

  private appendVpnRestartLog(tunnelName: string, createdAt: number): void {
    appendAgentLog(
      this.context as common.VpnExtensionContext,
      buildVpnRestartLogEntry(tunnelName, createdAt)
    ).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'append vpn restart log failed: %{public}s', this.formatError(err));
    });
  }

  private async resolveConfigText(): Promise<string> {
    hilog.info(DOMAIN, TAG, 'using config from preferences');
    return await loadConfig(this.context as common.VpnExtensionContext);
  }

  private async resolveActiveTunnelInfo(): Promise<ActiveTunnelInfo> {
    const activeInfo = await loadActiveTunnelInfo(this.context as common.VpnExtensionContext, true);
    if (activeInfo.configText.length > 0) {
      hilog.info(DOMAIN, TAG, 'using active tunnel config id=%{public}s name=%{public}s', activeInfo.id, activeInfo.name);
      return activeInfo;
    }

    const fallbackConfig = await this.resolveConfigText();
    const fallbackInfo: ActiveTunnelInfo = {
      id: '',
      name: '',
      configText: fallbackConfig
    };
    hilog.warn(DOMAIN, TAG, 'active tunnel config empty, fallback configBytes=%{public}d', fallbackConfig.length);
    return fallbackInfo;
  }

  private async resolveEndpointHost(host: string): Promise<string> {
    const normalized = host.trim();
    if (this.isIpAddress(normalized)) {
      return normalized;
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
      'cleanup begin handle=%{public}d hasConnection=%{public}s activeId=%{public}s publishStopped=%{public}s',
      this.tunnelHandle,
      String(this.vpnConnection !== undefined),
      this.activeTunnelId,
      String(publishStopped)
    );
    this.stopNetworkObserver();
    this.stopDataTransferNotificationUpdates();
    this.lastForceHandshakeAt = 0;

    if (this.tunnelHandle !== 0) {
      hilog.info(DOMAIN, TAG, 'stopping native tunnel');
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

    hilog.info(DOMAIN, TAG, 'cleanup end');
  }

  private startDataTransferNotificationUpdates(): void {
    this.stopDataTransferNotificationUpdates();
    this.updateDataTransferNotification().catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'initial dataTransfer notification update failed: %{public}s', this.formatError(err));
    });
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
    this.lastNotifiedTxBytes = -1;
    this.lastNotifiedRxBytes = -1;
  }

  private async updateDataTransferNotification(): Promise<void> {
    if (this.tunnelHandle === 0) {
      return;
    }

    const stats = NativeTunnel.stats(this.tunnelHandle);
    const txBytes = stats.txBytes;
    const rxBytes = stats.rxBytes;
    if (txBytes === this.lastNotifiedTxBytes && rxBytes === this.lastNotifiedRxBytes) {
      return;
    }

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
        this.handleNetworkChanged('netAvailable', netHandle);
      });
      netConnection.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
        this.handleNetworkChanged('netCapabilitiesChange', info.netHandle);
      });
      netConnection.on('netLost', (netHandle: connection.NetHandle) => {
        hilog.info(DOMAIN, TAG, 'network lost netId=%{public}d', netHandle.netId);
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

  private handleNetworkChanged(reason: string, netHandle: connection.NetHandle): void {
    hilog.info(DOMAIN, TAG, 'network changed reason=%{public}s netId=%{public}d', reason, netHandle.netId);
    this.forceHandshake(reason);
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
        txBytes = stats.txBytes;
        rxBytes = stats.rxBytes;
        latestHandshakeSeconds = stats.latestHandshakeSeconds;
        latestPacketSentSeconds = stats.latestPacketSentSeconds;
        loss = stats.loss;
        rttMillis = stats.rttMillis;
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
      updatedAt: Date.now()
    };
    await saveTunnelRuntimeStatus(this.context as common.VpnExtensionContext, status);
  }

  private isRefreshStatusWant(want: Want): boolean {
    return this.wantAction(want) === WANT_ACTION_REFRESH_STATUS;
  }

  private isRestoreWant(want: Want): boolean {
    return this.wantAction(want) === WANT_ACTION_RESTORE;
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

  private formatError(error: BusinessError): string {
    const message = error.message ?? '';
    if (message.length > 0) {
      return 'code=' + String(error.code) + ', message=' + message;
    }
    return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
  }
}
