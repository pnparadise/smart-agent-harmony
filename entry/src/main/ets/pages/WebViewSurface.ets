import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import {
  WEB_NATIVE_PULL_REFRESH_DISTANCE,
  WEB_NATIVE_PULL_REFRESH_MAX_DISTANCE
} from './WebPullRefresh';

const DOMAIN = 0x0001;
const TAG = 'WebViewSurface';
const NATIVE_REFRESH_SETTLE_FALLBACK_MS = 240;

export interface WebViewSurfacePageEvent {
  url: string;
}

export interface WebViewSurfaceNavigationEvent {
  url: string;
  isMainFrame: boolean;
  isSameDocument: boolean;
}

export interface WebViewSurfaceProgressEvent {
  newProgress: number;
}

export interface WebViewSurfaceTitleEvent {
  title: string;
}

export interface WebViewSurfaceFaviconEvent {
  favicon: image.PixelMap;
}

export interface WebViewSurfaceLoadErrorEvent {
  url: string;
  isMainFrame: boolean;
  code: number;
  message: string;
  kind: string;
}

export interface WebViewSurfaceFullScreenExitHandler {
  exitFullScreen(): void;
}

export interface WebViewSurfaceFullScreenEvent {
  handler: WebViewSurfaceFullScreenExitHandler;
  videoWidth: number;
  videoHeight: number;
}

export interface WebViewSurfaceExternalNavigationEvent {
  url: string;
}

export interface WebViewSurfaceScrollEvent {
  xOffset: number;
  yOffset: number;
}

class WebViewSurfaceFullScreenExitHandlerImpl implements WebViewSurfaceFullScreenExitHandler {
  private handler: FullScreenExitHandler;

  constructor(handler: FullScreenExitHandler) {
    this.handler = handler;
  }

  exitFullScreen(): void {
    this.handler.exitFullScreen();
  }
}

class WebViewSurfaceFullScreenEventImpl implements WebViewSurfaceFullScreenEvent {
  handler: WebViewSurfaceFullScreenExitHandler;
  videoWidth: number;
  videoHeight: number;

  constructor(handler: WebViewSurfaceFullScreenExitHandler, videoWidth: number, videoHeight: number) {
    this.handler = handler;
    this.videoWidth = videoWidth;
    this.videoHeight = videoHeight;
  }
}

class WebViewSurfaceNativeMediaPlayerConfig implements NativeMediaPlayerConfig {
  enable: boolean = true;
  shouldOverlay: boolean = true;
}

