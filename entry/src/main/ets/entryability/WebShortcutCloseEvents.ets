import { commonEventManager } from '@kit.BasicServicesKit';

export const WEB_SHORTCUT_CLOSE_EVENT = 'com.smart.agent.action.CLOSE_WEB_SHORTCUT';
const BUNDLE_NAME = 'com.smart.agent';

export function publishWebShortcutClose(shortcutId: string): void {
  const id = shortcutId.trim();
  if (id.length === 0) {
    return;
  }

  const data: commonEventManager.CommonEventPublishData = {
    bundleName: BUNDLE_NAME,
    data: id
  };
  try {
    commonEventManager.publish(WEB_SHORTCUT_CLOSE_EVENT, data, () => {
    });
  } catch (err) {
  }
}
