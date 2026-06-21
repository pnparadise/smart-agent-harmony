import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { productViewManager } from '@kit.AppGalleryKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { setWebVideoFullScreenWindow } from '../entryability/ImmersiveWindow';
import {
  DEFAULT_WEB_HOME_URL,
  deleteWebBookmark,
  loadWebBookmarks,
  saveLastWebUrl,
  saveWebBookmark,
  savePinnedWebUrl,
  saveWebShortcutMapping,
  WebBookmarkEntry
} from '../wireguard/ConfigStore';
import { PAGE_BACKGROUND } from './PageStyle';
import { WebBookmarkHome } from './WebBookmarkHome';
import { WebBrowserChrome } from './WebBrowserChrome';
import { WebBrowserStateStore } from './WebBrowserStateStore';
import { WebBrowserSurfaceRegistry, WebSurfaceEntry } from './WebBrowserSurfaceRegistry';
import { WebBrowserSurfaceStack } from './WebBrowserSurfaceStack';
import { WebBrowserTabModel, WebTabStateUpdate } from './WebBrowserTabModel';
import { PullRefreshState, WebBrowserErrorState, WebTabState } from './WebBrowserTypes';
import { WebFullscreenProbe, WebFullScreenProbeResult } from './WebFullscreenProbe';
import { WebPullRefresh } from './WebPullRefresh';
import { PageIconInfo, PwaAppInfo, ShortcutIconInfo, WebShortcutIconService } from './WebShortcutIconService';
import {
  WebViewSurfaceFullScreenEvent,
  WebViewSurfaceFullScreenExitHandler,
  WebViewSurfaceLoadErrorEvent,
  WebViewSurfaceNavigationEvent,
  WebViewSurfaceOverScrollEvent,
  WebViewSurfacePageEvent,
  WebViewSurfaceProgressEvent,
  WebViewSurfaceScrollEvent,
  WebViewSurfaceTitleEvent,
  WebViewSurfaceFaviconEvent,
  WebViewSurfacePullGestureEvent
} from './WebViewSurface';

const DOMAIN = 0x0001;
const TAG = 'WebBrowserPage';
const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const ENTRY_ABILITY = 'EntryAbility';
const WEB_SHORTCUT_ABILITY = 'WebShortcutAbility';
const WEB_SHORTCUT_URL_KEY = 'webUrl';
const WEB_SHORTCUT_ID_KEY = 'webShortcutId';
const WEB_CONTROLLER_ID_APP = 'smart_agent_web_app';
const TOOLBAR_HEIGHT = 52;
const SHORTCUT_DEFAULT_LABEL = '网页';
const WEB_HOME_TAB_ID = WEB_CONTROLLER_ID_APP;
const WEB_BOOKMARKS_HOME_URL = 'about:smart-bookmarks';
const WEB_BOOKMARKS_HOME_TAB_ID = 'smart_agent_web_bookmarks';
const WEB_FULLSCREEN_PROBE_INTERVAL_MS = 450;
const WEB_TOOLBAR_HIDE_GESTURE_DISTANCE = 22;
const WEB_PULL_REFRESH_OVERSCROLL_DISTANCE = 24;
const WEB_NOTICE_DURATION_MS = 2500;
const WEB_BROWSER_PULL_REFRESH_POLICY_SCRIPT =
  'JSON.stringify((function(){' +
    'try{' +
      'var doc=document;var win=window;' +
      'var root=doc.documentElement;var body=doc.body;var scrolling=doc.scrollingElement;' +
      'function behavior(el){if(!el)return "";var s=win.getComputedStyle(el);return String(s.overscrollBehaviorY||s.overscrollBehavior||"").toLowerCase();}' +
      'function blocks(value){return value==="contain"||value==="none";}' +
      'if(blocks(behavior(root))||blocks(behavior(body))||blocks(behavior(scrolling))){return {enabled:false};}' +
      'return {enabled:true};' +
    '}catch(e){return {enabled:true};}' +
  '})())';
const WEB_BROWSER_PULL_REFRESH_TOUCH_PROBE_SCRIPT =
  '(function(){' +
    'try{' +
      'var win=window;var key="__smartAgentPullRefreshProbe";' +
      'var state=win[key];' +
      'if(!state){' +
        'state={serial:0,preventedSerial:0,blockedSerial:0};win[key]=state;' +
        'function remember(e){try{if(e&&e.defaultPrevented){state.preventedSerial=state.serial;}}catch(err){}}' +
        'function begin(e){try{if(!e.__smartAgentPullRefreshSeen){state.serial++;e.__smartAgentPullRefreshSeen=true;}remember(e);}catch(err){}}' +
        'function blocks(value){value=String(value||"").toLowerCase();return value==="contain"||value==="none";}' +
        'function path(e){try{return e.composedPath?e.composedPath():[];}catch(err){return [];}}' +
        'function blocksByStyle(e){' +
          'try{' +
            'var list=path(e);if(!list||list.length===0){var n=e.target;while(n){list.push(n);n=n.parentNode;}}' +
            'for(var i=0;i<list.length;i++){' +
              'var el=list[i];if(!el||el===win||el.nodeType!==1){continue;}' +
              'var s=win.getComputedStyle(el);' +
              'if(blocks(s.overscrollBehaviorY||s.overscrollBehavior)||String(s.touchAction||"").toLowerCase()==="none"){return true;}' +
            '}' +
          '}catch(err){}' +
          'return false;' +
        '}' +
        'win.addEventListener("touchstart",function(e){begin(e);if(blocksByStyle(e)){state.blockedSerial=state.serial;}},{capture:true,passive:true});' +
        'document.addEventListener("touchstart",function(e){begin(e);if(blocksByStyle(e)){state.blockedSerial=state.serial;}},{capture:true,passive:true});' +
        'document.addEventListener("touchmove",remember,{capture:true,passive:true});' +
        'document.addEventListener("touchend",remember,{capture:true,passive:true});' +
        'document.addEventListener("touchcancel",remember,{capture:true,passive:true});' +
        'var rawPrevent=Event.prototype.preventDefault;' +
        'if(rawPrevent&&!Event.prototype.__smartAgentPullRefreshWrapped){' +
          'Event.prototype.preventDefault=function(){try{if(/^touch/.test(String(this.type||""))){state.preventedSerial=state.serial;}}catch(err){}return rawPrevent.apply(this,arguments);};' +
          'Event.prototype.__smartAgentPullRefreshWrapped=true;' +
        '}' +
      '}' +
      'return true;' +
    '}catch(e){return false;}' +
  '})()';
const WEB_BROWSER_PULL_REFRESH_CONSUMED_SCRIPT =
  'JSON.stringify((function(){' +
    'try{' +
      'var state=window.__smartAgentPullRefreshProbe;' +
      'if(!state){return {consumed:false};}' +
      'return {consumed:state.serial>0&&(state.preventedSerial===state.serial||state.blockedSerial===state.serial)};' +
    '}catch(e){return {consumed:false};}' +
  '})())';
const CHROME_MOBILE_USER_AGENT =
  'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

interface WebBrowserPullRefreshPolicyRaw {
  enabled?: boolean;
}

interface WebBrowserPullRefreshConsumedRaw {
  consumed?: boolean;
}

@Component
export struct WebBrowserPage {
  @StorageProp('topRectHeight') private topRectHeight: number = 0;
  @Prop @Watch('onInitialUrlChanged') initialUrl: string = DEFAULT_WEB_HOME_URL;
  @Prop persistBrowserState: boolean = true;
  @Prop @Watch('onWebControllerIdChanged') webControllerId: string = WEB_CONTROLLER_ID_APP;
  @Prop instanceKind: 'home' | 'bookmark' = 'home';
  @Prop isHomeInstance: boolean = true;
  @Prop allowBookmarkHome: boolean = true;
  @Prop showAddressBar: boolean = true;
  @Prop @Watch('onBookmarkHomeVisibleFromHostChanged') bookmarkHomeVisibleFromHost: boolean = false;
  @Prop homeTabBackCountFromHost: number = 0;
  onClose: () => void = () => {};
  onBackHandlerReady: (handler: () => boolean) => void = () => {};
  onBackHandlerRelease: () => void = () => {};
  onOpenBookmarkHome: () => void = () => {};
  onOpenHomeInstance: () => void = () => {};
  onOpenBookmarkInstance: (bookmark: WebBookmarkEntry) => void = () => {};
  onClearInstanceTabStack: (instanceId: string, fallbackUrl: string) => void = () => {};
  onCloseBookmarkInstance: (bookmark: WebBookmarkEntry) => void = () => {};
  onBookmarkDeleted: (bookmark: WebBookmarkEntry) => void = () => {};
  onBookmarksChanged: () => void = () => {};
  onTabStateChanged: (state: WebTabState) => void = () => {};
  tabBackCountFromHost: (bookmarkId: string) => number = () => 0;
  @State private currentUrl: string = DEFAULT_WEB_HOME_URL;
  @State private addressText: string = DEFAULT_WEB_HOME_URL;
  @State private loading: boolean = false;
  @State private progress: number = 0;
  @State private canGoBack: boolean = false;
  @State private canGoForward: boolean = false;
  @State private toolbarHidden: boolean = false;
  @State private notice: string = '';
  @State private addressFocused: boolean = false;
  @State private shortcutTid: string = '';
  @State private shortcutCheckUrl: string = '';
  @State private pageTitle: string = '';
  @State private bookmarkHomeVisible: boolean = false;
  @State private bookmarks: WebBookmarkEntry[] = [];
  @State private webTabStates: WebTabState[] = [];
  @State private bookmarksLoading: boolean = false;
  @State private addBookmarkConfirmVisible: boolean = false;
  @State private addBookmarkConfirmUrl: string = '';
  @State private addBookmarkConfirmTitle: string = '';
  @State private addBookmarkConfirmIcon: string = '';
  @State private addBookmarkConfirmBusy: boolean = false;
  @State private deleteBookmarkConfirmVisible: boolean = false;
  @State private deleteBookmarkConfirmId: string = '';
  @State private deleteBookmarkConfirmUrl: string = '';
  @State private deleteBookmarkConfirmTitle: string = '';
  @State private deleteBookmarkConfirmIcon: string = '';
  @State private deleteBookmarkConfirmBusy: boolean = false;
  @State private bookmarkDropBusy: boolean = false;
  @State private pullRefreshRevision: number = 0;
  @State private webFullScreen: boolean = false;
  @State private webError: WebBrowserErrorState = {
    visible: false,
    url: '',
    title: '',
    detail: '',
    code: 0,
    kind: ''
  };
  private controller: webview.WebviewController = new webview.WebviewController();
  private controllerAttached: boolean = false;
  private initialNavigationDone: boolean = false;
  private favicon?: image.PixelMap;
  private faviconUrl: string = '';
  private pageTitleUrl: string = '';
  private shortcutCheckSerial: number = 0;
  private shortcutCheckId: string = '';
  private restoringWebState: boolean = false;
  private instanceId: string = WEB_HOME_TAB_ID;
  private fullScreenExitHandler?: WebViewSurfaceFullScreenExitHandler;
  private nativeWebFullScreen: boolean = false;
  private scriptDetectedWebFullScreen: boolean = false;
  private webFullScreenProbeTimer: number = -1;
  private webFullScreenProbeInFlight: boolean = false;
  private addBookmarkConfirmSerial: number = 0;
  private noticeTimer: number = -1;
  private explicitLoadErrorUrl: string = '';
  private pendingLoadUrl: string = '';
  private pendingLoadSurfaceKey: string = '';
  private pwaAppInfo: PwaAppInfo = WebShortcutIconService.emptyPwaAppInfo();
  private pwaInfoSerial: number = 0;
  @State private webSurfaceKeys: string[] = [];
  @State private webSurfaceKey: string = WEB_HOME_TAB_ID + '_0';
  private webSurfaceRegistry: WebBrowserSurfaceRegistry = new WebBrowserSurfaceRegistry();

