import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import {
  loadActiveTunnelInfo,
  loadLastVpnRestoreAt,
  saveLastVpnRestoreAt,
  loadTunnelRuntimeStatus
} from '../wireguard/ConfigStore';
import { startVpnDataTransferTask, stopVpnDataTransferTask } from '../wireguard/VpnBackgroundTask';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';
const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const VPN_ABILITY = 'WgVpnExtensionAbility';
const VPN_ACTION_RESTORE = 'restore';
const VPN_RESTORE_DEBOUNCE_MS = 2000;

export default class EntryAbility extends UIAbility {
  private lastVpnRestoreAt: number = 0;
  private vpnRestoreInFlight: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    this.restoreVpnIfNeeded('onCreate').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restore vpn on create failed: %{public}s', this.formatError(err));
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    this.restoreVpnIfNeeded('onForeground').catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'restore vpn on foreground failed: %{public}s', this.formatError(err));
    });
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
    this.startVpnBackgroundTaskIfNeeded().catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'start vpn background task failed: %{public}s', this.formatError(err));
    });
  }

  private async startVpnBackgroundTaskIfNeeded(): Promise<void> {
    const status = await loadTunnelRuntimeStatus(this.context, true);
    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    const hasActiveTunnel = activeInfo.id.length > 0 || activeInfo.name.length > 0;
    if (!status.running) {
      await stopVpnDataTransferTask(this.context);
      hilog.info(
        DOMAIN,
        TAG,
        'skip vpn background task, runtime stopped activeTunnel=%{public}s',
        String(hasActiveTunnel)
      );
      return;
    }

    await startVpnDataTransferTask(this.context);
    hilog.info(
      DOMAIN,
      TAG,
      'vpn background task ensured running=%{public}s activeTunnel=%{public}s',
      String(status.running),
      String(hasActiveTunnel)
    );
  }

  private async restoreVpnIfNeeded(reason: string): Promise<void> {
    if (this.vpnRestoreInFlight) {
      hilog.info(DOMAIN, TAG, 'skip vpn restore reason=%{public}s, restore already in flight', reason);
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
    const now = Date.now();
    const lastRestoreAt = Math.max(this.lastVpnRestoreAt, await loadLastVpnRestoreAt(this.context, true));
    if (now - lastRestoreAt < VPN_RESTORE_DEBOUNCE_MS) {
      hilog.info(DOMAIN, TAG, 'skip vpn restore reason=%{public}s, debounce active', reason);
      return;
    }

    const activeInfo = await loadActiveTunnelInfo(this.context, true);
    const hasActiveTunnel = activeInfo.id.length > 0 || activeInfo.name.length > 0;
    if (!hasActiveTunnel) {
      hilog.info(DOMAIN, TAG, 'skip vpn restore reason=%{public}s, no active tunnel', reason);
      return;
    }

    this.lastVpnRestoreAt = now;
    await saveLastVpnRestoreAt(this.context, now);
    await startVpnDataTransferTask(this.context);
    await vpnExtension.startVpnExtensionAbility(this.buildVpnWant());
    hilog.info(
      DOMAIN,
      TAG,
      'vpn restore requested reason=%{public}s activeId=%{public}s activeName=%{public}s',
      reason,
      activeInfo.id,
      activeInfo.name
    );
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

  private formatError(error: BusinessError): string {
    const message = error.message ?? '';
    if (message.length > 0) {
      return 'code=' + String(error.code) + ', message=' + message;
    }
    return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
  }
}
