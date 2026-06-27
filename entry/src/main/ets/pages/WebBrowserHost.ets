import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_WEB_HOME_URL,
  hasWebShortcutMapping,
  loadWebBookmarks,
  WebBookmarkEntry
} from '../wireguard/ConfigStore';
import { publishWebShortcutClose } from '../entryability/WebShortcutCloseEvents';
import { PAGE_BACKGROUND } from './PageStyle';
import { WebBrowserPage } from './WebBrowserPage';
import { WebBrowserStateStore } from './WebBrowserStateStore';
import { BrowserInstance, WebTabState } from './WebBrowserTypes';

const DOMAIN = 0x0001;
const TAG = 'WebBrowserHost';
const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const WEB_SHORTCUT_ABILITY = 'WebShortcutAbility';
const WEB_SHORTCUT_URL_KEY = 'webUrl';
const WEB_SHORTCUT_ID_KEY = 'webShortcutId';
const WEB_HOME_INSTANCE_ID = 'smart_agent_web_app';
const WEB_STATIC_BROWSER_SHORTCUT_ID = 'smart_agent_web_static_browser';
const WEB_BOOKMARKS_HOME_URL = 'about:smart-bookmarks';
const WEB_BOOKMARKS_HOME_TAB_ID = 'smart_agent_web_bookmarks';

interface BrowserBackHandlerEntry {
  id: string;
  handler: () => boolean;
}

@Component
export struct WebBrowserHost {
  @Prop @Watch('onLaunchTargetChanged') initialUrl: string = DEFAULT_WEB_HOME_URL;
  @Prop @Watch('onLaunchTargetChanged') launchInstanceId: string = '';
  @Prop @Watch('onLaunchTargetChanged') launchRevision: number = 0;
  @StorageProp('webBrowserBackgroundPipRevision') private backgroundPipRevision: number = 0;
  onClose: () => void = () => {};
  onBackHandlerReady: (handler: () => boolean) => void = () => {};
  onBackHandlerRelease: () => void = () => {};
  @State private instances: BrowserInstance[] = [];
  @State private activeInstanceId: string = WEB_HOME_INSTANCE_ID;
  @State private bookmarkHomeVisible: boolean = false;
  @State private bookmarks: WebBookmarkEntry[] = [];
  @State private webTabStates: WebTabState[] = [];
  @State private tabStateRevision: number = 0;
  @State private clearTabStackRevision: number = 0;
  @State private clearTabStackTargetId: string = '';
  @State private clearTabStackFallbackUrl: string = '';
  @State private retainedShortcutInstanceIds: string[] = [];
  private backHandlers: BrowserBackHandlerEntry[] = [];
  private appeared: boolean = false;
  private pendingTabStateMerges: WebTabState[] = [];
  private pendingTabStateMergeTimer: number = -1;

  aboutToAppear(): void {
    this.appeared = true;
    const homeUrl = this.normalizeHomeInitialUrl(this.initialUrl);
    this.instances = [this.createHomeInstance(homeUrl)];
    this.activeInstanceId = WEB_HOME_INSTANCE_ID;
    this.bookmarkHomeVisible = this.shouldShowLaunchBookmarkHome(this.initialUrl);
    this.openLaunchInstanceIfNeeded(homeUrl);
    this.loadTabStates();
    this.loadBookmarks();
    this.onBackHandlerReady((): boolean => this.handleBackNavigation());
  }

