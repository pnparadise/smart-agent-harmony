import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import {
  loadLastWebShortcutUrl,
  loadWebBookmarks,
  loadWebShortcutUrl,
  WebBookmarkEntry
} from '../wireguard/ConfigStore';
import { syncWebHttpDnsFromDohSettings } from '../wireguard/WebHttpDns';
import { activateImmersiveWindow, configureImmersiveWindow } from './ImmersiveWindow';
import { notifyWebBrowserBackgroundForPictureInPicture } from './WebBrowserPictureInPictureEvents';
import { setCurrentWebShortcut } from './WebShortcutState';
import { WEB_SHORTCUT_CLOSE_EVENT } from './WebShortcutCloseEvents';

const DOMAIN = 0x0001;
const TAG = 'WebShortcutAbility';
const WEB_SHORTCUT_URL_KEY = 'webUrl';
const WEB_SHORTCUT_ID_KEY = 'webShortcutId';
const WEB_SHORTCUT_URL_STORAGE_KEY = 'webShortcutInitialUrl';
const WEB_SHORTCUT_ID_STORAGE_KEY = 'webShortcutId';
const WEB_SHORTCUT_LAUNCH_REVISION_STORAGE_KEY = 'webShortcutLaunchRevision';
const WEB_SHORTCUT_ID_PREFIX = 'smart_agent_web_';
const WEB_STATIC_BROWSER_SHORTCUT_ID = 'smart_agent_web_static_browser';
const WEB_DEFAULT_STACK_ID = 'smart_agent_web_app';
const WEB_BOOKMARKS_HOME_URL = 'about:smart-bookmarks';

