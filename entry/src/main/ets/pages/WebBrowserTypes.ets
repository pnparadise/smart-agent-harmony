export const CHROME_MOBILE_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

export interface WebBrowserErrorState {
  visible: boolean;
  url: string;
  title: string;
  detail: string;
  code: number;
  kind: string;
}

export type WebAddressSuggestionKind = 'history';

export interface WebAddressSuggestionItem {
  id: string;
  kind: WebAddressSuggestionKind;
  url: string;
  title: string;
  subtitle: string;
}

export interface PullRefreshState {
  refreshing: boolean;
  tracking: boolean;
  visible: boolean;
  settling: boolean;
  ready: boolean;
  distance: number;
  rotation: number;
  spinTimer: number;
  settleTimer: number;
  browserRefreshEnabled: boolean;
  probeSerial: number;
}

export interface WebTabState {
  id: string;
  url: string;
  backCount: number;
}

export interface BrowserInstance {
  id: string;
  kind: 'home' | 'bookmark';
  initialUrl: string;
  title: string;
  source?: 'bookmark-bar' | 'shortcut';
  bookmarkId?: string;
  shortcutId?: string;
  renderKey: string;
}
