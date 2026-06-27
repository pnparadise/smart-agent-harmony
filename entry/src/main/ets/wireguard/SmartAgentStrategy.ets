import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ActiveTunnelInfo,
  AgentRule,
  AgentRuleType,
  loadConfig,
  loadActiveTunnelInfo,
  loadAgentRules,
  loadSmartAgentEnabled,
  loadTunnels,
  TunnelConfig
} from './ConfigStore';

const DOMAIN = 0x0001;
const TAG = 'SmartAgentStrategy';
const NETWORK_FAMILY_IPV4 = 1;
const NETWORK_FAMILY_IPV6 = 2;

type StrategyContext = common.UIAbilityContext | common.VpnExtensionContext;

export interface SmartAgentNetworkSnapshot {
  netId: number;
  isDefaultNetworkAvailable: boolean;
  isValidated: boolean;
  isWifi: boolean;
  wifiSsid: string;
  wifiGateway: string;
  ipv4Available: boolean;
  ipv6Available: boolean;
}

export interface SmartAgentDecision {
  enabled: boolean;
  shouldConnectVpn: boolean;
  baseActiveInfo: ActiveTunnelInfo;
  selectedActiveInfo: ActiveTunnelInfo;
  matchedRuleId: string;
  matchedRuleType: AgentRuleType | '';
  matchedRuleValue: string;
  matchSource: 'manual' | 'rule' | 'direct';
  summary: string;
  network: SmartAgentNetworkSnapshot;
}

interface MatchedRuleResult {
  rule: AgentRule;
  summary: string;
}

interface ConnectionRouteLike {
  gateway: connection.NetAddress;
  isDefaultRoute: boolean;
}

interface ConnectionLinkAddressLike {
  address: connection.NetAddress;
}

export class SmartAgentStrategy {
  private readonly context: StrategyContext;

  constructor(context: StrategyContext) {
    this.context = context;
  }

  async resolveDecision(): Promise<SmartAgentDecision> {
    const baseActiveInfo = await this.resolveBaseActiveInfo();
    const network = this.collectNetworkSnapshot();
    const enabled = await loadSmartAgentEnabled(this.context, true);
    if (!enabled) {
      return this.fallbackDecision(false, baseActiveInfo, network, 'smart agent disabled');
    }

    const rules = await loadAgentRules(this.context, true);
    const matched = this.matchRule(rules, network);
    if (matched === undefined) {
      return this.fallbackDecision(true, baseActiveInfo, network, 'no rule matched');
    }

    if (matched.rule.targetTunnelId.length === 0) {
      return {
        enabled: true,
        shouldConnectVpn: false,
        baseActiveInfo: baseActiveInfo,
        selectedActiveInfo: this.emptyActiveInfo(),
        matchedRuleId: matched.rule.id,
        matchedRuleType: matched.rule.type,
        matchedRuleValue: matched.rule.matchValue,
        matchSource: 'direct',
        summary: matched.summary + ' -> direct',
        network: network
      };
    }

    const tunnels = await loadTunnels(this.context, true);
    const targetTunnel = this.findTunnelById(tunnels, matched.rule.targetTunnelId);
    if (targetTunnel === undefined) {
      hilog.warn(
        DOMAIN,
        TAG,
        'matched rule target tunnel missing ruleId=%{public}s targetTunnelId=%{public}s',
        matched.rule.id,
        matched.rule.targetTunnelId
      );
      return this.fallbackDecision(true, baseActiveInfo, network, matched.summary + ' -> target missing');
    }

    return {
      enabled: true,
      shouldConnectVpn: targetTunnel.configText.length > 0,
      baseActiveInfo: baseActiveInfo,
      selectedActiveInfo: {
        id: targetTunnel.id,
        name: targetTunnel.name,
        configText: targetTunnel.configText
      },
      matchedRuleId: matched.rule.id,
      matchedRuleType: matched.rule.type,
      matchedRuleValue: matched.rule.matchValue,
      matchSource: 'rule',
      summary: matched.summary + ' -> ' + targetTunnel.name,
      network: network
    };
  }

  private fallbackDecision(
    enabled: boolean,
    baseActiveInfo: ActiveTunnelInfo,
    network: SmartAgentNetworkSnapshot,
    summary: string
  ): SmartAgentDecision {
    return {
      enabled: enabled,
      shouldConnectVpn: baseActiveInfo.configText.length > 0,
      baseActiveInfo: baseActiveInfo,
      selectedActiveInfo: baseActiveInfo,
      matchedRuleId: '',
      matchedRuleType: '',
      matchedRuleValue: '',
      matchSource: 'manual',
      summary: summary,
      network: network
    };
  }

