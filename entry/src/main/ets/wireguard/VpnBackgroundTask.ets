import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import wantAgent from '@ohos.app.ability.wantAgent';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';

const DOMAIN = 0x0001;
const TAG = 'VpnBackgroundTask';
const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const ENTRY_ABILITY = 'EntryAbility';
const DATA_TRANSFER_BACKGROUND_MODES: Array<string> = ['dataTransfer'];

export async function startVpnDataTransferTask(context: common.Context): Promise<void> {
  const agent = await createEntryWantAgent();
  await backgroundTaskManager.startBackgroundRunning(context, DATA_TRANSFER_BACKGROUND_MODES, agent);
  hilog.info(DOMAIN, TAG, 'dataTransfer continuous task started');
}

export async function stopVpnDataTransferTask(context: common.Context): Promise<void> {
  await backgroundTaskManager.stopBackgroundRunning(context);
  hilog.info(DOMAIN, TAG, 'dataTransfer continuous task stopped');
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
