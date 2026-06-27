import { common, wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  clearDataTransferNotificationId,
  loadDataTransferNotificationId,
  saveDataTransferNotificationId
} from './ConfigStore';

const DOMAIN = 0x0001;
const TAG = 'VpnBackgroundTask';
const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const ENTRY_ABILITY = 'EntryAbility';
const DATA_TRANSFER_MODE = 'dataTransfer';
const LIVE_VIEW_TYPE_CODE_DATA_TRANSFER = 8;
const CLOCK_PROGRESS_TOTAL_SECONDS = 60;
const SYSTEM_PROGRESS_MAX = 100;

let vpnDataTransferTaskStarted = false;
let cachedDataTransferNotificationId = 0;

export async function startVpnDataTransferTask(context: common.UIAbilityContext): Promise<void> {
  const agent = await createVpnWantAgent();
  try {
    const notification = await backgroundTaskManager.startBackgroundRunning(
      context,
      [DATA_TRANSFER_MODE],
      agent
    );
    cachedDataTransferNotificationId = notification.notificationId;
    await saveDataTransferNotificationId(context, notification.notificationId);
    vpnDataTransferTaskStarted = true;
    await updateVpnDataTransferNotification(context, '', 0, 0);
  } catch (err) {
    const error = err as BusinessError;
    if (await hasContinuousTask(context)) {
      vpnDataTransferTaskStarted = true;
      await syncExistingDataTransferNotificationId(context);
      return;
    }
    vpnDataTransferTaskStarted = false;
    cachedDataTransferNotificationId = 0;
    await clearDataTransferNotificationId(context);
    throw new Error('start continuous task failed: ' + formatError(error));
  }
}

export async function stopVpnDataTransferTask(context: common.UIAbilityContext): Promise<void> {
  try {
    if (!vpnDataTransferTaskStarted && !await hasContinuousTask(context)) {
      return;
    }
    await backgroundTaskManager.stopBackgroundRunning(context);
    vpnDataTransferTaskStarted = false;
    cachedDataTransferNotificationId = 0;
    await clearDataTransferNotificationId(context);
  } catch (err) {
    const error = err as BusinessError;
    vpnDataTransferTaskStarted = false;
    cachedDataTransferNotificationId = 0;
    await clearDataTransferNotificationId(context);
    hilog.warn(DOMAIN, TAG, 'stop continuous task failed: %{public}s', formatError(error));
  }
}

export async function updateVpnDataTransferNotification(
  context: common.UIAbilityContext | common.VpnExtensionContext,
  tunnelName: string,
  txBytes: number,
  rxBytes: number
): Promise<void> {
  const notificationId = await resolveDataTransferNotificationId(context);
  if (notificationId <= 0) {
    return;
  }

  const title = tunnelName.length > 0 ? 'SmartAgent - ' + tunnelName : 'SmartAgent VPN';
  const text = '↑ ' + formatBytes(txBytes) + '  ↓ ' + formatBytes(rxBytes);
  const request: notificationManager.NotificationRequest = {
    id: notificationId,
    notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
      systemLiveView: {
        typeCode: LIVE_VIEW_TYPE_CODE_DATA_TRANSFER,
        title: title,
        text: text
      }
    },
    template: {
      name: 'downloadTemplate',
      data: {
        title: title,
        fileName: text,
        progressValue: progressValueForCurrentSecond()
      }
    }
  };

  try {
    await notificationManager.publish(request);
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'update dataTransfer notification failed: %{public}s', formatError(error));
  }
}

async function createVpnWantAgent(): Promise<WantAgent> {
  const vpnWant: Want = {
    bundleName: BUNDLE_NAME,
    moduleName: MODULE_NAME,
    abilityName: ENTRY_ABILITY
  };
  const wantAgentInfo: wantAgent.WantAgentInfo = {
    wants: [vpnWant],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
  };
  return await wantAgent.getWantAgent(wantAgentInfo);
}

async function hasContinuousTask(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const tasks = await backgroundTaskManager.getAllContinuousTasks(context, false);
    return tasks.length > 0;
  } catch (err) {
    const error = err as BusinessError;
    if (vpnDataTransferTaskStarted) {
      hilog.warn(DOMAIN, TAG, 'query continuous task failed while marked active: %{public}s', formatError(error));
    }
    return vpnDataTransferTaskStarted;
  }
}

async function syncExistingDataTransferNotificationId(context: common.UIAbilityContext): Promise<void> {
  try {
    const tasks = await backgroundTaskManager.getAllContinuousTasks(context, false);
    for (let index = 0; index < tasks.length; index++) {
      const notificationId = tasks[index].notificationId;
      if (notificationId > 0) {
        cachedDataTransferNotificationId = notificationId;
        await saveDataTransferNotificationId(context, notificationId);
        return;
      }
    }
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'sync dataTransfer notification id failed: %{public}s', formatError(error));
  }
}

async function resolveDataTransferNotificationId(
  context: common.UIAbilityContext | common.VpnExtensionContext
): Promise<number> {
  if (cachedDataTransferNotificationId > 0) {
    return cachedDataTransferNotificationId;
  }

  cachedDataTransferNotificationId = await loadDataTransferNotificationId(context, true);
  return cachedDataTransferNotificationId;
}

function formatBytes(value: number): string {
  const bytes = Math.max(0, value);
  if (bytes < 1024) {
    return String(bytes) + ' B';
  }
  const kib = bytes / 1024;
  if (kib < 1024) {
    return formatDecimal(kib) + ' KB';
  }
  const mib = kib / 1024;
  if (mib < 1024) {
    return formatDecimal(mib) + ' MB';
  }
  return formatDecimal(mib / 1024) + ' GB';
}

function formatDecimal(value: number): string {
  return value >= 100 ? value.toFixed(0) : value.toFixed(1);
}

function progressValueForCurrentSecond(): number {
  const seconds = new Date().getSeconds();
  return Math.min(
    SYSTEM_PROGRESS_MAX,
    Math.floor((seconds / CLOCK_PROGRESS_TOTAL_SECONDS) * SYSTEM_PROGRESS_MAX)
  );
}

function formatError(error: BusinessError): string {
  const message = error.message ?? '';
  if (message.length > 0) {
    return 'code=' + String(error.code) + ', message=' + message;
  }
  return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
}
