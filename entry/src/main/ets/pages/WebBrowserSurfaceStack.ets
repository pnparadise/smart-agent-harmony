import { webview } from '@kit.ArkWeb';
import {
  WebViewSurfaceExternalNavigationEvent,
  WebViewSurface,
  WebViewSurfaceFullScreenEvent,
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

const FALLBACK_SURFACE_CONTROLLER: webview.WebviewController =
  new webview.WebviewController('web_surface_fallback');

@Component
export struct WebBrowserSurfaceStack {
  @Prop surfaceKeys: string[] = [];
  @Prop activeSurfaceKey: string = '';
  @Prop bookmarkHomeVisible: boolean = false;
  @Prop webFullScreen: boolean = false;

  srcFor: (surfaceKey: string) => string = () => '';
  controllerFor: (surfaceKey: string) => webview.WebviewController = () => FALLBACK_SURFACE_CONTROLLER;
  surfaceVisibleFor: (surfaceKey: string) => boolean = () => false;
  onControllerAttached: (surfaceKey: string) => void = () => {};
  onPageBegin: (surfaceKey: string, event: WebViewSurfacePageEvent) => void = () => {};
  onNavigationCommitted: (surfaceKey: string, event: WebViewSurfaceNavigationEvent) => void = () => {};
  onProgressChange: (surfaceKey: string, event: WebViewSurfaceProgressEvent) => void = () => {};
  onPageVisible: (surfaceKey: string) => void = () => {};
  onPageEnd: (surfaceKey: string, event: WebViewSurfacePageEvent) => void = () => {};
  onTitleReceive: (surfaceKey: string, event: WebViewSurfaceTitleEvent) => void = () => {};
  onFaviconReceived: (surfaceKey: string, event: WebViewSurfaceFaviconEvent) => void = () => {};
  onTrackerBlocked: (surfaceKey: string, host: string) => void = () => {};
  onScroll: (surfaceKey: string, event: WebViewSurfaceScrollEvent) => void = () => {};
  onOverScroll: (surfaceKey: string, event: WebViewSurfaceOverScrollEvent) => void = () => {};
  onPullGestureStart: (surfaceKey: string) => void = () => {};
  onPullGestureUpdate: (surfaceKey: string, event: WebViewSurfacePullGestureEvent) => void = () => {};
  onPullGestureEnd: (surfaceKey: string) => void = () => {};
  onExternalNavigation: (surfaceKey: string, event: WebViewSurfaceExternalNavigationEvent) => void = () => {};
  onFullScreenEnter: (surfaceKey: string, event: WebViewSurfaceFullScreenEvent) => void = () => {};
  onFullScreenExit: (surfaceKey: string) => void = () => {};
  onLoadError: (surfaceKey: string, event: WebViewSurfaceLoadErrorEvent) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.surfaceKeys, (surfaceKey: string) => {
        WebViewSurface({
          src: this.srcFor(surfaceKey),
          controller: this.controllerFor(surfaceKey),
          onControllerAttached: (): void => {
            this.onControllerAttached(surfaceKey);
          },
          onPageBegin: (event: WebViewSurfacePageEvent): void => {
            this.onPageBegin(surfaceKey, event);
          },
          onNavigationCommitted: (event: WebViewSurfaceNavigationEvent): void => {
            this.onNavigationCommitted(surfaceKey, event);
          },
          onProgressChange: (event: WebViewSurfaceProgressEvent): void => {
            this.onProgressChange(surfaceKey, event);
          },
          onPageVisible: (): void => {
            this.onPageVisible(surfaceKey);
          },
          onPageEnd: (event: WebViewSurfacePageEvent): void => {
            this.onPageEnd(surfaceKey, event);
          },
          onTitleReceive: (event: WebViewSurfaceTitleEvent): void => {
            this.onTitleReceive(surfaceKey, event);
          },
          onFaviconReceived: (event: WebViewSurfaceFaviconEvent): void => {
            this.onFaviconReceived(surfaceKey, event);
          },
          onTrackerBlocked: (host: string): void => {
            this.onTrackerBlocked(surfaceKey, host);
          },
          onScroll: (event: WebViewSurfaceScrollEvent): void => {
            this.onScroll(surfaceKey, event);
          },
          onOverScroll: (event: WebViewSurfaceOverScrollEvent): void => {
            this.onOverScroll(surfaceKey, event);
          },
          onPullGestureStart: (): void => {
            this.onPullGestureStart(surfaceKey);
          },
          onPullGestureUpdate: (event: WebViewSurfacePullGestureEvent): void => {
            this.onPullGestureUpdate(surfaceKey, event);
          },
          onPullGestureEnd: (): void => {
            this.onPullGestureEnd(surfaceKey);
          },
          onExternalNavigation: (event: WebViewSurfaceExternalNavigationEvent): void => {
            this.onExternalNavigation(surfaceKey, event);
          },
          onFullScreenEnter: (event: WebViewSurfaceFullScreenEvent): void => {
            this.onFullScreenEnter(surfaceKey, event);
          },
          onFullScreenExit: (): void => {
            this.onFullScreenExit(surfaceKey);
          },
          onLoadError: (event: WebViewSurfaceLoadErrorEvent): void => {
            this.onLoadError(surfaceKey, event);
          }
        })
          .width('100%')
          .height('100%')
          .visibility(this.surfaceVisibleFor(surfaceKey) ? Visibility.Visible : Visibility.Hidden)
          .zIndex(surfaceKey === this.activeSurfaceKey ? (this.webFullScreen ? 100 : 1) : 0)
      }, (surfaceKey: string) => surfaceKey)
    }
    .width('100%')
    .height('100%')
  }
}
