import { WebBrowserStateStore } from './WebBrowserStateStore';
import { WebTabState } from './WebBrowserTypes';

export interface WebTabStateUpdate {
  state: WebTabState;
  states: WebTabState[];
}

export class WebBrowserTabModel {
  static tabBackCount(states: WebTabState[], tabId: string): number {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    for (let index = 0; index < states.length; index++) {
      if (states[index].id === id) {
        return Math.max(0, states[index].backCount);
      }
    }
    return 0;
  }

  static tabUrl(states: WebTabState[], tabId: string): string {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    for (let index = 0; index < states.length; index++) {
      if (states[index].id === id) {
        return states[index].url;
      }
    }
    return '';
  }

  static remove(states: WebTabState[], tabId: string): WebTabState[] {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    if (id.length === 0) {
      return states;
    }
    const next: WebTabState[] = [];
    for (let index = 0; index < states.length; index++) {
      if (states[index].id !== id) {
        next.push(states[index]);
      }
    }
    return next;
  }

  static upsert(states: WebTabState[], state: WebTabState): WebTabState[] {
    const id = WebBrowserStateStore.safeFileSegment(state.id);
    if (id.length === 0) {
      return states;
    }
    const normalizedState: WebTabState = {
      id: id,
      url: state.url,
      backCount: Math.max(0, state.backCount)
    };
    const next: WebTabState[] = [];
    let updated = false;
    for (let index = 0; index < states.length; index++) {
      if (states[index].id === id) {
        next.push(normalizedState);
        updated = true;
      } else {
        next.push(states[index]);
      }
    }
    if (!updated) {
      next.push(normalizedState);
    }
    return next;
  }

  static rememberCurrent(
    states: WebTabState[],
    tabId: string,
    currentUrl: string,
    bookmarkHomeVisible: boolean,
    homeTabId: string,
    defaultHomeUrl: string,
    backCount: number = -1
  ): WebTabStateUpdate {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    let url = currentUrl;
    if (bookmarkHomeVisible) {
      url = WebBrowserTabModel.tabUrl(states, id);
    }
    if (url.length === 0) {
      url = id === homeTabId ? defaultHomeUrl : currentUrl;
    }
    const count = backCount >= 0 ? backCount : WebBrowserTabModel.tabBackCount(states, id);
    const state: WebTabState = {
      id: id,
      url: url,
      backCount: Math.max(0, count)
    };
    return {
      state: state,
      states: WebBrowserTabModel.upsert(states, state)
    };
  }

}