export default class WebShortcutAbility extends UIAbility {
  private storage: LocalStorage = new LocalStorage();
  private contentLoaded: boolean = false;
  private pendingWant?: Want;
  private launchRevision: number = 0;
  private windowStage?: window.WindowStage;
  private shortcutId: string = '';
  private closeSubscriber?: commonEventManager.CommonEventSubscriber;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    this.initializeWebEngine();
    this.pendingWant = want;
    this.subscribeCloseEvent();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.unsubscribeCloseEvent();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    const want = this.pendingWant;
    if (want === undefined) {
      this.initializeStorageFromLastShortcut().then(() => {
        this.loadShortcutContent(windowStage);
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'initialize shortcut storage without want failed: %{public}s', this.formatError(err));
        this.setShortcutStorage('', '');
        this.loadShortcutContent(windowStage);
      });
      return;
    }

    this.initializeStorage(want).then(() => {
      this.loadShortcutContent(windowStage);
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'initialize shortcut storage failed: %{public}s', this.formatError(err));
      this.setShortcutStorage('', '');
      this.loadShortcutContent(windowStage);
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant');
    this.activateWindow();
    this.initializeStorage(want).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'update shortcut storage failed: %{public}s', this.formatError(err));
    });
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    this.activateWindow();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
    notifyWebBrowserBackgroundForPictureInPicture();
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
    this.windowStage = undefined;
  }

  private initializeWebEngine(): void {
    try {
      webview.WebviewController.initializeWebEngine();
      hilog.info(DOMAIN, TAG, 'web engine initialized');
      syncWebHttpDnsFromDohSettings(this.context).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'sync web httpdns failed: %{public}s', this.formatError(err));
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'initialize web engine failed: %{public}s', this.formatError(error));
    }
  }

  private loadShortcutContent(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/WebShortcut', this.storage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      configureImmersiveWindow(windowStage, DOMAIN, TAG);
      this.activateWindow();
      this.contentLoaded = true;
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  private activateWindow(): void {
    const stage = this.windowStage;
    if (stage === undefined) {
      return;
    }
    activateImmersiveWindow(stage, DOMAIN, TAG);
  }

  private setShortcutStorage(url: string, shortcutId: string): void {
    this.shortcutId = shortcutId;
    setCurrentWebShortcut(url, shortcutId);
    this.launchRevision++;
    this.storage.setOrCreate(WEB_SHORTCUT_URL_STORAGE_KEY, url);
    this.storage.setOrCreate(WEB_SHORTCUT_ID_STORAGE_KEY, shortcutId);
    this.storage.setOrCreate(WEB_SHORTCUT_LAUNCH_REVISION_STORAGE_KEY, this.launchRevision);
  }

  private subscribeCloseEvent(): void {
    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [WEB_SHORTCUT_CLOSE_EVENT]
    };
    try {
      commonEventManager.createSubscriber(subscribeInfo, (err: BusinessError,
        subscriber: commonEventManager.CommonEventSubscriber) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'create shortcut close subscriber failed: %{public}s', this.formatError(err));
          return;
        }
        this.closeSubscriber = subscriber;
        try {
          commonEventManager.subscribe(subscriber, (err: BusinessError,
            data: commonEventManager.CommonEventData) => {
            if (err) {
              hilog.warn(DOMAIN, TAG, 'shortcut close event failed: %{public}s', this.formatError(err));
              return;
            }
            this.handleCloseEvent(data);
          });
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'subscribe shortcut close event threw: %{public}s',
            this.formatError(error as BusinessError));
        }
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'create shortcut close subscriber threw: %{public}s',
        this.formatError(error as BusinessError));
    }
  }

  private unsubscribeCloseEvent(): void {
    const subscriber = this.closeSubscriber;
    if (subscriber === undefined) {
      return;
    }
    this.closeSubscriber = undefined;
    try {
      commonEventManager.unsubscribe(subscriber, () => {
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'unsubscribe shortcut close event threw: %{public}s',
        this.formatError(error as BusinessError));
    }
  }

  private handleCloseEvent(data: commonEventManager.CommonEventData): void {
    const value = data.data ?? '';
    if (value !== this.shortcutId || value.length === 0) {
      return;
    }
    this.context.terminateSelf().catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'terminate shortcut ability failed id=%{public}s: %{public}s',
        this.shortcutId,
        this.formatError(err)
      );
    });
  }

  private async initializeStorage(want: Want): Promise<void> {
    const shortcutIdFromWant = this.shortcutIdParameter(want);
    const url = await this.webUrlFromWant(want, shortcutIdFromWant);
    const shortcutId = await this.resolveStackShortcutId(url, shortcutIdFromWant);
    this.setShortcutStorage(url, shortcutId);
  }

  private async initializeStorageFromLastShortcut(): Promise<void> {
    const url = await loadLastWebShortcutUrl(this.context, true);
    const shortcutId = await this.resolveStackShortcutId(url, '');
    this.setShortcutStorage(url, shortcutId);
  }

  private async webUrlFromWant(want: Want, shortcutId: string): Promise<string> {
    const parameters = want.parameters;
    if (parameters !== undefined) {
      const value = parameters[WEB_SHORTCUT_URL_KEY];
      if (typeof value === 'string' && value.trim().length > 0) {
        hilog.info(DOMAIN, TAG, 'web shortcut url from want id=%{public}s', shortcutId);
        return value.trim();
      }
    }

    if (this.isStaticBrowserShortcut(shortcutId, '')) {
      return WEB_BOOKMARKS_HOME_URL;
    }

    const shortcutUrl = await loadWebShortcutUrl(this.context, shortcutId, true);
    if (shortcutUrl.length > 0) {
      hilog.info(DOMAIN, TAG, 'web shortcut url from saved id=%{public}s', shortcutId);
      return shortcutUrl;
    }

    const lastShortcutUrl = await loadLastWebShortcutUrl(this.context, true);
    if (lastShortcutUrl.length > 0) {
      hilog.info(DOMAIN, TAG, 'web shortcut url from last saved shortcut');
      return lastShortcutUrl;
    }

    hilog.warn(DOMAIN, TAG, 'web shortcut missing url id=%{public}s', shortcutId);
    return '';
  }

  private shortcutIdParameter(want: Want): string {
    const parameters = want.parameters;
    if (parameters !== undefined) {
      const value = parameters[WEB_SHORTCUT_ID_KEY];
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }
    return '';
  }

  private shortcutIdFromUrl(url: string): string {
    return WEB_SHORTCUT_ID_PREFIX + this.stableUrlKey(url);
  }

  private async resolveStackShortcutId(url: string, shortcutIdFromWant: string): Promise<string> {
    const normalizedUrl = url.trim();
    const requestedId = shortcutIdFromWant.trim();
    if (this.isStaticBrowserShortcut(requestedId, normalizedUrl)) {
      return WEB_DEFAULT_STACK_ID;
    }

    const bookmarkId = await this.bookmarkIdForUrlOrId(normalizedUrl, requestedId);
    if (bookmarkId.length > 0) {
      return bookmarkId;
    }

    if (requestedId.length > 0) {
      return requestedId;
    }
    if (normalizedUrl.length > 0) {
      return this.shortcutIdFromUrl(normalizedUrl);
    }
    return '';
  }

  private async bookmarkIdForUrlOrId(url: string, shortcutId: string): Promise<string> {
    if (url.length === 0 && shortcutId.length === 0) {
      return '';
    }

    try {
      const bookmarks = await loadWebBookmarks(this.context, true);
      for (let index = 0; index < bookmarks.length; index++) {
        const bookmark: WebBookmarkEntry = bookmarks[index];
        if (shortcutId.length > 0 && bookmark.id === shortcutId) {
          return bookmark.id;
        }
        if (url.length > 0 && bookmark.url.trim() === url) {
          return bookmark.id;
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'resolve bookmark shortcut stack failed: %{public}s', this.formatError(error));
    }
    return '';
  }

  private isStaticBrowserShortcut(shortcutId: string, url: string): boolean {
    if (shortcutId === WEB_STATIC_BROWSER_SHORTCUT_ID) {
      return true;
    }
    return url.trim() === WEB_BOOKMARKS_HOME_URL;
  }

  private stableUrlKey(url: string): string {
    let hash = 2166136261;
    for (let index = 0; index < url.length; index++) {
      hash ^= url.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  private formatError(error: BusinessError): string {
    const message = error.message ?? '';
    if (message.length > 0) {
      return 'code=' + String(error.code) + ', message=' + message;
    }
    return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
  }
}
