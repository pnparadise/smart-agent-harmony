import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';

const DOMAIN = 0x0001;
const TAG = 'WebViewSurface';

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

export interface WebViewSurfacePullGestureEvent {
  offsetY: number;
}

export interface WebViewSurfaceExternalNavigationEvent {
  url: string;
}

export interface WebViewSurfaceScrollEvent {
  xOffset: number;
  yOffset: number;
}

export interface WebViewSurfaceOverScrollEvent {
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
  onOverScroll: (event: WebViewSurfaceOverScrollEvent) => void = () => {};
  onPullGestureStart: () => void = () => {};
  onPullGestureUpdate: (event: WebViewSurfacePullGestureEvent) => void = () => {};
  onPullGestureEnd: () => void = () => {};
  onExternalNavigation: (event: WebViewSurfaceExternalNavigationEvent) => void = () => {};
  onFullScreenEnter: (event: WebViewSurfaceFullScreenEvent) => void = () => {};
  onFullScreenExit: () => void = () => {};
  onLoadError: (event: WebViewSurfaceLoadErrorEvent) => void = () => {};
  private controllerAttached: boolean = false;

  build() {
    Web({ src: this.src, controller: this.controller })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .databaseAccess(true)
      .onlineImageAccess(true)
      .imageAccess(true)
      .cacheMode(CacheMode.Default)
      .mixedMode(MixedMode.Compatible)
      .metaViewport(true)
      .overScrollMode(OverScrollMode.ALWAYS)
      .enableNativeMediaPlayer(new WebViewSurfaceNativeMediaPlayerConfig())
      .onControllerAttached(() => {
        this.controllerAttached = true;
        hilog.info(DOMAIN, TAG, 'controller attached src=%{public}s', this.src);
        this.onControllerAttached();
      })
      .onPageBegin((event) => {
        this.onPageBegin({ url: event && event.url.length > 0 ? event.url : '' });
      })
      .onNavigationEntryCommitted((event) => {
        if (!event) {
          return;
        }
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
        this.onPageVisible();
      })
      .onPageEnd((event) => {
        this.onPageEnd({ url: event && event.url.length > 0 ? event.url : '' });
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
          message: event ? ('render process not responding pid=' + String(event.pid ?? 0)) : 'render process not responding',
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
      .onOverScroll((event) => {
        this.onOverScroll({
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
      .parallelGesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 1 })
          .onActionStart(() => {
            this.onPullGestureStart();
          })
          .onActionUpdate((event: GestureEvent) => {
            this.onPullGestureUpdate({ offsetY: event.offsetY });
          })
          .onActionEnd(() => {
            this.onPullGestureEnd();
          })
          .onActionCancel(() => {
            this.onPullGestureEnd();
          })
      )
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

  private formatError(err: Object): string {
    const error = err as BusinessError;
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(err);
  }
}
