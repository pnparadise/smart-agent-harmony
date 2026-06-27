import { common, OpenLinkOptions, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { productViewManager } from '@kit.AppGalleryKit';
import { url } from '@kit.ArkTS';
import { PromptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { setWebVideoFullScreenWindow } from '../entryability/ImmersiveWindow';
import {
  DEFAULT_WEB_HOME_URL,
  deleteWebBookmark,
  deleteWebHistoryUrl,
  loadWebBookmarks,
  loadWebHistory,
  saveWebBookmark,
  saveWebHistoryUrl,
  saveWebShortcutMapping,
  WebBookmarkEntry,
  WebHistoryEntry
} from '../wireguard/ConfigStore';
import { PAGE_BACKGROUND } from './PageStyle';
import { WebBookmarkHome } from './WebBookmarkHome';
import { WebBrowserChrome } from './WebBrowserChrome';
import { WebBrowserStateStore } from './WebBrowserStateStore';
import { WebBrowserSurfaceRegistry, WebSurfaceEntry } from './WebBrowserSurfaceRegistry';
import { WebBrowserSurfaceStack } from './WebBrowserSurfaceStack';
import { WebBrowserTabModel, WebTabStateUpdate } from './WebBrowserTabModel';
import {
  PullRefreshState,
  WebAddressSuggestionItem,
  WebBrowserErrorState,
  WebTabState
} from './WebBrowserTypes';
import { WebPullRefresh } from './WebPullRefresh';
import { PageIconInfo, PwaAppInfo, ShortcutIconInfo, WebShortcutIconService } from './WebShortcutIconService';
import {
  WebViewSurfaceExternalNavigationEvent,
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
const WEB_TOOLBAR_HIDE_GESTURE_DISTANCE = 22;
const WEB_PULL_REFRESH_OVERSCROLL_DISTANCE = 24;
const WEB_NOTICE_DURATION_MS = 2500;
const WEB_BROWSER_INLINE_PIP_BUTTON_SCRIPT = `
(function () {
  try {
    if (location.hostname !== 'm.youtube.com') {
      return false;
    }

    var win = window;
    var doc = document;
    var key = '__smartAgentInlinePip';
    var state = win[key];

    function visitRoots(visitor) {
      var queue = [doc];
      var visited = [];
      while (queue.length > 0) {
        var root = queue.shift();
        if (!root || visited.indexOf(root) >= 0) {
          continue;
        }
        visited.push(root);
        var result = visitor(root);
        if (result) {
          return result;
        }
        var elements = [];
        try {
          elements = root.querySelectorAll('*');
        } catch (err) {
          elements = [];
        }
        for (var i = 0; i < elements.length; i++) {
          var element = elements[i];
          if (element && element.shadowRoot) {
            queue.push(element.shadowRoot);
          }
        }
      }
      return null;
    }

    function collectAll(selector) {
      var queue = [doc];
      var visited = [];
      var results = [];
      while (queue.length > 0) {
        var root = queue.shift();
        if (!root || visited.indexOf(root) >= 0) {
          continue;
        }
        visited.push(root);
        try {
          var found = root.querySelectorAll(selector);
          for (var i = 0; i < found.length; i++) {
            results.push(found[i]);
          }
        } catch (err) {
        }
        var elements = [];
        try {
          elements = root.querySelectorAll('*');
        } catch (err) {
          elements = [];
        }
        for (var j = 0; j < elements.length; j++) {
          var element = elements[j];
          if (element && element.shadowRoot) {
            queue.push(element.shadowRoot);
          }
        }
      }
      return results;
    }

    if (state && state.installed) {
      try {
        state.refresh();
      } catch (err) {
      }
      return true;
    }

    state = {
      installed: true,
      button: null,
      observer: null,
      pollTimer: 0,
      refreshTimers: []
    };
    win[key] = state;

    state.findFullscreenButton = function () {
      return visitRoots(function (root) {
        try {
          return root.querySelector('button.fullscreen-icon') ||
            root.querySelector('button[aria-label*="全屏"]') ||
            root.querySelector('button[aria-label*="Fullscreen"]');
        } catch (err) {
          return null;
        }
      });
    };

    state.findHost = function () {
      var fullscreenButton = state.findFullscreenButton();
      if (!fullscreenButton || !fullscreenButton.parentElement) {
        return null;
      }
      return fullscreenButton.parentElement;
    };

    state.findVideo = function () {
      var videos = collectAll('video');
      var fallback = null;
      for (var i = 0; i < videos.length; i++) {
        var video = videos[i];
        if (!video || video.disablePictureInPicture) {
          continue;
        }
        if (!fallback) {
          fallback = video;
        }
        if (!video.paused && !video.ended) {
          return video;
        }
      }
      return fallback;
    };

    state.removeStaleButtons = function (keepButton) {
      var buttons = collectAll('.smart-agent-pip-button');
      for (var i = 0; i < buttons.length; i++) {
        var button = buttons[i];
        if (button !== keepButton && button && button.parentElement) {
          button.parentElement.removeChild(button);
        }
      }
    };

    state.updateButtonState = function (button) {
      if (!button) {
        return;
      }
      var video = state.findVideo();
      var active = !!doc.pictureInPictureElement;
      var enabled = !!video && !!doc.pictureInPictureEnabled && !video.disablePictureInPicture;
      button.disabled = !enabled;
      button.style.opacity = enabled ? '1' : '0.48';
      button.setAttribute('aria-label', active ? '退出画中画' : '开启画中画');
      button.setAttribute('title', active ? '退出画中画' : '开启画中画');
    };

    state.ensureButton = function () {
      var host = state.findHost();
      if (!host) {
        if (state.button && state.button.parentElement) {
          state.button.parentElement.removeChild(state.button);
        }
        state.button = null;
        return null;
      }

      host.style.display = 'flex';
      host.style.alignItems = 'center';
      host.style.flexWrap = 'nowrap';

      if (state.button && state.button.parentElement === host) {
        state.removeStaleButtons(state.button);
        state.updateButtonState(state.button);
        return state.button;
      }

      state.removeStaleButtons(null);

      var button = doc.createElement('button');
      button.className = 'icon-button fullscreen-icon smart-agent-pip-button';
      button.type = 'button';
      button.setAttribute('aria-label', '开启画中画');
      button.setAttribute('title', '开启画中画');
      button.style.display = 'block';
      button.style.boxSizing = 'border-box';
      button.style.width = '48px';
      button.style.height = '48px';
      button.style.padding = '6px';
      button.style.margin = '0';
      button.style.border = '0';
      button.style.background = 'transparent';
      button.style.color = '#fff';
      button.style.flex = '0 0 auto';
      button.style.cursor = 'pointer';
      button.style.webkitAppearance = 'none';

      var visible = doc.createElement('div');
      visible.className = 'player-bottom-controls-fullscreen-icon-visible-area';
      visible.style.boxSizing = 'border-box';
      visible.style.width = '36px';
      visible.style.height = '36px';
      visible.style.borderRadius = '50%';
      visible.style.padding = '6px';
      visible.style.background = 'rgba(0, 0, 0, 0.3)';
      visible.style.textShadow = '0 0 2px #000';

      var icon = doc.createElement('c3-icon');
      icon.style.display = 'inline-flex';
      icon.style.flexShrink = '0';
      icon.style.width = '24px';
      icon.style.height = '24px';
      icon.style.fill = 'currentColor';
      icon.style.stroke = 'none';

      var span = doc.createElement('span');
      span.className = 'yt-icon-shape ytSpecIconShapeHost';

      var holder = doc.createElement('div');
      holder.style.width = '100%';
      holder.style.height = '100%';
      holder.style.display = 'block';
      holder.style.fill = 'currentColor';

      var svg = doc.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
      svg.setAttribute('height', '24');
      svg.setAttribute('viewBox', '0 0 24 24');
      svg.setAttribute('width', '24');
      svg.setAttribute('focusable', 'false');
      svg.setAttribute('aria-hidden', 'true');
      svg.style.pointerEvents = 'none';
      svg.style.display = 'inherit';
      svg.style.width = '100%';
      svg.style.height = '100%';

      var path1 = doc.createElementNS('http://www.w3.org/2000/svg', 'path');
      path1.setAttribute('d', 'M4 6h16v12H4V6Zm2 2v8h12V8H6Z');
      var path2 = doc.createElementNS('http://www.w3.org/2000/svg', 'path');
      path2.setAttribute('d', 'M13 10h5v5h-5z');

      svg.appendChild(path1);
      svg.appendChild(path2);
      holder.appendChild(svg);
      span.appendChild(holder);
      icon.appendChild(span);
      visible.appendChild(icon);
      button.appendChild(visible);

      button.addEventListener('click', async function (event) {
        event.preventDefault();
        event.stopPropagation();
        var video = state.findVideo();
        if (!video || !doc.pictureInPictureEnabled || video.disablePictureInPicture) {
          state.updateButtonState(button);
          return;
        }
        try {
          if (doc.pictureInPictureElement === video) {
            await doc.exitPictureInPicture();
          } else {
            await video.requestPictureInPicture();
          }
        } catch (err) {
        }
        win.setTimeout(function () {
          state.refresh();
        }, 0);
      }, true);

      host.appendChild(button);
      state.button = button;
      state.updateButtonState(button);
      state.removeStaleButtons(button);
      return button;
    };

    state.scanVideos = function () {
      var videos = collectAll('video');
      for (var i = 0; i < videos.length; i++) {
        var video = videos[i];
        if (!video || video.__smartAgentPipBound) {
          continue;
        }
        video.__smartAgentPipBound = true;
        var refresh = function () {
          state.refresh();
        };
        video.addEventListener('loadedmetadata', refresh, true);
        video.addEventListener('loadeddata', refresh, true);
        video.addEventListener('canplay', refresh, true);
        video.addEventListener('play', refresh, true);
        video.addEventListener('pause', refresh, true);
        video.addEventListener('ended', refresh, true);
        video.addEventListener('enterpictureinpicture', refresh, true);
        video.addEventListener('leavepictureinpicture', refresh, true);
      }
    };

    state.scheduleRefresh = function () {
      for (var i = 0; i < state.refreshTimers.length; i++) {
        win.clearTimeout(state.refreshTimers[i]);
      }
      state.refreshTimers = [];
      var delays = [0, 80, 240, 600];
      for (var j = 0; j < delays.length; j++) {
        state.refreshTimers.push(win.setTimeout(function () {
          state.refresh();
        }, delays[j]));
      }
    };

    state.refresh = function () {
      state.scanVideos();
      var button = state.ensureButton();
      if (!button) {
        return;
      }
      state.updateButtonState(button);
    };

    var wrapHistory = function (name) {
      var raw = history[name];
      if (typeof raw !== 'function' || raw.__smartAgentPipWrapped) {
        return;
      }
      history[name] = function () {
        var result = raw.apply(this, arguments);
        win.setTimeout(function () {
          state.refresh();
        }, 0);
        return result;
      };
      history[name].__smartAgentPipWrapped = true;
    };

    wrapHistory('pushState');
    wrapHistory('replaceState');
    win.addEventListener('popstate', function () {
      state.refresh();
    }, true);
    doc.addEventListener('play', function () {
      state.refresh();
    }, true);
    doc.addEventListener('pause', function () {
      state.refresh();
    }, true);
    doc.addEventListener('visibilitychange', function () {
      state.refresh();
    }, true);
    doc.addEventListener('click', function () {
      state.scheduleRefresh();
    }, true);
    doc.addEventListener('touchstart', function () {
      state.scheduleRefresh();
    }, true);
    doc.addEventListener('pointerup', function () {
      state.scheduleRefresh();
    }, true);
    win.addEventListener('load', function () {
      state.refresh();
    }, true);
    win.addEventListener('resize', function () {
      state.refresh();
    }, true);

    if (win.MutationObserver) {
      state.observer = new MutationObserver(function () {
        state.refresh();
      });
      if (doc.documentElement) {
        state.observer.observe(doc.documentElement, { childList: true, subtree: true });
      }
    }

    if (state.pollTimer) {
      win.clearInterval(state.pollTimer);
    }
    state.pollTimer = win.setInterval(function () {
      state.refresh();
    }, 1500);

    state.refresh();
    return true;
  } catch (err) {
    return false;
  }
})()
`;
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

type WebNavigationTrigger = 'load' | 'address' | 'refresh' | 'back' | 'forward';
type WebNavigationStatus = 'loading' | 'failed' | 'finished';

interface WebNavigationState {
  id: number;
  surfaceKey: string;
  trigger: WebNavigationTrigger;
  requestedUrl: string;
  currentUrl: string;
  status: WebNavigationStatus;
}

@Component
export struct WebBrowserPage {
  @StorageProp('topRectHeight') private topRectHeight: number = 0;
  @Prop @Watch('onInitialUrlChanged') initialUrl: string = DEFAULT_WEB_HOME_URL;
  @Prop persistBrowserState: boolean = true;
  @Prop @Watch('onWebControllerIdChanged') webControllerId: string = WEB_CONTROLLER_ID_APP;
  @Prop instanceKind: 'home' | 'bookmark' = 'home';
  @Prop @Watch('onHostActiveChanged') hostActive: boolean = true;
  @Prop isHomeInstance: boolean = true;
  @Prop allowBookmarkHome: boolean = true;
  @Prop showAddressBar: boolean = true;
  @Prop @Watch('onBookmarkHomeVisibleFromHostChanged') bookmarkHomeVisibleFromHost: boolean = false;
  @Prop @Watch('onBackgroundPipRevisionFromHostChanged') backgroundPipRevisionFromHost: number = 0;
  @Prop homeTabBackCountFromHost: number = 0;
  @Prop @Watch('onTabStateRevisionFromHostChanged') tabStateRevisionFromHost: number = 0;
  @Prop @Watch('onClearTabStackRevisionFromHostChanged') clearTabStackRevisionFromHost: number = 0;
  @Prop clearTabStackTargetIdFromHost: string = '';
  @Prop clearTabStackFallbackUrlFromHost: string = '';
  onClose: () => void = () => {};
  onBackHandlerReady: (handler: () => boolean) => void = () => {};
  onBackHandlerRelease: () => void = () => {};
  onOpenBookmarkHome: () => void = () => {};
  onOpenHomeInstance: () => void = () => {};
  onOpenBookmarkInstance: (bookmark: WebBookmarkEntry) => void = () => {};
  onClearInstanceTabStack: (instanceId: string, fallbackUrl: string) => void = () => {};
  onClearAllBookmarkStacks: () => void = () => {};
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
  @State private addressFocused: boolean = false;
  @State private addressSuggestions: WebAddressSuggestionItem[] = [];
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
  private addBookmarkConfirmSerial: number = 0;
  private pendingLoadUrl: string = '';
  private pendingLoadSurfaceKey: string = '';
  private pwaAppInfo: PwaAppInfo = WebShortcutIconService.emptyPwaAppInfo();
  private pwaInfoSerial: number = 0;
  private navigationSerial: number = 0;
  private activeNavigation?: WebNavigationState;
  private pendingManualHistoryUrl: string = '';
  private addressEditedSinceFocus: boolean = false;
  private addressSuggestionLoadVersion: number = 0;
  private handledClearTabStackRevision: number = 0;
  private handledBackgroundPipRevision: number = 0;
  @State private webSurfaceKeys: string[] = [];
  @State private webSurfaceKey: string = WEB_HOME_TAB_ID + '_0';
  private webSurfaceRegistry: WebBrowserSurfaceRegistry = new WebBrowserSurfaceRegistry();

  aboutToAppear(): void {
    this.configureBrowserStorage();
    this.handledBackgroundPipRevision = this.backgroundPipRevisionFromHost;
    const normalized = this.normalizeUrl(this.initialUrl);
    this.instanceId = this.instanceStateId();
    const restoredHomeState = this.readLaunchTabStateMeta(this.instanceId, normalized);
    this.bookmarkHomeVisible = this.canShowBookmarkHome() &&
      (this.bookmarkHomeVisibleFromHost || this.isBookmarkHomeUrl(restoredHomeState.url));
    const launchTabId = this.bookmarkHomeVisible ? WEB_BOOKMARKS_HOME_TAB_ID : this.instanceId;
    const tabState = this.readLaunchTabStateMeta(launchTabId,
      this.bookmarkHomeVisible ? WEB_BOOKMARKS_HOME_URL : normalized);
    this.webTabStates = [tabState];
    const startUrl = this.normalizeUrl(tabState.url);
    this.currentUrl = startUrl;
    this.setAddressText(startUrl);
    this.resetInstanceWebController();
    this.loadBookmarks();
    this.refreshAddressSuggestions();
    if (!this.bookmarkHomeVisible) {
      this.prepareShortcut(startUrl);
    }
    this.onBackHandlerReady((): boolean => {
      return this.handleBackNavigation();
    });
  }

  aboutToDisappear(): void {
    this.stopAllPullRefreshSpin();
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

        if (this.shouldBuildWebSurfaceStack()) {
          WebBrowserSurfaceStack({
            surfaceKeys: this.webSurfaceKeys,
            activeSurfaceKey: this.webSurfaceKey,
            bookmarkHomeVisible: this.bookmarkHomeVisible,
            webFullScreen: this.webFullScreen,
            srcFor: (surfaceKey: string): string => this.surfaceInitialUrl(surfaceKey),
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
            onExternalNavigation: (surfaceKey: string, event: WebViewSurfaceExternalNavigationEvent): void => {
              this.handleWebSurfaceExternalNavigation(surfaceKey, event.url);
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
        } else {
          Blank()
            .width('100%')
            .layoutWeight(1)
        }
      }
        .width('100%')
        .height('100%')

      if (!this.webFullScreen && this.canShowBookmarkHome() && this.bookmarkHomeVisible) {
        WebBookmarkHome({
          bookmarks: this.bookmarks,
          loading: this.bookmarksLoading,
          topPadding: this.toolbarHeight(),
          tabStateRevision: this.tabStateRevisionFromHost,
          homeTabBackCountValue: this.homeTabBackCountFromHost,
          homeTitle: this.homeTabTitle(),
          homeIconSource: $r('app.media.ic_browser_shortcut'),
          iconSource: (url: string): ResourceStr => this.bookmarkIconSource(url),
          tabBackCount: (bookmarkId: string): number => this.bookmarkBadgeCount(bookmarkId),
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
            hilog.info(DOMAIN, TAG,
              'page onClearHomeTabStack currentUrl=%{public}s homeVisible=%{public}s homeBackCount=%{public}d',
              this.currentUrl,
              String(this.bookmarkHomeVisible),
              this.homeTabBackCountFromHost);
            this.onClearInstanceTabStack(WEB_HOME_TAB_ID, WEB_BOOKMARKS_HOME_URL);
          },
          onClearAllBookmarkStacks: (): void => {
            this.onClearAllBookmarkStacks();
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
        })
          .id('bookmark_home_' + String(this.tabStateRevisionFromHost) + '_' +
            String(this.homeTabBackCountFromHost));
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
          canAddBookmark: this.canAddAddressBookmark(),
          bookmarkedUrls: this.bookmarkedUrls(),
          addressSuggestions: this.addressSuggestions,
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
            if (focused) {
              this.addressEditedSinceFocus = false;
              this.refreshAddressSuggestions();
              return;
            }
            this.addressEditedSinceFocus = false;
            this.addressSuggestions = [];
          },
          onAddressChange: (value: string): void => {
            this.setAddressText(value);
            this.addressEditedSinceFocus = true;
            this.refreshAddressSuggestions();
          },
          onAddressSubmit: (): void => {
            this.loadAddress();
          },
          onClearAddress: (): void => {
            this.clearAddressForEditing();
          },
          onSelectAddressSuggestion: (item: WebAddressSuggestionItem): void => {
            this.openAddressSuggestion(item);
          },
          onDeleteAddressSuggestionHistory: (item: WebAddressSuggestionItem): void => {
            this.deleteAddressSuggestionHistory(item);
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
          },
          onWebErrorPullRefreshStart: (): void => {
            this.handleWebErrorPullRefreshStart();
          },
          onWebErrorPullRefreshUpdate: (offsetY: number): void => {
            this.handleWebErrorPullRefreshUpdate(offsetY);
          },
          onWebErrorPullRefreshEnd: (): void => {
            this.handleWebErrorPullRefreshEnd();
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

  private showWebError(surfaceKey: string, event: WebViewSurfaceLoadErrorEvent): void {
    const url = event.url.length > 0 ? event.url : this.currentUrl;
    if (!this.shouldShowWebErrorForActiveNavigation(surfaceKey, event)) {
      hilog.info(DOMAIN, TAG, 'suppress passive web error kind=%{public}s code=%{public}d url=%{public}s',
        event.kind,
        event.code,
        url
      );
      this.loading = false;
      this.progress = 100;
      this.endPullRefresh(surfaceKey);
      return;
    }
    if (url.length > 0 && this.isBrowserStateUrl(url)) {
      this.commitCurrentUrl(url);
      this.updateActiveNavigationUrl(surfaceKey, url);
    }
    this.failActiveNavigation(surfaceKey, url);
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
    this.endPullRefresh(surfaceKey);
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
    if (event.kind === 'network') {
      return '网络连接失败';
    }
    if (event.kind === 'ssl') {
      return '安全连接失败';
    }
    if (event.kind === 'render-process') {
      return '页面渲染异常';
    }
    return '网页加载失败';
  }

  private webErrorDetail(event: WebViewSurfaceLoadErrorEvent): string {
    const message = event.message.trim();
    if (event.kind === 'http') {
      if (message.length > 0) {
        return 'HTTP 状态码 ' + String(event.code) + '，' + message;
      }
      return 'HTTP 状态码 ' + String(event.code);
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
    this.addressEditedSinceFocus = false;
    this.refreshAddressSuggestions();
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
    hilog.info(DOMAIN, TAG,
      'surface page begin surface=%{public}s url=%{public}s shouldHandle=%{public}s activeSurface=%{public}s bookmarkHomeVisible=%{public}s surfaces=%{public}s',
      surfaceKey,
      url,
      String(this.shouldHandleWebSurface(surfaceKey)),
      this.webSurfaceKey,
      String(this.bookmarkHomeVisible),
      this.surfaceStateSnapshot());
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    this.setWebSurfaceScrollY(surfaceKey, 0);
    this.setBrowserPullRefreshEnabled(surfaceKey, true);
    if (url.length > 0) {
      if (this.commitCurrentUrl(url)) {
        this.updateActiveNavigationUrl(surfaceKey, url);
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
    hilog.info(DOMAIN, TAG,
      'surface navigation committed surface=%{public}s url=%{public}s mainFrame=%{public}s shouldHandle=%{public}s activeSurface=%{public}s navigation=%{public}s surfaces=%{public}s',
      surfaceKey,
      url,
      String(isMainFrame),
      String(this.shouldHandleWebSurface(surfaceKey)),
      this.webSurfaceKey,
      this.describeActiveNavigation(surfaceKey),
      this.surfaceStateSnapshot());
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    if (isMainFrame && url.length > 0) {
      if (this.commitCurrentUrl(url)) {
        this.updateActiveNavigationUrl(surfaceKey, url);
        const navigation = this.activeNavigationForSurface(surfaceKey);
        if (navigation !== undefined && navigation.trigger === 'address' && this.pendingManualHistoryUrl.length > 0) {
          this.pendingManualHistoryUrl = this.normalizeUrl(url);
        }
        this.clearWebErrorFor(url);
        this.updateNavigationState();
        this.syncSurfaceTabStackSize(surfaceKey);
        this.prepareShortcut(url);
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
    hilog.info(DOMAIN, TAG,
      'surface page visible surface=%{public}s shouldHandle=%{public}s activeSurface=%{public}s currentUrl=%{public}s surfaces=%{public}s',
      surfaceKey,
      String(this.shouldHandleWebSurface(surfaceKey)),
      this.webSurfaceKey,
      this.currentUrl,
      this.surfaceStateSnapshot());
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    this.endPullRefresh(surfaceKey);
    this.syncUrlFromController();
    this.updateNavigationState();
    this.syncSurfaceTabStackSize(surfaceKey);
    this.persistWebState();
    this.installInlinePictureInPictureButton(surfaceKey);
  }

  private handleWebSurfacePageEnd(surfaceKey: string, url: string): void {
    hilog.info(DOMAIN, TAG,
      'surface page end surface=%{public}s url=%{public}s activeSurface=%{public}s bookmarkHomeVisible=%{public}s navigation=%{public}s surfaces=%{public}s',
      surfaceKey,
      url,
      this.webSurfaceKey,
      String(this.bookmarkHomeVisible),
      this.describeActiveNavigation(surfaceKey),
      this.surfaceStateSnapshot());
    if (!this.isActiveWebSurface(surfaceKey)) {
      return;
    }
    if (this.bookmarkHomeVisible) {
      return;
    }
    if (url.length > 0) {
      this.commitCurrentUrl(url);
    }
    this.syncUrlFromController();
    const navigationFailed = this.isActiveNavigationFailed(surfaceKey);
    this.loading = false;
    this.progress = 100;
    this.endPullRefresh(surfaceKey);
    this.updateNavigationState();
    this.syncSurfaceTabStackSize(surfaceKey);
    if (navigationFailed) {
      return;
    }
    this.finishActiveNavigation(surfaceKey, this.currentUrl);
    this.saveWebCookies();
    this.persistWebState();
    this.persistWebHistory(this.currentUrl, this.pageTitleUrl === this.currentUrl ? this.pageTitle.trim() : '');
    this.prepareShortcut(this.currentUrl);
    this.detectPwaApp(this.currentUrl);
    this.installInlinePictureInPictureButton(surfaceKey);
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
      this.persistWebHistory(this.currentUrl, title.trim());
      this.refreshAddressSuggestions();
      this.prepareShortcut(this.currentUrl);
    }
  }

  private handleWebSurfaceFaviconReceived(surfaceKey: string, favicon: image.PixelMap): void {
    if (!this.shouldHandleWebSurface(surfaceKey)) {
      return;
    }
    const surface = this.webSurfaceByKey(surfaceKey);
    const url = surface !== undefined ? this.surfaceCurrentUrl(surface) : this.currentUrl;
    if (!this.isBrowserShortcutUrl(url)) {
      return;
    }
    const normalized = this.normalizeUrl(url);
    this.favicon = favicon;
    this.faviconUrl = normalized;
    this.prepareShortcut(normalized);
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
    const allowDirectPullRefresh = this.canStartPullRefreshWithoutOverScroll(surfaceKey);
    this.updateToolbarVisibilityForWebGesture(surfaceKey, event.offsetY);
    if (pullRefresh.refreshing) {
      return;
    }
    if (!this.shouldHandleWebSurface(surfaceKey) || this.webFullScreen || this.loading) {
      this.resetPullRefresh(surfaceKey);
      return;
    }
    if (!pullRefresh.tracking) {
      if (event.offsetY <= 0 || !pullRefresh.browserRefreshEnabled ||
        (!pullRefresh.gestureOverScrollActive && !allowDirectPullRefresh) ||
        this.currentScrollY(surfaceKey) > 1) {
        return;
      }
      WebPullRefresh.beginTracking(pullRefresh, event.offsetY);
    }
    if (event.offsetY <= 0 || !pullRefresh.browserRefreshEnabled || this.currentScrollY(surfaceKey) > 1) {
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
      (pullRefresh.gestureOverScrollActive || this.canStartPullRefreshWithoutOverScroll(surfaceKey)) &&
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

  private handleWebErrorPullRefreshStart(): void {
    if (!this.webError.visible || this.bookmarkHomeVisible || this.webFullScreen) {
      return;
    }
    const pullRefresh = this.pullRefreshState(this.webSurfaceKey);
    if (pullRefresh.refreshing) {
      return;
    }
    WebPullRefresh.beginTracking(pullRefresh);
    this.bumpPullRefreshRevision();
  }

  private handleWebErrorPullRefreshUpdate(offsetY: number): void {
    if (!this.webError.visible || this.bookmarkHomeVisible || this.webFullScreen) {
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
      WebPullRefresh.beginTracking(pullRefresh, offsetY);
    }
    if (offsetY <= 0) {
      this.resetPullRefresh(this.webSurfaceKey);
      return;
    }
    this.updatePullRefresh(this.webSurfaceKey, offsetY - pullRefresh.gesturePullStartOffsetY);
  }

  private handleWebErrorPullRefreshEnd(): void {
    if (!this.webError.visible || this.bookmarkHomeVisible || this.webFullScreen) {
      return;
    }
    const pullRefresh = this.pullRefreshState(this.webSurfaceKey);
    pullRefresh.gestureLastOffsetY = 0;
    if (pullRefresh.refreshing) {
      return;
    }
    if (pullRefresh.tracking && pullRefresh.ready) {
      this.startBrowserPullRefresh(this.webSurfaceKey);
      return;
    }
    this.cancelPullRefresh(this.webSurfaceKey);
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
    this.showWebError(surfaceKey, event);
  }

  private installInlinePictureInPictureButton(surfaceKey: string): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined || !surface.attached || !this.isActiveWebSurface(surfaceKey) ||
      this.bookmarkHomeVisible || this.webFullScreen) {
      return;
    }

    try {
      surface.controller.runJavaScript(WEB_BROWSER_INLINE_PIP_BUTTON_SCRIPT).catch((err: BusinessError) => {
        hilog.info(DOMAIN, TAG, 'install inline pip button failed surface=%{public}s error=%{public}s',
          surfaceKey,
          this.formatError(err));
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.info(DOMAIN, TAG, 'install inline pip button rejected surface=%{public}s error=%{public}s',
        surfaceKey,
        this.formatError(error));
    }
  }

  private handleWebSurfaceExternalNavigation(surfaceKey: string, url: string): void {
    if (!this.isActiveWebSurface(surfaceKey) || this.bookmarkHomeVisible || !this.isExternalSchemeUrl(url)) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const options: OpenLinkOptions = {
      appLinkingOnly: false,
      hideFailureTipDialog: true
    };
    context.openLink(url, options).then(() => {
      hilog.info(DOMAIN, TAG, 'open external scheme success surface=%{public}s url=%{public}s', surfaceKey, url);
      this.loading = false;
      this.progress = 100;
      this.endPullRefresh(surfaceKey);
      this.updateNavigationState();
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'open external link failed surface=%{public}s url=%{public}s error=%{public}s',
        surfaceKey,
        url,
        this.formatError(err));
      this.loading = false;
      this.progress = 100;
      this.endPullRefresh(surfaceKey);
      this.showNotice('无法打开外部应用：' + this.formatError(err));
      this.updateNavigationState();
    });
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
  }

  private resetInstanceWebController(activateAttached: boolean = true): void {
    const stateKey = this.currentWebStateTabId();
    this.restoringWebState = false;
    this.clearPendingLoadUrl();
    this.clearActiveNavigation();
    this.nativeWebFullScreen = false;
    this.webFullScreen = false;
    this.canGoBack = false;
    this.canGoForward = false;
    this.resetPullRefresh();
    const surface = this.ensureWebSurface(stateKey);
    this.controller = surface.controller;
    this.controllerAttached = surface.attached;
    this.webSurfaceKey = surface.surfaceKey;
    this.updateWebSurfaceVisibility();
    hilog.info(DOMAIN, TAG,
      'resetInstanceWebController stateKey=%{public}s activateAttached=%{public}s bookmarkHomeVisible=%{public}s controllerAttached=%{public}s surface=%{public}s surfaces=%{public}s',
      stateKey,
      String(activateAttached),
      String(this.bookmarkHomeVisible),
      String(this.controllerAttached),
      this.describeSurface(surface),
      this.surfaceStateSnapshot());
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

  private shouldBuildWebSurfaceStack(): boolean {
    if (!this.bookmarkHomeVisible) {
      return true;
    }
    const surface = this.webSurfaceByKey(this.webSurfaceKey);
    if (surface === undefined || (!surface.attached && !surface.initialized)) {
      return false;
    }
    return this.surfaceInitialUrl(this.webSurfaceKey).length > 0;
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
    hilog.info(DOMAIN, TAG,
      'update web surface visibility activeSurface=%{public}s bookmarkHomeVisible=%{public}s surfaces=%{public}s',
      this.webSurfaceKey,
      String(this.bookmarkHomeVisible),
      this.surfaceStateSnapshot());
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

  private surfaceInitialUrl(surfaceKey: string): string {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface !== undefined) {
      if (this.shouldRestoreSurfaceOnAttach(surface)) {
        hilog.info(DOMAIN, TAG,
          'surface initial url deferred for restore surface=%{public}s id=%{public}s',
          surface.surfaceKey,
          surface.id);
        return '';
      }
      const tabUrl = WebBrowserTabModel.tabUrl(this.webTabStates, surface.id);
      if (this.isWebLoadableUrl(tabUrl)) {
        return this.normalizeUrl(tabUrl);
      }
    }
    if (this.isWebLoadableUrl(this.currentUrl)) {
      return this.normalizeUrl(this.currentUrl);
    }
    const initial = this.normalizeUrl(this.initialUrl);
    if (this.isWebLoadableUrl(initial)) {
      return initial;
    }
    return '';
  }

  private shouldRestoreSurfaceOnAttach(surface: WebSurfaceEntry): boolean {
    if (surface.initialized || this.bookmarkHomeVisible) {
      return false;
    }
    const tabUrl = WebBrowserTabModel.tabUrl(this.webTabStates, surface.id);
    if (!this.isBrowserStateUrl(tabUrl)) {
      return false;
    }
    return this.hasValidWebStateOwner(surface.id);
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

  private resetActiveWebSurfaceAfterHomeClear(tabId: string): void {
    const oldSurfaceKey = this.webSurfaceKey;
    this.clearPendingLoadUrl();
    const surface = this.webSurfaceRegistry.reset(tabId);
    this.controller = surface.controller;
    this.controllerAttached = false;
    this.webSurfaceKey = surface.surfaceKey;
    this.loading = false;
    this.progress = 100;
    this.resetPullRefresh(this.webSurfaceKey);
    this.updateWebSurfaceVisibility();
    this.publishWebSurfaceKeys();
    hilog.info(DOMAIN, TAG,
      'reset active web surface after home clear id=%{public}s oldSurface=%{public}s newSurface=%{public}s surfaces=%{public}s',
      tabId,
      oldSurfaceKey,
      this.describeSurface(surface),
      this.surfaceStateSnapshot());
  }

  private clearControllerHistory(tabId: string, fallbackUrl: string, revision: number): void {
    if (revision !== this.handledClearTabStackRevision || tabId !== this.currentWebStateTabId()) {
      return;
    }
    const normalized = this.normalizeUrl(fallbackUrl);
    hilog.info(DOMAIN, TAG,
      'clear controller history id=%{public}s fallback=%{public}s revision=%{public}d bookmarkHomeVisible=%{public}s attached=%{public}s currentUrl=%{public}s controllerUrl=%{public}s',
      tabId,
      normalized,
      revision,
      String(this.bookmarkHomeVisible),
      String(this.controllerAttached),
      this.currentUrl,
      this.safeControllerUrl());

    this.clearActiveNavigation();
    this.canGoBack = false;
    this.canGoForward = false;
    if (this.isBookmarkHomeUrl(normalized)) {
      this.currentUrl = WEB_BOOKMARKS_HOME_URL;
      this.rememberHomeTabClearedState();
      this.resetActiveWebSurfaceAfterHomeClear(tabId);
      this.showBookmarkHome();
      return;
    }

    this.commitCurrentUrl(normalized);
    this.rememberCurrentTabState(0);
    if (!this.controllerAttached) {
      this.setPendingLoadUrl(normalized);
      return;
    }
    try {
      this.controller.clearHistory();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clear controller history failed: %{public}s', this.formatError(err));
    }
    if (!this.bookmarkHomeVisible) {
      const controllerUrl = this.safeControllerUrl();
      if (!this.isBrowserStateUrl(controllerUrl) || this.normalizeUrl(controllerUrl) !== normalized) {
        this.loadTabInitialUrl(normalized);
      }
    }
  }

  private activateAttachedSurface(surfaceKey: string): void {
    const surface = this.webSurfaceByKey(surfaceKey);
    if (surface === undefined || !surface.attached || !this.isActiveWebSurface(surfaceKey) || this.bookmarkHomeVisible) {
      hilog.info(DOMAIN, TAG,
        'activateAttachedSurface skipped surface=%{public}s exists=%{public}s attached=%{public}s active=%{public}s bookmarkHomeVisible=%{public}s surfaces=%{public}s',
        surfaceKey,
        String(surface !== undefined),
        String(surface !== undefined ? surface.attached : false),
        String(this.isActiveWebSurface(surfaceKey)),
        String(this.bookmarkHomeVisible),
        this.surfaceStateSnapshot());
      return;
    }
    hilog.info(DOMAIN, TAG,
      'activateAttachedSurface begin surface=%{public}s surfaceState=%{public}s currentUrl=%{public}s pending=%{public}s',
      surfaceKey,
      this.describeSurface(surface),
      this.currentUrl,
      this.pendingLoadUrl);
    this.controller = surface.controller;
    this.controllerAttached = true;
    this.configureAttachedController();
    const pendingUrl = this.consumePendingLoadUrl(surfaceKey);
    if (pendingUrl.length > 0) {
      const initialUrl = this.surfaceInitialUrl(surfaceKey);
      hilog.info(DOMAIN, TAG,
        'activateAttachedSurface load pending surface=%{public}s url=%{public}s initialUrl=%{public}s initialized=%{public}s',
        surfaceKey,
        pendingUrl,
        initialUrl,
        String(surface.initialized));
      this.initialNavigationDone = true;
      if (!surface.initialized && initialUrl.length > 0 && this.normalizeUrl(initialUrl) === this.normalizeUrl(pendingUrl)) {
        surface.initialized = true;
        this.loading = true;
        this.progress = 8;
        this.webError = this.emptyWebError();
        return;
      }
      surface.initialized = true;
      this.loadTabInitialUrl(pendingUrl);
      return;
    }
    if (!surface.initialized) {
      hilog.info(DOMAIN, TAG,
        'activateAttachedSurface open attached page surface=%{public}s currentUrl=%{public}s',
        surfaceKey,
        this.currentUrl);
      surface.initialized = true;
      this.openAttachedPage();
      return;
    }
    hilog.info(DOMAIN, TAG,
      'activateAttachedSurface reuse current page surface=%{public}s controllerUrl=%{public}s',
      surfaceKey,
      this.safeControllerUrl());
    this.syncUrlFromController();
    this.updateNavigationState();
    this.syncSurfaceTabStackSize(surfaceKey);
    this.loading = false;
    this.progress = 100;
    this.prepareShortcut(this.currentUrl);
    this.installInlinePictureInPictureButton(surfaceKey);
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
    const restoredHomeState = this.readLaunchTabStateMeta(this.instanceId, normalized);
    const isBookmarkHome = this.canShowBookmarkHome() &&
      (this.bookmarkHomeVisibleFromHost || this.isBookmarkHomeUrl(restoredHomeState.url));
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

  private onHostActiveChanged(): void {
    if (this.hostActive) {
      this.handledBackgroundPipRevision = this.backgroundPipRevisionFromHost;
    }
  }

  private onBookmarkHomeVisibleFromHostChanged(): void {
    const nextBookmarkHomeVisible = this.canShowBookmarkHome() && this.bookmarkHomeVisibleFromHost;
    hilog.info(DOMAIN, TAG,
      'host bookmark home visible changed next=%{public}s current=%{public}s activeSurface=%{public}s instance=%{public}s currentUrl=%{public}s surfaces=%{public}s',
      String(nextBookmarkHomeVisible),
      String(this.bookmarkHomeVisible),
      this.webSurfaceKey,
      this.instanceId,
      this.currentUrl,
      this.surfaceStateSnapshot());
    if (nextBookmarkHomeVisible && !this.bookmarkHomeVisible) {
      this.persistWebState();
    }
    this.bookmarkHomeVisible = nextBookmarkHomeVisible;
    this.updateWebSurfaceVisibility();
    if (this.bookmarkHomeVisible) {
      this.saveWebCookies();
      this.clearActiveNavigation();
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

  private onBackgroundPipRevisionFromHostChanged(): void {
    if (!this.hostActive) {
      return;
    }
    if (this.backgroundPipRevisionFromHost <= 0 ||
      this.backgroundPipRevisionFromHost === this.handledBackgroundPipRevision) {
      return;
    }
    this.handledBackgroundPipRevision = this.backgroundPipRevisionFromHost;
  }

  private onTabStateRevisionFromHostChanged(): void {
    if (!this.bookmarkHomeVisible) {
      return;
    }
    if (this.homeTabBackCountFromHost <= 0) {
      const state: WebTabState = {
        id: WEB_HOME_TAB_ID,
        url: WEB_BOOKMARKS_HOME_URL,
        backCount: 0
      };
      this.webTabStates = WebBrowserTabModel.upsert(this.webTabStates, state);
      this.currentUrl = WEB_BOOKMARKS_HOME_URL;
      this.setAddressText('');
    }
    this.bookmarks = this.bookmarks.slice();
  }

  private onClearTabStackRevisionFromHostChanged(): void {
    if (this.clearTabStackRevisionFromHost <= 0 ||
      this.clearTabStackRevisionFromHost === this.handledClearTabStackRevision) {
      return;
    }
    const targetId = this.safeFileSegment(this.clearTabStackTargetIdFromHost);
    if (targetId.length === 0 || targetId !== this.currentWebStateTabId()) {
      return;
    }
    const revision = this.clearTabStackRevisionFromHost;
    this.handledClearTabStackRevision = revision;
    const fallbackUrl = this.normalizeUrl(this.clearTabStackFallbackUrlFromHost);
    hilog.info(DOMAIN, TAG,
      'schedule controller history clear id=%{public}s fallback=%{public}s revision=%{public}d bookmarkHomeVisible=%{public}s attached=%{public}s',
      targetId,
      fallbackUrl,
      revision,
      String(this.bookmarkHomeVisible),
      String(this.controllerAttached));
    setTimeout(() => {
      this.clearControllerHistory(targetId, fallbackUrl, revision);
    }, 0);
  }

  private loadAddress(): void {
    const normalized = this.normalizeUrl(this.addressText);
    hilog.info(DOMAIN, TAG,
      'loadAddress raw=%{public}s normalized=%{public}s bookmarkHomeVisible=%{public}s activeSurface=%{public}s controllerAttached=%{public}s currentUrl=%{public}s pending=%{public}s surfaces=%{public}s',
      this.addressText,
      normalized,
      String(this.bookmarkHomeVisible),
      this.webSurfaceKey,
      String(this.controllerAttached),
      this.currentUrl,
      this.pendingLoadUrl,
      this.surfaceStateSnapshot());
    this.setAddressText(normalized);
    this.addressFocused = false;
    this.addressEditedSinceFocus = false;
    this.addressSuggestions = [];
    this.pendingManualHistoryUrl = normalized;
    this.loadUrl(normalized, 'address');
  }

  private loadTabInitialUrl(url: string): boolean {
    return this.loadUrl(url, 'load');
  }

  private setPendingLoadUrl(url: string): void {
    this.pendingLoadUrl = this.normalizeUrl(url);
    this.pendingLoadSurfaceKey = this.webSurfaceKey;
    hilog.info(DOMAIN, TAG,
      'set pending load url=%{public}s surface=%{public}s instance=%{public}s surfaces=%{public}s',
      this.pendingLoadUrl,
      this.pendingLoadSurfaceKey,
      this.instanceId,
      this.surfaceStateSnapshot());
  }

  private consumePendingLoadUrl(surfaceKey: string): string {
    if (this.pendingLoadUrl.length === 0 || this.pendingLoadSurfaceKey !== surfaceKey) {
      return '';
    }
    const url = this.pendingLoadUrl;
    this.clearPendingLoadUrl();
    hilog.info(DOMAIN, TAG,
      'consume pending load url=%{public}s surface=%{public}s instance=%{public}s surfaces=%{public}s',
      url,
      surfaceKey,
      this.instanceId,
      this.surfaceStateSnapshot());
    return url;
  }

  private clearPendingLoadUrl(): void {
    this.pendingLoadUrl = '';
    this.pendingLoadSurfaceKey = '';
  }

  private loadUrl(url: string, trigger: WebNavigationTrigger = 'load'): boolean {
    const normalized = this.normalizeUrl(url);
    let surface = this.webSurfaceByKey(this.webSurfaceKey);
    hilog.info(DOMAIN, TAG,
      'loadUrl trigger=%{public}s url=%{public}s normalized=%{public}s bookmarkHomeVisible=%{public}s activeSurface=%{public}s controllerAttached=%{public}s instance=%{public}s surface=%{public}s pending=%{public}s surfaces=%{public}s',
      trigger,
      url,
      normalized,
      String(this.bookmarkHomeVisible),
      this.webSurfaceKey,
      String(this.controllerAttached),
      this.instanceId,
      this.describeSurface(surface),
      this.pendingLoadUrl,
      this.surfaceStateSnapshot());
    if (this.isBookmarkHomeUrl(normalized)) {
      hilog.info(DOMAIN, TAG, 'loadUrl redirected to bookmark home normalized=%{public}s', normalized);
      this.onOpenBookmarkHome();
      return true;
    }
    const switchingFromBookmarkHome = this.bookmarkHomeVisible;
    if (switchingFromBookmarkHome) {
      hilog.info(DOMAIN, TAG,
        'loadUrl switching from bookmark home normalized=%{public}s activeSurface=%{public}s instance=%{public}s',
        normalized,
        this.webSurfaceKey,
        this.instanceId);
      this.bookmarkHomeVisible = false;
      this.currentUrl = normalized;
      this.instanceId = WEB_HOME_TAB_ID;
      this.resetInstanceWebController(false);
      surface = this.webSurfaceByKey(this.webSurfaceKey);
    }
    this.commitCurrentUrl(normalized);
    this.beginNavigation(this.webSurfaceKey, trigger, normalized);
    this.resetPwaAppInfo();

    try {
      this.bookmarkHomeVisible = false;
      this.updateWebSurfaceVisibility();
      this.warmupServiceWorker(normalized);
      const surfaceReady = surface !== undefined && surface.attached && surface.initialized;
      if (switchingFromBookmarkHome || !this.controllerAttached || !surfaceReady) {
        hilog.info(DOMAIN, TAG,
          'loadUrl defer trigger=%{public}s url=%{public}s switchingFromBookmarkHome=%{public}s controllerAttached=%{public}s surfaceInitialized=%{public}s surfaceAttached=%{public}s activeSurface=%{public}s surfaces=%{public}s',
          trigger,
          normalized,
          String(switchingFromBookmarkHome),
          String(this.controllerAttached),
          String(surface !== undefined ? surface.initialized : false),
          String(surface !== undefined ? surface.attached : false),
          this.webSurfaceKey,
          this.surfaceStateSnapshot());
        this.setPendingLoadUrl(normalized);
        this.loading = true;
        this.progress = 0;
        this.webError = this.emptyWebError();
        if (switchingFromBookmarkHome) {
          this.onOpenHomeInstance();
        }
        if (surface !== undefined && surface.attached) {
          this.activateAttachedSurface(this.webSurfaceKey);
        }
        return true;
      }
      this.clearPendingLoadUrl();
      hilog.info(DOMAIN, TAG,
        'loadUrl direct controller.loadUrl normalized=%{public}s activeSurface=%{public}s controllerUrl=%{public}s surfaces=%{public}s',
        normalized,
        this.webSurfaceKey,
        this.safeControllerUrl(),
        this.surfaceStateSnapshot());
      this.controller.loadUrl(normalized);
      this.loading = true;
      this.progress = 8;
      this.webError = this.emptyWebError();
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG,
        'loadUrl failed trigger=%{public}s url=%{public}s activeSurface=%{public}s error=%{public}s surfaces=%{public}s',
        trigger,
        normalized,
        this.webSurfaceKey,
        this.formatError(err),
        this.surfaceStateSnapshot());
      this.showWebError(this.webSurfaceKey, {
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
    this.beginNavigation(this.webSurfaceKey, 'refresh', normalized);
    try {
      this.controller.refresh();
      this.commitCurrentUrl(normalized);
      this.loading = true;
      this.progress = 8;
      this.webError = this.emptyWebError();
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'web refresh failed, reload current url instead: %{public}s',
        error.message ?? JSON.stringify(err));
      return this.loadUrl(normalized, 'refresh');
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
      this.beginNavigation(this.webSurfaceKey, 'back', this.currentUrl);
      this.controller.backward();
      this.loading = true;
      this.progress = 8;
      this.updateNavigationState();
      this.syncActiveTabStackSize();
      this.webError = this.emptyWebError();
      return true;
    } catch (err) {
      this.clearActiveNavigation();
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
    if (value.length === 0) {
      return;
    }
    try {
      const promptAction: PromptAction = this.getUIContext().getPromptAction();
      promptAction.showToast({
        message: value,
        duration: WEB_NOTICE_DURATION_MS,
        bottom: '80vp'
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'show toast failed: %{public}s', error.message ?? JSON.stringify(err));
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
      this.beginNavigation(this.webSurfaceKey, 'forward', this.currentUrl);
      this.controller.forward();
      this.loading = true;
      this.progress = 8;
      this.updateNavigationState();
      this.webError = this.emptyWebError();
    } catch (err) {
      this.clearActiveNavigation();
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
    hilog.info(DOMAIN, TAG,
      'emit tab state source=rememberCurrentTabState id=%{public}s url=%{public}s backCount=%{public}d activeSurface=%{public}s bookmarkHomeVisible=%{public}s',
      update.state.id,
      update.state.url,
      update.state.backCount,
      this.webSurfaceKey,
      String(this.bookmarkHomeVisible));
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
    const backCount = this.controllerPageCount(surface.controller);
    this.rememberTabState(surface.id, this.surfaceCurrentUrl(surface), backCount);
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
    hilog.info(DOMAIN, TAG,
      'emit tab state source=rememberTabState id=%{public}s url=%{public}s backCount=%{public}d activeSurface=%{public}s bookmarkHomeVisible=%{public}s',
      update.state.id,
      update.state.url,
      update.state.backCount,
      this.webSurfaceKey,
      String(this.bookmarkHomeVisible));
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
    hilog.info(DOMAIN, TAG,
      'emit tab state source=rememberBookmarkHomeState id=%{public}s url=%{public}s backCount=%{public}d activeSurface=%{public}s bookmarkHomeVisible=%{public}s',
      state.id,
      state.url,
      state.backCount,
      this.webSurfaceKey,
      String(this.bookmarkHomeVisible));
    this.onTabStateChanged(state);
  }

  private rememberHomeTabClearedState(): void {
    const state: WebTabState = {
      id: WEB_HOME_TAB_ID,
      url: WEB_BOOKMARKS_HOME_URL,
      backCount: 0
    };
    this.webTabStates = WebBrowserTabModel.upsert(this.webTabStates, state);
    this.persistTabState(state);
    this.setAddressText('');
    hilog.info(DOMAIN, TAG,
      'emit tab state source=rememberHomeTabClearedState id=%{public}s url=%{public}s backCount=%{public}d activeSurface=%{public}s bookmarkHomeVisible=%{public}s',
      state.id,
      state.url,
      state.backCount,
      this.webSurfaceKey,
      String(this.bookmarkHomeVisible));
    this.onTabStateChanged(state);
  }

  private currentTabStackSize(): number {
    if (!this.controllerAttached || this.bookmarkHomeVisible) {
      return this.tabBackCount(this.currentWebStateTabId());
    }
    return this.controllerPageCount(this.controller);
  }

  private controllerPageCount(controller: webview.WebviewController): number {
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

  private resolvedCurrentBrowserUrl(): string {
    if (!this.bookmarkHomeVisible && this.controllerAttached) {
      try {
        const controllerUrl = this.controller.getUrl();
        if (this.isBrowserStateUrl(controllerUrl)) {
          return this.normalizeUrl(controllerUrl);
        }
      } catch (err) {
      }
    }
    const url = this.currentUrl.trim();
    if (!this.isBrowserStateUrl(url)) {
      return '';
    }
    return this.normalizeUrl(url);
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

  private resolvedHomeTabClearFallbackUrl(): string {
    const current = this.resolvedCurrentBrowserUrl();
    if (current.length > 0 && !this.isBookmarkHomeUrl(current)) {
      return current;
    }
    const stateUrl = WebBrowserTabModel.tabUrl(this.webTabStates, WEB_HOME_TAB_ID).trim();
    if (this.isWebLoadableUrl(stateUrl)) {
      return this.normalizeUrl(stateUrl);
    }
    const initial = this.normalizeUrl(this.initialUrl);
    if (this.isWebLoadableUrl(initial)) {
      return initial;
    }
    return WEB_BOOKMARKS_HOME_URL;
  }

  private persistWebHistory(urlValue: string, title: string = ''): void {
    if (!this.isBrowserShortcutUrl(urlValue)) {
      return;
    }
    const normalizedUrl = this.normalizeUrl(urlValue);
    if (this.pendingManualHistoryUrl.length === 0 || normalizedUrl !== this.pendingManualHistoryUrl) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    saveWebHistoryUrl(context, normalizedUrl, title).then(() => {
      if (this.pendingManualHistoryUrl === normalizedUrl) {
        this.pendingManualHistoryUrl = '';
      }
      if (this.addressFocused) {
        this.refreshAddressSuggestions();
      }
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'save web history failed: %{public}s', this.formatError(err));
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
    const context = getContext(this) as common.UIAbilityContext;
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
    this.prepareShortcutIcons(context, normalized, true).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'prepare bookmark icon failed, fallback to default icon: %{public}s',
        this.formatError(err));
    }).then(() => {
      return saveWebBookmark(context, normalized, title, bookmarkId);
    }).then((added: boolean) => {
      if (!added) {
        this.showNotice('书签已存在');
        this.hideAddBookmarkConfirm();
        return;
      }
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
    if (this.bookmarkHomeVisible || this.loading) {
      return '';
    }
    const url = this.resolvedCurrentBrowserUrl();
    if (!this.isBrowserShortcutUrl(url)) {
      return '';
    }
    return url;
  }

  private canAddAddressBookmark(): boolean {
    const url = this.currentPageUrlForBookmark();
    if (url.length === 0) {
      return false;
    }
    const navigation = this.activeNavigationForSurface(this.webSurfaceKey);
    if (navigation !== undefined) {
      if (navigation.status !== 'finished') {
        return false;
      }
    } else if (!this.controllerAttached) {
      return false;
    }
    return !this.hasBookmarkUrl(this.bookmarks, url);
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
    this.resetPullRefresh();
    this.endPullRefresh();
    this.setVideoFullScreenSystemBars(true);
  }

  private exitWebFullScreen(): void {
    hilog.info(DOMAIN, TAG, 'exit web fullscreen');
    this.nativeWebFullScreen = false;
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

  private openAttachedPage(): void {
    hilog.info(DOMAIN, TAG,
      'openAttachedPage currentUrl=%{public}s bookmarkHomeVisible=%{public}s controllerAttached=%{public}s activeSurface=%{public}s instance=%{public}s surfaces=%{public}s',
      this.currentUrl,
      String(this.bookmarkHomeVisible),
      String(this.controllerAttached),
      this.webSurfaceKey,
      this.instanceId,
      this.surfaceStateSnapshot());
    if (!this.initialNavigationDone) {
      this.initialNavigationDone = true;
    }
    if (this.isBookmarkHomeUrl(this.currentUrl)) {
      this.showBookmarkHome();
      return;
    }

    if (this.restoreWebState()) {
      hilog.info(DOMAIN, TAG,
        'openAttachedPage restored web state currentUrl=%{public}s controllerUrl=%{public}s',
        this.currentUrl,
        this.safeControllerUrl());
      if (this.syncRestoredUrlOrLoad(this.currentUrl)) {
        this.updateNavigationState();
        this.loading = false;
        this.progress = 100;
        this.prepareShortcut(this.currentUrl);
        return;
      }
    }

    hilog.info(DOMAIN, TAG,
      'openAttachedPage load initial currentUrl=%{public}s activeSurface=%{public}s',
      this.currentUrl,
      this.webSurfaceKey);
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
    if (this.bookmarkHomeVisible && this.homeTabBackCountFromHost <= 0) {
      hilog.info(DOMAIN, TAG, 'ignore open home tab without stack');
      return;
    }
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
          return true;
        }
        this.loadTabInitialUrl(fallbackUrl);
        return false;
      }
    } catch (err) {
    }

    this.commitCurrentUrl(fallbackUrl);
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
        url: WEB_BOOKMARKS_HOME_URL,
        backCount: 0
      };
    }
    if (!this.isBrowserStateUrl(state.url)) {
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

  private isWebLoadableUrl(url: string): boolean {
    const value = url.trim();
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('file://') ||
      value.startsWith('resource://');
  }

  private isBrowserShortcutUrl(url: string): boolean {
    const value = url.trim();
    return value.startsWith('http://') || value.startsWith('https://');
  }

  private isExternalSchemeUrl(url: string): boolean {
    const value = url.trim();
    if (value.length === 0) {
      return false;
    }
    return !value.startsWith('http://') && !value.startsWith('https://') &&
      !value.startsWith('file://') && !value.startsWith('resource://') && !value.startsWith('about:');
  }

  private shouldShowWebErrorForActiveNavigation(surfaceKey: string, event: WebViewSurfaceLoadErrorEvent): boolean {
    const navigation = this.activeNavigationForSurface(surfaceKey);
    if (navigation === undefined || navigation.status !== 'loading') {
      return false;
    }
    return event.isMainFrame;
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
      return 'https://www.google.com/search?q=' + encodeURIComponent(input);
    }
    return 'https://' + input;
  }

  private stripHttpPrefix(value: string): string {
    const trimmed = value.trim();
    if (trimmed.startsWith('https://')) {
      return trimmed.substring(8);
    }
    if (trimmed.startsWith('http://')) {
      return trimmed.substring(7);
    }
    return trimmed;
  }

  private normalizeSuggestionQuery(value: string): string {
    return this.stripHttpPrefix(value).trim().toLowerCase();
  }

  private openAddressSuggestion(item: WebAddressSuggestionItem): void {
    const normalized = this.normalizeUrl(item.url);
    this.setAddressText(normalized);
    this.addressFocused = false;
    this.addressEditedSinceFocus = false;
    this.addressSuggestions = [];
    this.pendingManualHistoryUrl = normalized;
    this.loadUrl(normalized, 'address');
  }

  private deleteAddressSuggestionHistory(item: WebAddressSuggestionItem): void {
    if (item.kind !== 'history') {
      return;
    }
    const normalized = this.normalizeSuggestionUrl(item.url);
    if (normalized.length === 0) {
      return;
    }
    this.addressSuggestions = this.addressSuggestions.filter((entry: WebAddressSuggestionItem) => {
      return entry.kind !== 'history' || this.normalizeSuggestionUrl(entry.url) !== normalized;
    });
    const context = getContext(this) as common.UIAbilityContext;
    deleteWebHistoryUrl(context, normalized).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'delete web history failed: %{public}s', this.formatError(err));
      this.showNotice('删除历史失败：' + this.formatError(err));
      this.refreshAddressSuggestions();
    });
  }

  private refreshAddressSuggestions(): void {
    const loadVersion = ++this.addressSuggestionLoadVersion;
    if (!this.addressFocused || this.webFullScreen) {
      this.addressSuggestions = [];
      return;
    }

    const query = this.addressEditedSinceFocus ? this.normalizeSuggestionQuery(this.addressText) : '';
    const context = getContext(this) as common.UIAbilityContext;
    loadWebHistory(context, true).then((historyEntries) => {
      if (loadVersion !== this.addressSuggestionLoadVersion || !this.addressFocused || this.webFullScreen) {
        return;
      }
      this.addressSuggestions = this.buildHistorySuggestions(historyEntries, query);
    }).catch((err: BusinessError) => {
      if (loadVersion !== this.addressSuggestionLoadVersion || !this.addressFocused || this.webFullScreen) {
        return;
      }
      hilog.warn(DOMAIN, TAG, 'load web history failed: %{public}s', this.formatError(err));
      this.addressSuggestions = [];
    });
  }

  private buildHistorySuggestions(historyEntries: WebHistoryEntry[], query: string): WebAddressSuggestionItem[] {
    const items: WebAddressSuggestionItem[] = [];
    for (let index = 0; index < historyEntries.length; index++) {
      const entry = historyEntries[index];
      const normalizedUrl = this.normalizeSuggestionUrl(entry.url);
      if (!this.isBrowserShortcutUrl(normalizedUrl)) {
        continue;
      }
      const comparableUrl = this.normalizeSuggestionQuery(normalizedUrl);
      const comparableTitle = entry.title.trim().toLowerCase();
      if (query.length > 0 && comparableUrl.indexOf(query) < 0 && comparableTitle.indexOf(query) < 0) {
        continue;
      }
      const title = entry.title.trim();
      items.push({
        id: 'history_' + String(index) + '_' + normalizedUrl,
        kind: 'history',
        url: normalizedUrl,
        title: title,
        subtitle: normalizedUrl
      });
      if (items.length >= 8) {
        break;
      }
    }
    return items;
  }

  private normalizeSuggestionUrl(value: string): string {
    const input = value.trim();
    if (input.length === 0) {
      return '';
    }
    const candidate = input.startsWith('http://') || input.startsWith('https://') ? input : 'https://' + input;
    try {
      const parsed = url.URL.parseURL(candidate);
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
        return '';
      }
      if (parsed.hostname.trim().length === 0) {
        return '';
      }
      return parsed.toString();
    } catch (err) {
      return '';
    }
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

  private beginNavigation(surfaceKey: string, trigger: WebNavigationTrigger, url: string): void {
    const normalized = this.normalizeUrl(url);
    this.activeNavigation = {
      id: ++this.navigationSerial,
      surfaceKey: surfaceKey,
      trigger: trigger,
      requestedUrl: normalized,
      currentUrl: normalized,
      status: 'loading'
    };
  }

  private clearActiveNavigation(): void {
    this.activeNavigation = undefined;
  }

  private activeNavigationForSurface(surfaceKey: string): WebNavigationState | undefined {
    const navigation = this.activeNavigation;
    if (navigation === undefined || navigation.surfaceKey !== surfaceKey) {
      return undefined;
    }
    return navigation;
  }

  private describeActiveNavigation(surfaceKey: string): string {
    const navigation = this.activeNavigationForSurface(surfaceKey);
    if (navigation === undefined) {
      return 'none';
    }
    return 'id=' + String(navigation.id) +
      ',trigger=' + navigation.trigger +
      ',status=' + navigation.status +
      ',requested=' + navigation.requestedUrl +
      ',current=' + navigation.currentUrl;
  }

  private describeSurface(surface?: WebSurfaceEntry): string {
    if (surface === undefined) {
      return 'undefined';
    }
    return surface.surfaceKey +
      '{id=' + surface.id +
      ',attached=' + String(surface.attached) +
      ',initialized=' + String(surface.initialized) +
      ',visible=' + String(surface.visible) +
      ',scrollY=' + String(surface.scrollY) +
      '}';
  }

  private surfaceStateSnapshot(): string {
    const entries = this.webSurfaceRegistry.entries();
    if (entries.length === 0) {
      return '[]';
    }
    const parts: string[] = [];
    for (let index = 0; index < entries.length; index++) {
      parts.push(this.describeSurface(entries[index]));
    }
    return '[' + parts.join(';') + ']';
  }

  private safeControllerUrl(): string {
    if (!this.controllerAttached) {
      return 'detached';
    }
    try {
      return this.controller.getUrl();
    } catch (err) {
      return 'error:' + this.formatError(err);
    }
  }

  private updateActiveNavigationUrl(surfaceKey: string, url: string): void {
    const navigation = this.activeNavigationForSurface(surfaceKey);
    if (navigation === undefined || navigation.status !== 'loading' || !this.isBrowserStateUrl(url)) {
      return;
    }
    navigation.currentUrl = this.normalizeUrl(url);
  }

  private finishActiveNavigation(surfaceKey: string, url: string): void {
    const navigation = this.activeNavigationForSurface(surfaceKey);
    if (navigation === undefined || navigation.status !== 'loading') {
      return;
    }
    if (this.isBrowserStateUrl(url)) {
      navigation.currentUrl = this.normalizeUrl(url);
    }
    navigation.status = 'finished';
  }

  private failActiveNavigation(surfaceKey: string, url: string): void {
    const navigation = this.activeNavigationForSurface(surfaceKey);
    if (navigation === undefined) {
      return;
    }
    if (url.length > 0 && this.isBrowserStateUrl(url)) {
      navigation.currentUrl = this.normalizeUrl(url);
    }
    navigation.status = 'failed';
  }

  private isActiveNavigationFailed(surfaceKey: string): boolean {
    const navigation = this.activeNavigationForSurface(surfaceKey);
    return navigation !== undefined && navigation.status === 'failed';
  }

  private canStartPullRefreshWithoutOverScroll(surfaceKey: string): boolean {
    return this.webError.visible || this.isActiveNavigationFailed(surfaceKey);
  }
}
