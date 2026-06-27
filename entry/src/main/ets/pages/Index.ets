import { common, Want } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';
import { fileIo, picker, ReadOptions } from '@kit.CoreFileKit';
import { vpnExtension } from '@kit.NetworkKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  AgentLogEntry,
  AgentRule,
  clearAgentLogs,
  clearActiveTunnel,
  createAgentRuleId,
  createTunnelId,
  loadBrowserDohSettings,
  deleteTunnel,
  DEFAULT_DOH_PROVIDER,
  loadAgentRules,
  loadActiveTunnelInfo,
  loadAgentLogs,
  loadAppSplitEnabled,
  loadDohSettings,
  loadSelectedSplitApps,
  loadSmartAgentEnabled,
  loadTunnelRuntimeStatus,
  loadTunnels,
  saveAgentRules,
  saveActiveTunnel,
  saveAppSplitEnabled,
  saveBrowserDohSettings,
  saveDohSettings,
  saveSelectedSplitApps,
  saveSmartAgentEnabled,
  saveTunnelRuntimeStatus,
  saveTunnel,
  SplitAppInfo,
  TunnelConfig,
  TunnelRuntimeStatus
} from '../wireguard/ConfigStore';
import { applyWebHttpDnsFromDohSettings } from '../wireguard/WebHttpDns';
import { startVpnDataTransferTask, stopVpnDataTransferTask } from '../wireguard/VpnBackgroundTask';
import { DEFAULT_WG_CONFIG, parseWireGuardConfig } from '../wireguard/WireGuardConfig';
import { AppPickerPage } from './AppPickerPage';
import { LogsPage } from './LogsPage';
import {
  ACTION_BUTTON_BACKGROUND,
  ACTION_BUTTON_RADIUS,
  CARD_BACKGROUND,
  PAGE_BACKGROUND,
  PRIMARY_BLUE,
  TEXT_PRIMARY,
  TEXT_SECONDARY
} from './PageStyle';
import { RulesPage } from './RulesPage';
import { TunnelEditorPage } from './TunnelEditorPage';
import { TunnelsPage } from './TunnelsPage';

const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const VPN_ABILITY = 'WgVpnExtensionAbility';
const VPN_ACTION_RESTORE = 'restore';
const CONFIG_FILE_SUFFIX_FILTERS: string[] = ['WireGuard|.conf,.txt'];
const ISSUE_REPORT_URL = 'https://github.com/pnparadise/smart-agent-harmony';
const MAX_IMPORT_CONFIG_BYTES = 64 * 1024;
const STATUS_REFRESH_INTERVAL_MS = 3000;
const STARTUP_GRACE_MS = 15000;
const RUNTIME_STOP_GRACE_MS = 15000;
const VPN_RUNTIME_ALIVE_MAX_AGE_MS = 10000;
const TAB_TUNNELS = 0;
const TAB_RULES = 1;
const TAB_LOGS = 2;
const DOMAIN = 0x0001;
const TAG = 'Index';
const PRESET_SPLIT_APPS: SplitAppInfo[] = [
  {
    bundleName: 'com.huawei.hmos.browser',
    label: '华为浏览器'
  },
  {
    bundleName: 'com.uc.mobile',
    label: 'UC浏览器'
  },
  {
    bundleName: 'com.tencent.mtthm',
    label: 'QQ浏览器'
  },
  {
    bundleName: 'com.huawei.hmos.arkwebcore',
    label: 'ArkWeb 内核'
  },
  {
    bundleName: 'com.huawei.hmos.arkwebcorelegacy',
    label: 'ArkWeb 兼容库'
  }
];