  aboutToAppear(): void {
    this.configureBrowserStorage();
    const normalized = this.normalizeUrl(this.initialUrl);
    this.instanceId = this.instanceStateId();
    this.bookmarkHomeVisible = this.canShowBookmarkHome() && this.bookmarkHomeVisibleFromHost;
    const launchTabId = this.bookmarkHomeVisible ? WEB_BOOKMARKS_HOME_TAB_ID : this.instanceId;
    const tabState = this.readLaunchTabStateMeta(launchTabId,
      this.bookmarkHomeVisible ? WEB_BOOKMARKS_HOME_URL : normalized);
    this.webTabStates = [tabState];
    const startUrl = this.normalizeUrl(tabState.url);
    this.currentUrl = startUrl;
    this.setAddressText(startUrl);
    this.resetInstanceWebController();
    this.loadBookmarks();
    if (!this.bookmarkHomeVisible) {
      this.prepareShortcut(startUrl);
    }
    this.onBackHandlerReady((): boolean => {
      return this.handleBackNavigation();
    });
  }

  aboutToDisappear(): void {
    this.stopWebFullScreenProbe();
    this.stopAllPullRefreshSpin();
    this.stopNoticeTimer();
    if (this.bookmarkHomeVisible) {
      this.rememberBookmarkHomeState();
    } else {
      this.rememberCurrentTabState();
    }
    this.persistWebState();
    this.saveWebCookies();
    this.onBackHandlerRelease();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Blank()
          .height(this.browserTopInset())
          .animation({ duration: 180, curve: Curve.EaseInOut })

        WebBrowserSurfaceStack({
          surfaceKeys: this.webSurfaceKeys,
          activeSurfaceKey: this.webSurfaceKey,
          bookmarkHomeVisible: this.bookmarkHomeVisible,
          webFullScreen: this.webFullScreen,
          controllerFor: (surfaceKey: string): webview.WebviewController => this.surfaceController(surfaceKey),
          surfaceVisibleFor: (surfaceKey: string): boolean => this.webSurfaceVisible(surfaceKey),
          onControllerAttached: (surfaceKey: string): void => {
            this.handleWebSurfaceControllerAttached(surfaceKey);
          },
          onPageBegin: (surfaceKey: string, event: WebViewSurfacePageEvent): void => {
            this.handleWebSurfacePageBegin(surfaceKey, event.url);
          },
          onNavigationCommitted: (surfaceKey: string, event: WebViewSurfaceNavigationEvent): void => {
            this.handleWebSurfaceNavigationCommitted(surfaceKey, event.url, event.isMainFrame);
          },
          onProgressChange: (surfaceKey: string, event: WebViewSurfaceProgressEvent): void => {
            this.handleWebSurfaceProgressChange(surfaceKey, event.newProgress);
          },
          onPageVisible: (surfaceKey: string): void => {
            this.handleWebSurfacePageVisible(surfaceKey);
          },
          onPageEnd: (surfaceKey: string, event: WebViewSurfacePageEvent): void => {
            this.handleWebSurfacePageEnd(surfaceKey, event.url);
          },
          onTitleReceive: (surfaceKey: string, event: WebViewSurfaceTitleEvent): void => {
            this.handleWebSurfaceTitleReceive(surfaceKey, event.title);
          },
          onFaviconReceived: (surfaceKey: string, event: WebViewSurfaceFaviconEvent): void => {
            this.handleWebSurfaceFaviconReceived(surfaceKey, event.favicon);
          },
          onTrackerBlocked: (surfaceKey: string, host: string): void => {
            this.handleWebSurfaceTrackerBlocked(surfaceKey, host);
          },
          onScroll: (surfaceKey: string, event: WebViewSurfaceScrollEvent): void => {
            this.handleWebSurfaceScroll(surfaceKey, event);
          },
          onOverScroll: (surfaceKey: string, event: WebViewSurfaceOverScrollEvent): void => {
            this.handleWebSurfaceOverScroll(surfaceKey, event);
          },
          onPullGestureStart: (surfaceKey: string): void => {
            this.handleWebSurfacePullGestureStart(surfaceKey);
          },
          onPullGestureUpdate: (surfaceKey: string, event: WebViewSurfacePullGestureEvent): void => {
            this.handleWebSurfacePullGestureUpdate(surfaceKey, event);
          },
          onPullGestureEnd: (surfaceKey: string): void => {
            this.handleWebSurfacePullGestureEnd(surfaceKey);
          },
          onFullScreenEnter: (surfaceKey: string, event: WebViewSurfaceFullScreenEvent): void => {
            this.handleWebSurfaceFullScreenEnter(surfaceKey, event);
          },
          onFullScreenExit: (surfaceKey: string): void => {
            this.handleWebSurfaceFullScreenExit(surfaceKey);
          },
          onLoadError: (surfaceKey: string, event: WebViewSurfaceLoadErrorEvent): void => {
            this.handleWebSurfaceLoadError(surfaceKey, event);
          }
        })
          .width('100%')
          .layoutWeight(1)
      }
        .width('100%')
        .height('100%')

      if (!this.webFullScreen && this.canShowBookmarkHome() && this.bookmarkHomeVisible) {
        WebBookmarkHome({
          bookmarks: this.bookmarks,
          loading: this.bookmarksLoading,
          topPadding: this.toolbarHeight(),
          homeTitle: this.homeTabTitle(),
          homeIconSource: $r('app.media.ic_browser_shortcut'),
          iconSource: (url: string): ResourceStr => this.bookmarkIconSource(url),
          tabBackCount: (bookmarkId: string): number => this.bookmarkBadgeCount(bookmarkId),
          homeTabBackCount: (): number => this.homeTabBackCountFromHost,
          onOpenHome: (): void => {
            this.openHomeTab();
          },
          onOpenBookmark: (bookmark: WebBookmarkEntry): void => {
            this.openBookmark(bookmark);
          },
          onCreateDesktopShortcut: (bookmark: WebBookmarkEntry): void => {
            this.createDesktopShortcutFromBookmark(bookmark);
          },
          onDeleteBookmark: (bookmark: WebBookmarkEntry): void => {
            this.confirmDeleteBookmark(bookmark);
          },
          onClearHomeTabStack: (): void => {
            this.onClearInstanceTabStack(WEB_HOME_TAB_ID, DEFAULT_WEB_HOME_URL);
          },
          onCloseBookmarkInstance: (bookmark: WebBookmarkEntry): void => {
            this.onCloseBookmarkInstance(bookmark);
          },
          onPullRefreshStart: (): void => {
            this.handleBookmarkPullRefreshStart();
          },
          onPullRefreshUpdate: (offsetY: number): void => {
            this.handleBookmarkPullRefreshUpdate(offsetY);
          },
          onPullRefreshEnd: (): void => {
            this.handleBookmarkPullRefreshEnd();
          }
        });
      }

      if (!this.webFullScreen) {
        WebBrowserChrome({
          topRectHeight: this.topRectHeight,
          showToolbar: this.showAddressBar,
          toolbarHidden: this.toolbarHidden,
          addressText: this.addressText,
          addressFocused: this.addressFocused,
          loading: this.loading,
          progress: this.progress,
          canGoForward: this.canGoForward,
          bookmarkedUrls: this.bookmarkedUrls(),
          notice: this.notice,
          webError: this.webError,
          pullRefreshVisible: this.activePullRefreshVisible(),
          pullRefreshRefreshing: this.activePullRefreshRefreshing(),
          pullRefreshRotation: this.activePullRefreshRotation(),
          pullRefreshOffset: this.activePullRefreshIndicatorOffset(),
          pullRefreshDistance: this.activePullRefreshDistance(),
          addBookmarkConfirmVisible: this.addBookmarkConfirmVisible,
          addBookmarkConfirmTitle: this.addBookmarkConfirmTitle,
          addBookmarkConfirmIcon: this.addBookmarkConfirmIcon,
          addBookmarkConfirmBusy: this.addBookmarkConfirmBusy,
          deleteBookmarkConfirmVisible: this.deleteBookmarkConfirmVisible,
          deleteBookmarkConfirmTitle: this.deleteBookmarkConfirmTitle,
          deleteBookmarkConfirmIcon: this.deleteBookmarkConfirmIcon,
          deleteBookmarkConfirmBusy: this.deleteBookmarkConfirmBusy,
          onAddressFocusChanged: (focused: boolean): void => {
            this.addressFocused = focused;
          },
          onAddressChange: (value: string): void => {
            this.setAddressText(value);
            this.clearNotice();
          },
          onAddressSubmit: (): void => {
            this.loadAddress();
          },
          onClearAddress: (): void => {
            this.clearAddressForEditing();
          },
          onGoForward: (): void => {
            this.goForward();
          },
          onOpenBookmarks: (): void => {
            this.handleToolbarAction('bookmarks');
          },
          onAddBookmark: (): void => {
            this.handleToolbarAction('shortcut');
          },
          onHideAddBookmarkConfirm: (): void => {
            this.hideAddBookmarkConfirm();
          },
          onSubmitAddBookmarkConfirm: (): void => {
            this.submitAddBookmarkConfirm();
          },
          onHideDeleteBookmarkConfirm: (): void => {
            this.hideDeleteBookmarkConfirm();
          },
          onSubmitDeleteBookmarkConfirm: (): void => {
            this.submitDeleteBookmarkConfirm();
          },
          onReloadWebError: (): void => {
            this.webError = this.emptyWebError();
            this.refresh();
          }
        })
          .zIndex(30)
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(PAGE_BACKGROUND)
  }

  private showWebError(event: WebViewSurfaceLoadErrorEvent): void {
    if (!event.isMainFrame) {
      return;
    }
    const url = event.url.length > 0 ? event.url : this.currentUrl;
    if (!this.shouldShowWebErrorFor(url)) {
      hilog.info(DOMAIN, TAG, 'suppress passive web error kind=%{public}s code=%{public}d url=%{public}s',
        event.kind,
        event.code,
        url
      );
      this.loading = false;
      this.progress = 100;
      this.endPullRefresh();
      return;
    }
    this.webError = {
      visible: true,
      url: url,
      title: this.webErrorTitle(event),
      detail: this.webErrorDetail(event),
      code: event.code,
      kind: event.kind
    };
    this.loading = false;
    this.progress = 100;
    this.endPullRefresh();
  }

  private clearWebErrorFor(url: string): void {
    if (!this.webError.visible) {
      return;
    }
    if (url.length > 0 && this.webError.url.length > 0 && url !== this.webError.url) {
      this.webError = this.emptyWebError();
    }
  }

  private emptyWebError(): WebBrowserErrorState {
    return {
      visible: false,
      url: '',
      title: '',
      detail: '',
      code: 0,
      kind: ''
    };
  }

  private webErrorTitle(event: WebViewSurfaceLoadErrorEvent): string {
    if (event.kind === 'http') {
      return 'HTTP ' + String(event.code);
    }
    if (event.code !== 0) {
      return '网页加载失败 ' + String(event.code);
    }
    return '网页加载失败';
  }

  private webErrorDetail(event: WebViewSurfaceLoadErrorEvent): string {
    const message = event.message.trim();
    if (event.kind === 'http') {
      return message.length > 0 ? message : '服务器返回了错误状态码';
    }
    return message.length > 0 ? message : '网络连接或 WebView 加载异常';
  }

