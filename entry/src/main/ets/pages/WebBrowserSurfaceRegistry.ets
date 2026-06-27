import { webview } from '@kit.ArkWeb';
import { WebBrowserStateStore } from './WebBrowserStateStore';
import { PullRefreshState } from './WebBrowserTypes';
import { WebPullRefresh } from './WebPullRefresh';

const WEB_HOME_TAB_ID = 'smart_agent_web_app';

export interface WebSurfaceEntry {
  id: string;
  surfaceKey: string;
  controller: webview.WebviewController;
  attached: boolean;
  initialized: boolean;
  visible: boolean;
  scrollY: number;
  pullRefresh: PullRefreshState;
}

export class WebBrowserSurfaceRegistry {
  private serial: number = 0;
  private surfaces: WebSurfaceEntry[] = [];

  ensure(tabId: string): WebSurfaceEntry {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    const stateKey = id.length > 0 ? id : WEB_HOME_TAB_ID;
    for (let index = 0; index < this.surfaces.length; index++) {
      if (this.surfaces[index].id === stateKey) {
        return this.surfaces[index];
      }
    }
    return this.createSurface(stateKey);
  }

  reset(tabId: string): WebSurfaceEntry {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    const stateKey = id.length > 0 ? id : WEB_HOME_TAB_ID;
    const nextSurfaces: WebSurfaceEntry[] = [];
    for (let index = 0; index < this.surfaces.length; index++) {
      if (this.surfaces[index].id !== stateKey) {
        nextSurfaces.push(this.surfaces[index]);
      }
    }
    this.surfaces = nextSurfaces;
    return this.createSurface(stateKey);
  }

  private createSurface(stateKey: string): WebSurfaceEntry {
    const key = stateKey + '_' + (++this.serial).toString();
    const surface: WebSurfaceEntry = {
      id: stateKey,
      surfaceKey: key,
      controller: new webview.WebviewController(key),
      attached: false,
      initialized: false,
      visible: false,
      scrollY: 0,
      pullRefresh: WebPullRefresh.emptyState()
    };
    this.surfaces.push(surface);
    return surface;
  }

  byKey(surfaceKey: string): WebSurfaceEntry | undefined {
    for (let index = 0; index < this.surfaces.length; index++) {
      if (this.surfaces[index].surfaceKey === surfaceKey) {
        return this.surfaces[index];
      }
    }
    return undefined;
  }

  keys(): string[] {
    const keys: string[] = [];
    for (let index = 0; index < this.surfaces.length; index++) {
      keys.push(this.surfaces[index].surfaceKey);
    }
    return keys;
  }

  entries(): WebSurfaceEntry[] {
    const entries: WebSurfaceEntry[] = [];
    for (let index = 0; index < this.surfaces.length; index++) {
      entries.push(this.surfaces[index]);
    }
    return entries;
  }

  updateVisibility(activeSurfaceKey: string, bookmarkHomeVisible: boolean): void {
    for (let index = 0; index < this.surfaces.length; index++) {
      const surface = this.surfaces[index];
      surface.visible = !bookmarkHomeVisible && surface.surfaceKey === activeSurfaceKey;
    }
  }

}
