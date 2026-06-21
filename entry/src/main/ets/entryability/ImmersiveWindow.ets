import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TOP_AVOID_AREA_HEIGHT_KEY = 'topRectHeight';
const BOTTOM_AVOID_AREA_HEIGHT_KEY = 'bottomRectHeight';
const WINDOW_BACKGROUND_COLOR = '#F4F6FA';
let currentMainWindow: window.Window | undefined = undefined;

export function configureImmersiveWindow(windowStage: window.WindowStage, domain: number, tag: string): void {
  const windowClass = windowStage.getMainWindowSync();
  currentMainWindow = windowClass;
  try {
    windowClass.setWindowBackgroundColor(WINDOW_BACKGROUND_COLOR);
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(domain, tag, 'set window background failed: %{public}s', formatError(error));
  }
  updateAvoidAreaStorage(windowClass, domain, tag);
  registerAvoidAreaListener(windowClass, domain, tag);

  windowClass.setPreferredOrientation(window.Orientation.PORTRAIT).then(() => {
    hilog.info(domain, tag, 'default window orientation locked to portrait');
  }).catch((err: BusinessError) => {
    hilog.warn(domain, tag, 'set default window orientation failed: %{public}s', formatError(err));
  });

  windowClass.setWindowLayoutFullScreen(true).then(() => {
    hilog.info(domain, tag, 'window layout fullscreen enabled');
    updateAvoidAreaStorage(windowClass, domain, tag);
    hideNavigationIndicator(windowClass, domain, tag);
  }).catch((err: BusinessError) => {
    hilog.warn(domain, tag, 'set window layout fullscreen failed: %{public}s', formatError(err));
  });
}

export function activateImmersiveWindow(windowStage: window.WindowStage, domain: number, tag: string): void {
  const windowClass = windowStage.getMainWindowSync();
  currentMainWindow = windowClass;
  updateAvoidAreaStorage(windowClass, domain, tag);
  hideNavigationIndicator(windowClass, domain, tag);
}

export function setWebVideoFullScreenWindow(fullScreen: boolean, domain: number, tag: string): void {
  const windowClass = currentMainWindow;
  if (windowClass === undefined) {
    hilog.warn(domain, tag, 'set web video fullscreen window skipped, main window is undefined');
    return;
  }

  hilog.info(domain, tag, 'set web video fullscreen window fullScreen=%{public}s', String(fullScreen));

  windowClass.setWindowLayoutFullScreen(true).then(() => {
    hilog.info(domain, tag, 'web video fullscreen layout fullscreen ensured');
    updateAvoidAreaStorage(windowClass, domain, tag);
  }).catch((err: BusinessError) => {
    hilog.warn(domain, tag, 'ensure web video fullscreen layout failed: %{public}s', formatError(err));
  });

  const enabledSystemBars: Array<'status' | 'navigation'> = fullScreen ? [] : ['status'];
  windowClass.setWindowSystemBarEnable(enabledSystemBars).then(() => {
    hilog.info(domain, tag, 'web video fullscreen system bars updated fullScreen=%{public}s', String(fullScreen));
    updateAvoidAreaStorage(windowClass, domain, tag);
  }).catch((err: BusinessError) => {
    hilog.warn(domain, tag, 'set web video fullscreen system bars failed: %{public}s', formatError(err));
  });

  windowClass.setPreferredOrientation(fullScreen ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT)
    .then(() => {
      hilog.info(domain, tag, 'web video fullscreen orientation updated fullScreen=%{public}s', String(fullScreen));
    })
    .catch((err: BusinessError) => {
      hilog.warn(domain, tag, 'set web video fullscreen orientation failed: %{public}s', formatError(err));
    });

  windowClass.setSpecificSystemBarEnabled('status', !fullScreen, false).then(() => {
    updateAvoidAreaStorage(windowClass, domain, tag);
  }).catch((err: BusinessError) => {
    hilog.warn(domain, tag, 'set web video fullscreen status bar failed: %{public}s', formatError(err));
  });

  windowClass.setSpecificSystemBarEnabled('navigationIndicator', false, false).then(() => {
    updateAvoidAreaStorage(windowClass, domain, tag);
  }).catch((err: BusinessError) => {
    hilog.warn(domain, tag, 'set web video fullscreen navigation indicator failed: %{public}s', formatError(err));
  });
}

function registerAvoidAreaListener(windowClass: window.Window, domain: number, tag: string): void {
  try {
    windowClass.on('avoidAreaChange', (data) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        AppStorage.setOrCreate(TOP_AVOID_AREA_HEIGHT_KEY, data.area.topRect.height);
      } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        AppStorage.setOrCreate(BOTTOM_AVOID_AREA_HEIGHT_KEY, data.area.bottomRect.height);
      }
    });
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(domain, tag, 'register avoid area listener failed: %{public}s', formatError(error));
  }
}

function updateAvoidAreaStorage(windowClass: window.Window, domain: number, tag: string): void {
  try {
    const systemArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    AppStorage.setOrCreate(TOP_AVOID_AREA_HEIGHT_KEY, systemArea.topRect.height);

    const navigationArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    AppStorage.setOrCreate(BOTTOM_AVOID_AREA_HEIGHT_KEY, navigationArea.bottomRect.height);
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(domain, tag, 'update avoid area storage failed: %{public}s', formatError(error));
  }
}

function hideNavigationIndicator(windowClass: window.Window, domain: number, tag: string): void {
  windowClass.setSpecificSystemBarEnabled('navigationIndicator', false).then(() => {
    hilog.info(domain, tag, 'navigation indicator hidden');
    updateAvoidAreaStorage(windowClass, domain, tag);
  }).catch((err: BusinessError) => {
    hilog.warn(domain, tag, 'hide navigation indicator failed: %{public}s', formatError(err));
  });
}

function formatError(error: BusinessError): string {
  const message = error.message ?? '';
  if (message.length > 0) {
    return 'code=' + String(error.code) + ', message=' + message;
  }
  return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
}
