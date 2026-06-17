import { common, Want } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';
import { fileIo, picker, ReadOptions } from '@kit.CoreFileKit';
import { vpnExtension } from '@kit.NetworkKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  ActiveTunnelInfo,
  AgentLogEntry,
  clearAgentLogs,
  clearActiveTunnel,
  createTunnelId,
  deleteTunnel,
  DEFAULT_DOH_PROVIDER,
  loadActiveTunnelInfo,
  loadAgentLogs,
  loadAppSplitEnabled,
  loadDohSettings,
  loadSelectedSplitApps,
  loadTunnelRuntimeStatus,
  loadTunnels,
  saveActiveTunnel,
  saveAppSplitEnabled,
  saveDohSettings,
  saveSelectedSplitApps,
  saveTunnelRuntimeStatus,
  saveTunnel,
  SplitAppInfo,
  TunnelConfig,
  TunnelRuntimeStatus
} from '../wireguard/ConfigStore';
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
const VPN_ACTION_REFRESH_STATUS = 'refreshStatus';
const CONFIG_FILE_SUFFIX_FILTERS: string[] = ['WireGuard|.conf,.txt'];
const ISSUE_REPORT_URL = 'https://github.com/pnparadise/smart-agent-harmony';
const MAX_IMPORT_CONFIG_BYTES = 64 * 1024;
const STATUS_REFRESH_INTERVAL_MS = 5000;
const STARTUP_GRACE_MS = 15000;
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
  @State private dohEnabled: boolean = true;
  @State private dohProvider: string = DEFAULT_DOH_PROVIDER;
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

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'aboutToAppear');
    this.loadTunnelList();
    this.loadAppSplitSettings();
    this.loadDohSettings();
    this.loadLogs();
    this.refreshRuntimeStatus();
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
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    .backgroundColor(CARD_BACKGROUND)
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
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    .backgroundColor(CARD_BACKGROUND)
    .shadow({ radius: 14, color: '#10000000', offsetX: 0, offsetY: 2 })
    .zIndex(2)
  }

  @Builder
  private buildMainHeader() {
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
    .width('100%')
    .height(76)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 22, right: 22, top: 16 })
    .backgroundColor(CARD_BACKGROUND)
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
            dohEnabled: this.dohEnabled,
            dohProvider: this.dohProvider,
            selectedSplitAppCount: this.selectedSplitApps.length,
            onToggleAppSplit: () => {
              this.toggleAppSplit().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onToggleSmartAgent: () => {
              this.smartAgentEnabled = !this.smartAgentEnabled;
            },
            onToggleDoh: () => {
              this.toggleDohEnabled().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
            },
            onRotateDohProvider: () => {
              this.rotateDohProvider().catch((err: BusinessError) => {
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
    .height(54)
    .backgroundColor(CARD_BACKGROUND)
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
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.tunnels = await loadTunnels(context);
      if (this.tunnels.length === 0) {
        this.statusText = 'No tunnels';
      }
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    }
  }

  private openTunnel(tunnel: TunnelConfig): void {
    this.editingTunnelId = tunnel.id;
    this.editingName = tunnel.name;
    this.editingConfig = tunnel.configText;
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

  private async loadAppSplitSettings(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.appSplitEnabled = await loadAppSplitEnabled(context, true);
      this.selectedSplitApps = await loadSelectedSplitApps(context, true);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load app split settings failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async loadDohSettings(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const settings = await loadDohSettings(context, true);
      this.dohEnabled = settings.enabled;
      this.dohProvider = settings.provider;
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load doh settings failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async toggleDohEnabled(): Promise<void> {
    const nextEnabled = !this.dohEnabled;
    this.dohEnabled = nextEnabled;
    const context = getContext(this) as common.UIAbilityContext;
    await saveDohSettings(context, {
      enabled: nextEnabled,
      provider: this.dohProvider
    });
    await this.restartVpnIfRunning('doh toggle');
  }

  private async toggleAppSplit(): Promise<void> {
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

    hilog.info(DOMAIN, TAG, 'restart vpn for rule change reason=%{public}s', reason);
    await vpnExtension.startVpnExtensionAbility(this.buildWant());
    this.statusText = 'Rules updated';
  }

  private async loadLogs(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.logs = await loadAgentLogs(context, true);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load logs failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async clearLogs(): Promise<void> {
    try {
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
    if (this.vpnEnabled && this.activeTunnelId === tunnelId) {
      this.statusText = 'Stop VPN before deleting';
      return;
    }

    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await deleteTunnel(context, tunnelId);
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

  private startStatusRefresh(): void {
    this.stopStatusRefresh();
    hilog.info(DOMAIN, TAG, 'start runtime status refresh interval=%{public}d', STATUS_REFRESH_INTERVAL_MS);
    this.statusRefreshTimer = setInterval(() => {
      this.refreshRuntimeStatus();
    }, STATUS_REFRESH_INTERVAL_MS);
  }

  private stopStatusRefresh(): void {
    if (this.statusRefreshTimer >= 0) {
      clearInterval(this.statusRefreshTimer);
      this.statusRefreshTimer = -1;
      hilog.info(DOMAIN, TAG, 'stop runtime status refresh');
    }
  }

  private async refreshRuntimeStatus(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const activeInfo: ActiveTunnelInfo = await loadActiveTunnelInfo(context, true);
      this.logs = await loadAgentLogs(context, true);
      let status: TunnelRuntimeStatus = await loadTunnelRuntimeStatus(context, true);
      const wasRunning = this.runtimeRunning || this.vpnEnabled || status.running;
      if (wasRunning || this.startingTunnelId.length > 0) {
        await this.requestRuntimeStatusRefresh();
        await this.sleep(150);
        status = await loadTunnelRuntimeStatus(context, true);
      }

      const pendingStart = this.isStartupGraceActive(status);
      const running = status.running || pendingStart;
      const hasRuntimeStats = running;

      const resolvedTunnelId = running ? this.resolveRuntimeTunnelId(status, activeInfo.id) : '';
      const resolvedTunnelName = running ? this.resolveRuntimeTunnelName(status, resolvedTunnelId, activeInfo.name) : '';
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
      if (status.running) {
        this.runtimeConfirmedRunning = true;
        this.startingTunnelId = resolvedTunnelId;
        this.startingTunnelName = resolvedTunnelName;
        this.startingTunnelAt = 0;
      } else {
        this.clearRequestedRuntimeTunnel();
      }

      if (wasRunning && !running && !this.busy && this.runtimeConfirmedRunning) {
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

  private async rotateDohProvider(): Promise<void> {
    if (this.dohProvider === 'https://dns.alidns.com/dns-query') {
      this.dohProvider = 'https://cloudflare-dns.com/dns-query';
    } else if (this.dohProvider === 'https://cloudflare-dns.com/dns-query') {
      this.dohProvider = 'https://dns.google/dns-query';
    } else {
      this.dohProvider = 'https://dns.alidns.com/dns-query';
    }
    const context = getContext(this) as common.UIAbilityContext;
    await saveDohSettings(context, {
      enabled: this.dohEnabled,
      provider: this.dohProvider
    });
    await this.restartVpnIfRunning('doh provider');
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

  private buildRefreshStatusWant(): Want {
    const want = this.buildWant();
    want.parameters = {
      action: VPN_ACTION_REFRESH_STATUS
    };
    return want;
  }

  private async requestRuntimeStatusRefresh(): Promise<void> {
    try {
      await vpnExtension.startVpnExtensionAbility(this.buildRefreshStatusWant());
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'request runtime status refresh failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private sleep(durationMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, durationMs);
    });
  }
}