  aboutToDisappear(): void {
    this.appeared = false;
    this.stopPendingTabStateMergeTimer();
    this.onBackHandlerRelease();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.instances, (instance: BrowserInstance) => {
        WebBrowserPage({
          initialUrl: instance.initialUrl,
          persistBrowserState: true,
          webControllerId: instance.id,
          instanceKind: instance.kind,
          hostActive: instance.id === this.activeInstanceId,
          backgroundPipRevisionFromHost: instance.id === this.activeInstanceId ? this.backgroundPipRevision : 0,
          isHomeInstance: instance.id === WEB_HOME_INSTANCE_ID,
          allowBookmarkHome: instance.id === WEB_HOME_INSTANCE_ID,
          showAddressBar: instance.id === WEB_HOME_INSTANCE_ID,
          bookmarkHomeVisibleFromHost: this.bookmarkHomeVisible && instance.id === WEB_HOME_INSTANCE_ID,
          homeTabBackCountFromHost: this.tabBackCount(WEB_HOME_INSTANCE_ID),
          tabStateRevisionFromHost: this.tabStateRevision,
          clearTabStackRevisionFromHost: this.clearTabStackRevision,
          clearTabStackTargetIdFromHost: this.clearTabStackTargetId,
          clearTabStackFallbackUrlFromHost: this.clearTabStackFallbackUrl,
          tabBackCountFromHost: (bookmarkId: string): number => this.tabBackCount(bookmarkId),
          onClose: () => {
            this.onClose();
          },
          onBackHandlerReady: (handler: () => boolean) => {
            this.setBackHandler(instance.id, handler);
          },
          onBackHandlerRelease: () => {
            this.removeBackHandler(instance.id);
          },
          onOpenBookmarkHome: () => {
            this.openDefaultBookmarkAbility();
          },
          onOpenHomeInstance: () => {
            this.openHomeInstance();
          },
          onOpenBookmarkInstance: (bookmark: WebBookmarkEntry) => {
            this.openBookmarkInstance(bookmark);
          },
          onClearInstanceTabStack: (instanceId: string, fallbackUrl: string) => {
            this.clearInstanceTabStack(instanceId, fallbackUrl);
          },
          onClearAllBookmarkStacks: () => {
            this.clearAllBookmarkStacks();
          },
          onCloseBookmarkInstance: (bookmark: WebBookmarkEntry) => {
            this.closeBookmarkInstanceFromBadge(bookmark);
          },
          onBookmarkDeleted: (bookmark: WebBookmarkEntry) => {
            this.closeBookmarkInstanceIfUnlinked(bookmark);
          },
          onBookmarksChanged: () => {
            this.loadBookmarks();
          },
          onTabStateChanged: (state: WebTabState) => {
            this.handleTabStateChanged(state);
          }
        })
          .width('100%')
          .height('100%')
          .visibility(instance.id === this.activeInstanceId ? Visibility.Visible : Visibility.Hidden)
          .zIndex(instance.id === this.activeInstanceId ? 2 : 0)
      }, (instance: BrowserInstance) => instance.renderKey)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(PAGE_BACKGROUND)
  }

  private handleBackNavigation(): boolean {
    const handler = this.activeBackHandler();
    if (handler !== undefined) {
      return handler();
    }
    this.onClose();
    return true;
  }

  private setBackHandler(instanceId: string, handler: () => boolean): void {
    const id = this.safeFileSegment(instanceId);
    const next: BrowserBackHandlerEntry[] = [];
    let updated = false;
    for (let index = 0; index < this.backHandlers.length; index++) {
      const entry = this.backHandlers[index];
      if (entry.id === id) {
        next.push({ id: id, handler: handler });
        updated = true;
      } else {
        next.push(entry);
      }
    }
    if (!updated) {
      next.push({ id: id, handler: handler });
    }
    this.backHandlers = next;
  }

  private removeBackHandler(instanceId: string): void {
    const id = this.safeFileSegment(instanceId);
    const next: BrowserBackHandlerEntry[] = [];
    for (let index = 0; index < this.backHandlers.length; index++) {
      if (this.backHandlers[index].id !== id) {
        next.push(this.backHandlers[index]);
      }
    }
    this.backHandlers = next;
  }

  private activeBackHandler(): (() => boolean) | undefined {
    const id = this.safeFileSegment(this.activeInstanceId);
    for (let index = 0; index < this.backHandlers.length; index++) {
      const entry = this.backHandlers[index];
      if (entry.id === id) {
        return entry.handler;
      }
    }
    return undefined;
  }

  private createHomeInstance(initialUrl: string): BrowserInstance {
    return {
      id: WEB_HOME_INSTANCE_ID,
      kind: 'home',
      initialUrl: initialUrl,
      title: 'Browser',
      renderKey: WEB_HOME_INSTANCE_ID
    };
  }

  private createBookmarkInstance(bookmark: WebBookmarkEntry): BrowserInstance {
    return {
      id: this.safeFileSegment(bookmark.id),
      kind: 'bookmark',
      initialUrl: this.bookmarkInitialUrl(bookmark),
      title: bookmark.title,
      source: 'bookmark-bar',
      bookmarkId: this.safeFileSegment(bookmark.id),
      renderKey: this.safeFileSegment(bookmark.id)
    };
  }

  private createShortcutBookmarkInstance(instanceId: string, initialUrl: string): BrowserInstance {
    const id = this.safeFileSegment(instanceId);
    return {
      id: id,
      kind: 'bookmark',
      initialUrl: this.bookmarkInstanceInitialUrl(id, initialUrl),
      title: 'Browser',
      source: 'shortcut',
      bookmarkId: id,
      shortcutId: id,
      renderKey: id
    };
  }

  private openLaunchInstanceIfNeeded(homeUrl: string): void {
    const id = this.safeFileSegment(this.launchInstanceId);
    if (id.length === 0 || id === WEB_HOME_INSTANCE_ID) {
      return;
    }
    this.openLaunchInstance(id, this.isBookmarkHomeUrl(this.initialUrl) ? homeUrl : this.normalizeUrl(this.initialUrl));
  }

  private onLaunchTargetChanged(): void {
    if (!this.appeared) {
      return;
    }
    const id = this.safeFileSegment(this.launchInstanceId);
    if (id.length === 0) {
      return;
    }
    if (id === WEB_HOME_INSTANCE_ID) {
      if (this.isBookmarkHomeUrl(this.initialUrl)) {
        if (this.shouldShowLaunchBookmarkHome(this.initialUrl)) {
          this.openBookmarkHome();
          return;
        }
        this.openHomeInstance();
        this.updateHomeInitialUrl(this.normalizeHomeInitialUrl(this.initialUrl));
        this.loadTabStates();
        return;
      }
      this.openHomeInstance();
      this.updateHomeInitialUrl(this.normalizeUrl(this.initialUrl));
      return;
    }
    const url = this.isBookmarkHomeUrl(this.initialUrl) ? DEFAULT_WEB_HOME_URL : this.normalizeUrl(this.initialUrl);
    this.openLaunchInstance(id, url);
  }

  private openLaunchInstance(instanceId: string, initialUrl: string): void {
    const id = this.safeFileSegment(instanceId);
    if (id.length === 0 || id === WEB_HOME_INSTANCE_ID) {
      return;
    }
    if (!this.hasInstance(id)) {
      const next = this.instances.slice();
      next.push(this.createShortcutBookmarkInstance(id, initialUrl));
      this.instances = next;
    }
    this.activeInstanceId = id;
    this.bookmarkHomeVisible = false;
    this.rememberShortcutLinkedInstance(id);
    this.loadTabStates();
  }

  private normalizeHomeInitialUrl(initialUrl: string): string {
    if (this.isBookmarkHomeUrl(initialUrl)) {
      const restoredUrl = this.restoredHomeUrl();
      if (restoredUrl.length > 0) {
        return restoredUrl;
      }
      return WEB_BOOKMARKS_HOME_URL;
    }
    return this.normalizeUrl(initialUrl);
  }

  private shouldShowLaunchBookmarkHome(initialUrl: string): boolean {
    return this.isBookmarkHomeUrl(initialUrl) && !this.hasRestorableHomeStack();
  }

  private hasRestorableHomeStack(): boolean {
    return this.restoredHomeUrl().length > 0;
  }

  private restoredHomeUrl(): string {
    const state = this.webStateStore().readTabStateMeta(WEB_HOME_INSTANCE_ID, '');
    if (this.isWebLoadableUrl(state.url)) {
      return this.normalizeUrl(state.url);
    }
    return '';
  }

  private updateHomeInitialUrl(url: string): void {
    const normalized = this.normalizeUrl(url);
    const next: BrowserInstance[] = [];
    for (let index = 0; index < this.instances.length; index++) {
      const instance = this.instances[index];
      if (instance.id === WEB_HOME_INSTANCE_ID) {
        next.push({
          id: instance.id,
          kind: instance.kind,
          initialUrl: normalized,
          title: instance.title,
          source: instance.source,
          bookmarkId: instance.bookmarkId,
          shortcutId: instance.shortcutId,
          renderKey: instance.renderKey
        });
      } else {
        next.push(instance);
      }
    }
    this.instances = next;
  }

  private openBookmarkHome(): void {
    this.activeInstanceId = WEB_HOME_INSTANCE_ID;
    this.bookmarkHomeVisible = true;
    this.loadBookmarks();
    this.loadTabStates();
  }

  private openDefaultBookmarkAbility(): void {
    if (this.activeInstanceId === WEB_HOME_INSTANCE_ID) {
      this.openBookmarkHome();
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    context.startAbility(this.buildDefaultBookmarkWant()).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'start default bookmark ability failed: %{public}s',
        err.message ?? JSON.stringify(err));
      this.openBookmarkHome();
    });
  }

  private buildDefaultBookmarkWant(): Want {
    const want: Want = {
      bundleName: BUNDLE_NAME,
      moduleName: MODULE_NAME,
      abilityName: WEB_SHORTCUT_ABILITY,
      parameters: {
        openWeb: '1'
      }
    };
    if (want.parameters !== undefined) {
      want.parameters[WEB_SHORTCUT_URL_KEY] = WEB_BOOKMARKS_HOME_URL;
      want.parameters[WEB_SHORTCUT_ID_KEY] = WEB_STATIC_BROWSER_SHORTCUT_ID;
    }
    return want;
  }

  private openHomeInstance(): void {
    this.activeInstanceId = WEB_HOME_INSTANCE_ID;
    this.bookmarkHomeVisible = false;
  }

  private openBookmarkInstance(bookmark: WebBookmarkEntry): void {
    const id = this.safeFileSegment(bookmark.id);
    if (id.length === 0) {
      return;
    }
    if (this.activeInstanceId !== id && this.activeInstanceId === WEB_HOME_INSTANCE_ID) {
      this.startBookmarkAbility(bookmark, id);
      return;
    }
    if (!this.hasInstance(id)) {
      const next = this.instances.slice();
      next.push(this.createBookmarkInstance(bookmark));
      this.instances = next;
    }
    this.activeInstanceId = id;
    this.bookmarkHomeVisible = false;
  }

  private startBookmarkAbility(bookmark: WebBookmarkEntry, shortcutId: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    context.startAbility(this.buildBookmarkWant(bookmark, shortcutId)).then(() => {
      this.bookmarkHomeVisible = false;
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'start bookmark ability failed id=%{public}s: %{public}s',
        shortcutId,
        err.message ?? JSON.stringify(err)
      );
      this.openBookmarkInstanceLocally(bookmark, shortcutId);
    });
  }

  private openBookmarkInstanceLocally(bookmark: WebBookmarkEntry, shortcutId: string): void {
    const id = this.safeFileSegment(shortcutId);
    if (id.length === 0) {
      return;
    }
    if (!this.hasInstance(id)) {
      const next = this.instances.slice();
      next.push(this.createBookmarkInstance(bookmark));
      this.instances = next;
    }
    this.activeInstanceId = id;
    this.bookmarkHomeVisible = false;
  }

  private buildBookmarkWant(bookmark: WebBookmarkEntry, shortcutId: string): Want {
    const want: Want = {
      bundleName: BUNDLE_NAME,
      moduleName: MODULE_NAME,
      abilityName: WEB_SHORTCUT_ABILITY,
      parameters: {
        openWeb: '1'
      }
    };
    if (want.parameters !== undefined) {
      want.parameters[WEB_SHORTCUT_URL_KEY] = bookmark.url;
      want.parameters[WEB_SHORTCUT_ID_KEY] = shortcutId;
    }
    return want;
  }

  private closeBookmarkInstance(bookmarkId: string): void {
    const id = this.safeFileSegment(bookmarkId);
    if (id.length === 0 || id === WEB_HOME_INSTANCE_ID) {
      return;
    }
    const next: BrowserInstance[] = [];
    for (let index = 0; index < this.instances.length; index++) {
      if (this.instances[index].id !== id) {
        next.push(this.instances[index]);
      }
    }
    this.instances = next;
    this.removeTabState(id);
    this.webStateStore().truncateWebState(id);
    if (this.activeInstanceId === id) {
      this.activeInstanceId = WEB_HOME_INSTANCE_ID;
      this.bookmarkHomeVisible = true;
    }
  }

  private closeBookmarkInstanceFromBadge(bookmark: WebBookmarkEntry): void {
    const id = this.safeFileSegment(bookmark.id);
    if (id.length === 0 || id === WEB_HOME_INSTANCE_ID) {
      return;
    }

    const next: BrowserInstance[] = [];
    for (let index = 0; index < this.instances.length; index++) {
      if (this.instances[index].id !== id) {
        next.push(this.instances[index]);
      }
    }
    if (next.length !== this.instances.length) {
      this.instances = next;
      this.removeBackHandler(id);
    }
    if (this.activeInstanceId === id) {
      this.activeInstanceId = WEB_HOME_INSTANCE_ID;
      this.bookmarkHomeVisible = true;
    }
    this.clearBookmarkInstanceState(id, bookmark.url);
    publishWebShortcutClose(id);
    setTimeout(() => {
      this.clearBookmarkInstanceState(id, bookmark.url);
    }, 120);
  }

  private closeBookmarkInstanceIfUnlinked(bookmark: WebBookmarkEntry): void {
    const id = this.safeFileSegment(bookmark.id);
    if (id.length === 0) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    hasWebShortcutMapping(context, id, true).then((hasMapping: boolean) => {
      if (!hasMapping) {
        this.closeBookmarkInstance(id);
        this.forgetShortcutLinkedInstance(id);
      } else {
        this.rememberShortcutLinkedInstance(id);
      }
      this.loadBookmarks();
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'check shortcut mapping failed: %{public}s', err.message ?? JSON.stringify(err));
      this.rememberShortcutLinkedInstance(id);
      this.loadBookmarks();
    });
  }

  private clearInstanceTabStack(instanceId: string, fallbackUrl: string): void {
    const id = this.safeFileSegment(instanceId);
    if (id.length === 0) {
      return;
    }
    const fallback = this.tabFallbackUrl(id, fallbackUrl);
    hilog.info(DOMAIN, TAG,
      'clear instance tab stack id=%{public}s fallback=%{public}s active=%{public}s bookmarkHomeVisible=%{public}s backCount=%{public}d states=%{public}s',
      id,
      fallback,
      this.activeInstanceId,
      String(this.bookmarkHomeVisible),
      this.tabBackCount(id),
      this.describeTabStates());
    this.removePendingTabStateMerge(id);
    const state: WebTabState = {
      id: id,
      url: this.normalizeUrl(fallback),
      backCount: 0
    };
    this.mergeTabState(state);
    hilog.info(DOMAIN, TAG,
      'clear instance tab stack merged id=%{public}s states=%{public}s',
      id,
      this.describeTabStates());
    this.webStateStore().persistTabState(state);
    this.webStateStore().truncateWebState(id);
    if (id !== WEB_BOOKMARKS_HOME_TAB_ID) {
      this.requestControllerHistoryClear(id, fallback);
    }
  }

  private requestControllerHistoryClear(instanceId: string, fallbackUrl: string): void {
    this.clearTabStackTargetId = instanceId;
    this.clearTabStackFallbackUrl = this.normalizeUrl(fallbackUrl);
    this.clearTabStackRevision++;
    hilog.info(DOMAIN, TAG,
      'request controller history clear id=%{public}s fallback=%{public}s revision=%{public}d active=%{public}s bookmarkHomeVisible=%{public}s',
      this.clearTabStackTargetId,
      this.clearTabStackFallbackUrl,
      this.clearTabStackRevision,
      this.activeInstanceId,
      String(this.bookmarkHomeVisible));
  }

  private clearAllBookmarkStacks(): void {
    if (this.tabBackCount(WEB_HOME_INSTANCE_ID) > 0) {
      this.clearInstanceTabStack(WEB_HOME_INSTANCE_ID, DEFAULT_WEB_HOME_URL);
    }
    const targets: WebBookmarkEntry[] = [];
    for (let index = 0; index < this.bookmarks.length; index++) {
      const bookmark = this.bookmarks[index];
      if (this.tabBackCount(bookmark.id) > 0) {
        targets.push(bookmark);
      }
    }
    if (targets.length === 0) {
      this.loadTabStates();
      return;
    }
    for (let index = 0; index < targets.length; index++) {
      this.closeBookmarkInstanceFromBadge(targets[index]);
    }
    this.loadTabStates();
  }

  private clearBookmarkInstanceState(instanceId: string, fallbackUrl: string): void {
    const id = this.safeFileSegment(instanceId);
    if (id.length === 0) {
      return;
    }
    const state: WebTabState = {
      id: id,
      url: this.normalizeUrl(fallbackUrl),
      backCount: 0
    };
    this.mergeTabState(state);
    this.webStateStore().persistTabState(state);
    this.webStateStore().truncateWebState(id);
  }

  private loadBookmarks(): void {
    const context = getContext(this) as common.UIAbilityContext;
    loadWebBookmarks(context, true).then((bookmarks: WebBookmarkEntry[]) => {
      this.bookmarks = bookmarks;
      this.loadTabStates();
      this.closeDeletedBookmarkInstances(bookmarks);
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'load bookmarks failed: %{public}s', err.message ?? JSON.stringify(err));
    });
  }

  private closeDeletedBookmarkInstances(bookmarks: WebBookmarkEntry[]): void {
    const next: BrowserInstance[] = [];
    const removedBookmarkIds: string[] = [];
    for (let index = 0; index < this.instances.length; index++) {
      const instance = this.instances[index];
      if (instance.kind !== 'bookmark' || this.hasBookmarkId(bookmarks, instance.id)) {
        next.push(instance);
      } else if (this.hasRetainedShortcutInstanceId(instance.id)) {
        next.push(instance);
      } else {
        removedBookmarkIds.push(instance.id);
      }
    }
    if (next.length !== this.instances.length) {
      this.instances = next;
      if (!this.hasInstance(this.activeInstanceId)) {
        this.activeInstanceId = WEB_HOME_INSTANCE_ID;
        this.bookmarkHomeVisible = true;
      }
      this.restoreShortcutLinkedInstances(removedBookmarkIds);
    }
  }

  private restoreShortcutLinkedInstances(instanceIds: string[]): void {
    const context = getContext(this) as common.UIAbilityContext;
    for (let index = 0; index < instanceIds.length; index++) {
      const id = this.safeFileSegment(instanceIds[index]);
      if (id.length === 0) {
        continue;
      }
      hasWebShortcutMapping(context, id, true).then((hasMapping: boolean) => {
        if (!hasMapping || this.hasInstance(id)) {
          return;
        }
        this.rememberShortcutLinkedInstance(id);
        const state = this.webStateStore().readTabStateMeta(id, DEFAULT_WEB_HOME_URL);
        const next = this.instances.slice();
        next.push(this.createShortcutBookmarkInstance(id, state.url));
        this.instances = next;
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'restore shortcut linked instance failed: %{public}s',
          err.message ?? JSON.stringify(err));
      });
    }
  }

  private loadTabStates(): void {
    const states: WebTabState[] = [];
    states.push(this.webStateStore().readTabStateMeta(WEB_HOME_INSTANCE_ID, DEFAULT_WEB_HOME_URL));
    states.push(this.webStateStore().readTabStateMeta(WEB_BOOKMARKS_HOME_TAB_ID, WEB_BOOKMARKS_HOME_URL));
    for (let index = 0; index < this.bookmarks.length; index++) {
      const bookmark = this.bookmarks[index];
      states.push(this.webStateStore().readTabStateMeta(bookmark.id, bookmark.url));
    }
    hilog.info(DOMAIN, TAG,
      'loadTabStates count=%{public}d active=%{public}s bookmarkHomeVisible=%{public}s',
      states.length,
      this.activeInstanceId,
      String(this.bookmarkHomeVisible));
    this.webTabStates = states;
    this.bumpTabStateRevision();
  }

  private handleTabStateChanged(state: WebTabState): void {
    const id = this.safeFileSegment(state.id);
    if (id.length === 0) {
      return;
    }
    const nextState: WebTabState = {
      id: id,
      url: state.url,
      backCount: Math.max(0, state.backCount)
    };
    if (!this.shouldMergeTabState(nextState)) {
      hilog.info(DOMAIN, TAG,
        'skip tab state merge unchanged id=%{public}s url=%{public}s backCount=%{public}d states=%{public}s',
        nextState.id,
        nextState.url,
        nextState.backCount,
        this.describeTabStates());
      return;
    }
    this.enqueueTabStateMerge(nextState);
  }

  private enqueueTabStateMerge(state: WebTabState): void {
    const next: WebTabState[] = [];
    let updated = false;
    for (let index = 0; index < this.pendingTabStateMerges.length; index++) {
      const pending = this.pendingTabStateMerges[index];
      if (pending.id === state.id) {
        next.push(state);
        updated = true;
      } else {
        next.push(pending);
      }
    }
    if (!updated) {
      next.push(state);
    }
    this.pendingTabStateMerges = next;
    hilog.info(DOMAIN, TAG,
      'defer tab state merge id=%{public}s url=%{public}s backCount=%{public}d active=%{public}s bookmarkHomeVisible=%{public}s',
      state.id,
      state.url,
      state.backCount,
      this.activeInstanceId,
      String(this.bookmarkHomeVisible));
    if (this.pendingTabStateMergeTimer >= 0) {
      return;
    }
    this.pendingTabStateMergeTimer = setTimeout(() => {
      this.flushPendingTabStateMerges();
    }, 0);
  }

  private flushPendingTabStateMerges(): void {
    this.pendingTabStateMergeTimer = -1;
    if (!this.appeared) {
      this.pendingTabStateMerges = [];
      hilog.info(DOMAIN, TAG, 'skip deferred tab state merges host disappeared');
      return;
    }
    const pending = this.pendingTabStateMerges;
    this.pendingTabStateMerges = [];
    for (let index = 0; index < pending.length; index++) {
      const state = pending[index];
      if (!this.shouldMergeTabState(state)) {
        continue;
      }
      hilog.info(DOMAIN, TAG,
        'flush deferred tab state merge id=%{public}s url=%{public}s backCount=%{public}d active=%{public}s bookmarkHomeVisible=%{public}s',
        state.id,
        state.url,
        state.backCount,
        this.activeInstanceId,
        String(this.bookmarkHomeVisible));
      this.mergeTabState(state);
    }
  }

  private stopPendingTabStateMergeTimer(): void {
    if (this.pendingTabStateMergeTimer >= 0) {
      clearTimeout(this.pendingTabStateMergeTimer);
      this.pendingTabStateMergeTimer = -1;
    }
    this.pendingTabStateMerges = [];
  }

  private removePendingTabStateMerge(tabId: string): void {
    const id = this.safeFileSegment(tabId);
    if (id.length === 0 || this.pendingTabStateMerges.length === 0) {
      return;
    }
    const next: WebTabState[] = [];
    const before = this.pendingTabStateMerges.length;
    for (let index = 0; index < this.pendingTabStateMerges.length; index++) {
      if (this.pendingTabStateMerges[index].id !== id) {
        next.push(this.pendingTabStateMerges[index]);
      }
    }
    this.pendingTabStateMerges = next;
    hilog.info(DOMAIN, TAG,
      'remove pending tab state merge id=%{public}s before=%{public}d after=%{public}d',
      id,
      before,
      this.pendingTabStateMerges.length);
  }

  private shouldMergeTabState(state: WebTabState): boolean {
    for (let index = 0; index < this.webTabStates.length; index++) {
      const current = this.webTabStates[index];
      if (current.id === state.id) {
        return current.url !== state.url || current.backCount !== Math.max(0, state.backCount);
      }
    }
    return true;
  }

  private mergeTabState(state: WebTabState): void {
    const id = this.safeFileSegment(state.id);
    if (id.length === 0) {
      return;
    }
    hilog.info(DOMAIN, TAG,
      'mergeTabState id=%{public}s url=%{public}s backCount=%{public}d active=%{public}s bookmarkHomeVisible=%{public}s',
      id,
      state.url,
      state.backCount,
      this.activeInstanceId,
      String(this.bookmarkHomeVisible));
    const next: WebTabState[] = [];
    let updated = false;
    for (let index = 0; index < this.webTabStates.length; index++) {
      if (this.webTabStates[index].id === id) {
        next.push({
          id: id,
          url: state.url,
          backCount: Math.max(0, state.backCount)
        });
        updated = true;
      } else {
        next.push(this.webTabStates[index]);
      }
    }
    if (!updated) {
      next.push({
        id: id,
        url: state.url,
        backCount: Math.max(0, state.backCount)
      });
    }
    this.webTabStates = next;
    this.bumpTabStateRevision();
  }

  private removeTabState(tabId: string): void {
    const id = this.safeFileSegment(tabId);
    hilog.info(DOMAIN, TAG,
      'removeTabState id=%{public}s active=%{public}s bookmarkHomeVisible=%{public}s',
      id,
      this.activeInstanceId,
      String(this.bookmarkHomeVisible));
    const next: WebTabState[] = [];
    for (let index = 0; index < this.webTabStates.length; index++) {
      if (this.webTabStates[index].id !== id) {
        next.push(this.webTabStates[index]);
      }
    }
    this.webTabStates = next;
    this.bumpTabStateRevision();
  }

  private bumpTabStateRevision(): void {
    this.tabStateRevision++;
    hilog.info(DOMAIN, TAG,
      'bumpTabStateRevision revision=%{public}d active=%{public}s bookmarkHomeVisible=%{public}s',
      this.tabStateRevision,
      this.activeInstanceId,
      String(this.bookmarkHomeVisible));
  }

  private bookmarkInitialUrl(bookmark: WebBookmarkEntry): string {
    return this.bookmarkInstanceInitialUrl(bookmark.id, bookmark.url);
  }

  private bookmarkInstanceInitialUrl(instanceId: string, fallbackUrl: string): string {
    const state = this.webStateStore().readTabStateMeta(instanceId, fallbackUrl);
    if (state.url.length > 0 && !this.isBookmarkHomeUrl(state.url)) {
      return this.normalizeUrl(state.url);
    }
    return this.normalizeUrl(fallbackUrl);
  }

  private tabBackCount(tabId: string): number {
    const id = this.safeFileSegment(tabId);
    for (let index = 0; index < this.webTabStates.length; index++) {
      if (this.webTabStates[index].id === id) {
        return Math.max(0, this.webTabStates[index].backCount);
      }
    }
    return 0;
  }

  private homeInstanceFallbackUrl(fallbackUrl: string): string {
    if (this.isBookmarkHomeUrl(fallbackUrl)) {
      return WEB_BOOKMARKS_HOME_URL;
    }
    if (this.isWebLoadableUrl(fallbackUrl)) {
      return this.normalizeUrl(fallbackUrl);
    }
    const stored = this.tabUrl(WEB_HOME_INSTANCE_ID);
    if (this.isWebLoadableUrl(stored)) {
      return this.normalizeUrl(stored);
    }
    return WEB_BOOKMARKS_HOME_URL;
  }

  private tabFallbackUrl(tabId: string, fallbackUrl: string): string {
    if (tabId === WEB_BOOKMARKS_HOME_TAB_ID) {
      return WEB_BOOKMARKS_HOME_URL;
    }
    if (tabId === WEB_HOME_INSTANCE_ID) {
      return this.homeInstanceFallbackUrl(fallbackUrl);
    }
    return fallbackUrl;
  }

  private tabUrl(tabId: string): string {
    const id = this.safeFileSegment(tabId);
    for (let index = 0; index < this.webTabStates.length; index++) {
      if (this.webTabStates[index].id === id) {
        return this.webTabStates[index].url;
      }
    }
    return '';
  }

  private describeTabStates(): string {
    if (this.webTabStates.length === 0) {
      return '[]';
    }
    const parts: string[] = [];
    for (let index = 0; index < this.webTabStates.length; index++) {
      const state = this.webTabStates[index];
      parts.push(state.id + ':' + state.url + '#' + String(state.backCount));
    }
    return '[' + parts.join(';') + ']';
  }

  private hasInstance(instanceId: string): boolean {
    const id = this.safeFileSegment(instanceId);
    for (let index = 0; index < this.instances.length; index++) {
      if (this.instances[index].id === id) {
        return true;
      }
    }
    return false;
  }

  private rememberShortcutLinkedInstance(instanceId: string): void {
    const id = this.safeFileSegment(instanceId);
    if (id.length === 0 || this.hasRetainedShortcutInstanceId(id)) {
      return;
    }
    const next = this.retainedShortcutInstanceIds.slice();
    next.push(id);
    this.retainedShortcutInstanceIds = next;
  }

  private forgetShortcutLinkedInstance(instanceId: string): void {
    const id = this.safeFileSegment(instanceId);
    const next: string[] = [];
    for (let index = 0; index < this.retainedShortcutInstanceIds.length; index++) {
      if (this.retainedShortcutInstanceIds[index] !== id) {
        next.push(this.retainedShortcutInstanceIds[index]);
      }
    }
    this.retainedShortcutInstanceIds = next;
  }

  private hasRetainedShortcutInstanceId(instanceId: string): boolean {
    const id = this.safeFileSegment(instanceId);
    for (let index = 0; index < this.retainedShortcutInstanceIds.length; index++) {
      if (this.retainedShortcutInstanceIds[index] === id) {
        return true;
      }
    }
    return false;
  }

  private hasBookmarkId(bookmarks: WebBookmarkEntry[], bookmarkId: string): boolean {
    const id = this.safeFileSegment(bookmarkId);
    for (let index = 0; index < bookmarks.length; index++) {
      if (this.safeFileSegment(bookmarks[index].id) === id) {
        return true;
      }
    }
    return false;
  }

  private isBookmarkHomeUrl(url: string): boolean {
    return url.trim() === 'about:smart-bookmarks';
  }

  private isWebLoadableUrl(url: string): boolean {
    const value = url.trim();
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('file://') ||
      value.startsWith('resource://');
  }

  private normalizeUrl(raw: string): string {
    const value = raw.trim();
    if (value.length === 0) {
      return DEFAULT_WEB_HOME_URL;
    }
    if (value.indexOf('://') >= 0 || value.startsWith('about:')) {
      return value;
    }
    if (value.indexOf('.') >= 0 && value.indexOf(' ') < 0) {
      return 'https://' + value;
    }
    return 'https://www.google.com/search?q=' + encodeURIComponent(value);
  }

  private webStateStore(): WebBrowserStateStore {
    return new WebBrowserStateStore(getContext(this) as common.UIAbilityContext);
  }

  private safeFileSegment(value: string): string {
    return WebBrowserStateStore.safeFileSegment(value);
  }
}