  private toolbarHeight(): number {
    return TOOLBAR_HEIGHT + this.statusBarPadding();
  }

  private browserTopInset(): number {
    if (this.webFullScreen) {
      return 0;
    }
    if (!this.showAddressBar || this.toolbarHidden) {
      return this.statusBarPadding();
    }
    return this.toolbarHeight();
  }

  private statusBarPadding(): number {
    if (this.topRectHeight <= 0) {
      return 0;
    }
    return this.getUIContext().px2vp(this.topRectHeight);
  }

  private clearAddressForEditing(): void {
    this.setAddressText('https://');
    this.clearNotice();
  }

  private handleWebSurfaceControllerAttached(surfaceKey: string): void {
    this.markWebSurfaceAttached(surfaceKey);
    if (!this.isActiveWebSurface(surfaceKey) || this.bookmarkHomeVisible) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'web controller attached key=%{public}s', this.instanceId);
    this.activateAttachedSurface(surfaceKey);
  }

  private handleWebSurfacePageBegin(surfaceKey: string, url: string): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    this.setWebSurfaceScrollY(surfaceKey, 0);
    this.setBrowserPullRefreshEnabled(surfaceKey, true);
    if (url.length > 0) {
      if (this.commitCurrentUrl(url)) {
        this.resetPageMetadata(url);
      }
    }
    this.clearWebErrorFor(url);
    this.resetPullRefreshIfIdle(surfaceKey);
    this.loading = true;
    this.progress = 8;
  }

  private handleWebSurfaceNavigationCommitted(
    surfaceKey: string,
    url: string,
    isMainFrame: boolean
  ): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    if (isMainFrame && url.length > 0) {
      if (this.commitCurrentUrl(url)) {
        this.clearWebErrorFor(url);
        this.updateNavigationState();
        this.syncSurfaceTabStackSize(surfaceKey);
        this.persistLastUrl();
        this.prepareShortcut(url);
        if (this.explicitLoadErrorUrl.length > 0 && this.normalizeUrl(url) !== this.explicitLoadErrorUrl) {
          this.explicitLoadErrorUrl = '';
        }
      }
    }
  }

  private handleWebSurfaceProgressChange(surfaceKey: string, newProgress: number): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    this.progress = newProgress;
    this.loading = newProgress < 100;
  }

  private handleWebSurfacePageVisible(surfaceKey: string): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    this.syncUrlFromController();
    this.updateNavigationState();
    this.syncSurfaceTabStackSize(surfaceKey);
    this.persistWebState();
  }

  private handleWebSurfacePageEnd(surfaceKey: string, url: string): void {
    if (!this.isActiveWebSurface(surfaceKey)) {
      return;
    }
    if (this.bookmarkHomeVisible) {
      return;
    }
    if (url.length > 0) {
      if (!this.commitCurrentUrl(url)) {
        this.syncUrlFromController();
      }
    } else {
      this.syncUrlFromController();
    }
    this.loading = false;
    this.progress = 100;
    this.endPullRefresh(surfaceKey);
    this.updateNavigationState();
    this.syncSurfaceTabStackSize(surfaceKey);
    this.saveWebCookies();
    this.persistWebState();
    this.persistLastUrl();
    this.explicitLoadErrorUrl = '';
    this.prepareShortcut(this.currentUrl);
    this.detectPwaApp(this.currentUrl);
    this.installBrowserPullRefreshTouchProbe(surfaceKey);
    this.probeBrowserPullRefreshPolicy(surfaceKey);
  }

  private handleWebSurfaceTitleReceive(surfaceKey: string, title: string): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    if (title.trim().length > 0) {
      this.pageTitle = title.trim();
      this.pageTitleUrl = this.currentUrl;
      this.prepareShortcut(this.currentUrl);
    }
  }

  private handleWebSurfaceFaviconReceived(surfaceKey: string, favicon: image.PixelMap): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    this.favicon = favicon;
    this.faviconUrl = this.currentUrl;
    this.prepareShortcut(this.currentUrl);
  }

  private handleWebSurfaceTrackerBlocked(surfaceKey: string, host: string): void {
    if (!this.isActiveWebSurface(surfaceKey)) {
      return;
    }
    hilog.warn(DOMAIN, TAG, 'arkweb prevented tracker cookie on host: %{public}s', host);
  }

  private handleWebSurfaceScroll(surfaceKey: string, event: WebViewSurfaceScrollEvent): void {
    const scrollY = Math.max(0, event.yOffset);
    this.setWebSurfaceScrollY(surfaceKey, scrollY);
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined) {
      return;
    }
    if (surface.scrollY > 1 && surface.pullRefresh.tracking && !surface.pullRefresh.refreshing) {
      WebPullRefresh.reset(surface.pullRefresh);
      this.bumpPullRefreshRevision();
    }
    if (surface.scrollY > 1) {
      surface.pullRefresh.gestureOverScrollActive = false;
    }
  }

  private setWebSurfaceScrollY(surfaceKey: string, scrollY: number): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface !== undefined) {
      surface.scrollY = Math.max(0, scrollY);
    }
  }

  private handleWebSurfaceOverScroll(surfaceKey: string, event: WebViewSurfaceOverScrollEvent): void {
    const pullRefresh = this.pullRefreshState(surfaceKey);
    if (!this.shouldHandleWebSurface(surfaceKey) || this.webFullScreen || this.loading || pullRefresh.refreshing ||
      !pullRefresh.browserRefreshEnabled) {
      pullRefresh.gestureOverScrollActive = false;
      return;
    }
    if (Math.abs(event.yOffset) >= WEB_PULL_REFRESH_OVERSCROLL_DISTANCE && this.currentScrollY(surfaceKey) <= 1) {
      pullRefresh.gestureOverScrollActive = true;
    }
  }

  private handleWebSurfacePullGestureStart(surfaceKey: string): void {
    const pullRefresh = this.pullRefreshState(surfaceKey);
    pullRefresh.gestureLastOffsetY = 0;
    pullRefresh.gestureOverScrollActive = false;
    if (pullRefresh.refreshing) {
      return;
    }
    if (!this.shouldHandleWebSurface(surfaceKey) || this.webFullScreen || this.loading) {
      this.resetPullRefresh(surfaceKey);
      return;
    }
    if (!pullRefresh.browserRefreshEnabled || this.currentScrollY(surfaceKey) > 1) {
      this.resetPullRefresh(surfaceKey);
      return;
    }
  }

  private handleWebSurfacePullGestureUpdate(surfaceKey: string, event: WebViewSurfacePullGestureEvent): void {
    const pullRefresh = this.pullRefreshState(surfaceKey);
    this.updateToolbarVisibilityForWebGesture(surfaceKey, event.offsetY);
    if (pullRefresh.refreshing) {
      return;
    }
    if (!this.shouldHandleWebSurface(surfaceKey) || this.webFullScreen || this.loading) {
      this.resetPullRefresh(surfaceKey);
      return;
    }
    if (!pullRefresh.tracking) {
      if (event.offsetY <= 0 || !pullRefresh.browserRefreshEnabled || !pullRefresh.gestureOverScrollActive ||
        this.currentScrollY(surfaceKey) > 1) {
        return;
      }
      WebPullRefresh.beginTracking(pullRefresh, event.offsetY);
    }
    if (event.offsetY <= 0 || !pullRefresh.browserRefreshEnabled || !pullRefresh.gestureOverScrollActive ||
      this.currentScrollY(surfaceKey) > 1) {
      this.resetPullRefresh(surfaceKey);
      return;
    }
    this.updatePullRefresh(surfaceKey, event.offsetY - pullRefresh.gesturePullStartOffsetY);
  }

  private handleWebSurfacePullGestureEnd(surfaceKey: string): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    const pullRefresh = this.pullRefreshState(surfaceKey);
    pullRefresh.gestureLastOffsetY = 0;
    if (pullRefresh.refreshing) {
      return;
    }
    if (pullRefresh.tracking && pullRefresh.ready && pullRefresh.browserRefreshEnabled &&
      pullRefresh.gestureOverScrollActive &&
      this.currentScrollY(surfaceKey) <= 1) {
      this.refreshAfterWebGestureCheck(surfaceKey);
      return;
    }
    this.cancelPullRefresh(surfaceKey);
    pullRefresh.gestureOverScrollActive = false;
  }

  private handleBookmarkPullRefreshStart(): void {
    if (!this.bookmarkHomeVisible || this.webFullScreen) {
      return;
    }
    const pullRefresh = this.pullRefreshState(this.webSurfaceKey);
    if (pullRefresh.refreshing) {
      return;
    }
    WebPullRefresh.beginTracking(pullRefresh);
    this.bumpPullRefreshRevision();
  }

  private handleBookmarkPullRefreshUpdate(offsetY: number): void {
    if (!this.bookmarkHomeVisible || this.webFullScreen) {
      return;
    }
    const pullRefresh = this.pullRefreshState(this.webSurfaceKey);
    if (pullRefresh.refreshing) {
      return;
    }
    if (!pullRefresh.tracking) {
      if (offsetY <= 0) {
        return;
      }
      WebPullRefresh.beginTracking(pullRefresh);
    }
    if (offsetY <= 0) {
      this.resetPullRefresh(this.webSurfaceKey);
      return;
    }
    this.updatePullRefresh(this.webSurfaceKey, offsetY);
  }

  private handleBookmarkPullRefreshEnd(): void {
    if (!this.bookmarkHomeVisible) {
      return;
    }
    const pullRefresh = this.pullRefreshState(this.webSurfaceKey);
    if (pullRefresh.refreshing) {
      return;
    }
    if (pullRefresh.tracking && pullRefresh.ready) {
      this.startBookmarkPullRefresh();
      return;
    }
    this.cancelPullRefresh(this.webSurfaceKey);
  }

  private startBookmarkPullRefresh(): void {
    const pullRefresh = this.pullRefreshState(this.webSurfaceKey);
    if (!this.bookmarkHomeVisible || pullRefresh.refreshing) {
      this.resetPullRefresh(this.webSurfaceKey);
      return;
    }
    WebPullRefresh.markRefreshing(pullRefresh);
    this.bumpPullRefreshRevision();
    this.startPullRefreshSpin(this.webSurfaceKey);
    this.loadBookmarks(() => {
      this.onBookmarksChanged();
      this.endPullRefresh(this.webSurfaceKey);
    });
  }

  private updateToolbarVisibilityForWebGesture(surfaceKey: string, offsetY: number): void {
    if (!this.showAddressBar || !this.shouldHandleWebSurface(surfaceKey) || this.webFullScreen || this.bookmarkHomeVisible ||
      this.addressFocused) {
      return;
    }
    const pullRefresh = this.pullRefreshState(surfaceKey);
    const deltaFromLast = offsetY - pullRefresh.gestureLastOffsetY;
    pullRefresh.gestureLastOffsetY = offsetY;
    if (deltaFromLast < -WEB_TOOLBAR_HIDE_GESTURE_DISTANCE) {
      this.toolbarHidden = true;
      return;
    }
    if (deltaFromLast > WEB_TOOLBAR_HIDE_GESTURE_DISTANCE && !pullRefresh.tracking) {
      this.toolbarHidden = false;
    }
  }

  private handleWebSurfaceFullScreenEnter(surfaceKey: string, event: WebViewSurfaceFullScreenEvent): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    this.enterWebFullScreen(event);
  }

  private handleWebSurfaceFullScreenExit(surfaceKey: string): void {
    if (!this.isActiveWebSurface(surfaceKey)) {
      return;
    }
    this.exitWebFullScreen();
  }

  private handleWebSurfaceLoadError(surfaceKey: string, event: WebViewSurfaceLoadErrorEvent): void {
    if (!this.isActiveWebSurface(surfaceKey)) {
      return;
    }
    if (this.bookmarkHomeVisible) {
      return;
    }
    this.showWebError(event);
  }

  private handleToolbarAction(action: string): void {
    if (action === 'bookmarks') {
      if (this.bookmarkHomeVisible) {
        this.loadBookmarks();
        return;
      }
      this.persistWebState();
      this.saveWebCookies();
      this.onOpenBookmarkHome();
      return;
    }
    if (!this.canAddAddressBookmark()) {
      this.showNotice('当前页面不能添加书签');
      return;
    }
    this.confirmAddCurrentPageToBookmarks();
  }

  private configureBrowserStorage(): void {
    try {
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'configure web cookies failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private configureAttachedController(): void {
    hilog.info(DOMAIN, TAG, 'configure attached web controller');
    try {
      this.controller.setCustomUserAgent(CHROME_MOBILE_USER_AGENT);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'set chrome mobile user agent failed: %{public}s',
        error.message ?? JSON.stringify(err));
    }

    try {
      this.controller.enableIntelligentTrackingPrevention(false);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'disable web tracking prevention failed: %{public}s', error.message ?? JSON.stringify(err));
    }

    try {
      const options = new webview.BackForwardCacheOptions();
      options.size = 8;
      options.timeToLive = 1800;
      this.controller.setBackForwardCacheOptions(options);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'configure web back forward cache failed: %{public}s', error.message ?? JSON.stringify(err));
    }

    this.startWebFullScreenProbe();
  }

  private resetInstanceWebController(activateAttached: boolean = true): void {
    const stateKey = this.currentWebStateTabId();
    this.stopWebFullScreenProbe();
    this.restoringWebState = false;
    this.clearPendingLoadUrl();
    this.nativeWebFullScreen = false;
    this.scriptDetectedWebFullScreen = false;
    this.webFullScreen = false;
    this.canGoBack = false;
    this.canGoForward = false;
    this.resetPullRefresh();
    const surface = this.ensureWebSurface(stateKey);
    this.controller = surface.controller;
    this.controllerAttached = surface.attached;
    this.webSurfaceKey = surface.surfaceKey;
    this.updateWebSurfaceVisibility();
    this.publishWebSurfaceKeys();
    this.loading = !this.bookmarkHomeVisible && !surface.initialized;
    this.progress = this.bookmarkHomeVisible || surface.initialized ? 100 : 0;
    if (activateAttached && surface.attached && !this.bookmarkHomeVisible) {
      this.activateAttachedSurface(surface.surfaceKey);
    }
  }

  private isActiveWebSurface(surfaceKey: string): boolean {
    return surfaceKey === this.webSurfaceKey;
  }

  private webSurfaceVisible(surfaceKey: string): boolean {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined) {
      return false;
    }
    return surface.visible;
  }

  private shouldHandleWebSurface(surfaceKey: string): boolean {
    return !this.bookmarkHomeVisible && this.isActiveWebSurface(surfaceKey);
  }

  private ensureWebSurface(tabId: string): WebSurfaceEntry {
    const surface = this.webSurfaceRegistry.ensure(tabId);
    this.publishWebSurfaceKeys();
    return surface;
  }

  private updateWebSurfaceVisibility(): void {
    this.webSurfaceRegistry.updateVisibility(this.webSurfaceKey, this.bookmarkHomeVisible);
  }

  private publishWebSurfaceKeys(): void {
    this.webSurfaceKeys = this.webSurfaceRegistry.keys();
  }

  private webSurfaceByKey(surfaceKey: string): WebSurfaceEntry | undefined {
    return this.webSurfaceRegistry.byKey(surfaceKey);
  }

  private surfaceController(surfaceKey: string): webview.WebviewController {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface !== undefined) {
      return surface.controller;
    }
    return this.controller;
  }

  private markWebSurfaceAttached(surfaceKey: string): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined) {
      return;
    }
    surface.attached = true;
    if (this.isActiveWebSurface(surfaceKey)) {
      this.controller = surface.controller;
      this.controllerAttached = true;
    }
  }

  private activateAttachedSurface(surfaceKey: string): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined || !surface.attached || !this.isActiveWebSurface(surfaceKey) || this.bookmarkHomeVisible) {
      return;
    }
    this.controller = surface.controller;
    this.controllerAttached = true;
    this.configureAttachedController();
    const pendingUrl = this.consumePendingLoadUrl(surfaceKey);
    if (pendingUrl.length > 0) {
      this.initialNavigationDone = true;
      surface.initialized = true;
      this.loadTabInitialUrl(pendingUrl);
      return;
    }
    if (!surface.initialized) {
      surface.initialized = true;
      this.openAttachedPage();
      return;
    }
    this.syncUrlFromController();
    this.updateNavigationState();
    this.syncSurfaceTabStackSize(surfaceKey);
    this.loading = false;
    this.progress = 100;
    this.prepareShortcut(this.currentUrl);
    this.installBrowserPullRefreshTouchProbe(surfaceKey);
    this.probeBrowserPullRefreshPolicy(surfaceKey);
  }

  private saveWebCookies(): void {
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'save web cookies failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private onInitialUrlChanged(): void {
    if (!this.initialNavigationDone) {
      return;
    }
    this.rememberCurrentTabState();
    this.persistWebState();
    const normalized = this.normalizeUrl(this.initialUrl);
    this.instanceId = this.instanceStateId();
    const isBookmarkHome = this.canShowBookmarkHome() && this.bookmarkHomeVisibleFromHost;
    this.bookmarkHomeVisible = isBookmarkHome;
    const launchTabId = isBookmarkHome ? WEB_BOOKMARKS_HOME_TAB_ID : this.instanceId;
    const tabState = this.readLaunchTabStateMeta(launchTabId,
      isBookmarkHome ? WEB_BOOKMARKS_HOME_URL : normalized);
    this.webTabStates = WebBrowserTabModel.upsert(this.webTabStates, tabState);
    const startUrl = this.normalizeUrl(tabState.url);
    this.currentUrl = startUrl;
    this.setAddressText(startUrl);
    this.resetInstanceWebController();
    if (isBookmarkHome) {
      this.loading = false;
      this.progress = 100;
      this.canGoBack = false;
      this.canGoForward = false;
      this.toolbarHidden = false;
      this.webError = this.emptyWebError();
      this.resetPullRefresh();
      this.rememberBookmarkHomeState();
      this.loadBookmarks();
      return;
    }
    this.prepareShortcut(startUrl);
  }

  private onWebControllerIdChanged(): void {
    if (!this.initialNavigationDone) {
      return;
    }
    const nextId = this.instanceStateId();
    if (this.safeFileSegment(nextId) === this.safeFileSegment(this.instanceId)) {
      return;
    }
    this.rememberCurrentTabState();
    this.persistWebState();
    this.instanceId = nextId;
    this.resetInstanceWebController();
  }

  private onBookmarkHomeVisibleFromHostChanged(): void {
    const nextBookmarkHomeVisible = this.canShowBookmarkHome() && this.bookmarkHomeVisibleFromHost;
    if (nextBookmarkHomeVisible && !this.bookmarkHomeVisible) {
      this.persistWebState();
    }
    this.bookmarkHomeVisible = nextBookmarkHomeVisible;
    this.updateWebSurfaceVisibility();
    if (this.bookmarkHomeVisible) {
      this.saveWebCookies();
      this.loading = false;
      this.progress = 100;
      this.canGoBack = false;
      this.canGoForward = false;
      this.toolbarHidden = false;
      this.webError = this.emptyWebError();
      this.resetPullRefresh();
      this.rememberBookmarkHomeState();
      this.loadBookmarks();
      return;
    }
    this.syncUrlFromController();
    if (this.controllerAttached) {
      this.activateAttachedSurface(this.webSurfaceKey);
    }
    this.updateNavigationState();
  }

  private loadAddress(): void {
    const normalized = this.normalizeUrl(this.addressText);
    this.setAddressText(normalized);
    this.loadUrl(normalized);
  }

  private loadTabInitialUrl(url: string): boolean {
    return this.loadUrl(url);
  }

  private setPendingLoadUrl(url: string): void {
    this.pendingLoadUrl = this.normalizeUrl(url);
    this.pendingLoadSurfaceKey = this.webSurfaceKey;
  }

  private consumePendingLoadUrl(surfaceKey: string): string {
    if (this.pendingLoadUrl.length === 0 || this.pendingLoadSurfaceKey !== surfaceKey) {
      return '';
    }
    const url = this.pendingLoadUrl;
    this.clearPendingLoadUrl();
    return url;
  }

  private clearPendingLoadUrl(): void {
    this.pendingLoadUrl = '';
    this.pendingLoadSurfaceKey = '';
  }

  private loadUrl(url: string): boolean {
    const normalized = this.normalizeUrl(url);
    if (this.isBookmarkHomeUrl(normalized)) {
      this.onOpenBookmarkHome();
      return true;
    }
    const switchingFromBookmarkHome = this.bookmarkHomeVisible;
    if (this.bookmarkHomeVisible) {
      this.onOpenHomeInstance();
      this.bookmarkHomeVisible = false;
      this.currentUrl = normalized;
      this.instanceId = WEB_HOME_TAB_ID;
      this.resetInstanceWebController(false);
    }
    this.commitCurrentUrl(normalized);
    this.explicitLoadErrorUrl = normalized;
    this.resetPwaAppInfo();

    try {
      this.bookmarkHomeVisible = false;
      this.updateWebSurfaceVisibility();
      this.warmupServiceWorker(normalized);
      const surface = this.webSurfaceByKey(this.webSurfaceKey);
      if (switchingFromBookmarkHome || !this.controllerAttached || (surface !== undefined && !surface.initialized)) {
        this.setPendingLoadUrl(normalized);
        this.loading = true;
        this.progress = 0;
        this.clearNotice();
        this.webError = this.emptyWebError();
        if (this.controllerAttached) {
          this.activateAttachedSurface(this.webSurfaceKey);
        }
        return true;
      }
      this.clearPendingLoadUrl();
      this.controller.loadUrl(normalized);
      this.loading = true;
      this.progress = 8;
      this.clearNotice();
      this.webError = this.emptyWebError();
      return true;
    } catch (err) {
      this.showWebError({
        url: normalized,
        isMainFrame: true,
        code: 0,
        message: this.formatError(err),
        kind: 'controller'
      });
      return false;
    }
  }

  private warmupServiceWorker(url: string): void {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return;
    }

    try {
      webview.WebviewController.warmupServiceWorker(url);
    } catch (err) {
    }
  }

  private refresh(): boolean {
    if (this.bookmarkHomeVisible) {
      this.loadBookmarks();
      return true;
    }
    const normalized = this.currentReloadUrl();
    this.explicitLoadErrorUrl = normalized;
    try {
      this.controller.refresh();
      this.commitCurrentUrl(normalized);
      this.loading = true;
      this.progress = 8;
      this.clearNotice();
      this.webError = this.emptyWebError();
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'web refresh failed, reload current url instead: %{public}s',
        error.message ?? JSON.stringify(err));
      return this.loadUrl(normalized);
    }
  }

  private refreshAfterWebGestureCheck(surfaceKey: string): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined || !this.isActiveWebSurface(surfaceKey)) {
      this.cancelPullRefresh(surfaceKey);
      return;
    }

    try {
      surface.controller.runJavaScript(WEB_BROWSER_PULL_REFRESH_CONSUMED_SCRIPT).then((raw: string) => {
        if (!this.isActiveWebSurface(surfaceKey)) {
          this.cancelPullRefresh(surfaceKey);
          return;
        }
        if (this.parseBrowserPullRefreshConsumed(raw)) {
          this.cancelPullRefresh(surfaceKey);
          return;
        }
        this.startBrowserPullRefresh(surfaceKey);
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'check web pull refresh consumption failed: %{public}s',
          err.message ?? JSON.stringify(err));
        this.startBrowserPullRefresh(surfaceKey);
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'check web pull refresh consumption rejected: %{public}s',
        error.message ?? JSON.stringify(err));
      this.startBrowserPullRefresh(surfaceKey);
    }
  }

  private startBrowserPullRefresh(surfaceKey: string): void {
    const pullRefresh = this.pullRefreshState(surfaceKey);
    if (!this.shouldHandleWebSurface(surfaceKey) || pullRefresh.refreshing || !pullRefresh.browserRefreshEnabled ||
      this.currentScrollY(surfaceKey) > 1) {
      this.resetPullRefresh(surfaceKey);
      return;
    }
    WebPullRefresh.markRefreshing(pullRefresh);
    this.bumpPullRefreshRevision();
    this.startPullRefreshSpin(surfaceKey);
    if (!this.refresh()) {
      this.endPullRefresh(surfaceKey);
    }
  }

  private installBrowserPullRefreshTouchProbe(surfaceKey: string): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined || !surface.attached || !this.isActiveWebSurface(surfaceKey) ||
      this.bookmarkHomeVisible || this.webFullScreen) {
      return;
    }

    try {
      surface.controller.runJavaScript(WEB_BROWSER_PULL_REFRESH_TOUCH_PROBE_SCRIPT).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'install browser pull refresh probe failed: %{public}s',
          err.message ?? JSON.stringify(err));
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'install browser pull refresh probe rejected: %{public}s',
        error.message ?? JSON.stringify(err));
    }
  }

  private probeBrowserPullRefreshPolicy(surfaceKey: string): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined || !surface.attached || !this.isActiveWebSurface(surfaceKey) ||
      this.bookmarkHomeVisible || this.webFullScreen) {
      return;
    }

    const serial = ++surface.pullRefresh.probeSerial;
    try {
      surface.controller.runJavaScript(WEB_BROWSER_PULL_REFRESH_POLICY_SCRIPT).then((raw: string) => {
        if (surface.pullRefresh.probeSerial !== serial) {
          return;
        }
        this.setBrowserPullRefreshEnabled(surfaceKey, this.parseBrowserPullRefreshPolicy(raw));
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'probe browser pull refresh policy failed: %{public}s',
          err.message ?? JSON.stringify(err));
        this.setBrowserPullRefreshEnabled(surfaceKey, true);
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'probe browser pull refresh policy rejected: %{public}s',
        error.message ?? JSON.stringify(err));
      this.setBrowserPullRefreshEnabled(surfaceKey, true);
    }
  }

  private parseBrowserPullRefreshPolicy(raw: string): boolean {
    if (raw.length === 0 || raw === 'null' || raw === 'undefined') {
      return true;
    }

    try {
      const parsed: WebBrowserPullRefreshPolicyRaw | string =
        JSON.parse(raw) as WebBrowserPullRefreshPolicyRaw | string;
      const value: WebBrowserPullRefreshPolicyRaw =
        typeof parsed === 'string' ? JSON.parse(parsed) as WebBrowserPullRefreshPolicyRaw : parsed;
      if (value.enabled === false) {
        return false;
      }
    } catch (err) {
      return true;
    }
    return true;
  }

  private parseBrowserPullRefreshConsumed(raw: string): boolean {
    if (raw.length === 0 || raw === 'null' || raw === 'undefined') {
      return false;
    }

    try {
      const parsed: WebBrowserPullRefreshConsumedRaw | string =
        JSON.parse(raw) as WebBrowserPullRefreshConsumedRaw | string;
      const value: WebBrowserPullRefreshConsumedRaw =
        typeof parsed === 'string' ? JSON.parse(parsed) as WebBrowserPullRefreshConsumedRaw : parsed;
      return value.consumed === true;
    } catch (err) {
      return false;
    }
  }

  private setBrowserPullRefreshEnabled(surfaceKey: string, enabled: boolean): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined) {
      return;
    }
    surface.pullRefresh.browserRefreshEnabled = enabled;
    if (!enabled && !surface.pullRefresh.refreshing) {
      WebPullRefresh.reset(surface.pullRefresh);
    }
    this.bumpPullRefreshRevision();
  }

  private currentReloadUrl(): string {
    if (this.bookmarkHomeVisible) {
      return WEB_BOOKMARKS_HOME_URL;
    }
    this.syncUrlFromController();
    const candidate = this.currentUrl.length > 0 ? this.currentUrl : this.addressText;
    return this.normalizeUrl(candidate);
  }

  private handleBackNavigation(): boolean {
    if (this.webFullScreen) {
      this.requestExitWebFullScreen();
      return true;
    }

    if (this.bookmarkHomeVisible) {
      this.onClose();
      return true;
    }

    try {
      if (!this.controllerAttached) {
        this.onClose();
        return true;
      }
      if (!this.controller.accessBackward()) {
        this.canGoBack = false;
        this.canGoForward = false;
        this.syncActiveTabStackSize();
        this.persistWebState();
        this.saveWebCookies();
        this.onClose();
        return true;
      }
      this.controller.backward();
      this.updateNavigationState();
      this.syncActiveTabStackSize();
      this.clearNotice();
      this.webError = this.emptyWebError();
      return true;
    } catch (err) {
      this.showNotice(this.formatError(err));
      return true;
    }
  }

  private syncUrlFromController(): void {
    try {
      const url = this.controller.getUrl();
      if (url.length > 0) {
        this.commitCurrentUrl(url);
      }
    } catch (err) {
    }
  }

  private commitCurrentUrl(url: string): boolean {
    if (!this.isBrowserStateUrl(url)) {
      hilog.warn(DOMAIN, TAG, 'ignore non-browser url state: %{public}s', url);
      return false;
    }
    this.currentUrl = url;
    this.setAddressText(url);
    return true;
  }

  private setAddressText(value: string): void {
    if (this.addressText !== value) {
      this.addressText = value;
    }
  }

  private showNotice(message: string): void {
    const value = message.trim();
    this.stopNoticeTimer();
    if (value.length === 0) {
      this.notice = '';
      return;
    }
    this.notice = value;
    this.noticeTimer = setTimeout(() => {
      this.notice = '';
      this.noticeTimer = -1;
    }, WEB_NOTICE_DURATION_MS);
  }

  private clearNotice(): void {
    this.stopNoticeTimer();
    this.notice = '';
  }

  private stopNoticeTimer(): void {
    if (this.noticeTimer >= 0) {
      clearTimeout(this.noticeTimer);
      this.noticeTimer = -1;
    }
  }

  private updateNavigationState(): void {
    try {
      this.canGoBack = this.controller.accessBackward();
      this.canGoForward = this.controller.accessForward();
    } catch (err) {
      this.canGoBack = false;
      this.canGoForward = false;
    }
  }

  private goForward(): void {
    if (this.bookmarkHomeVisible || !this.controllerAttached) {
      this.canGoForward = false;
      return;
    }
    try {
      if (!this.controller.accessForward()) {
        this.canGoForward = false;
        return;
      }
      this.controller.forward();
      this.updateNavigationState();
      this.clearNotice();
      this.webError = this.emptyWebError();
    } catch (err) {
      this.showNotice(this.formatError(err));
      this.updateNavigationState();
    }
  }

  private instanceStateId(): string {
    const id = this.safeFileSegment(this.webControllerId);
    if (id.length > 0) {
      return id;
    }
    return WEB_HOME_TAB_ID;
  }

  private tabBackCount(tabId: string): number {
    return WebBrowserTabModel.tabBackCount(this.webTabStates, tabId);
  }

  private bookmarkBadgeCount(bookmarkId: string): number {
    return this.tabBackCountFromHost(bookmarkId);
  }

  private rememberCurrentTabState(backCount: number = -1): void {
    const id = this.currentWebStateTabId();
    if (id.length === 0) {
      return;
    }
    const update: WebTabStateUpdate = WebBrowserTabModel.rememberCurrent(
      this.webTabStates,
      id,
      this.currentUrl,
      this.isBookmarkHomeUrl(this.currentUrl),
      WEB_HOME_TAB_ID,
      DEFAULT_WEB_HOME_URL,
      backCount >= 0 ? backCount : this.currentTabStackSize()
    );
    this.webTabStates = update.states;
    this.persistTabState(update.state);
    this.onTabStateChanged(update.state);
  }

  private syncActiveTabStackSize(): void {
    this.syncSurfaceTabStackSize(this.webSurfaceKey);
  }

  private syncSurfaceTabStackSize(surfaceKey: string): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined || !surface.attached || this.bookmarkHomeVisible) {
      return;
    }
    const stackSize = this.controllerBackForwardListSize(surface.controller);
    if (stackSize <= 0) {
      return;
    }
    this.rememberTabState(surface.id, this.surfaceCurrentUrl(surface), stackSize);
  }

  private rememberTabState(tabId: string, url: string, backCount: number): void {
    const id = this.safeFileSegment(tabId);
    if (id.length === 0) {
      return;
    }
    const update: WebTabStateUpdate = WebBrowserTabModel.rememberCurrent(
      this.webTabStates,
      id,
      url,
      false,
      WEB_HOME_TAB_ID,
      DEFAULT_WEB_HOME_URL,
      backCount
    );
    this.webTabStates = update.states;
    this.persistTabState(update.state);
    this.onTabStateChanged(update.state);
  }

  private rememberBookmarkHomeState(): void {
    const state: WebTabState = {
      id: WEB_BOOKMARKS_HOME_TAB_ID,
      url: WEB_BOOKMARKS_HOME_URL,
      backCount: 0
    };
    this.webTabStates = WebBrowserTabModel.upsert(this.webTabStates, state);
    this.persistTabState(state);
    this.onTabStateChanged(state);
  }

  private currentTabStackSize(): number {
    if (!this.controllerAttached || this.bookmarkHomeVisible) {
      return this.tabBackCount(this.currentWebStateTabId());
    }
    const stackSize = this.controllerBackForwardListSize(this.controller);
    if (stackSize <= 0) {
      return this.tabBackCount(this.currentWebStateTabId());
    }
    return stackSize;
  }

  private controllerBackForwardListSize(controller: webview.WebviewController): number {
    try {
      const list = controller.getBackForwardEntries();
      return Math.max(0, list.size);
    } catch (err) {
      return 0;
    }
  }

  private surfaceCurrentUrl(surface: WebSurfaceEntry): string {
    try {
      const url = surface.controller.getUrl();
      if (url.length > 0 && this.isBrowserStateUrl(url)) {
        return url;
      }
    } catch (err) {
    }
    if (surface.id === this.currentWebStateTabId() && this.isBrowserStateUrl(this.currentUrl)) {
      return this.currentUrl;
    }
    return WebBrowserTabModel.tabUrl(this.webTabStates, surface.id);
  }

  private currentWebStateTabId(): string {
    return this.safeFileSegment(this.instanceId);
  }

  private homeTabTitle(): string {
    if (this.bookmarkHomeVisible) {
      return '首页';
    }
    if (this.isHomeInstance && !this.bookmarkHomeVisible && this.pageTitle.trim().length > 0) {
      return this.pageTitle.trim();
    }
    return 'Browser';
  }

  private persistLastUrl(): void {
    if (!this.persistBrowserState) {
      return;
    }
    if (!this.isHomeInstance || this.currentWebStateTabId() !== WEB_HOME_TAB_ID) {
      return;
    }
    if (!this.isBrowserStateUrl(this.currentUrl)) {
      return;
    }

    const context = getContext(this) as common.UIAbilityContext;
    saveLastWebUrl(context, this.currentUrl).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'save last web url failed: %{public}s', err.message ?? JSON.stringify(err));
    });
  }

  private prepareShortcut(url: string): void {
    if (!this.isBrowserShortcutUrl(url)) {
      return;
    }
    const normalized = this.normalizeUrl(url);
    const shortcutId = this.shortcutId(normalized);
    this.shortcutCheckUrl = normalized;
    this.shortcutCheckId = shortcutId;
    this.shortcutTid = '';
    const serial = ++this.shortcutCheckSerial;
    const context = getContext(this) as common.UIAbilityContext;
    if (this.persistBrowserState && this.isHomeInstance) {
      savePinnedWebUrl(context, normalized).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'save pinned web url failed: %{public}s', err.message ?? JSON.stringify(err));
      });
    }

    this.queryPinShortcutPermitted(context, normalized).then((result: productViewManager.CheckShortcutResult) => {
      if (this.shortcutCheckSerial === serial && this.shortcutCheckUrl === normalized &&
        this.shortcutCheckId === shortcutId) {
        this.shortcutTid = result.tid ?? '';
      }
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'check pin shortcut failed: %{public}s', err.message ?? JSON.stringify(err));
    });
  }

  private detectPwaApp(url: string): void {
    const normalized = this.normalizeUrl(url);
    if (!this.isBrowserShortcutUrl(normalized) || !this.controllerAttached || this.currentUrl !== normalized) {
      this.resetPwaAppInfo();
      return;
    }
    const serial = ++this.pwaInfoSerial;
    const context = getContext(this) as common.UIAbilityContext;
    const service = new WebShortcutIconService(context);
    service.queryPwaAppInfo(normalized, this.currentUserAgent(), this.controller).then((info: PwaAppInfo) => {
      if (serial !== this.pwaInfoSerial || this.currentUrl !== normalized) {
        return;
      }
      this.pwaAppInfo = info;
      if (info.isPwa) {
        hilog.info(DOMAIN, TAG, 'pwa detected start_url=%{public}s scope=%{public}s', info.startUrl, info.scope);
      }
    }).catch((err: BusinessError) => {
      if (serial === this.pwaInfoSerial) {
        this.pwaAppInfo = WebShortcutIconService.emptyPwaAppInfo();
      }
      hilog.warn(DOMAIN, TAG, 'detect pwa failed: %{public}s', this.formatError(err));
    });
  }

  private resetPwaAppInfo(): void {
    this.pwaInfoSerial++;
    this.pwaAppInfo = WebShortcutIconService.emptyPwaAppInfo();
  }

  private confirmAddCurrentPageToBookmarks(): void {
    const normalized = this.currentPageUrlForBookmark();
    if (normalized.length === 0) {
      this.showNotice('当前页面不能添加书签');
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    loadWebBookmarks(context, true).then((bookmarks: WebBookmarkEntry[]) => {
      if (this.hasBookmarkUrl(bookmarks, normalized)) {
        this.showNotice('书签已存在');
        this.bookmarks = bookmarks;
        return;
      }
      this.showAddBookmarkConfirm(context, normalized);
    }).catch((err: BusinessError) => {
      this.showNotice(err.message ?? JSON.stringify(err));
    });
  }

  private showAddBookmarkConfirm(context: common.UIAbilityContext, url: string): void {
    this.captureShortcutMetadata(url);
    const normalized = this.normalizeUrl(url);
    const title = this.bookmarkTitleForUrl(normalized);
    const serial = ++this.addBookmarkConfirmSerial;
    this.addBookmarkConfirmUrl = normalized;
    this.addBookmarkConfirmTitle = title;
    this.addBookmarkConfirmIcon = this.bookmarkIconFileSource(normalized);
    this.addBookmarkConfirmBusy = true;
    this.addBookmarkConfirmVisible = true;
    this.prepareShortcutIcons(context, normalized, true).then(() => {
      if (serial === this.addBookmarkConfirmSerial && this.addBookmarkConfirmUrl === normalized) {
        this.addBookmarkConfirmIcon = this.bookmarkIconFileSource(normalized);
        this.addBookmarkConfirmBusy = false;
      }
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'prepare bookmark confirm icon failed: %{public}s', this.formatError(err));
      if (serial === this.addBookmarkConfirmSerial && this.addBookmarkConfirmUrl === normalized) {
        this.addBookmarkConfirmBusy = false;
      }
    });
  }

  private hideAddBookmarkConfirm(): void {
    this.addBookmarkConfirmSerial++;
    this.addBookmarkConfirmVisible = false;
    this.addBookmarkConfirmBusy = false;
    this.addBookmarkConfirmUrl = '';
    this.addBookmarkConfirmTitle = '';
    this.addBookmarkConfirmIcon = '';
  }

  private submitAddBookmarkConfirm(): void {
    if (this.addBookmarkConfirmBusy) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const addressUrl = this.currentPageUrlForBookmark();
    if (addressUrl.length === 0) {
      this.addBookmarkConfirmBusy = false;
      this.showNotice('当前页面不能添加书签');
      return;
    }
    this.addBookmarkConfirmBusy = true;
    this.addBookmark(context, addressUrl);
  }

  private addBookmark(context: common.UIAbilityContext, url: string): void {
    if (!this.isBrowserShortcutUrl(url)) {
      this.addBookmarkConfirmBusy = false;
      this.showNotice('只支持添加 http:// 或 https:// 页面');
      return;
    }
    const normalized = this.normalizeUrl(url);
    if (!this.isBrowserShortcutUrl(normalized)) {
      this.addBookmarkConfirmBusy = false;
      this.showNotice('只支持添加 http:// 或 https:// 页面');
      return;
    }
    const title = this.addBookmarkConfirmTitle.trim().length > 0 ? this.addBookmarkConfirmTitle.trim() :
      this.shortcutLabel(normalized);
    const bookmarkId = this.shortcutId(normalized);
    this.prepareShortcutIcons(context, normalized, true).then(() => {
      return saveWebBookmark(context, normalized, title, bookmarkId);
    }).then((added: boolean) => {
      if (!added) {
        this.showNotice('书签已存在');
        this.hideAddBookmarkConfirm();
        return;
      }
      this.clearNotice();
      this.initializeNewBookmarkTabState(bookmarkId, normalized);
      this.hideAddBookmarkConfirm();
      this.loadBookmarks();
      this.onBookmarksChanged();
    }).catch((err: BusinessError) => {
      this.addBookmarkConfirmBusy = false;
      this.showNotice('添加书签失败：' + this.formatError(err));
    });
  }

  private currentPageUrlForBookmark(): string {
    const addressUrl = this.addressText.trim();
    if (!this.isBrowserShortcutUrl(addressUrl)) {
      return '';
    }
    return this.normalizeUrl(addressUrl);
  }

  private canAddAddressBookmark(): boolean {
    const url = this.currentPageUrlForBookmark();
    return url.length > 0 && !this.hasBookmarkUrl(this.bookmarks, url);
  }

  private initializeNewBookmarkTabState(bookmarkId: string, url: string): void {
    const id = this.safeFileSegment(bookmarkId);
    if (id.length === 0) {
      return;
    }
    const state: WebTabState = {
      id: id,
      url: url,
      backCount: 0
    };
    this.persistTabState(state);
    this.truncateWebState(id);
  }

  private requestPinShortcut(
    context: common.UIAbilityContext,
    url: string,
    title: string = '',
    shortcutIdOverride: string = ''
  ): void {
    const normalized = this.normalizeUrl(url);
    const label = title.trim().length > 0 ? title.trim() : this.shortcutLabel(normalized);
    const shortcutId = shortcutIdOverride.length > 0 ? shortcutIdOverride : this.shortcutId(normalized);
    saveWebShortcutMapping(context, shortcutId, normalized).then(() => {
      this.requestPinnedShortcutAfterBookmarkSaved(context, normalized, label, shortcutId);
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'save shortcut mapping failed: %{public}s', this.formatError(err));
      this.requestPinnedShortcutAfterBookmarkSaved(context, normalized, label, shortcutId);
    });
  }

  private requestPinnedShortcutAfterBookmarkSaved(
    context: common.UIAbilityContext,
    normalized: string,
    title: string = '',
    shortcutIdOverride: string = ''
  ): void {
    const shortcutId = shortcutIdOverride.length > 0 ? shortcutIdOverride : this.shortcutId(normalized);
    this.shortcutTid = '';
    this.queryPinShortcutPermitted(context, normalized, true, title, shortcutId)
      .then((result: productViewManager.CheckShortcutResult) => {
        const tid = result.tid ?? '';
        if (tid.length === 0) {
          hilog.warn(DOMAIN, TAG, 'pin shortcut skipped, system returned empty tid');
          return;
        }
        this.shortcutTid = tid;
        this.shortcutCheckUrl = normalized;
        this.shortcutCheckId = shortcutId;
        this.requestPinShortcutWithTid(context, tid, normalized);
      }).catch((err: BusinessError) => {
        this.handlePinShortcutFailure(err, normalized);
      });
  }

  private async queryPinShortcutPermitted(
    context: common.UIAbilityContext,
    url: string,
    preferWebIcon: boolean = false,
    title: string = '',
    shortcutIdOverride: string = ''
  ): Promise<productViewManager.CheckShortcutResult> {
    this.captureShortcutMetadata(url);
    const iconInfo = await this.prepareShortcutIcons(context, url, preferWebIcon);
    const shortcutId = shortcutIdOverride.length > 0 ? shortcutIdOverride : this.shortcutId(url);
    const label = title.trim().length > 0 ? title.trim() : this.shortcutLabel(url);

    return productViewManager.checkPinShortcutPermitted(
      context,
      shortcutId,
      this.buildShortcutWant(url, shortcutId, WEB_SHORTCUT_ABILITY),
      label,
      iconInfo.foregroundIcon,
      ''
    );
  }

  private async prepareShortcutIcons(
    context: common.UIAbilityContext,
    url: string,
    preferWebIcon: boolean = false
  ): Promise<ShortcutIconInfo> {
    const iconService = new WebShortcutIconService(context);
    return iconService.prepareShortcutIcons(
      url,
      preferWebIcon,
      this.favicon,
      this.faviconUrl,
      this.currentUserAgent(),
      (pageUrl: string): Promise<PageIconInfo> => this.queryShortcutPageIconInfo(pageUrl)
    );
  }

  private currentUserAgent(): string {
    try {
      const customUserAgent = this.controller.getCustomUserAgent();
      if (customUserAgent.length > 0) {
        return customUserAgent;
      }
    } catch (err) {
    }
    return CHROME_MOBILE_USER_AGENT;
  }

  private queryPageIconInfo(url: string): Promise<PageIconInfo> {
    const empty: PageIconInfo = {
      manifestUrl: '',
      icons: []
    };
    if (!this.controllerAttached) {
      return Promise.resolve(empty);
    }
    return WebShortcutIconService.queryPageIconInfo(this.controller);
  }

  private queryShortcutPageIconInfo(url: string): Promise<PageIconInfo> {
    return this.queryPageIconInfo(url).then((info: PageIconInfo) => {
      if (info.manifestUrl.length > 0) {
        return info;
      }
      if (this.pwaAppInfo.isPwa && this.pwaAppInfo.manifestUrl.length > 0 &&
        this.normalizeUrl(url).startsWith(this.pwaAppInfo.scope)) {
        return {
          manifestUrl: this.pwaAppInfo.manifestUrl,
          icons: info.icons
        } as PageIconInfo;
      }
      return info;
    });
  }

  private shortcutLabel(url: string): string {
    const title = this.pageTitleUrl === url ? this.pageTitle.trim() : '';
    if (title.length > 0) {
      return title;
    }
    const host = this.hostFromUrl(url);
    return host.length > 0 ? host : SHORTCUT_DEFAULT_LABEL;
  }

  private bookmarkTitleForUrl(url: string): string {
    const normalized = this.normalizeUrl(url);
    if (this.pwaAppInfo.isPwa && this.pwaAppInfo.name.length > 0 &&
      (normalized === this.normalizeUrl(this.pwaAppInfo.startUrl) ||
        (this.pwaAppInfo.scope.length > 0 && normalized.startsWith(this.pwaAppInfo.scope)))) {
      return this.pwaAppInfo.name;
    }
    return this.shortcutLabel(normalized);
  }

  private resetPageMetadata(url: string): void {
    if (this.faviconUrl !== url) {
      this.favicon = undefined;
      this.faviconUrl = '';
    }
    if (this.pageTitleUrl !== url) {
      this.pageTitle = '';
      this.pageTitleUrl = '';
    }
  }

  private hostFromUrl(url: string): string {
    return WebShortcutIconService.hostFromUrl(url);
  }

  private shortcutId(url: string): string {
    return WebShortcutIconService.shortcutId(url);
  }

  private requestPinShortcutWithTid(context: common.UIAbilityContext, tid: string, url: string): void {
    productViewManager.requestNewPinShortcut(context, tid).then(() => {
      this.shortcutTid = '';
    }).catch((err: BusinessError) => {
      this.handlePinShortcutFailure(err, url);
    });
  }

  private handlePinShortcutFailure(err: BusinessError, url: string): void {
    if (this.isShortcutLimitError(err)) {
      hilog.warn(DOMAIN, TAG, 'pin shortcut skipped, system shortcut limit reached');
      this.showNotice('桌面快捷方式数量已达上限');
      return;
    }

    hilog.warn(DOMAIN, TAG, 'pin shortcut failed: %{public}s', this.formatError(err));
    this.showNotice('创建桌面快捷方式失败：' + this.formatError(err));
  }

  private isShortcutLimitError(err: BusinessError): boolean {
    if (err.code === 1006620004) {
      return true;
    }
    const message = err.message ?? '';
    return message.indexOf('1006620004') >= 0 || message.indexOf('maximum') >= 0 ||
      message.indexOf('maximu') >= 0;
  }

  private captureShortcutMetadata(url: string): void {
    if (!this.controllerAttached || this.currentUrl !== url) {
      return;
    }

    try {
      const title = this.controller.getTitle().trim();
      if (title.length > 0) {
        this.pageTitle = title;
        this.pageTitleUrl = url;
      }
    } catch (err) {
    }

    if (this.favicon !== undefined && this.faviconUrl === url) {
      return;
    }

    try {
      this.favicon = this.controller.getFavicon();
      this.faviconUrl = url;
    } catch (err) {
    }
  }

  private buildShortcutWant(url: string, shortcutId: string, abilityName: string = ENTRY_ABILITY): Want {
    const want: Want = {
      bundleName: BUNDLE_NAME,
      moduleName: MODULE_NAME,
      abilityName: abilityName,
      parameters: {
        openWeb: '1'
      }
    };
    if (want.parameters !== undefined) {
      want.parameters[WEB_SHORTCUT_URL_KEY] = url;
      want.parameters[WEB_SHORTCUT_ID_KEY] = shortcutId;
    }
    return want;
  }

  private enterWebFullScreen(event: WebViewSurfaceFullScreenEvent): void {
    hilog.info(DOMAIN, TAG, 'enter web fullscreen video=%{public}dx%{public}d',
      event.videoWidth, event.videoHeight);
    this.nativeWebFullScreen = true;
    this.fullScreenExitHandler = event.handler;
    this.webFullScreen = true;
    this.toolbarHidden = true;
    this.clearNotice();
    this.resetPullRefresh();
    this.endPullRefresh();
    this.setVideoFullScreenSystemBars(true);
  }

  private exitWebFullScreen(): void {
    hilog.info(DOMAIN, TAG, 'exit web fullscreen');
    this.nativeWebFullScreen = false;
    this.scriptDetectedWebFullScreen = false;
    this.fullScreenExitHandler = undefined;
    this.webFullScreen = false;
    this.toolbarHidden = false;
    this.resetPullRefresh();
    this.updateNavigationState();
    this.setVideoFullScreenSystemBars(false);
  }

  private requestExitWebFullScreen(): void {
    const handler = this.fullScreenExitHandler;
    if (handler === undefined) {
      if (this.scriptDetectedWebFullScreen) {
        this.requestExitScriptDetectedWebFullScreen();
        return;
      }
      this.exitWebFullScreen();
      return;
    }

    try {
      handler.exitFullScreen();
    } catch (err) {
      this.exitWebFullScreen();
    }
  }

  private setVideoFullScreenSystemBars(fullScreen: boolean): void {
    setWebVideoFullScreenWindow(fullScreen, DOMAIN, TAG);
  }

  private startWebFullScreenProbe(): void {
    if (this.webFullScreenProbeTimer >= 0) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'start web fullscreen probe');
    this.webFullScreenProbeTimer = setInterval(() => {
      this.probeWebFullScreen();
    }, WEB_FULLSCREEN_PROBE_INTERVAL_MS);
    this.probeWebFullScreen();
  }

  private stopWebFullScreenProbe(): void {
    if (this.webFullScreenProbeTimer >= 0) {
      clearInterval(this.webFullScreenProbeTimer);
      this.webFullScreenProbeTimer = -1;
      hilog.info(DOMAIN, TAG, 'stop web fullscreen probe');
    }
    this.webFullScreenProbeInFlight = false;
  }

  private probeWebFullScreen(): void {
    if (!this.controllerAttached || this.webFullScreenProbeInFlight || this.nativeWebFullScreen) {
      return;
    }

    this.webFullScreenProbeInFlight = true;
    try {
      this.controller.runJavaScript(WebFullscreenProbe.probeScript()).then((raw: string) => {
        this.webFullScreenProbeInFlight = false;
        if (this.webFullScreenProbeTimer < 0) {
          return;
        }
        this.applyWebFullScreenProbeResult(WebFullscreenProbe.parseResult(raw));
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'web fullscreen probe failed: %{public}s',
          err.message ?? JSON.stringify(err));
        this.webFullScreenProbeInFlight = false;
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'web fullscreen probe rejected: %{public}s',
        error.message ?? JSON.stringify(err));
      this.webFullScreenProbeInFlight = false;
    }
  }

  private applyWebFullScreenProbeResult(result: WebFullScreenProbeResult): void {
    if (this.nativeWebFullScreen) {
      return;
    }

    if (result.fullScreen) {
      if (!this.webFullScreen) {
        hilog.info(DOMAIN, TAG, 'script detected web fullscreen source=%{public}s video=%{public}dx%{public}d',
          result.source, result.videoWidth, result.videoHeight);
        this.scriptDetectedWebFullScreen = true;
        this.webFullScreen = true;
        this.toolbarHidden = true;
        this.clearNotice();
        this.resetPullRefresh();
        this.endPullRefresh();
        this.setVideoFullScreenSystemBars(true);
      }
      return;
    }

    if (this.scriptDetectedWebFullScreen) {
      this.exitWebFullScreen();
    }
  }

  private requestExitScriptDetectedWebFullScreen(): void {
    try {
      this.controller.runJavaScript(WebFullscreenProbe.exitScript()).then(() => {
        this.exitWebFullScreen();
      }).catch(() => {
        this.exitWebFullScreen();
      });
    } catch (err) {
      this.exitWebFullScreen();
    }
  }

  private openAttachedPage(): void {
    if (!this.initialNavigationDone) {
      this.initialNavigationDone = true;
    }
    if (this.isBookmarkHomeUrl(this.currentUrl)) {
      this.showBookmarkHome();
      return;
    }

    if (this.explicitLoadErrorUrl.length > 0 && this.normalizeUrl(this.currentUrl) === this.explicitLoadErrorUrl) {
      this.loadTabInitialUrl(this.currentUrl);
      return;
    }

    if (this.restoreWebState()) {
      if (this.syncRestoredUrlOrLoad(this.currentUrl)) {
        this.updateNavigationState();
        this.loading = false;
        this.progress = 100;
        this.prepareShortcut(this.currentUrl);
        return;
      }
    }

    this.loadTabInitialUrl(this.currentUrl);
  }

  private showBookmarkHome(): void {
    this.persistWebState();
    if (!this.canShowBookmarkHome()) {
      this.onOpenBookmarkHome();
      return;
    }
    this.bookmarkHomeVisible = true;
    this.loading = false;
    this.progress = 100;
    this.canGoBack = false;
    this.canGoForward = false;
    this.toolbarHidden = false;
    this.webError = this.emptyWebError();
    this.resetPullRefresh();
    this.rememberBookmarkHomeState();
    this.loadBookmarks();
  }

  private openHomeTab(): void {
    this.onOpenHomeInstance();
  }

  private loadBookmarks(onComplete: () => void = () => {}): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.bookmarksLoading = true;
    loadWebBookmarks(context, true).then((bookmarks: WebBookmarkEntry[]) => {
      this.bookmarks = bookmarks;
      this.bookmarksLoading = false;
      this.ensureBookmarkIcons(context, bookmarks);
      onComplete();
    }).catch((err: BusinessError) => {
      this.bookmarksLoading = false;
      this.showNotice('加载书签栏失败：' + this.formatError(err));
      onComplete();
    });
  }

  private openBookmark(bookmark: WebBookmarkEntry): void {
    this.onOpenBookmarkInstance(bookmark);
  }

  private hasBookmarkUrl(bookmarks: WebBookmarkEntry[], url: string): boolean {
    const normalized = this.normalizeUrl(url);
    for (let index = 0; index < bookmarks.length; index++) {
      if (this.normalizeUrl(bookmarks[index].url) === normalized) {
        return true;
      }
    }
    return false;
  }

  private bookmarkedUrls(): string[] {
    const urls: string[] = [];
    for (let index = 0; index < this.bookmarks.length; index++) {
      urls.push(this.normalizeUrl(this.bookmarks[index].url));
    }
    return urls;
  }

  private bookmarkIconSource(url: string): ResourceStr {
    const context = getContext(this) as common.UIAbilityContext;
    const source = new WebShortcutIconService(context).foregroundIconFileSource(this.normalizeUrl(url));
    if (source.length > 0) {
      return source;
    }
    return $r('app.media.ic_browser_shortcut');
  }

  private bookmarkIconFileSource(url: string): string {
    const context = getContext(this) as common.UIAbilityContext;
    return new WebShortcutIconService(context).foregroundIconFileSource(this.normalizeUrl(url));
  }

  private ensureBookmarkIcons(context: common.UIAbilityContext, bookmarks: WebBookmarkEntry[]): void {
    const iconService = new WebShortcutIconService(context);
    for (let index = 0; index < bookmarks.length; index++) {
      const bookmark = bookmarks[index];
      const normalized = this.normalizeUrl(bookmark.url);
      if (iconService.foregroundIconFileSource(normalized).length > 0) {
        continue;
      }
      this.prepareShortcutIcons(context, normalized, true).then(() => {
        this.bookmarks = this.bookmarks.slice();
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'ensure bookmark icon failed: %{public}s', this.formatError(err));
      });
    }
  }

  private createDesktopShortcutFromBookmark(bookmark: WebBookmarkEntry): void {
    if (this.bookmarkDropBusy) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    this.bookmarkDropBusy = true;
    this.prepareShortcutIcons(context, bookmark.url, true).then(() => {
      this.requestPinShortcut(context, bookmark.url, bookmark.title, bookmark.id);
      this.bookmarkDropBusy = false;
    }).catch((err: BusinessError) => {
      this.bookmarkDropBusy = false;
      this.showNotice('创建桌面快捷方式失败：' + this.formatError(err));
    });
  }

  private confirmDeleteBookmark(bookmark: WebBookmarkEntry): void {
    if (this.bookmarkDropBusy || this.deleteBookmarkConfirmBusy) {
      return;
    }
    this.deleteBookmarkConfirmId = bookmark.id;
    this.deleteBookmarkConfirmUrl = bookmark.url;
    this.deleteBookmarkConfirmTitle = bookmark.title;
    this.deleteBookmarkConfirmIcon = this.bookmarkIconFileSource(bookmark.url);
    this.deleteBookmarkConfirmBusy = false;
    this.deleteBookmarkConfirmVisible = true;
  }

  private hideDeleteBookmarkConfirm(): void {
    this.deleteBookmarkConfirmVisible = false;
    this.deleteBookmarkConfirmBusy = false;
    this.deleteBookmarkConfirmId = '';
    this.deleteBookmarkConfirmUrl = '';
    this.deleteBookmarkConfirmTitle = '';
    this.deleteBookmarkConfirmIcon = '';
  }

  private submitDeleteBookmarkConfirm(): void {
    if (this.deleteBookmarkConfirmBusy || this.deleteBookmarkConfirmUrl.length === 0) {
      return;
    }
    const bookmark: WebBookmarkEntry = {
      id: this.deleteBookmarkConfirmId,
      url: this.deleteBookmarkConfirmUrl,
      title: this.deleteBookmarkConfirmTitle,
      updatedAt: 0
    };
    this.deleteBookmarkConfirmBusy = true;
    this.deleteBookmark(bookmark);
  }

  private deleteBookmark(bookmark: WebBookmarkEntry): void {
    if (this.bookmarkDropBusy) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    this.bookmarkDropBusy = true;
    deleteWebBookmark(context, bookmark.id, bookmark.url).then(() => {
      this.bookmarkDropBusy = false;
      this.clearNotice();
      this.hideDeleteBookmarkConfirm();
      this.loadBookmarks();
      this.onBookmarkDeleted(bookmark);
      this.onBookmarksChanged();
    }).catch((err: BusinessError) => {
      this.bookmarkDropBusy = false;
      this.deleteBookmarkConfirmBusy = false;
      this.showNotice('删除书签失败：' + this.formatError(err));
    });
  }

  private isBookmarkHomeUrl(url: string): boolean {
    return url.trim() === WEB_BOOKMARKS_HOME_URL;
  }

  private canShowBookmarkHome(): boolean {
    return this.allowBookmarkHome && this.isHomeInstance && this.instanceKind === 'home';
  }

  private syncRestoredUrlOrLoad(fallbackUrl: string): boolean {
    try {
      const restoredUrl = this.controller.getUrl();
      if (restoredUrl.length > 0) {
        if (this.commitCurrentUrl(restoredUrl)) {
          this.explicitLoadErrorUrl = '';
          return true;
        }
        this.loadTabInitialUrl(fallbackUrl);
        return false;
      }
    } catch (err) {
    }

    this.commitCurrentUrl(fallbackUrl);
    this.explicitLoadErrorUrl = '';
    return true;
  }

  private restoreWebState(): boolean {
    if (!this.hasValidWebStateOwner(this.webStateKey())) {
      return false;
    }
    const state = this.readWebState();
    if (state.byteLength <= 0) {
      return false;
    }

    try {
      this.restoringWebState = true;
      this.controller.restoreWebState(state);
      this.clearNotice();
      hilog.info(DOMAIN, TAG, 'restored web state key=%{public}s bytes=%{public}d',
        this.webStateKey(),
        state.byteLength
      );
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'restore web state failed: %{public}s', error.message ?? JSON.stringify(err));
      return false;
    } finally {
      this.restoringWebState = false;
    }
  }

  private persistWebState(): void {
    if (!this.controllerAttached || this.restoringWebState || this.bookmarkHomeVisible) {
      return;
    }
    if (!this.isBrowserStateUrl(this.currentUrl)) {
      return;
    }

    try {
      const controllerUrl = this.controller.getUrl();
      if (controllerUrl.length > 0 && !this.isBrowserStateUrl(controllerUrl)) {
        hilog.warn(DOMAIN, TAG, 'skip web state for non-browser controller url: %{public}s', controllerUrl);
        return;
      }
    } catch (err) {
    }

    try {
      this.webStateStore().writeControllerWebState(this.webStateKey(), this.controller);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'persist web state failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private readWebState(): Uint8Array {
    return this.webStateStore().readWebState(this.webStateKey());
  }

  private readTabStateMeta(tabId: string, fallbackUrl: string): WebTabState {
    return this.webStateStore().readTabStateMeta(tabId, fallbackUrl);
  }

  private readLaunchTabStateMeta(tabId: string, fallbackUrl: string): WebTabState {
    const state = this.readTabStateMeta(tabId, fallbackUrl);
    const id = this.safeFileSegment(tabId);
    if (id.length === 0) {
      return state;
    }
    if (id === WEB_BOOKMARKS_HOME_TAB_ID) {
      return {
        id: id,
        url: WEB_BOOKMARKS_HOME_URL,
        backCount: 0
      };
    }
    if (this.isBookmarkHomeUrl(state.url)) {
      return {
        id: id,
        url: this.isBookmarkHomeUrl(fallbackUrl) ? DEFAULT_WEB_HOME_URL : fallbackUrl,
        backCount: 0
      };
    }
    if (this.isBookmarkHomeUrl(fallbackUrl)) {
      return state;
    }
    if (this.hasValidWebStateOwner(id)) {
      return state;
    }
    return {
      id: id,
      url: fallbackUrl,
      backCount: 0
    };
  }

  private persistTabState(state: WebTabState): void {
    this.webStateStore().persistTabState(state);
  }

  private hasValidWebStateOwner(tabId: string): boolean {
    return this.webStateStore().hasValidWebStateOwner(tabId);
  }

  private truncateWebState(tabId: string): void {
    this.webStateStore().truncateWebState(tabId);
  }

  private webStateStore(): WebBrowserStateStore {
    return new WebBrowserStateStore(getContext(this) as common.UIAbilityContext);
  }

  private webStateKey(): string {
    const id = this.currentWebStateTabId();
    if (id.length > 0) {
      return id;
    }
    return WebShortcutIconService.shortcutId(this.currentUrl);
  }

  private safeFileSegment(value: string): string {
    return WebBrowserStateStore.safeFileSegment(value);
  }

  private pullRefreshState(surfaceKey: string): PullRefreshState {
    const surface = this.webSurfaceByKey(surfaceKey.length > 0 ? surfaceKey : this.webSurfaceKey);
    if (surface !== undefined) {
      return surface.pullRefresh;
    }
    return WebPullRefresh.emptyState();
  }

  private activePullRefreshState(): PullRefreshState {
    if (this.pullRefreshRevision < 0) {
      return WebPullRefresh.emptyState();
    }
    return this.pullRefreshState(this.webSurfaceKey);
  }

  private bumpPullRefreshRevision(): void {
    this.pullRefreshRevision++;
  }

  private activePullRefreshVisible(): boolean {
    return WebPullRefresh.shouldShowIndicator(this.activePullRefreshState());
  }

  private activePullRefreshRefreshing(): boolean {
    return WebPullRefresh.isRefreshing(this.activePullRefreshState());
  }

  private activePullRefreshRotation(): number {
    return WebPullRefresh.activeRotation(this.activePullRefreshState());
  }

  private activePullRefreshIndicatorOffset(): number {
    return WebPullRefresh.indicatorOffset(this.activePullRefreshState());
  }

  private activePullRefreshDistance(): number {
    return WebPullRefresh.distance(this.activePullRefreshState());
  }

  private updatePullRefresh(surfaceKey: string, deltaFromStart: number): void {
    WebPullRefresh.update(this.pullRefreshState(surfaceKey), deltaFromStart);
    this.bumpPullRefreshRevision();
  }

  private resetPullRefresh(surfaceKey: string = ''): void {
    WebPullRefresh.reset(this.pullRefreshState(surfaceKey));
    this.bumpPullRefreshRevision();
  }

  private cancelPullRefresh(surfaceKey: string = ''): void {
    WebPullRefresh.cancel(this.pullRefreshState(surfaceKey), (): void => {
      this.bumpPullRefreshRevision();
    });
  }

  private resetPullRefreshIfIdle(surfaceKey: string = ''): void {
    const pullRefresh = this.pullRefreshState(surfaceKey);
    if (pullRefresh.refreshing) {
      return;
    }
    WebPullRefresh.reset(pullRefresh);
    this.bumpPullRefreshRevision();
  }

  private endPullRefresh(surfaceKey: string = ''): void {
    WebPullRefresh.end(this.pullRefreshState(surfaceKey), (): void => {
      this.bumpPullRefreshRevision();
    });
  }

  private startPullRefreshSpin(surfaceKey: string): void {
    WebPullRefresh.startSpin(this.pullRefreshState(surfaceKey), (): void => {
      this.bumpPullRefreshRevision();
    });
  }

  private stopPullRefreshSpin(surfaceKey: string = ''): void {
    WebPullRefresh.stopSpin(this.pullRefreshState(surfaceKey), (): void => {
      this.bumpPullRefreshRevision();
    });
  }

  private stopAllPullRefreshSpin(): void {
    const surfaces = this.webSurfaceRegistry.entries();
    for (let index = 0; index < surfaces.length; index++) {
      this.stopPullRefreshSpin(surfaces[index].surfaceKey);
    }
  }

  private currentScrollY(surfaceKey: string): number {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface !== undefined) {
      return surface.scrollY;
    }
    return Number.MAX_SAFE_INTEGER;
  }

  private isBrowserStateUrl(url: string): boolean {
    const value = url.trim();
    if (this.isBookmarkHomeUrl(value)) {
      return false;
    }
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('file://') ||
      value.startsWith('resource://') || value.startsWith('about:');
  }

  private isBrowserShortcutUrl(url: string): boolean {
    const value = url.trim();
    return value.startsWith('http://') || value.startsWith('https://');
  }

  private shouldShowWebErrorFor(url: string): boolean {
    if (this.explicitLoadErrorUrl.length === 0) {
      return false;
    }
    if (url.length === 0) {
      return true;
    }
    return this.normalizeUrl(url) === this.explicitLoadErrorUrl;
  }

  private normalizeUrl(value: string): string {
    const input = value.trim();
    if (input.length === 0) {
      return DEFAULT_WEB_HOME_URL;
    }
    if (input.startsWith('http://') || input.startsWith('https://') ||
      input.startsWith('file://') || input.startsWith('resource://') || input.startsWith('about:')) {
      return input;
    }
    const schemeIndex = input.indexOf(':');
    if (schemeIndex > 0 && input.indexOf('/') >= schemeIndex) {
      return input;
    }
    if (input.indexOf(' ') >= 0 || input.indexOf('.') < 0) {
      return 'https://www.bing.com/search?q=' + encodeURIComponent(input);
    }
    return 'https://' + input;
  }


  private formatError(err: Object): string {
    const error = err as BusinessError;
    if (error.code !== undefined) {
      const message = error.message ?? '';
      if (message.length > 0) {
        return 'code=' + String(error.code) + ', message=' + message;
      }
      return 'code=' + String(error.code);
    }
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(err);
  }
}