@Entry
@Component
struct Index {
  @StorageProp('topRectHeight') private topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') private bottomRectHeight: number = 0;
  @State private tunnels: TunnelConfig[] = [];
  @State private statusText: string = 'Idle';
  @State private busy: boolean = false;
  @State private vpnEnabled: boolean = false;
  @State private activeTunnelId: string = '';
  @State private editingTunnelId: string = '';
  @State private editingName: string = '';
  @State private editingConfig: string = DEFAULT_WG_CONFIG;
  @State private runtimeRunning: boolean = false;
  @State private runtimeTunnelId: string = '';
  @State private runtimeTunnelName: string = '';
  @State private runtimeTxBytes: number = 0;
  @State private runtimeRxBytes: number = 0;
  @State private runtimeLatestHandshakeSeconds: number = -1;
  @State private runtimeLatestPacketSentSeconds: number = -1;
  @State private runtimeRttMillis: number = -1;
  @State private runtimeUpdatedAt: number = 0;
  @State private startingTunnelId: string = '';
  @State private startingTunnelName: string = '';
  @State private startingTunnelAt: number = 0;
  @State private currentTabIndex: number = TAB_TUNNELS;
  @State private appSplitEnabled: boolean = false;
  @State private smartAgentEnabled: boolean = false;
  @State private agentRules: AgentRule[] = [];
  @State private dohEnabled: boolean = true;
  @State private dohProvider: string = DEFAULT_DOH_PROVIDER;
  @State private browserDohEnabled: boolean = true;
  @State private browserDohProvider: string = DEFAULT_DOH_PROVIDER;
  @State private selectedSplitApps: SplitAppInfo[] = [];
  @State private appPickerOpen: boolean = false;
  @State private availableSplitApps: SplitAppInfo[] = [];
  @State private draftSelectedBundleNames: string[] = [];
  @State private appPickerLoading: boolean = false;
  @State private appPickerError: string = '';
  @State private appBundleNameInput: string = '';
  @State private appPickerNotice: string = '';
  @State private logs: AgentLogEntry[] = [];
  @State private tabBarWidth: number = 0;
  @State private tabIndicatorProgress: number = TAB_TUNNELS;
  @State private tabIndicatorAnimationDuration: number = 240;
  @State private highlightedTabIndex: number = TAB_TUNNELS;
  private statusRefreshTimer: number = -1;
  private runtimeConfirmedRunning: boolean = false;
  private tunnelLoadVersion: number = 0;
  private appSplitLoadVersion: number = 0;
  private smartAgentLoadVersion: number = 0;
  private dohLoadVersion: number = 0;
  private browserDohLoadVersion: number = 0;
  private logsLoadVersion: number = 0;

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'aboutToAppear');
    this.loadTunnelList();
    this.loadAppSplitSettings();
    this.loadSmartAgentSettings();
    this.loadDohSettings();
    this.loadBrowserDohSettings();
    if (this.currentTabIndex === TAB_LOGS) {
      this.loadLogs();
    }
    this.refreshRuntimeStatus();
    if (this.currentTabIndex === TAB_TUNNELS) {
      this.ensureActiveTunnelRunningOnVpnHome('aboutToAppear').catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'vpn home ensure running failed: %{public}s', err.message ?? JSON.stringify(err));
      });
    }
    this.startStatusRefresh();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'aboutToDisappear');
    this.stopStatusRefresh();
  }

  build() {
    Column() {
      if (this.editingTunnelId.length > 0) {
        this.buildEditorHeader();
        TunnelEditorPage({
          editingName: this.editingName,
          editingConfig: this.editingConfig,
          editingDisabled: this.isEditingActiveTunnel(),
          onNameChange: (value: string) => {
            this.editingName = value;
          },
          onConfigChange: (value: string) => {
            this.editingConfig = value;
          }
        });
      } else if (this.appPickerOpen) {
        this.buildAppPickerHeader();
        AppPickerPage({
          appPickerLoading: this.appPickerLoading,
          appPickerError: this.appPickerError,
          appPickerNotice: this.appPickerNotice,
          appBundleNameInput: this.appBundleNameInput,
          availableSplitApps: this.availableSplitApps,
          draftSelectedBundleNames: this.draftSelectedBundleNames,
          onRetry: () => {
            this.loadAvailableSplitApps().catch((err: BusinessError) => {
              this.appPickerError = err.message ?? JSON.stringify(err);
            });
          },
          onBundleNameInputChange: (value: string) => {
            this.appBundleNameInput = value;
            this.appPickerNotice = '';
          },
          onAddBundleName: () => {
            this.addSplitAppByBundleName().catch((err: BusinessError) => {
              this.appPickerNotice = err.message ?? JSON.stringify(err);
            });
          },
          onToggleApp: (bundleName: string) => {
            this.toggleDraftSplitApp(bundleName);
          }
        });
      } else {
        this.buildMainHeader();
        this.buildMainTabs();
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private buildEditorHeader() {
    Row() {
      Button() {
        Image($r('app.media.ic_back_blue'))
          .width(22)
          .height(22)
      }
        .enabled(!this.busy)
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ right: 12 })
        .onClick(() => {
          this.closeEditor();
        })

      Row() {
        Image($r('app.media.ic_key_blue'))
          .width(22)
          .height(22)
          .margin({ right: 12 })
        Text('SmartAgent')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      if (this.isSavedEditingTunnel()) {
        Button() {
          Image($r('app.media.ic_delete_blue'))
            .width(22)
            .height(22)
        }
          .enabled(!this.busy && !this.isEditingActiveTunnel())
          .type(ButtonType.Normal)
          .width(44)
          .height(44)
          .backgroundColor(ACTION_BUTTON_BACKGROUND)
          .borderRadius(ACTION_BUTTON_RADIUS)
          .borderWidth(0)
          .margin({ left: 8 })
          .onClick(() => {
            this.deleteTunnelById(this.editingTunnelId);
          })
      }

      Button() {
        Image($r('app.media.ic_check_blue'))
          .width(22)
          .height(22)
      }
        .enabled(!this.busy && !this.isEditingActiveTunnel())
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ left: 8 })
        .onClick(() => {
          this.saveEditingTunnel();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: this.statusBarPadding() + 22, bottom: 18 })
    .backgroundColor(CARD_BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .shadow({ radius: 14, color: '#10000000', offsetX: 0, offsetY: 2 })
    .zIndex(2)
  }

  @Builder
  private buildAppPickerHeader() {
    Row() {
      Button() {
        Image($r('app.media.ic_back_blue'))
          .width(22)
          .height(22)
      }
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ right: 12 })
        .onClick(() => {
          this.closeAppPicker();
        })

      Column() {
        Text('选择应用')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text('仅选中的应用流量走 VPN')
          .fontSize(12)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        Image($r('app.media.ic_check_blue'))
          .width(22)
          .height(22)
      }
        .enabled(!this.appPickerLoading)
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ left: 8 })
        .onClick(() => {
          this.saveAppPickerSelection().catch((err: BusinessError) => {
            this.appPickerError = err.message ?? JSON.stringify(err);
          });
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: this.statusBarPadding() + 22, bottom: 18 })
    .backgroundColor(CARD_BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .shadow({ radius: 14, color: '#10000000', offsetX: 0, offsetY: 2 })
    .zIndex(2)
  }

  @Builder
  private buildMainHeader() {
    Row() {
      Row() {
        Image($r('app.media.ic_key_blue'))
          .width(24)
          .height(24)
          .margin({ right: 12 })
        Text('SmartAgent')
          .fontSize(23)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.statusBarPadding() + 76)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 22, right: 22, top: this.statusBarPadding() + 16 })
    .backgroundColor(CARD_BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  @Builder
  private buildMainTabs() {
    Column() {
      this.buildAnimatedTabBar();

      Tabs({ barPosition: BarPosition.Start, index: this.currentTabIndex }) {
        TabContent() {
          TunnelsPage({
            tunnels: this.tunnels,
            busy: this.busy,
            runtimeRunning: this.runtimeRunning,
            activeTunnelId: this.activeTunnelId,
            runtimeTunnelId: this.runtimeTunnelId,
            runtimeTunnelName: this.runtimeTunnelName,
            runtimeTxBytes: this.runtimeTxBytes,
            runtimeRxBytes: this.runtimeRxBytes,
            runtimeLatestHandshakeSeconds: this.runtimeLatestHandshakeSeconds,
            startingTunnelId: this.startingTunnelId,
            startingTunnelName: this.startingTunnelName,
            onImportConfig: () => {
              this.importConfig().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onCreateTunnel: () => {
              this.createNewTunnelDraft();
            },
            onOpenTunnel: (tunnel: TunnelConfig) => {
              this.openTunnel(tunnel);
            },
            onToggleTunnel: (tunnel: TunnelConfig) => {
              this.toggleTunnel(tunnel).catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            }
          });
        }
        .height('100%')
        .layoutWeight(1)

        TabContent() {
          RulesPage({
            appSplitEnabled: this.appSplitEnabled,
            smartAgentEnabled: this.smartAgentEnabled,
            agentRules: this.agentRules,
            tunnels: this.tunnels,
            dohEnabled: this.dohEnabled,
            dohProvider: this.dohProvider,
            browserDohEnabled: this.browserDohEnabled,
            browserDohProvider: this.browserDohProvider,
            selectedSplitAppCount: this.selectedSplitApps.length,
            onToggleAppSplit: () => {
              this.toggleAppSplit().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onToggleSmartAgent: () => {
              this.toggleSmartAgent().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onSaveAgentRule: (rule: AgentRule) => {
              return this.saveAgentRuleFromPage(rule).catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
                throw new Error(err.message ?? JSON.stringify(err));
              });
            },
            onDeleteAgentRule: (ruleId: string) => {
              this.deleteAgentRuleFromPage(ruleId).catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onReorderAgentRule: (ruleId: string, targetIndex: number) => {
              this.reorderAgentRuleFromPage(ruleId, targetIndex).catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onToggleDoh: () => {
              this.toggleDohEnabled().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onSelectDohProvider: (provider: string) => {
              this.selectDohProvider(provider).catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onToggleBrowserDoh: () => {
              this.toggleBrowserDohEnabled().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onSelectBrowserDohProvider: (provider: string) => {
              this.selectBrowserDohProvider(provider).catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onOpenAppPicker: () => {
              this.openAppPicker().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onOpenIssueReport: () => {
              this.openIssueReport().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            }
          });
        }
        .height('100%')
        .layoutWeight(1)

        TabContent() {
          LogsPage({
            logs: this.logs,
            onClearLogs: () => {
              this.clearLogs();
            },
            onRefreshLogs: async () => {
              await this.loadLogs();
            }
          });
        }
        .height('100%')
        .layoutWeight(1)
      }
      .barHeight(0)
      .vertical(false)
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        this.updateTabIndicatorFromSwipe(index, event.currentOffset);
      })
      .onAnimationStart((index: number, targetIndex: number) => {
        this.animateTabIndicatorTo(targetIndex);
      })
      .onAnimationEnd((index: number) => {
        this.completeTabIndicator(index);
      })
      .onChange((index: number) => {
        this.setCurrentTab(index);
      })
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(PAGE_BACKGROUND)
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private buildAnimatedTabBar() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row() {
        this.buildTabButton('Tunnels', TAB_TUNNELS);
        this.buildTabButton('Rules', TAB_RULES);
        this.buildTabButton('Logs', TAB_LOGS);
      }
      .width('100%')
      .height(54)

      Row() {
      }
        .width(48)
        .height(4)
        .backgroundColor(PRIMARY_BLUE)
        .borderRadius(3)
        .offset({ x: this.tabIndicatorOffset(), y: 0 })
        .animation({ duration: this.tabIndicatorAnimationDuration, curve: Curve.EaseInOut })
    }
    .width('100%')
    .height(this.bottomBarHeight())
    .backgroundColor(CARD_BACKGROUND)
    .padding({ bottom: this.navigationBarPadding() })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.tabBarWidth = Number(newValue.width);
    })
  }

  @Builder
  private buildTabButton(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.highlightedTabIndex === index ? PRIMARY_BLUE : '#777A80')
        .height(44)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .height(54)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.setCurrentTab(index);
    })
  }

  private async loadTunnelList(): Promise<void> {
    const loadVersion = ++this.tunnelLoadVersion;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const tunnels = await loadTunnels(context);
      if (loadVersion !== this.tunnelLoadVersion) {
        return;
      }
      this.tunnels = tunnels;
      if (tunnels.length === 0) {
        this.statusText = 'No tunnels';
      }
    } catch (err) {
      if (loadVersion !== this.tunnelLoadVersion) {
        return;
      }
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    }
  }

  private openTunnel(tunnel: TunnelConfig): void {
    this.editingTunnelId = tunnel.id;
    this.editingName = tunnel.name;
    this.editingConfig = tunnel.configText;
  }

  private createNewTunnelDraft(): void {
    this.editingTunnelId = createTunnelId();
    this.editingName = '';
    this.editingConfig = DEFAULT_WG_CONFIG;
  }

  private closeEditor(): void {
    this.editingTunnelId = '';
    this.editingName = '';
    this.editingConfig = DEFAULT_WG_CONFIG;
  }

  private closeAppPicker(): void {
    this.appPickerOpen = false;
    this.appPickerLoading = false;
    this.appPickerError = '';
    this.appBundleNameInput = '';
    this.appPickerNotice = '';
    this.availableSplitApps = [];
    this.draftSelectedBundleNames = [];
  }

  onBackPress(): boolean {
    return false;
  }

  private async loadAppSplitSettings(): Promise<void> {
    const loadVersion = ++this.appSplitLoadVersion;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const appSplitEnabled = await loadAppSplitEnabled(context, true);
      const selectedSplitApps = await loadSelectedSplitApps(context, true);
      if (loadVersion !== this.appSplitLoadVersion) {
        return;
      }
      this.appSplitEnabled = appSplitEnabled;
      this.selectedSplitApps = selectedSplitApps;
    } catch (err) {
      if (loadVersion !== this.appSplitLoadVersion) {
        return;
      }
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load app split settings failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async loadSmartAgentSettings(): Promise<void> {
    const loadVersion = ++this.smartAgentLoadVersion;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const smartAgentEnabled = await loadSmartAgentEnabled(context, true);
      const agentRules = await loadAgentRules(context, true);
      if (loadVersion !== this.smartAgentLoadVersion) {
        return;
      }
      this.smartAgentEnabled = smartAgentEnabled;
      this.agentRules = agentRules;
    } catch (err) {
      if (loadVersion !== this.smartAgentLoadVersion) {
        return;
      }
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load smart agent settings failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async loadDohSettings(): Promise<void> {
    const loadVersion = ++this.dohLoadVersion;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const settings = await loadDohSettings(context, true);
      if (loadVersion !== this.dohLoadVersion) {
        return;
      }
      this.dohEnabled = settings.enabled;
      this.dohProvider = settings.provider;
    } catch (err) {
      if (loadVersion !== this.dohLoadVersion) {
        return;
      }
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load doh settings failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async loadBrowserDohSettings(): Promise<void> {
    const loadVersion = ++this.browserDohLoadVersion;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const settings = await loadBrowserDohSettings(context, true);
      if (loadVersion !== this.browserDohLoadVersion) {
        return;
      }
      this.browserDohEnabled = settings.enabled;
      this.browserDohProvider = settings.provider;
    } catch (err) {
      if (loadVersion !== this.browserDohLoadVersion) {
        return;
      }
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load browser doh settings failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async toggleSmartAgent(): Promise<void> {
    this.smartAgentLoadVersion++;
    const nextEnabled = !this.smartAgentEnabled;
    this.smartAgentEnabled = nextEnabled;
    const context = getContext(this) as common.UIAbilityContext;
    await saveSmartAgentEnabled(context, nextEnabled);
    await this.refreshVpnStatusForIndependentSettings('smart agent toggle');
  }

  private async saveAgentRuleFromPage(rule: AgentRule): Promise<void> {
    this.smartAgentLoadVersion++;
    const normalizedRule = this.normalizeAgentRuleForSave(rule);
    if (normalizedRule.targetTunnelId.length > 0) {
      normalizedRule.targetTunnelName = this.resolveTunnelName(normalizedRule.targetTunnelId, normalizedRule.targetTunnelName);
    }

    const nextRules: AgentRule[] = [];
    let found = false;
    for (let index = 0; index < this.agentRules.length; index++) {
      const existing = this.agentRules[index];
      if (existing.id === normalizedRule.id) {
        nextRules.push(normalizedRule);
        found = true;
      } else {
        nextRules.push(existing);
      }
    }
    if (!found) {
      nextRules.push(normalizedRule);
    }

    const context = getContext(this) as common.UIAbilityContext;
    hilog.info(
      DOMAIN,
      TAG,
      'saveAgentRuleFromPage begin rule=%{public}s existing=%{public}s next=%{public}s',
      this.describeAgentRule(normalizedRule),
      this.describeAgentRules(this.agentRules),
      this.describeAgentRules(nextRules)
    );
    await saveAgentRules(context, nextRules);
    const persistedRules = await loadAgentRules(context, true);
    const persistedRule = this.findAgentRuleById(persistedRules, normalizedRule.id);
    this.agentRules = persistedRules;
    if (persistedRule === undefined || !this.sameAgentRuleValue(persistedRule, normalizedRule)) {
      hilog.warn(
        DOMAIN,
        TAG,
        'saveAgentRuleFromPage verification failed expected=%{public}s persisted=%{public}s persistedList=%{public}s',
        this.describeAgentRule(normalizedRule),
        this.describeAgentRuleOrMissing(persistedRule),
        this.describeAgentRules(persistedRules)
      );
      throw new Error('rule save verification failed');
    }
    hilog.info(
      DOMAIN,
      TAG,
      'saveAgentRuleFromPage verified rule=%{public}s persistedList=%{public}s',
      this.describeAgentRule(persistedRule),
      this.describeAgentRules(persistedRules)
    );
    this.statusText = 'Rules updated';
    this.refreshIndependentSettingsInBackground('smart agent rules');
  }

  private async deleteAgentRuleFromPage(ruleId: string): Promise<void> {
    this.smartAgentLoadVersion++;
    const nextRules: AgentRule[] = [];
    for (let index = 0; index < this.agentRules.length; index++) {
      const rule = this.agentRules[index];
      if (rule.id !== ruleId) {
        nextRules.push(rule);
      }
    }

    const context = getContext(this) as common.UIAbilityContext;
    await saveAgentRules(context, nextRules);
    this.agentRules = nextRules;
    this.statusText = 'Rules updated';
    this.refreshIndependentSettingsInBackground('smart agent rules');
  }

  private async reorderAgentRuleFromPage(ruleId: string, targetIndex: number): Promise<void> {
    this.smartAgentLoadVersion++;
    const currentIndex = this.indexOfAgentRule(ruleId);
    if (currentIndex < 0) {
      return;
    }

    if (targetIndex < 0 || targetIndex >= this.agentRules.length) {
      return;
    }

    const nextRules: AgentRule[] = [];
    for (let index = 0; index < this.agentRules.length; index++) {
      if (index !== currentIndex) {
        nextRules.push(this.agentRules[index]);
      }
    }

    const insertIndex = targetIndex;
    if (insertIndex >= nextRules.length) {
      nextRules.push(this.agentRules[currentIndex]);
    } else {
      const reorderedRules: AgentRule[] = [];
      for (let index = 0; index < nextRules.length; index++) {
        if (index === insertIndex) {
          reorderedRules.push(this.agentRules[currentIndex]);
        }
        reorderedRules.push(nextRules[index]);
      }
      nextRules.length = 0;
      for (let index = 0; index < reorderedRules.length; index++) {
        nextRules.push(reorderedRules[index]);
      }
    }

    this.agentRules = nextRules;
    const context = getContext(this) as common.UIAbilityContext;
    await saveAgentRules(context, nextRules);
    this.statusText = 'Rules updated';
    this.refreshIndependentSettingsInBackground('smart agent rule order');
  }

  private async toggleDohEnabled(): Promise<void> {
    this.dohLoadVersion++;
    const nextEnabled = !this.dohEnabled;
    this.dohEnabled = nextEnabled;
    const context = getContext(this) as common.UIAbilityContext;
    await saveDohSettings(context, {
      enabled: nextEnabled,
      provider: this.dohProvider
    });
    await this.restartVpnIfRunning('tunnel doh toggle');
  }

  private async toggleBrowserDohEnabled(): Promise<void> {
    this.browserDohLoadVersion++;
    const nextEnabled = !this.browserDohEnabled;
    this.browserDohEnabled = nextEnabled;
    const context = getContext(this) as common.UIAbilityContext;
    await saveBrowserDohSettings(context, {
      enabled: nextEnabled,
      provider: this.browserDohProvider
    });
    applyWebHttpDnsFromDohSettings({
      enabled: nextEnabled,
      provider: this.browserDohProvider
    });
    await this.refreshVpnStatusForIndependentSettings('browser doh toggle');
  }

  private async toggleAppSplit(): Promise<void> {
    this.appSplitLoadVersion++;
    const nextEnabled = !this.appSplitEnabled;
    this.appSplitEnabled = nextEnabled;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await saveAppSplitEnabled(context, nextEnabled);
      await this.restartVpnIfRunning('app split toggle');
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    }
  }

  private async openAppPicker(): Promise<void> {
    if (!this.appSplitEnabled) {
      return;
    }

    this.appPickerOpen = true;
    this.draftSelectedBundleNames = this.bundleNamesForApps(this.selectedSplitApps);
    await this.loadAvailableSplitApps();
  }

  private async loadAvailableSplitApps(): Promise<void> {
    this.appPickerLoading = true;
    this.appPickerError = '';
    this.availableSplitApps = this.mergeSelectedSplitApps(PRESET_SPLIT_APPS);
    this.appPickerLoading = false;
    hilog.info(DOMAIN, TAG, 'loaded manual split app list count=%{public}d', this.availableSplitApps.length);
  }

  private async addSplitAppByBundleName(): Promise<void> {
    const bundleName = this.normalizeBundleName(this.appBundleNameInput);
    if (bundleName.length === 0) {
      this.appPickerNotice = '请输入应用包名';
      return;
    }
    if (bundleName === BUNDLE_NAME) {
      this.appPickerNotice = '不能选择当前 VPN 应用';
      return;
    }
    if (this.hasSplitApp(this.availableSplitApps, bundleName)) {
      this.toggleDraftBundleOn(bundleName);
      this.appBundleNameInput = '';
      this.appPickerNotice = '已在列表中';
      return;
    }

    const app: SplitAppInfo = {
      bundleName: bundleName,
      label: bundleName
    };
    this.availableSplitApps = this.appendAndSortSplitApp(this.availableSplitApps, app);
    this.toggleDraftBundleOn(app.bundleName);
    this.appBundleNameInput = '';
    this.appPickerNotice = '已添加 ' + app.bundleName;
  }

  private appendAndSortSplitApp(apps: SplitAppInfo[], app: SplitAppInfo): SplitAppInfo[] {
    const nextApps: SplitAppInfo[] = [];
    let exists = false;
    for (let index = 0; index < apps.length; index++) {
      const existing = apps[index];
      if (existing.bundleName === app.bundleName) {
        nextApps.push(app);
        exists = true;
      } else {
        nextApps.push(existing);
      }
    }
    if (!exists) {
      nextApps.push(app);
    }
    nextApps.sort((left: SplitAppInfo, right: SplitAppInfo) => left.label.localeCompare(right.label));
    return nextApps;
  }

  private hasSplitApp(apps: SplitAppInfo[], bundleName: string): boolean {
    for (let index = 0; index < apps.length; index++) {
      if (apps[index].bundleName === bundleName) {
        return true;
      }
    }
    return false;
  }

  private mergeSelectedSplitApps(apps: SplitAppInfo[]): SplitAppInfo[] {
    const merged: SplitAppInfo[] = [];
    const bundleNames: string[] = [];
    for (let index = 0; index < apps.length; index++) {
      const app = apps[index];
      merged.push(app);
      bundleNames.push(app.bundleName);
    }

    for (let index = 0; index < this.selectedSplitApps.length; index++) {
      const app = this.selectedSplitApps[index];
      if (!this.hasString(bundleNames, app.bundleName)) {
        merged.push(app);
        bundleNames.push(app.bundleName);
      }
    }
    return merged;
  }

  private async saveAppPickerSelection(): Promise<void> {
    this.appSplitLoadVersion++;
    const selectedApps: SplitAppInfo[] = [];
    for (let index = 0; index < this.availableSplitApps.length; index++) {
      const app = this.availableSplitApps[index];
      if (this.isDraftAppSelected(app.bundleName)) {
        selectedApps.push(app);
      }
    }

    const context = getContext(this) as common.UIAbilityContext;
    await saveSelectedSplitApps(context, selectedApps);
    this.selectedSplitApps = selectedApps;
    this.closeAppPicker();
    await this.restartVpnIfRunning('app split apps');
  }

  private async restartVpnIfRunning(reason: string): Promise<void> {
    if (!this.runtimeRunning && !this.vpnEnabled) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'restart vpn for config change reason=%{public}s', reason);
    await vpnExtension.startVpnExtensionAbility(this.buildWant());
    this.statusText = 'Rules updated';
  }

  private async refreshVpnStatusForIndependentSettings(reason: string): Promise<void> {
    hilog.info(DOMAIN, TAG, 'settings updated without vpn restart reason=%{public}s', reason);
    this.statusText = 'Rules updated';
  }

  private refreshIndependentSettingsInBackground(reason: string): void {
    this.refreshVpnStatusForIndependentSettings(reason).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'background settings refresh failed reason=%{public}s error=%{public}s',
        reason, err.message ?? JSON.stringify(err));
    });
  }

  private async loadLogs(): Promise<void> {
    const loadVersion = ++this.logsLoadVersion;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const logs = await loadAgentLogs(context, true);
      if (loadVersion !== this.logsLoadVersion) {
        return;
      }
      this.logs = logs;
    } catch (err) {
      if (loadVersion !== this.logsLoadVersion) {
        return;
      }
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load logs failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async clearLogs(): Promise<void> {
    try {
      this.logsLoadVersion++;
      const context = getContext(this) as common.UIAbilityContext;
      await clearAgentLogs(context);
      this.logs = [];
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'clear logs failed: %{public}s', error.message ?? JSON.stringify(err));
      this.statusText = error.message ?? JSON.stringify(err);
    }
  }

  private bundleNamesForApps(apps: SplitAppInfo[]): string[] {
    const bundleNames: string[] = [];
    for (let index = 0; index < apps.length; index++) {
      bundleNames.push(apps[index].bundleName);
    }
    return bundleNames;
  }

  private isDraftAppSelected(bundleName: string): boolean {
    return this.hasString(this.draftSelectedBundleNames, bundleName);
  }

  private toggleDraftSplitApp(bundleName: string): void {
    const nextBundleNames: string[] = [];
    let removed = false;
    for (let index = 0; index < this.draftSelectedBundleNames.length; index++) {
      const value = this.draftSelectedBundleNames[index];
      if (value === bundleName) {
        removed = true;
      } else {
        nextBundleNames.push(value);
      }
    }

    if (!removed) {
      nextBundleNames.push(bundleName);
    }
    this.draftSelectedBundleNames = nextBundleNames;
  }

  private toggleDraftBundleOn(bundleName: string): void {
    if (this.hasString(this.draftSelectedBundleNames, bundleName)) {
      return;
    }

    const nextBundleNames: string[] = [];
    for (let index = 0; index < this.draftSelectedBundleNames.length; index++) {
      nextBundleNames.push(this.draftSelectedBundleNames[index]);
    }
    nextBundleNames.push(bundleName);
    this.draftSelectedBundleNames = nextBundleNames;
  }

  private normalizeBundleName(value: string): string {
    return value.trim();
  }

  private hasString(values: string[], value: string): boolean {
    for (let index = 0; index < values.length; index++) {
      if (values[index] === value) {
        return true;
      }
    }
    return false;
  }

  private normalizeAgentRuleForSave(rule: AgentRule): AgentRule {
    const normalizedId = rule.id.length > 0 ? rule.id : createAgentRuleId();
    const normalized: AgentRule = {
      id: normalizedId,
      type: rule.type,
      matchValue: rule.matchValue.trim(),
      targetTunnelId: rule.targetTunnelId,
      targetTunnelName: rule.targetTunnelName.trim(),
      enabled: rule.enabled
    };
    return normalized;
  }

  private indexOfAgentRule(ruleId: string): number {
    for (let index = 0; index < this.agentRules.length; index++) {
      if (this.agentRules[index].id === ruleId) {
        return index;
      }
    }
    return -1;
  }

  private findAgentRuleById(rules: AgentRule[], ruleId: string): AgentRule | undefined {
    for (let index = 0; index < rules.length; index++) {
      if (rules[index].id === ruleId) {
        return rules[index];
      }
    }
    return undefined;
  }

  private sameAgentRuleValue(left: AgentRule, right: AgentRule): boolean {
    return left.id === right.id &&
      left.type === right.type &&
      left.matchValue === right.matchValue &&
      left.targetTunnelId === right.targetTunnelId &&
      left.targetTunnelName === right.targetTunnelName &&
      left.enabled === right.enabled;
  }

  private describeAgentRules(rules: AgentRule[]): string {
    if (rules.length === 0) {
      return '<empty>';
    }

    const parts: string[] = [];
    for (let index = 0; index < rules.length; index++) {
      parts.push(this.describeAgentRule(rules[index]));
    }
    return parts.join('|');
  }

  private describeAgentRuleOrMissing(rule: AgentRule | undefined): string {
    if (rule === undefined) {
      return '<missing>';
    }
    return this.describeAgentRule(rule);
  }

  private describeAgentRule(rule: AgentRule): string {
    const target = rule.targetTunnelId.length > 0 ? rule.targetTunnelId : 'direct';
    const value = rule.matchValue.length > 0 ? rule.matchValue : '-';
    return this.shortRuleId(rule.id) + ':' + rule.type + ':' + value + ':' + target + ':' + (rule.enabled ? 'on' : 'off');
  }

  private shortRuleId(ruleId: string): string {
    if (ruleId.length <= 8) {
      return ruleId;
    }
    return ruleId.substring(ruleId.length - 8);
  }

  private resolveTunnelName(tunnelId: string, fallbackName: string): string {
    for (let index = 0; index < this.tunnels.length; index++) {
      const tunnel = this.tunnels[index];
      if (tunnel.id === tunnelId) {
        return tunnel.name;
      }
    }
    return fallbackName;
  }

  private async saveEditingTunnel(): Promise<void> {
    if (this.editingTunnelId.length === 0) {
      return;
    }
    if (this.isEditingActiveTunnel()) {
      this.statusText = 'Stop VPN before editing';
      return;
    }

    this.busy = true;
    try {
      parseWireGuardConfig(this.editingConfig);
      const context = getContext(this) as common.UIAbilityContext;
      const name = this.normalizedTunnelName(this.editingName);
      const tunnel: TunnelConfig = {
        id: this.editingTunnelId,
        name: name,
        configText: this.editingConfig
      };
      await saveTunnel(context, tunnel);
      this.tunnelLoadVersion++;
      this.tunnels = await loadTunnels(context);
      this.closeEditor();
      this.statusText = 'Saved';
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    } finally {
      this.busy = false;
    }
  }

  private async importConfig(): Promise<void> {
    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = CONFIG_FILE_SUFFIX_FILTERS;
      options.maxSelectNumber = 1;

      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        this.statusText = 'Import canceled';
        return;
      }

      const importedConfig = await this.readImportedText(uris[0]);
      parseWireGuardConfig(importedConfig);
      const tunnel: TunnelConfig = {
        id: createTunnelId(),
        name: this.nextTunnelName(),
        configText: importedConfig
      };
      await saveTunnel(context, tunnel);
      this.tunnelLoadVersion++;
      this.tunnels = await loadTunnels(context);
      this.openTunnel(tunnel);
      this.statusText = 'Imported';
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    } finally {
      this.busy = false;
    }
  }

  private async readImportedText(uri: string): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(MAX_IMPORT_CONFIG_BYTES);
      const readOptions: ReadOptions = {
        length: MAX_IMPORT_CONFIG_BYTES
      };
      const bytesRead = await fileIo.read(file.fd, data, readOptions);
      if (bytesRead <= 0) {
        return '';
      }
      if (bytesRead >= MAX_IMPORT_CONFIG_BYTES) {
        throw new Error('Config file is too large');
      }

      const bytes = new Uint8Array(data, 0, bytesRead);
      return buffer.from(bytes).toString('utf8');
    } finally {
      await fileIo.close(file);
    }
  }

  private async toggleTunnel(tunnel: TunnelConfig): Promise<void> {
    this.busy = true;
    try {
      if (this.isTunnelRunning(tunnel)) {
        await this.stopActiveVpn();
        return;
      }

      await this.startTunnel(tunnel);
    } catch (err) {
      const error = err as BusinessError;
      if (this.startingTunnelId === tunnel.id) {
        this.clearRequestedRuntimeTunnel();
      }
      this.statusText = error.message ?? JSON.stringify(err);
    } finally {
      this.busy = false;
    }
  }

  private async startTunnel(tunnel: TunnelConfig): Promise<void> {
    hilog.info(DOMAIN, TAG, 'start tunnel requested id=%{public}s name=%{public}s', tunnel.id, tunnel.name);
    parseWireGuardConfig(tunnel.configText);
    this.markRequestedRuntimeTunnel(tunnel);
    const context = getContext(this) as common.UIAbilityContext;
    const notificationEnabled = await this.ensureNotificationEnabled(context);
    const switching = this.runtimeRunning || this.vpnEnabled;

    await saveActiveTunnel(context, tunnel);
    hilog.info(DOMAIN, TAG, 'active tunnel saved id=%{public}s name=%{public}s', tunnel.id, tunnel.name);
    await saveTunnelRuntimeStatus(context, this.buildPendingRuntimeStatus(tunnel));
    await startVpnDataTransferTask(context);
    try {
      await vpnExtension.startVpnExtensionAbility(this.buildWant());
    } catch (err) {
      await this.stopVpnContinuousTask(context, 'start vpn rollback');
      await saveTunnelRuntimeStatus(context, this.buildStoppedRuntimeStatus());
      const error = err as BusinessError;
      throw new Error(error.message ?? JSON.stringify(err));
    }
    this.vpnEnabled = true;
    this.activeTunnelId = tunnel.id;
    this.runtimeRunning = true;
    this.runtimeTunnelId = tunnel.id;
    this.runtimeTunnelName = tunnel.name;
    this.runtimeTxBytes = 0;
    this.runtimeRxBytes = 0;
    this.runtimeLatestHandshakeSeconds = -1;
    this.runtimeLatestPacketSentSeconds = -1;
    this.runtimeRttMillis = -1;
    this.runtimeUpdatedAt = Date.now();
    if (switching) {
      this.statusText = notificationEnabled ? 'Switched: ' + tunnel.name : 'Switched, notification disabled';
    } else {
      this.statusText = notificationEnabled ? 'Enabled: ' + tunnel.name : 'Enabled, notification disabled';
    }
    hilog.info(
      DOMAIN,
      TAG,
      'start vpn extension returned id=%{public}s name=%{public}s switching=%{public}s',
      tunnel.id,
      tunnel.name,
      String(switching)
    );
  }

  private async stopActiveVpn(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'stop active vpn requested activeId=%{public}s runtimeRunning=%{public}s', this.activeTunnelId, String(this.runtimeRunning));
    const context = getContext(this) as common.UIAbilityContext;
    await vpnExtension.stopVpnExtensionAbility(this.buildWant());
    await this.stopVpnContinuousTask(context, 'stop vpn');
    await clearActiveTunnel(context);
    await saveTunnelRuntimeStatus(context, this.buildStoppedRuntimeStatus());
    this.vpnEnabled = false;
    this.activeTunnelId = '';
    this.runtimeRunning = false;
    this.runtimeTunnelId = '';
    this.runtimeTunnelName = '';
    this.runtimeTxBytes = 0;
    this.runtimeRxBytes = 0;
    this.runtimeLatestHandshakeSeconds = -1;
    this.runtimeLatestPacketSentSeconds = -1;
    this.runtimeRttMillis = -1;
    this.runtimeUpdatedAt = Date.now();
    this.runtimeConfirmedRunning = false;
    this.clearRequestedRuntimeTunnel();
    this.statusText = 'Stopped';
    hilog.info(DOMAIN, TAG, 'stop active vpn finished');
  }

  private async stopVpnContinuousTask(context: common.UIAbilityContext, reason: string): Promise<void> {
    try {
      await stopVpnDataTransferTask(context);
      hilog.info(DOMAIN, TAG, 'continuous task stopped reason=%{public}s', reason);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'stop continuous task failed reason=%{public}s code=%{public}d message=%{public}s',
        reason,
        error.code,
        error.message ?? JSON.stringify(err)
      );
    }
  }

  private async deleteTunnelById(tunnelId: string): Promise<void> {
    if (tunnelId.length === 0) {
      return;
    }
    if (!this.isSavedTunnelId(tunnelId)) {
      if (this.editingTunnelId === tunnelId) {
        this.closeEditor();
      }
      return;
    }
    if (this.vpnEnabled && this.activeTunnelId === tunnelId) {
      this.statusText = 'Stop VPN before deleting';
      return;
    }

    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await deleteTunnel(context, tunnelId);
      this.tunnelLoadVersion++;
      this.tunnels = await loadTunnels(context);
      if (this.editingTunnelId === tunnelId) {
        this.closeEditor();
      }
      this.statusText = 'Deleted';
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    } finally {
      this.busy = false;
    }
  }

  private markRequestedRuntimeTunnel(tunnel: TunnelConfig): void {
    this.startingTunnelId = tunnel.id;
    this.startingTunnelName = tunnel.name;
    this.runtimeUpdatedAt = Date.now();
    this.startingTunnelAt = Date.now();
    this.runtimeConfirmedRunning = false;
  }

  private clearRequestedRuntimeTunnel(): void {
    this.startingTunnelId = '';
    this.startingTunnelName = '';
    this.startingTunnelAt = 0;
  }

  private isRuntimeActive(): boolean {
    return this.runtimeRunning || this.startingTunnelId.length > 0;
  }

  private isTunnelRunning(tunnel: TunnelConfig): boolean {
    if (this.startingTunnelId === tunnel.id) {
      return true;
    }
    if (!this.runtimeRunning) {
      return false;
    }
    if (this.activeTunnelId.length === 0) {
      return this.runtimeTunnelName.length > 0 && this.runtimeTunnelName === tunnel.name;
    }
    return this.activeTunnelId === tunnel.id;
  }

  private isEditingActiveTunnel(): boolean {
    if (this.startingTunnelId.length > 0 && this.startingTunnelId === this.editingTunnelId) {
      return true;
    }
    if (!this.runtimeRunning) {
      return false;
    }
    if (this.activeTunnelId.length === 0) {
      return this.runtimeTunnelName.length > 0 && this.runtimeTunnelName === this.editingName;
    }
    return this.activeTunnelId === this.editingTunnelId;
  }

  private isSavedEditingTunnel(): boolean {
    return this.isSavedTunnelId(this.editingTunnelId);
  }

  private isSavedTunnelId(tunnelId: string): boolean {
    if (tunnelId.length === 0) {
      return false;
    }
    for (let index = 0; index < this.tunnels.length; index++) {
      if (this.tunnels[index].id === tunnelId) {
        return true;
      }
    }
    return false;
  }

  private startStatusRefresh(): void {
    this.stopStatusRefresh();
    this.statusRefreshTimer = setInterval(() => {
      this.refreshRuntimeStatus();
    }, STATUS_REFRESH_INTERVAL_MS);
  }

  private stopStatusRefresh(): void {
    if (this.statusRefreshTimer >= 0) {
      clearInterval(this.statusRefreshTimer);
      this.statusRefreshTimer = -1;
    }
  }

  private async refreshRuntimeStatus(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const status: TunnelRuntimeStatus = await loadTunnelRuntimeStatus(context, true);
      const runtimeAlive = this.isRuntimeStatusAlive(status);
      const wasRunning = this.runtimeRunning || this.vpnEnabled || runtimeAlive;
      if (this.currentTabIndex === TAB_LOGS) {
        this.logs = await loadAgentLogs(context, true);
      }

      const pendingStart = this.isStartupGraceActive(status);
      const running = runtimeAlive || pendingStart;
      const hasRuntimeStats = running;

      const resolvedTunnelId = running ? this.resolveRuntimeTunnelId(status, this.activeTunnelId) : '';
      const resolvedTunnelName = running ? this.resolveRuntimeTunnelName(status, resolvedTunnelId, this.runtimeTunnelName) : '';
      this.runtimeRunning = running;
      this.runtimeTunnelId = hasRuntimeStats ? resolvedTunnelId : '';
      this.runtimeTunnelName = hasRuntimeStats ? resolvedTunnelName : '';
      this.runtimeTxBytes = hasRuntimeStats ? status.txBytes : 0;
      this.runtimeRxBytes = hasRuntimeStats ? status.rxBytes : 0;
      this.runtimeLatestHandshakeSeconds = hasRuntimeStats ? status.latestHandshakeSeconds : -1;
      this.runtimeLatestPacketSentSeconds = hasRuntimeStats ? status.latestPacketSentSeconds : -1;
      this.runtimeRttMillis = hasRuntimeStats ? status.rttMillis : -1;
      this.runtimeUpdatedAt = status.updatedAt;
      this.vpnEnabled = running;
      this.activeTunnelId = resolvedTunnelId;
      if (runtimeAlive) {
        this.runtimeConfirmedRunning = true;
        this.startingTunnelId = resolvedTunnelId;
        this.startingTunnelName = resolvedTunnelName;
        this.startingTunnelAt = 0;
      } else {
        this.clearRequestedRuntimeTunnel();
      }

      if (wasRunning && !running && await this.shouldKeepRuntimeAliveDuringGrace(context, status)) {
        this.vpnEnabled = true;
        const reconnectingName = this.resolveRuntimeTunnelName(status, this.activeTunnelId, this.runtimeTunnelName);
        this.statusText = reconnectingName.length > 0 ? 'Reconnecting: ' + reconnectingName : 'Reconnecting';
        hilog.warn(DOMAIN, TAG, 'ignore transient stopped runtime during grace age=%{public}d', this.runtimeStatusAge(status));
      } else if (wasRunning && !running && !this.busy && this.runtimeConfirmedRunning) {
        this.runtimeConfirmedRunning = false;
        await this.stopVpnContinuousTask(context, 'runtime stopped');
        this.statusText = 'Stopped';
        hilog.info(DOMAIN, TAG, 'runtime transitioned to stopped');
      } else if (wasRunning && !running && !this.busy) {
        await this.stopVpnContinuousTask(context, 'runtime stopped');
        this.statusText = 'Stopped';
        hilog.info(DOMAIN, TAG, 'runtime reported stopped');
      } else if (!running && !this.runtimeConfirmedRunning) {
        this.statusText = 'Stopped';
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'refresh runtime status failed: %{public}s', error.message ?? JSON.stringify(err));
      if (!this.busy) {
        this.statusText = error.message ?? JSON.stringify(err);
      }
    }
  }

  private isStartupGraceActive(status: TunnelRuntimeStatus): boolean {
    if (this.startingTunnelId.length === 0 || this.startingTunnelAt <= 0) {
      return false;
    }
    if (Date.now() - this.startingTunnelAt > STARTUP_GRACE_MS) {
      return false;
    }
    if (status.running) {
      return false;
    }
    if (status.tunnelId.length > 0 && status.tunnelId !== this.startingTunnelId) {
      return false;
    }
    return true;
  }

  private async shouldKeepRuntimeAliveDuringGrace(
    context: common.UIAbilityContext,
    status: TunnelRuntimeStatus
  ): Promise<boolean> {
    if (this.busy) {
      return true;
    }
    if (!this.runtimeConfirmedRunning && !this.vpnEnabled && this.startingTunnelId.length === 0) {
      return false;
    }
    if (this.activeTunnelId.length === 0 && this.startingTunnelId.length === 0 && this.runtimeTunnelId.length === 0) {
      const activeInfo = await loadActiveTunnelInfo(context, true);
      if (activeInfo.configText.length === 0) {
        return false;
      }
    }
    const age = this.runtimeStatusAge(status);
    return age >= 0 && age <= RUNTIME_STOP_GRACE_MS;
  }

  private runtimeStatusAge(status: TunnelRuntimeStatus): number {
    if (status.updatedAt <= 0) {
      return -1;
    }
    return Date.now() - status.updatedAt;
  }

  private resolveRuntimeTunnelId(status: TunnelRuntimeStatus, activeTunnelId: string = ''): string {
    if (status.tunnelId.length > 0) {
      return status.tunnelId;
    }
    if (activeTunnelId.length > 0) {
      return activeTunnelId;
    }
    if (this.startingTunnelId.length > 0) {
      return this.startingTunnelId;
    }
    if (this.runtimeTunnelId.length > 0) {
      return this.runtimeTunnelId;
    }
    return this.activeTunnelId;
  }

  private resolveRuntimeTunnelName(
    status: TunnelRuntimeStatus,
    tunnelId: string,
    activeTunnelName: string = ''
  ): string {
    if (status.tunnelName.length > 0) {
      return status.tunnelName;
    }
    if (activeTunnelName.length > 0) {
      return activeTunnelName;
    }
    if (this.startingTunnelName.length > 0) {
      return this.startingTunnelName;
    }
    if (this.runtimeTunnelName.length > 0) {
      return this.runtimeTunnelName;
    }
    return this.tunnelNameForId(tunnelId);
  }

  private tunnelNameForId(tunnelId: string): string {
    for (let index = 0; index < this.tunnels.length; index++) {
      const tunnel = this.tunnels[index];
      if (tunnel.id === tunnelId) {
        return tunnel.name;
      }
    }
    return '';
  }

  private setCurrentTab(index: number): void {
    if (index === this.currentTabIndex) {
      return;
    }
    this.currentTabIndex = index;
    this.highlightedTabIndex = index;
    this.animateTabIndicatorTo(index);
    if (index === TAB_LOGS) {
      this.loadLogs();
      return;
    }
    if (index === TAB_TUNNELS) {
      this.ensureActiveTunnelRunningOnVpnHome('tab').catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'vpn tab ensure running failed: %{public}s', err.message ?? JSON.stringify(err));
      });
    }
  }

  private updateTabIndicatorFromSwipe(index: number, currentOffset: number): void {
    if (this.tabBarWidth <= 0) {
      return;
    }

    this.tabIndicatorAnimationDuration = 0;
    this.tabIndicatorProgress = this.clampTabIndicatorProgress(index - currentOffset / this.tabBarWidth);
    this.highlightedTabIndex = this.targetTabIndexForSwipe(index, currentOffset);
  }

  private animateTabIndicatorTo(index: number): void {
    this.tabIndicatorAnimationDuration = 220;
    this.highlightedTabIndex = this.clampTabIndex(index);
    this.tabIndicatorProgress = this.clampTabIndicatorProgress(index);
  }

  private completeTabIndicator(index: number): void {
    this.currentTabIndex = index;
    this.highlightedTabIndex = index;
    this.tabIndicatorAnimationDuration = 220;
    this.tabIndicatorProgress = this.clampTabIndicatorProgress(index);
  }

  private targetTabIndexForSwipe(index: number, currentOffset: number): number {
    if (Math.abs(currentOffset) < 1) {
      return this.clampTabIndex(index);
    }
    if (currentOffset < 0) {
      return this.clampTabIndex(index + 1);
    }
    return this.clampTabIndex(index - 1);
  }

  private clampTabIndex(index: number): number {
    if (index < TAB_TUNNELS) {
      return TAB_TUNNELS;
    }
    if (index > TAB_LOGS) {
      return TAB_LOGS;
    }
    return index;
  }

  private clampTabIndicatorProgress(progress: number): number {
    if (Number.isNaN(progress)) {
      return this.currentTabIndex;
    }
    if (progress < TAB_TUNNELS) {
      return TAB_TUNNELS;
    }
    if (progress > TAB_LOGS) {
      return TAB_LOGS;
    }
    return progress;
  }

  private tabIndicatorOffset(): number {
    if (this.tabBarWidth <= 0) {
      return 0;
    }
    const tabWidth = this.tabBarWidth / 3;
    return tabWidth * this.tabIndicatorProgress + (tabWidth - 48) / 2;
  }

  private statusBarPadding(): number {
    return this.avoidAreaPaddingVp(this.topRectHeight);
  }

  private navigationBarPadding(): number {
    return this.avoidAreaPaddingVp(this.bottomRectHeight);
  }

  private bottomBarHeight(): number {
    return 54 + this.navigationBarPadding();
  }

  private avoidAreaPaddingVp(value: number): number {
    if (value <= 0) {
      return 0;
    }
    return this.getUIContext().px2vp(value);
  }

  private async selectDohProvider(provider: string): Promise<void> {
    if (provider.length === 0 || this.dohProvider === provider) {
      return;
    }
    this.dohLoadVersion++;
    this.dohProvider = provider;
    const context = getContext(this) as common.UIAbilityContext;
    await saveDohSettings(context, {
      enabled: this.dohEnabled,
      provider: this.dohProvider
    });
    await this.restartVpnIfRunning('tunnel doh provider');
  }

  private async selectBrowserDohProvider(provider: string): Promise<void> {
    if (provider.length === 0 || this.browserDohProvider === provider) {
      return;
    }
    this.browserDohLoadVersion++;
    this.browserDohProvider = provider;
    const context = getContext(this) as common.UIAbilityContext;
    await saveBrowserDohSettings(context, {
      enabled: this.browserDohEnabled,
      provider: this.browserDohProvider
    });
    applyWebHttpDnsFromDohSettings({
      enabled: this.browserDohEnabled,
      provider: this.browserDohProvider
    });
    await this.refreshVpnStatusForIndependentSettings('browser doh provider');
  }

  private async openIssueReport(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: ISSUE_REPORT_URL
    };
    await context.startAbility(want);
  }

  private buildStoppedRuntimeStatus(): TunnelRuntimeStatus {
    const status: TunnelRuntimeStatus = {
      running: false,
      tunnelId: '',
      tunnelName: '',
      txBytes: 0,
      rxBytes: 0,
      latestHandshakeSeconds: -1,
      latestPacketSentSeconds: -1,
      loss: 0,
      rttMillis: -1,
      updatedAt: Date.now()
    };
    return status;
  }

  private buildPendingRuntimeStatus(tunnel: TunnelConfig): TunnelRuntimeStatus {
    const status: TunnelRuntimeStatus = {
      running: true,
      tunnelId: tunnel.id,
      tunnelName: tunnel.name,
      txBytes: 0,
      rxBytes: 0,
      latestHandshakeSeconds: -1,
      latestPacketSentSeconds: -1,
      loss: 0,
      rttMillis: -1,
      updatedAt: Date.now()
    };
    return status;
  }

  private buildPendingRuntimeStatusByIdentity(tunnelId: string, tunnelName: string): TunnelRuntimeStatus {
    const status: TunnelRuntimeStatus = {
      running: true,
      tunnelId: tunnelId,
      tunnelName: tunnelName,
      txBytes: 0,
      rxBytes: 0,
      latestHandshakeSeconds: -1,
      latestPacketSentSeconds: -1,
      loss: 0,
      rttMillis: -1,
      updatedAt: Date.now()
    };
    return status;
  }

  private normalizedTunnelName(name: string): string {
    const normalized = name.trim();
    if (normalized.length > 0) {
      return normalized;
    }
    return 'Tunnel';
  }

  private nextTunnelName(): string {
    return 'Tunnel ' + String(this.tunnels.length + 1);
  }

  private async ensureNotificationEnabled(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }

      await notificationManager.requestEnableNotification(context);
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      return false;
    }
  }

  private buildWant(): Want {
    const want: Want = {
      deviceId: '',
      bundleName: BUNDLE_NAME,
      moduleName: MODULE_NAME,
      abilityName: VPN_ABILITY
    };
    return want;
  }

  private buildRestoreWant(): Want {
    const want = this.buildWant();
    want.parameters = {
      action: VPN_ACTION_RESTORE
    };
    return want;
  }

  private async ensureActiveTunnelRunningOnVpnHome(reason: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const activeInfo = await loadActiveTunnelInfo(context, true);
    const hasActiveTunnel = activeInfo.configText.length > 0 || activeInfo.id.length > 0 || activeInfo.name.length > 0;
    if (!hasActiveTunnel) {
      return;
    }

    const runtimeStatus = await loadTunnelRuntimeStatus(context, true);
    if (this.isRuntimeStatusAlive(runtimeStatus)) {
      return;
    }

    hilog.info(
      DOMAIN,
      TAG,
      'vpn home restore requested reason=%{public}s activeId=%{public}s activeName=%{public}s',
      reason,
      activeInfo.id,
      activeInfo.name
    );
    await saveTunnelRuntimeStatus(context, this.buildPendingRuntimeStatusByIdentity(activeInfo.id, activeInfo.name));
    try {
      await startVpnDataTransferTask(context);
      await vpnExtension.startVpnExtensionAbility(this.buildRestoreWant());
    } catch (err) {
      await saveTunnelRuntimeStatus(context, this.buildStoppedRuntimeStatus());
      const error = err as BusinessError;
      throw new Error(error.message ?? JSON.stringify(err));
    }
  }

  private isRuntimeStatusAlive(status: TunnelRuntimeStatus): boolean {
    if (!status.running || status.updatedAt <= 0) {
      return false;
    }
    return Date.now() - status.updatedAt <= VPN_RUNTIME_ALIVE_MAX_AGE_MS;
  }
}
