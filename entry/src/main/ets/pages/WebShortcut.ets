import { common } from '@kit.AbilityKit';
import { currentWebShortcutId, currentWebShortcutUrl } from '../entryability/WebShortcutState';
import { PAGE_BACKGROUND } from './PageStyle';
import { WebBrowserHost } from './WebBrowserHost';
import { WebShortcutIconService } from './WebShortcutIconService';

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
  @State private launchCoverVisible: boolean = true;
  @State private launchIconFileSource: string = '';
  private backHandler?: () => boolean;

  aboutToAppear(): void {
    this.targetUrl = this.effectiveInitialUrl();
    this.updateLaunchIcon(this.targetUrl);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.targetUrl.length > 0) {
        WebBrowserHost({
          initialUrl: this.targetUrl,
          launchInstanceId: this.webControllerId(),
          launchRevision: this.launchRevision,
          onFirstContentVisible: () => {
            this.launchCoverVisible = false;
          },
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

      if (this.launchCoverVisible || this.targetUrl.length === 0) {
        WebShortcutLaunchCover({ iconFileSource: this.launchIconFileSource })
          .zIndex(20)
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
    if (nextUrl !== this.targetUrl) {
      this.launchCoverVisible = true;
      this.updateLaunchIcon(nextUrl);
    }
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

  private updateLaunchIcon(url: string): void {
    if (url.length === 0) {
      this.launchIconFileSource = '';
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    this.launchIconFileSource = new WebShortcutIconService(context).foregroundIconFileSource(this.normalizeIconUrl(url));
  }

  private normalizeIconUrl(value: string): string {
    const input = value.trim();
    if (input.startsWith('http://') || input.startsWith('https://') ||
      input.startsWith('file://') || input.startsWith('resource://') || input.startsWith('about:')) {
      return input;
    }
    const schemeIndex = input.indexOf(':');
    if (schemeIndex > 0 && input.indexOf('/') >= schemeIndex) {
      return input;
    }
    if (input.indexOf('.') >= 0 && input.indexOf(' ') < 0) {
      return 'https://' + input;
    }
    return input;
  }
}

@Component
struct WebShortcutLaunchCover {
  @Prop iconFileSource: string = '';

  build() {
    Column() {
      Image(this.iconSource())
        .width(72)
        .height(72)
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(PAGE_BACKGROUND)
  }

  private iconSource(): ResourceStr {
    return this.iconFileSource.length > 0 ? this.iconFileSource : $r('app.media.ic_browser_shortcut');
  }
}
