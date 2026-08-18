import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import {
  hasActiveTunnelSelection,
  loadActiveTunnelInfo,
  loadVpnPictureInPictureEnabled,
  loadTunnelRuntimeStatus
} from '../wireguard/ConfigStore';
import { startVpnDataTransferTask, stopVpnDataTransferTask } from '../wireguard/VpnBackgroundTask';
import { SmartAgentStrategy } from '../wireguard/SmartAgentStrategy';
import { syncWebHttpDnsFromDohSettings } from '../wireguard/WebHttpDns';
import { activateImmersiveWindow, configureImmersiveWindow } from './ImmersiveWindow';
import { VpnPictureInPictureManager } from './VpnPictureInPictureManager';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';
const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const VPN_ABILITY = 'WgVpnExtensionAbility';
const VPN_ACTION_RESTORE = 'restore';
const VPN_RUNTIME_ALIVE_MAX_AGE_MS = 10000;
const VPN_PIP_MONITOR_INTERVAL_MS = 3000;
const VPN_PIP_RESTORE_COOLDOWN_MS = 15000;
const VPN_PIP_STARTUP_GRACE_MS = 15000;

export default class EntryAbility extends UIAbility {
  private vpnRestoreInFlight: boolean = false;
  private windowStage?: window.WindowStage;
  private uiContext?: UIContext;
  private vpnPipMonitorTimer: number = -1;
  private lastVpnPipRestoreAt: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
    this.initializeWebEngine();
    this.restoreVpnIfNeeded('onCreate').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restore vpn on create failed: %{public}s', this.formatError(err));
    });
    this.startVpnPictureInPictureMonitor();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onDestroy');
    this.stopVpnPictureInPictureMonitor();
    VpnPictureInPictureManager.getInstance().release();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      configureImmersiveWindow(windowStage, DOMAIN, TAG);
      this.uiContext = windowStage.getMainWindowSync().getUIContext();
      this.activateWindow();
      this.runVpnPictureInPictureMonitor('window ready').catch((monitorErr: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'vpn picture in picture window sync failed: %{public}s', this.formatError(monitorErr));
      });
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onNewWant');
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageDestroy');
    VpnPictureInPictureManager.getInstance().release();
    this.uiContext = undefined;
    this.windowStage = undefined;
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onForeground');
    VpnPictureInPictureManager.getInstance().onForeground();
    this.activateWindow();
    this.restoreVpnIfNeeded('onForeground').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restore vpn on foreground failed: %{public}s', this.formatError(err));
    });
    this.runVpnPictureInPictureMonitor('onForeground').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'vpn picture in picture foreground monitor failed: %{public}s', this.formatError(err));
    });
  }

  private activateWindow(): void {
    const stage = this.windowStage;
    if (stage === undefined) {
      return;
    }
    activateImmersiveWindow(stage, DOMAIN, TAG);
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onBackground');
    this.startVpnBackgroundTaskIfNeeded().catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'start vpn background task failed: %{public}s', this.formatError(err));
    });
    this.restoreVpnIfNeeded('onBackground').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restore vpn on background failed: %{public}s', this.formatError(err));
    });
    this.runVpnPictureInPictureMonitor('onBackground').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'vpn picture in picture background monitor failed: %{public}s', this.formatError(err));
    });
  }

  private startVpnPictureInPictureMonitor(): void {
    this.stopVpnPictureInPictureMonitor();
    this.vpnPipMonitorTimer = setInterval(() => {
      this.runVpnPictureInPictureMonitor('interval').catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'vpn picture in picture monitor failed: %{public}s', this.formatError(err));
      });
    }, VPN_PIP_MONITOR_INTERVAL_MS);
  }

  private stopVpnPictureInPictureMonitor(): void {
    if (this.vpnPipMonitorTimer < 0) {
      return;
    }
    clearInterval(this.vpnPipMonitorTimer);
    this.vpnPipMonitorTimer = -1;
  }

  private async runVpnPictureInPictureMonitor(reason: string): Promise<void> {
    const enabled = await loadVpnPictureInPictureEnabled(this.context, true);
    if (!enabled) {
      this.configureVpnPictureInPicture(false);
      return;
    }

    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    if (!hasActiveTunnelSelection(activeInfo)) {
      this.configureVpnPictureInPicture(false);
      hilog.info(DOMAIN, TAG, 'vpn picture in picture monitor idle reason=%{public}s, no active tunnel', reason);
      return;
    }

    const decision = await new SmartAgentStrategy(this.context).resolveDecision();
    if (!decision.shouldConnectVpn || !hasActiveTunnelSelection(decision.selectedActiveInfo)) {
      this.configureVpnPictureInPicture(false);
      hilog.info(DOMAIN, TAG, 'vpn picture in picture monitor idle reason=%{public}s, smart agent direct', reason);
      return;
    }

    const expectedTunnelId = decision.selectedActiveInfo.id;
    const runtimeStatus = await loadTunnelRuntimeStatus(this.context, true);
    if (this.isRuntimeStatusAlive(
      runtimeStatus.running,
      runtimeStatus.tunnelId,
      runtimeStatus.updatedAt,
      expectedTunnelId
    )) {
      this.configureVpnPictureInPicture(true);
      return;
    }

    this.configureVpnPictureInPicture(true);

    const now = Date.now();
    if (this.isRuntimeStartupPending(
      runtimeStatus.running,
      runtimeStatus.tunnelId,
      runtimeStatus.updatedAt,
      expectedTunnelId
    )) {
      return;
    }

    if (now - this.lastVpnPipRestoreAt < VPN_PIP_RESTORE_COOLDOWN_MS) {
      return;
    }
    this.lastVpnPipRestoreAt = now;
    hilog.warn(
      DOMAIN,
      TAG,
      'vpn picture in picture detected stale runtime reason=%{public}s activeId=%{public}s runtimeId=%{public}s age=%{public}d',
      reason,
      expectedTunnelId,
      runtimeStatus.tunnelId,
      runtimeStatus.updatedAt <= 0 ? -1 : now - runtimeStatus.updatedAt
    );
    await this.restoreVpnIfNeeded('picture in picture monitor');
  }

  private configureVpnPictureInPicture(enabled: boolean): void {
    const uiContext = this.uiContext;
    if (uiContext === undefined) {
      return;
    }
    VpnPictureInPictureManager.getInstance().configure(this.context, uiContext, enabled);
  }

  private async startVpnBackgroundTaskIfNeeded(): Promise<void> {
    const status = await loadTunnelRuntimeStatus(this.context, true);
    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    const hasActiveTunnel = hasActiveTunnelSelection(activeInfo);
    if (!status.running || status.tunnelId.length === 0 || !hasActiveTunnel) {
      await stopVpnDataTransferTask(this.context);
      hilog.info(
        DOMAIN,
        TAG,
        'EntryAbility skip vpn background task, runtime stopped activeTunnel=%{public}s',
        String(hasActiveTunnel)
      );
      return;
    }
    await startVpnDataTransferTask(this.context);
    hilog.info(
      DOMAIN,
      TAG,
      'EntryAbility vpn background task ensured running=%{public}s activeTunnel=%{public}s',
      String(status.running),
      String(hasActiveTunnel)
    );
  }

  private async restoreVpnIfNeeded(reason: string): Promise<void> {
    if (this.vpnRestoreInFlight) {
      hilog.info(DOMAIN, TAG, 'EntryAbility skip vpn restore reason=%{public}s, restore already in flight', reason);
      return;
    }

    this.vpnRestoreInFlight = true;
    try {
      await this.doRestoreVpnIfNeeded(reason);
    } finally {
      this.vpnRestoreInFlight = false;
    }
  }

  private async doRestoreVpnIfNeeded(reason: string): Promise<void> {
    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    if (!hasActiveTunnelSelection(activeInfo)) {
      hilog.info(DOMAIN, TAG, 'EntryAbility skip vpn restore reason=%{public}s, no active tunnel', reason);
      return;
    }

    const decision = await new SmartAgentStrategy(this.context).resolveDecision();
    if (!decision.shouldConnectVpn || !hasActiveTunnelSelection(decision.selectedActiveInfo)) {
      hilog.info(DOMAIN, TAG, 'EntryAbility skip vpn restore reason=%{public}s, smart agent direct', reason);
      return;
    }

    const runtimeStatus = await loadTunnelRuntimeStatus(this.context, true);
    if (this.isRuntimeStatusAlive(
      runtimeStatus.running,
      runtimeStatus.tunnelId,
      runtimeStatus.updatedAt,
      decision.selectedActiveInfo.id
    )) {
      hilog.info(
        DOMAIN,
        TAG,
        'EntryAbility skip vpn restore reason=%{public}s, runtime alive tunnelId=%{public}s',
        reason,
        runtimeStatus.tunnelId
      );
      return;
    }
    if (this.isRuntimeStartupPending(
      runtimeStatus.running,
      runtimeStatus.tunnelId,
      runtimeStatus.updatedAt,
      decision.selectedActiveInfo.id
    )) {
      hilog.info(DOMAIN, TAG, 'EntryAbility skip vpn restore reason=%{public}s, startup pending', reason);
      return;
    }

    await startVpnDataTransferTask(this.context);
    await vpnExtension.startVpnExtensionAbility(this.buildVpnWant());
    hilog.info(
      DOMAIN,
      TAG,
      'EntryAbility vpn restore requested reason=%{public}s activeId=%{public}s activeName=%{public}s',
      reason,
      decision.selectedActiveInfo.id,
      decision.selectedActiveInfo.name
    );
  }

  private isRuntimeStatusAlive(
    running: boolean,
    tunnelId: string,
    updatedAt: number,
    expectedTunnelId: string
  ): boolean {
    if (!running || tunnelId.length === 0 || updatedAt <= 0) {
      return false;
    }
    if (expectedTunnelId.length === 0 || tunnelId !== expectedTunnelId) {
      return false;
    }
    return Date.now() - updatedAt <= VPN_RUNTIME_ALIVE_MAX_AGE_MS;
  }

  private isRuntimeStartupPending(
    running: boolean,
    tunnelId: string,
    updatedAt: number,
    expectedTunnelId: string
  ): boolean {
    return !running &&
      expectedTunnelId.length > 0 &&
      tunnelId === expectedTunnelId &&
      updatedAt > 0 &&
      Date.now() - updatedAt <= VPN_PIP_STARTUP_GRACE_MS;
  }

  private buildVpnWant(): Want {
    const want: Want = {
      deviceId: '',
      bundleName: BUNDLE_NAME,
      moduleName: MODULE_NAME,
      abilityName: VPN_ABILITY,
      parameters: {
        action: VPN_ACTION_RESTORE
      }
    };
    return want;
  }

  private initializeWebEngine(): void {
    try {
      webview.WebviewController.initializeWebEngine();
      hilog.info(DOMAIN, TAG, 'EntryAbility web engine initialized');
      syncWebHttpDnsFromDohSettings(this.context).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'sync web httpdns failed: %{public}s', this.formatError(err));
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'initialize web engine failed: %{public}s', this.formatError(error));
    }
  }

  private formatError(error: BusinessError): string {
    const message = error.message ?? '';
    if (message.length > 0) {
      return 'code=' + String(error.code) + ', message=' + message;
    }
    return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
  }
}