  private collectNetworkSnapshot(): SmartAgentNetworkSnapshot {
    const snapshot: SmartAgentNetworkSnapshot = {
      netId: 0,
      isDefaultNetworkAvailable: false,
      isValidated: false,
      isWifi: false,
      wifiSsid: '',
      wifiGateway: '',
      ipv4Available: false,
      ipv6Available: false
    };

    try {
      const netHandle = connection.getDefaultNetSync();
      snapshot.netId = netHandle.netId;
      if (netHandle.netId === 0) {
        return snapshot;
      }

      snapshot.isDefaultNetworkAvailable = true;
      const capabilities = connection.getNetCapabilitiesSync(netHandle);
      const bearerTypes: connection.NetBearType[] = capabilities.bearerTypes;
      const networkCaps: connection.NetCap[] = capabilities.networkCap || [];
      snapshot.isValidated = networkCaps.includes(connection.NetCap.NET_CAPABILITY_VALIDATED);
      snapshot.isWifi = bearerTypes.includes(connection.NetBearType.BEARER_WIFI);

      const properties = connection.getConnectionPropertiesSync(netHandle);
      const routes = (properties.routes || []) as ConnectionRouteLike[];
      const linkAddresses = (properties.linkAddresses || []) as ConnectionLinkAddressLike[];
      snapshot.ipv4Available = this.hasLinkAddressFamily(linkAddresses, NETWORK_FAMILY_IPV4) ||
        this.hasGatewayFamily(routes, NETWORK_FAMILY_IPV4);
      snapshot.ipv6Available = this.hasLinkAddressFamily(linkAddresses, NETWORK_FAMILY_IPV6) ||
        this.hasGatewayFamily(routes, NETWORK_FAMILY_IPV6);

      if (snapshot.isWifi) {
        snapshot.wifiSsid = this.resolveLinkedWifiSsid();
        snapshot.wifiGateway = this.resolveWifiGateway(routes);
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'collect network snapshot failed: %{public}s', this.formatError(error));
    }

    return snapshot;
  }

  private async resolveBaseActiveInfo(): Promise<ActiveTunnelInfo> {
    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    if (activeInfo.configText.length > 0) {
      return activeInfo;
    }

    const fallbackConfig = await loadConfig(this.context, true);
    return {
      id: activeInfo.id,
      name: activeInfo.name,
      configText: fallbackConfig
    };
  }

  private matchRule(rules: AgentRule[], network: SmartAgentNetworkSnapshot): MatchedRuleResult | undefined {
    for (let index = 0; index < rules.length; index++) {
      const rule = rules[index];
      if (!rule.enabled) {
        continue;
      }
      if (!this.ruleMatches(rule, network)) {
        continue;
      }
      return {
        rule: rule,
        summary: this.ruleSummary(rule, network)
      };
    }
    return undefined;
  }

  private ruleMatches(rule: AgentRule, network: SmartAgentNetworkSnapshot): boolean {
    if (rule.type === 'wifiGateway') {
      return network.isWifi &&
        network.wifiGateway.length > 0 &&
        this.normalizeValue(rule.matchValue) === this.normalizeValue(network.wifiGateway);
    }
    if (rule.type === 'wifiSsid') {
      return network.isWifi &&
        network.wifiSsid.length > 0 &&
        this.normalizeSsid(rule.matchValue) === this.normalizeSsid(network.wifiSsid);
    }
    if (rule.type === 'ipv6Available') {
      return network.ipv6Available;
    }
    return network.ipv4Available;
  }

  private ruleSummary(rule: AgentRule, network: SmartAgentNetworkSnapshot): string {
    if (rule.type === 'wifiGateway') {
      return 'wifi gateway=' + network.wifiGateway;
    }
    if (rule.type === 'wifiSsid') {
      return 'wifi ssid=' + network.wifiSsid;
    }
    if (rule.type === 'ipv6Available') {
      return 'ipv6 available';
    }
    return 'ipv4 available';
  }

  private resolveLinkedWifiSsid(): string {
    try {
      const linkedInfo = wifiManager.getLinkedInfoSync();
      return this.normalizeSsid(linkedInfo.ssid);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'resolve wifi ssid failed: %{public}s', this.formatError(error));
      return '';
    }
  }

  private resolveWifiGateway(routes: ConnectionRouteLike[]): string {
    for (let index = 0; index < routes.length; index++) {
      const route = routes[index];
      if (!route.isDefaultRoute) {
        continue;
      }
      const gateway = route.gateway.address;
      if (route.gateway.family === NETWORK_FAMILY_IPV4 && gateway.length > 0) {
        return gateway;
      }
    }

    for (let index = 0; index < routes.length; index++) {
      const route = routes[index];
      const gateway = route.gateway.address;
      if (route.gateway.family === NETWORK_FAMILY_IPV4 && gateway.length > 0) {
        return gateway;
      }
    }
    return '';
  }

  private hasLinkAddressFamily(linkAddresses: ConnectionLinkAddressLike[], family: number): boolean {
    for (let index = 0; index < linkAddresses.length; index++) {
      const linkAddress = linkAddresses[index];
      if (linkAddress.address.family === family && linkAddress.address.address.length > 0) {
        return true;
      }
    }
    return false;
  }

  private hasGatewayFamily(routes: ConnectionRouteLike[], family: number): boolean {
    for (let index = 0; index < routes.length; index++) {
      const gateway = routes[index].gateway;
      if (gateway.family === family && gateway.address.length > 0) {
        return true;
      }
    }
    return false;
  }

  private findTunnelById(tunnels: TunnelConfig[], tunnelId: string): TunnelConfig | undefined {
    for (let index = 0; index < tunnels.length; index++) {
      const tunnel = tunnels[index];
      if (tunnel.id === tunnelId) {
        return tunnel;
      }
    }
    return undefined;
  }

  private emptyActiveInfo(): ActiveTunnelInfo {
    return {
      id: '',
      name: '',
      configText: ''
    };
  }

  private normalizeSsid(value: string): string {
    const normalized = this.normalizeValue(value);
    if (normalized.length >= 2 && normalized[0] === '"' && normalized[normalized.length - 1] === '"') {
      return normalized.substring(1, normalized.length - 1);
    }
    return normalized;
  }

  private normalizeValue(value: string): string {
    return value.trim();
  }

  private formatError(error: BusinessError): string {
    const message = error.message ?? '';
    if (message.length > 0) {
      return 'code=' + String(error.code) + ', message=' + message;
    }
    return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
  }
}
