import { common } from '@kit.AbilityKit';
import { currentWebShortcutId, currentWebShortcutUrl } from '../entryability/WebShortcutState';
import { WebBrowserHost } from './WebBrowserHost';

const WEB_SHORTCUT_URL_STORAGE_KEY = 'webShortcutInitialUrl';
const WEB_SHORTCUT_ID_STORAGE_KEY = 'webShortcutId';
const WEB_SHORTCUT_LAUNCH_REVISION_STORAGE_KEY = 'webShortcutLaunchRevision';
const WEB_HOME_INSTANCE_ID = 'smart_agent_web_app';
const WEB_STATIC_BROWSER_SHORTCUT_ID = 'smart_agent_web_static_browser';
const webShortcutStorage: LocalStorage = new LocalStorage();

@Entry(webShortcutStorage)
@Component
struct WebShortcut {
  @LocalStorageLink(WEB_SHORTCUT_URL_STORAGE_KEY) @Watch('onShortcutTargetChanged') private initialUrl: string = '';
  @LocalStorageLink(WEB_SHORTCUT_ID_STORAGE_KEY) @Watch('onShortcutTargetChanged') private shortcutId: string = '';
  @LocalStorageLink(WEB_SHORTCUT_LAUNCH_REVISION_STORAGE_KEY) @Watch('onShortcutTargetChanged')
  private launchRevision: number = 0;
  @State private targetUrl: string = currentWebShortcutUrl();
  private backHandler?: () => boolean;

  aboutToAppear(): void {
    this.targetUrl = this.effectiveInitialUrl();
  }

  build() {
    Column() {
      if (this.targetUrl.length > 0) {
        WebBrowserHost({
          initialUrl: this.targetUrl,
          launchInstanceId: this.webControllerId(),
          launchRevision: this.launchRevision,
          onClose: () => {
            this.closeShortcut();
          },
          onBackHandlerReady: (handler: () => boolean) => {
            this.backHandler = handler;
          },
          onBackHandlerRelease: () => {
            this.backHandler = undefined;
          }
        });
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  onBackPress(): boolean {
    if (this.backHandler !== undefined) {
      return this.backHandler();
    }
    this.closeShortcut();
    return true;
  }

  private onShortcutTargetChanged(): void {
    const nextUrl = this.effectiveInitialUrl();
    this.targetUrl = nextUrl;
    if (nextUrl.length === 0) {
      return;
    }
  }

  private effectiveInitialUrl(): string {
    if (this.initialUrl.length > 0) {
      return this.initialUrl;
    }
    return currentWebShortcutUrl();
  }

  private webControllerId(): string {
    const id = this.shortcutId.length > 0 ? this.shortcutId : currentWebShortcutId();
    if (this.isStaticBrowserShortcut(id)) {
      return WEB_HOME_INSTANCE_ID;
    }
    return id.length > 0 ? id : 'smart_agent_web_shortcut';
  }

  private isStaticBrowserShortcut(shortcutId: string): boolean {
    return shortcutId === WEB_STATIC_BROWSER_SHORTCUT_ID || this.effectiveInitialUrl().trim() === 'about:smart-bookmarks';
  }

  private closeShortcut(): void {
    const context = getContext(this) as common.UIAbilityContext;
    context.terminateSelf().catch(() => {
    });
  }
}
