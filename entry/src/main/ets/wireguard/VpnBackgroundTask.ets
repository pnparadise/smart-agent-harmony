import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import wantAgent from '@ohos.app.ability.wantAgent';
import notification from '@ohos.notification';
import notificationManager from '@ohos.notificationManager';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';

const DOMAIN = 0x0001;
const TAG = 'VpnBackgroundTask';
const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const ENTRY_ABILITY = 'EntryAbility';
const VPN_NOTIFICATION_ID = 1001;

export async function startVpnDataTransferTask(context: common.Context): Promise<void> {
  const agent = await createEntryWantAgent();
  await notificationManager.publish(buildVpnNotificationRequest());
  hilog.info(DOMAIN, TAG, 'vpn foreground notification published id=%{public}d', VPN_NOTIFICATION_ID);
  await backgroundTaskManager.startBackgroundRunning(
    context,
    backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
    agent
  );
  hilog.info(DOMAIN, TAG, 'dataTransfer continuous task started');
}

export async function stopVpnDataTransferTask(context: common.Context): Promise<void> {
  try {
    await backgroundTaskManager.stopBackgroundRunning(context);
    hilog.info(DOMAIN, TAG, 'dataTransfer continuous task stopped');
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'stop continuous task failed: %{public}s', formatError(error));
  }

  try {
    await notificationManager.cancel(VPN_NOTIFICATION_ID);
    hilog.info(DOMAIN, TAG, 'vpn foreground notification canceled id=%{public}d', VPN_NOTIFICATION_ID);
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'cancel vpn notification failed: %{public}s', formatError(error));
  }
}

function buildVpnNotificationRequest(): notificationManager.NotificationRequest {
  const request: notificationManager.NotificationRequest = {
    id: VPN_NOTIFICATION_ID,
    notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
    isOngoing: true,
    isUnremovable: true,
    tapDismissed: false,
    content: {
      contentType: notification.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: 'Smart Agent VPN',
        text: 'Secure data transfer active',
        additionalText: 'WireGuard tunnel running'
      }
    }
  };
  return request;
}

async function createEntryWantAgent(): Promise<object> {
  const entryWant: Want = {
    bundleName: BUNDLE_NAME,
    moduleName: MODULE_NAME,
    abilityName: ENTRY_ABILITY
  };
  const entryWants: Array<Want> = [entryWant];
  const actionFlags: Array<wantAgent.WantAgentFlags> = [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG];
  const wantAgentInfo: wantAgent.WantAgentInfo = {
    wants: entryWants,
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    actionFlags: actionFlags
  };
  return await wantAgent.getWantAgent(wantAgentInfo);
}

function formatError(error: BusinessError): string {
  const message = error.message ?? '';
  if (message.length > 0) {
    return 'code=' + String(error.code) + ', message=' + message;
  }
  return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
}
