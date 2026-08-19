import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connection, vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import {
  hasActiveTunnelSelection,
  isVpnKeepAliveEnabled,
  loadActiveTunnelInfo,
  loadVpnKeepAliveSettings,
  VpnKeepAliveSettings
} from '../wireguard/ConfigStore';
import { startVpnDataTransferTask, stopVpnDataTransferTask } from '../wireguard/VpnBackgroundTask';
import { queryVpnNetworkAvailable, VpnNetworkMonitor } from '../wireguard/VpnNetworkMonitor';
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
const VPN_ACTION_NETWORK_LOST = 'networkLost';
const VPN_RESTORE_COOLDOWN_MS = 5000;

export default class EntryAbility extends UIAbility {
  private vpnRestoreInFlight: boolean = false;
  private windowStage?: window.WindowStage;
  private uiContext?: UIContext;
  private vpnNetworkMonitor: VpnNetworkMonitor = new VpnNetworkMonitor();
  private lastVpnRestoreAt: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
    this.initializeWebEngine();
    this.restoreVpnIfNeeded('onCreate').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restore vpn on create failed: %{public}s', this.formatError(err));
    });
    this.startVpnNetworkObserver();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onDestroy');
    this.stopVpnNetworkObserver();
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
      this.syncVpnPictureInPicture().catch((monitorErr: BusinessError) => {
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
    this.startVpnNetworkObserver();
    VpnPictureInPictureManager.getInstance().onForeground();
    this.activateWindow();
    this.restoreVpnIfNeeded('onForeground').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restore vpn on foreground failed: %{public}s', this.formatError(err));
    });
    this.syncVpnPictureInPicture().catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'vpn picture in picture foreground sync failed: %{public}s', this.formatError(err));
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
    this.syncVpnPictureInPicture().catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'vpn picture in picture background sync failed: %{public}s', this.formatError(err));
    });
  }

  private startVpnNetworkObserver(): void {
    this.vpnNetworkMonitor.start({
      onAvailable: (netHandle: connection.NetHandle) => {
        hilog.info(DOMAIN, TAG, 'vpn network available netId=%{public}d', netHandle.netId);
        this.syncVpnPictureInPicture().catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'sync picture in picture on vpn available failed: %{public}s', this.formatError(err));
        });
      },
      onLost: (netHandle: connection.NetHandle) => {
        this.handleVpnNetworkLost(netHandle).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'handle vpn network lost failed: %{public}s', this.formatError(err));
        });
      },
      onError: (operation: string, error: BusinessError) => {
        hilog.warn(
          DOMAIN,
          TAG,
          'vpn network observer failed operation=%{public}s error=%{public}s',
          operation,
          this.formatError(error)
        );
      }
    });
  }

  private stopVpnNetworkObserver(): void {
    this.vpnNetworkMonitor.stop((operation: string, error: BusinessError) => {
      hilog.warn(
        DOMAIN,
        TAG,
        'stop vpn network observer failed operation=%{public}s error=%{public}s',
        operation,
        this.formatError(error)
      );
    });
  }

  private async handleVpnNetworkLost(netHandle: connection.NetHandle): Promise<void> {
    hilog.warn(DOMAIN, TAG, 'vpn network lost netId=%{public}d', netHandle.netId);
    const settings: VpnKeepAliveSettings = await loadVpnKeepAliveSettings(this.context, true);
    if (!isVpnKeepAliveEnabled(settings)) {
      hilog.info(DOMAIN, TAG, 'skip vpn network recovery, keep alive disabled');
      return;
    }
    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    if (!hasActiveTunnelSelection(activeInfo)) {
      hilog.info(DOMAIN, TAG, 'skip vpn network recovery, no active tunnel');
      return;
    }
    const decision = await new SmartAgentStrategy(this.context).resolveDecision();
    if (!decision.shouldConnectVpn || !hasActiveTunnelSelection(decision.selectedActiveInfo)) {
      hilog.info(DOMAIN, TAG, 'skip vpn network recovery, smart agent direct');
      return;
    }
    await startVpnDataTransferTask(this.context);
    await vpnExtension.startVpnExtensionAbility(this.buildVpnWant(VPN_ACTION_NETWORK_LOST, netHandle.netId));
  }

  private async syncVpnPictureInPicture(): Promise<void> {
    const settings: VpnKeepAliveSettings = await loadVpnKeepAliveSettings(this.context, true);
    if (!settings.pictureInPictureEnabled) {
      this.configureVpnPictureInPicture(false);
      return;
    }
    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    if (!hasActiveTunnelSelection(activeInfo)) {
      this.configureVpnPictureInPicture(false);
      return;
    }
    const decision = await new SmartAgentStrategy(this.context).resolveDecision();
    this.configureVpnPictureInPicture(
      decision.shouldConnectVpn && hasActiveTunnelSelection(decision.selectedActiveInfo)
    );
  }

  private configureVpnPictureInPicture(enabled: boolean): void {
    const uiContext = this.uiContext;
    if (uiContext === undefined) {
      return;
    }
    VpnPictureInPictureManager.getInstance().configure(this.context, uiContext, enabled);
  }

  private async startVpnBackgroundTaskIfNeeded(): Promise<void> {
    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    const hasActiveTunnel = hasActiveTunnelSelection(activeInfo);
    const vpnNetworkAvailable = queryVpnNetworkAvailable();
    if (vpnNetworkAvailable === undefined) {
      hilog.warn(DOMAIN, TAG, 'skip vpn background task sync, vpn network query failed');
      return;
    }
    if (!vpnNetworkAvailable || !hasActiveTunnel) {
      await stopVpnDataTransferTask(this.context);
      hilog.info(
        DOMAIN,
        TAG,
        'EntryAbility skip vpn background task, vpnNetwork=%{public}s activeTunnel=%{public}s',
        String(vpnNetworkAvailable),
        String(hasActiveTunnel)
      );
      return;
    }
    await startVpnDataTransferTask(this.context);
    hilog.info(
      DOMAIN,
      TAG,
      'EntryAbility vpn background task ensured vpnNetwork=%{public}s activeTunnel=%{public}s',
      String(vpnNetworkAvailable),
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

    const vpnNetworkAvailable = queryVpnNetworkAvailable();
    if (vpnNetworkAvailable === undefined) {
      hilog.warn(DOMAIN, TAG, 'EntryAbility skip vpn restore reason=%{public}s, vpn network query failed', reason);
      return;
    }
    if (vpnNetworkAvailable) {
      hilog.info(DOMAIN, TAG, 'EntryAbility skip vpn restore reason=%{public}s, vpn network available', reason);
      return;
    }

    const now = Date.now();
    if (now - this.lastVpnRestoreAt < VPN_RESTORE_COOLDOWN_MS) {
      hilog.info(DOMAIN, TAG, 'EntryAbility skip vpn restore reason=%{public}s, cooldown active', reason);
      return;
    }
    this.lastVpnRestoreAt = now;

    await startVpnDataTransferTask(this.context);
    await vpnExtension.startVpnExtensionAbility(this.buildVpnWant(VPN_ACTION_RESTORE));
    hilog.info(
      DOMAIN,
      TAG,
      'EntryAbility vpn restore requested reason=%{public}s activeId=%{public}s activeName=%{public}s',
      reason,
      decision.selectedActiveInfo.id,
      decision.selectedActiveInfo.name
    );
  }

  private buildVpnWant(action: string, lostNetId: number = -1): Want {
    const want: Want = {
      deviceId: '',
      bundleName: BUNDLE_NAME,
      moduleName: MODULE_NAME,
      abilityName: VPN_ABILITY,
      parameters: {
        action: action,
        lostNetId: lostNetId
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