@Component
export struct WebViewSurface {
  @Prop src: string = '';
  @Prop pullRefreshEnabled: boolean = false;
  @Prop @Watch('onPullRefreshRefreshingChanged') pullRefreshRefreshing: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();
  onControllerAttached: () => void = () => {};
  onPageBegin: (event: WebViewSurfacePageEvent) => void = () => {};
  onNavigationCommitted: (event: WebViewSurfaceNavigationEvent) => void = () => {};
  onProgressChange: (event: WebViewSurfaceProgressEvent) => void = () => {};
  onPageVisible: () => void = () => {};
  onPageEnd: (event: WebViewSurfacePageEvent) => void = () => {};
  onTitleReceive: (event: WebViewSurfaceTitleEvent) => void = () => {};
  onFaviconReceived: (event: WebViewSurfaceFaviconEvent) => void = () => {};
  onTrackerBlocked: (host: string) => void = () => {};
  onScroll: (event: WebViewSurfaceScrollEvent) => void = () => {};
  onPullRefreshOffsetChange: (offset: number) => void = () => {};
  onPullRefreshing: () => boolean = () => false;
  onExternalNavigation: (event: WebViewSurfaceExternalNavigationEvent) => void = () => {};
  onFullScreenEnter: (event: WebViewSurfaceFullScreenEvent) => void = () => {};
  onFullScreenExit: () => void = () => {};
  onLoadError: (event: WebViewSurfaceLoadErrorEvent) => void = () => {};
  @State private nativeRefreshing: boolean = false;
  @State private nativeRefreshSettling: boolean = false;
  private suppressRefreshSettleOffset: boolean = false;
  private nativeRefreshSettleTimer: number = -1;
  private popupController: webview.WebviewController = new webview.WebviewController('web_popup_initial');
  @State private popupVisible: boolean = false;
  private popupOrigin: string = '';
  private popupSerial: number = 0;
  private primaryOrigin: string = '';

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Refresh({ refreshing: $$this.nativeRefreshing, builder: this.buildRefreshPlaceholder() }) {
      Web({ src: this.src, controller: this.controller })
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .javaScriptAccess(true)
        .multiWindowAccess(true)
        .allowWindowOpenMethod(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .cacheMode(CacheMode.Default)
        .mixedMode(MixedMode.Compatible)
        .metaViewport(true)
        .overScrollMode(OverScrollMode.NEVER)
        .nestedScroll({
          scrollUp: NestedScrollMode.SELF_FIRST,
          scrollDown: NestedScrollMode.SELF_FIRST
        })
        .enableNativeMediaPlayer(new WebViewSurfaceNativeMediaPlayerConfig())
        .onControllerAttached(() => {
          hilog.info(DOMAIN, TAG, 'controller attached src=%{public}s', this.src);
          this.debug('controller attached src=' + this.debugUrl(this.src));
          this.onControllerAttached();
        })
        .onWindowNew((event) => {
          if (!event || !event.handler) {
            return;
          }
          try {
            const parentUrl = this.currentUrl();
            this.popupController = this.createPopupController(parentUrl);
            event.handler.setWebController(this.popupController);
            this.popupVisible = true;
            hilog.info(DOMAIN, TAG, 'open web popup origin=%{public}s src=%{public}s',
              this.popupOrigin, this.src);
            this.debug('windowNew parent=' + this.popupOrigin + ' current=' +
              this.debugUrl(parentUrl) + ' src=' + this.debugUrl(this.src));
          } catch (err) {
            this.popupVisible = false;
            hilog.warn(DOMAIN, TAG, 'open web popup failed: %{public}s',
              this.formatError(err));
            this.debug('windowNew failed=' + this.formatError(err));
          }
        })
        .onWindowNewExt((event) => {
          if (!event || !event.handler) {
            return;
          }
          try {
            const parentUrl = this.currentUrl();
            this.popupController = this.createPopupController(parentUrl);
            event.handler.setWebController(this.popupController);
            this.popupVisible = true;
            hilog.info(DOMAIN, TAG, 'open extended web popup origin=%{public}s src=%{public}s',
              this.popupOrigin, this.src);
            this.debug('windowNewExt parent=' + this.popupOrigin + ' current=' +
              this.debugUrl(parentUrl) + ' src=' + this.debugUrl(this.src));
          } catch (err) {
            this.popupVisible = false;
            hilog.warn(DOMAIN, TAG, 'open extended web popup failed: %{public}s',
              this.formatError(err));
            this.debug('windowNewExt failed=' + this.formatError(err));
          }
        })
        .onActivateContent(() => {
          if (this.popupControllerAttached()) {
            this.popupVisible = true;
            this.debug('activate popup url=' + this.debugUrl(this.popupCurrentUrl()));
          }
        })
        .onPageBegin((event) => {
          const pageUrl = event && event.url.length > 0 ? event.url : '';
          this.debug('main pageBegin url=' + this.debugUrl(pageUrl));
          this.rememberPrimaryOrigin(pageUrl);
          this.onPageBegin({ url: pageUrl });
        })
        .onNavigationEntryCommitted((event) => {
          if (!event) {
            return;
          }
          this.debug('main navigationCommitted url=' + this.debugUrl(event.url) +
            ' main=' + String(event.isMainFrame) + ' same=' + String(event.isSameDocument));
          this.onNavigationCommitted({
            url: event.url,
            isMainFrame: event.isMainFrame,
            isSameDocument: event.isSameDocument
          });
        })
        .onRefreshAccessedHistory((event) => {
          if (!event || event.url.length === 0 || event.isMainFrame === false) {
            return;
          }
          this.onNavigationCommitted({
            url: event.url,
            isMainFrame: true,
            isSameDocument: false
          });
        })
        .onProgressChange((event) => {
          this.onProgressChange({ newProgress: event ? event.newProgress : 0 });
        })
        .onPageVisible(() => {
          this.debug('main pageVisible url=' + this.debugUrl(this.currentUrl()));
          this.onPageVisible();
        })
        .onPageEnd((event) => {
          const pageUrl = event && event.url.length > 0 ? event.url : '';
          this.debug('main pageEnd url=' + this.debugUrl(pageUrl) +
            ' controller=' + this.debugUrl(this.currentUrl()));
          this.onPageEnd({ url: pageUrl });
        })
        .onTitleReceive((event) => {
          this.onTitleReceive({ title: event ? event.title : '' });
        })
        .onFaviconReceived((event) => {
          if (event) {
            this.onFaviconReceived({ favicon: event.favicon });
          }
        })
        .onHttpErrorReceive((event) => {
          if (!event || !event.request.isMainFrame()) {
            return;
          }
          const responseCode = event.response.getResponseCode();
          if (responseCode < 400) {
            return;
          }
          this.onLoadError({
            url: event.request.getRequestUrl(),
            isMainFrame: true,
            code: responseCode,
            message: event.response.getReasonMessage(),
            kind: 'http'
          });
        })
        .onErrorReceive((event) => {
          if (!event || !event.request.isMainFrame()) {
            return;
          }
          this.onLoadError({
            url: event.request.getRequestUrl(),
            isMainFrame: true,
            code: event.error.getErrorCode(),
            message: event.error.getErrorInfo(),
            kind: 'network'
          });
        })
        .onSslErrorEventReceive((event) => {
          if (!event) {
            return;
          }
          try {
            event.handler.handleCancel();
          } catch (err) {
          }
          this.onLoadError({
            url: this.currentUrl(),
            isMainFrame: true,
            code: 0,
            message: 'SSL error',
            kind: 'ssl'
          });
        })
        .onRenderProcessNotResponding((event) => {
          this.onLoadError({
            url: this.currentUrl(),
            isMainFrame: true,
            code: 0,
            message: event ? ('render process not responding pid=' + String(event.pid ?? 0)) :
              'render process not responding',
            kind: 'render-process'
          });
        })
        .onLoadIntercept((event) => {
          if (!event || !event.data || !event.data.isMainFrame()) {
            return false;
          }
          const requestUrl = event.data.getRequestUrl();
          if (requestUrl.startsWith('http://') || requestUrl.startsWith('https://') ||
            requestUrl.startsWith('file://') || requestUrl.startsWith('resource://') || requestUrl.startsWith('about:')) {
            return false;
          }
          hilog.info(DOMAIN, TAG, 'intercept external navigation by load intercept url=%{public}s', requestUrl);
          this.onExternalNavigation({ url: requestUrl });
          return true;
        })
        .onOverrideUrlLoading((event: WebResourceRequest) => {
          if (!event) {
            return false;
          }
          const requestUrl = event.getRequestUrl();
          if (requestUrl.startsWith('http://') || requestUrl.startsWith('https://') ||
            requestUrl.startsWith('file://') || requestUrl.startsWith('resource://') || requestUrl.startsWith('about:')) {
            return false;
          }
          hilog.info(DOMAIN, TAG, 'intercept external scheme navigation url=%{public}s', requestUrl);
          this.onExternalNavigation({ url: requestUrl });
          return true;
        })
        .onIntelligentTrackingPreventionResult((event) => {
          this.onTrackerBlocked(event ? event.host ?? '' : '');
        })
        .onScroll((event) => {
          this.onScroll({
            xOffset: event ? event.xOffset : 0,
            yOffset: event ? event.yOffset : 0
          });
        })
        .onFullScreenEnter((event) => {
          hilog.info(DOMAIN, TAG, 'web fullscreen enter video=%{public}dx%{public}d',
            event.videoWidth ?? 0, event.videoHeight ?? 0);
          this.onFullScreenEnter(new WebViewSurfaceFullScreenEventImpl(
            new WebViewSurfaceFullScreenExitHandlerImpl(event.handler),
            event.videoWidth ?? 0,
            event.videoHeight ?? 0
          ));
        })
        .onFullScreenExit(() => {
          hilog.info(DOMAIN, TAG, 'web fullscreen exit');
          this.onFullScreenExit();
        })
      }
        .width('100%')
        .height('100%')
        .pullToRefresh(this.nativePullRefreshEnabled())
        .pullDownRatio(this.nativePullRefreshEnabled() ? 1 : 0)
        .refreshOffset(WEB_NATIVE_PULL_REFRESH_DISTANCE)
        .maxPullDownDistance(WEB_NATIVE_PULL_REFRESH_MAX_DISTANCE)
        .onOffsetChange((offset: number) => {
          if (this.suppressRefreshSettleOffset) {
            if (offset <= 0) {
              this.completeNativeRefreshSettle();
              this.onPullRefreshOffsetChange(0);
            }
            return;
          }
          this.onPullRefreshOffsetChange(offset);
        })
        .onRefreshing(() => {
          // The custom browser indicator owns the long-running refresh state. Keep
          // the native Refresh component only for recognizing the pull gesture so
          // it does not retain the WebView's vertical gesture stream.
          this.beginNativeRefreshSettle();
          this.onPullRefreshing();
          this.nativeRefreshing = false;
        })
      if (this.popupVisible) {
        Web({ src: '', controller: this.popupController })
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(2)
          .javaScriptAccess(true)
          .multiWindowAccess(true)
          .allowWindowOpenMethod(true)
          .domStorageAccess(true)
          .databaseAccess(true)
          .onlineImageAccess(true)
          .imageAccess(true)
          .cacheMode(CacheMode.Default)
          .mixedMode(MixedMode.Compatible)
          .metaViewport(true)
          .overScrollMode(OverScrollMode.NEVER)
          .onWindowNew((event) => {
            if (!event || !event.handler) {
              return;
            }
            try {
              event.handler.setWebController(this.popupController);
            } catch (err) {
              hilog.warn(DOMAIN, TAG, 'reuse web popup controller failed: %{public}s',
                this.formatError(err));
            }
          })
          .onWindowNewExt((event) => {
            if (!event || !event.handler) {
              return;
            }
            try {
              event.handler.setWebController(this.popupController);
              this.popupVisible = true;
              this.debug('popup windowNewExt reuse controller url=' +
                this.debugUrl(this.popupCurrentUrl()));
            } catch (err) {
              hilog.warn(DOMAIN, TAG, 'reuse extended web popup controller failed: %{public}s',
                this.formatError(err));
            }
          })
          .onActivateContent(() => {
            this.popupVisible = true;
            this.debug('popup activate content url=' + this.debugUrl(this.popupCurrentUrl()));
          })
          .onPageBegin((event) => {
            this.debug('popup pageBegin url=' + this.debugUrl(event ? event.url : ''));
            this.handlePopupNavigation(event ? event.url : '');
          })
          .onPageEnd((event) => {
            this.debug('popup pageEnd url=' + this.debugUrl(event ? event.url : '') +
              ' controller=' + this.debugUrl(this.popupCurrentUrl()));
            this.handlePopupNavigation(event ? event.url : '');
          })
          .onPageVisible(() => {
            this.debug('popup pageVisible url=' + this.debugUrl(this.popupCurrentUrl()));
            this.handlePopupNavigation(this.popupCurrentUrl());
          })
          .onWindowExit(() => {
            this.debug('popup windowExit url=' + this.debugUrl(this.popupCurrentUrl()));
            this.popupVisible = false;
          })
      }
    }
      .width('100%')
      .height('100%')
  }

  aboutToAppear(): void {
    this.stopNativeRefreshSettleTimer();
    this.suppressRefreshSettleOffset = false;
    this.nativeRefreshSettling = false;
    this.nativeRefreshing = false;
  }

  aboutToDisappear(): void {
    this.stopNativeRefreshSettleTimer();
    this.popupVisible = false;
  }

  @Builder
  private buildRefreshPlaceholder() {
    Blank()
      .width('100%')
      .height(0)
  }

  private onPullRefreshRefreshingChanged(): void {
    if (!this.pullRefreshRefreshing) {
      this.beginNativeRefreshSettle();
    }
  }

  private nativePullRefreshEnabled(): boolean {
    return this.pullRefreshEnabled && !this.pullRefreshRefreshing && !this.nativeRefreshSettling;
  }

  private beginNativeRefreshSettle(): void {
    this.suppressRefreshSettleOffset = true;
    this.nativeRefreshSettling = true;
    this.stopNativeRefreshSettleTimer();
    this.nativeRefreshSettleTimer = setTimeout(() => {
      this.nativeRefreshSettleTimer = -1;
      this.completeNativeRefreshSettle();
    }, NATIVE_REFRESH_SETTLE_FALLBACK_MS);
  }

  private completeNativeRefreshSettle(): void {
    this.stopNativeRefreshSettleTimer();
    this.suppressRefreshSettleOffset = false;
    this.nativeRefreshSettling = false;
  }

  private stopNativeRefreshSettleTimer(): void {
    if (this.nativeRefreshSettleTimer >= 0) {
      clearTimeout(this.nativeRefreshSettleTimer);
      this.nativeRefreshSettleTimer = -1;
    }
  }

  loadUrl(url: string): boolean {
    if (url.length === 0) {
      return false;
    }

    try {
      this.controller.loadUrl(url);
      return true;
    } catch (err) {
      this.onLoadError({
        url: url,
        isMainFrame: true,
        code: 0,
        message: this.formatError(err),
        kind: 'controller'
      });
      return false;
    }
  }

  refresh(): boolean {
    try {
      this.controller.refresh();
      return true;
    } catch (err) {
      this.onLoadError({
        url: this.currentUrl(),
        isMainFrame: true,
        code: 0,
        message: this.formatError(err),
        kind: 'controller'
      });
      return false;
    }
  }

  canGoBack(): boolean {
    try {
      return this.controller.accessBackward();
    } catch (err) {
      return false;
    }
  }

  goBack(): boolean {
    try {
      if (!this.controller.accessBackward()) {
        return false;
      }
      this.controller.backward();
      return true;
    } catch (err) {
      this.onLoadError({
        url: this.currentUrl(),
        isMainFrame: true,
        code: 0,
        message: this.formatError(err),
        kind: 'controller'
      });
      return false;
    }
  }

  currentUrl(): string {
    try {
      return this.controller.getUrl();
    } catch (err) {
      return '';
    }
  }

  private handlePopupNavigation(value: string): void {
    const popupUrl = value.trim();
    if (popupUrl.length === 0 || popupUrl.toLowerCase() === 'about:blank' || !this.popupVisible) {
      return;
    }
    const origin = this.webOrigin(popupUrl);
    this.debug('popup evaluate url=' + this.debugUrl(popupUrl) + ' origin=' + origin +
      ' parent=' + this.popupOrigin);
    if (origin.length === 0 || this.popupOrigin.length === 0 || origin !== this.popupOrigin) {
      return;
    }
    this.popupVisible = false;
    try {
      this.controller.loadUrl(popupUrl);
      hilog.info(DOMAIN, TAG, 'route same-origin popup navigation to primary surface url=%{public}s', popupUrl);
      this.debug('same-origin popup navigation routed to main url=' + this.debugUrl(popupUrl));
    } catch (err) {
      this.onLoadError({
        url: popupUrl,
        isMainFrame: true,
        code: 0,
        message: this.formatError(err),
        kind: 'popup-controller'
      });
      this.debug('popup callback route failed=' + this.formatError(err));
    }
  }

  private createPopupController(parentUrl: string): webview.WebviewController {
    const currentOrigin = this.webOrigin(parentUrl);
    const sourceOrigin = this.webOrigin(this.src);
    this.popupOrigin = currentOrigin.length > 0 ? currentOrigin : sourceOrigin;
    if (this.popupOrigin.length === 0) {
      this.popupOrigin = this.primaryOrigin;
    }
    return new webview.WebviewController('web_popup_' + String(++this.popupSerial));
  }

  private popupControllerAttached(): boolean {
    return this.popupCurrentUrl().trim().length > 0;
  }

  private webOrigin(value: string): string {
    const match = value.trim().match(/^https?:\/\/[^/]+/i);
    if (match === null) {
      return '';
    }
    return match[0].toLowerCase().replace(':443', '').replace(':80', '');
  }

  private rememberPrimaryOrigin(value: string): void {
    const origin = this.webOrigin(value);
    if (origin.length > 0 && !this.popupVisible) {
      this.primaryOrigin = origin;
    }
  }

  private popupCurrentUrl(): string {
    try {
      return this.popupController.getUrl();
    } catch (err) {
      return '';
    }
  }

  private debug(message: string): void {
    console.info('[WebViewSurface] ' + message);
  }

  private debugUrl(value: string): string {
    const input = value.trim();
    const queryIndex = input.indexOf('?');
    if (queryIndex < 0) {
      return input;
    }
    return input.substring(0, queryIndex) + '?<query>';
  }

  private formatError(err: Object): string {
    const error = err as BusinessError;
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(err);
  }
}
