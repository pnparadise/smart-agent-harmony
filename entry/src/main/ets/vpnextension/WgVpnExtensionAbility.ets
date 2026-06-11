import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connection, vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ActiveTunnelInfo,
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

const DOMAIN = 0x0001;
const TAG = 'WgVpnExtension';
const VPN_INTERFACE = 'vpn-tun';
const STATS_REFRESH_INTERVAL_MS = 1000;
const FORCE_HANDSHAKE_DEBOUNCE_MS = 1500;

export default class WgVpnExtensionAbility extends VpnExtensionAbility {
  private vpnConnection?: vpnExtension.VpnConnection;
  private netConnection?: connection.NetConnection;
  private tunnelHandle: number = 0;
  private statsTimer: number = -1;
  private activeTunnelId: string = '';
  private activeTunnelName: string = '';
  private restartQueue: Promise<void> = Promise.resolve();
  private lastForceHandshakeAt: number = 0;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    this.restartWireGuard('onCreate', false).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'start failed: %{public}s', this.formatError(err));
      this.cleanup().catch((cleanupErr: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'cleanup after start failure failed: %{public}s', this.formatError(cleanupErr));
      });
    });
  }

  onRequest(want: Want, startId: number): void {
    hilog.info(DOMAIN, TAG, 'onRequest startId=%{public}d ability=%{public}s', startId, want.abilityName ?? '');
    this.restartWireGuard('onRequest', true).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'restart failed: %{public}s', this.formatError(err));
      this.cleanup().catch((cleanupErr: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'cleanup after restart failure failed: %{public}s', this.formatError(cleanupErr));
      });
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.cleanup().catch((err: BusinessError) => {
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

    this.tunnelHandle = NativeTunnel.create(config);
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
        selectedSplitApps.length
      );
      this.logVpnConfigDetails(vpnConfig);

      const tunFd = await this.vpnConnection.create(vpnConfig);
      hilog.info(DOMAIN, TAG, 'vpn tun created, fd=%{public}d', tunFd);

      NativeTunnel.start(this.tunnelHandle, tunFd);
      hilog.info(DOMAIN, TAG, 'native tunnel started');
      this.startNetworkObserver();
      try {
        this.startStatsPublisher();
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'start stats publisher failed: %{public}s', this.formatError(error));
      }
      this.publishRuntimeStatus(true).catch((err: BusinessError) => {
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
      .map((parsed: ParsedCidr) => this.buildRoute(parsed));

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
      if (bundleName.length > 0) {
        bundleNames.push(bundleName);
      }
    }
    return bundleNames;
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

  private buildRoute(parsed: ParsedCidr): vpnExtension.RouteInfo {
    const gateway = parsed.family === 1 ? '0.0.0.0' : '::';
    const route: vpnExtension.RouteInfo = {
      'interface': VPN_INTERFACE,
      destination: this.buildLinkAddress(parsed),
      gateway: this.buildNetAddress(gateway, parsed.family),
      hasGateway: false,
      isDefaultRoute: parsed.prefixLength === 0
    };
    return route;
  }

  private logVpnConfigDetails(vpnConfig: vpnExtension.VpnConfig): void {
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
  }

  private formatLinkAddress(value: vpnExtension.LinkAddress): string {
    return value.address.address + '/' + String(value.prefixLength);
  }

  private formatRoute(value: vpnExtension.RouteInfo): string {
    return this.formatLinkAddress(value.destination) + ',default=' + String(value.isDefaultRoute);
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
    this.stopStatsPublisher();
    this.lastForceHandshakeAt = 0;

    if (this.tunnelHandle !== 0) {
      hilog.info(DOMAIN, TAG, 'stopping native tunnel');
      NativeTunnel.stop(this.tunnelHandle);
      this.tunnelHandle = 0;
    }

    if (publishStopped) {
      this.publishRuntimeStatus(false).catch((err: BusinessError) => {
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

  private startStatsPublisher(): void {
    this.stopStatsPublisher();
    hilog.info(DOMAIN, TAG, 'start stats publisher interval=%{public}d', STATS_REFRESH_INTERVAL_MS);
    this.statsTimer = setInterval(() => {
      this.publishRuntimeStatus(true).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'publish runtime status failed: %{public}s', this.formatError(err));
      });
    }, STATS_REFRESH_INTERVAL_MS);
  }

  private stopStatsPublisher(): void {
    if (this.statsTimer >= 0) {
      clearInterval(this.statsTimer);
      this.statsTimer = -1;
      hilog.info(DOMAIN, TAG, 'stop stats publisher');
    }
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

  private async publishRuntimeStatus(running: boolean): Promise<void> {
    let txBytes = 0;
    let rxBytes = 0;
    let latestHandshakeSeconds = -1;
    let latestPacketSentSeconds = -1;
    let loss = 0;
    let rttMillis = -1;
    if (running && this.tunnelHandle !== 0) {
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
    hilog.info(
      DOMAIN,
      TAG,
      'publish runtime status running=%{public}s id=%{public}s name=%{public}s tx=%{public}s rx=%{public}s handshake=%{public}s packetSent=%{public}s rtt=%{public}s updatedAt=%{public}s',
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
    await saveTunnelRuntimeStatus(this.context as common.VpnExtensionContext, status);
  }

  private formatError(error: BusinessError): string {
    const message = error.message ?? '';
    if (message.length > 0) {
      return 'code=' + String(error.code) + ', message=' + message;
    }
    return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
  }
}
