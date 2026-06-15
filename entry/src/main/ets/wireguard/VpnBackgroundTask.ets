import { common, wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'VpnBackgroundTask';
const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const VPN_ABILITY = 'WgVpnExtensionAbility';

let vpnDataTransferTaskStarted = false;

export async function startVpnDataTransferTask(context: common.UIAbilityContext): Promise<void> {
  const agent = await createVpnWantAgent();
  try {
    await backgroundTaskManager.startBackgroundRunning(
      context,
      backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
      agent
    );
    vpnDataTransferTaskStarted = true;
    hilog.info(DOMAIN, TAG, 'dataTransfer continuous task started');
  } catch (err) {
    const error = err as BusinessError;
    if (await hasContinuousTask(context)) {
      vpnDataTransferTaskStarted = true;
      hilog.info(DOMAIN, TAG, 'dataTransfer continuous task already active after start attempt: %{public}s', formatError(error));
      return;
    }
    vpnDataTransferTaskStarted = false;
    throw new Error('start continuous task failed: ' + formatError(error));
  }
}

export async function stopVpnDataTransferTask(context: common.UIAbilityContext): Promise<void> {
  try {
    if (!vpnDataTransferTaskStarted && !await hasContinuousTask(context)) {
      hilog.info(DOMAIN, TAG, 'dataTransfer continuous task not active');
      return;
    }
    await backgroundTaskManager.stopBackgroundRunning(context);
    vpnDataTransferTaskStarted = false;
    hilog.info(DOMAIN, TAG, 'dataTransfer continuous task stopped');
  } catch (err) {
    const error = err as BusinessError;
    vpnDataTransferTaskStarted = false;
    hilog.warn(DOMAIN, TAG, 'stop continuous task failed: %{public}s', formatError(error));
  }
}

async function createVpnWantAgent(): Promise<WantAgent> {
  const vpnWant: Want = {
    bundleName: BUNDLE_NAME,
    moduleName: MODULE_NAME,
    abilityName: VPN_ABILITY
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

function formatError(error: BusinessError): string {
  const message = error.message ?? '';
  if (message.length > 0) {
    return 'code=' + String(error.code) + ', message=' + message;
  }
  return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
}
