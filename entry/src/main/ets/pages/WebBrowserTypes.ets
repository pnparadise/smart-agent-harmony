export interface WebBrowserErrorState {
  visible: boolean;
  url: string;
  title: string;
  detail: string;
  code: number;
  kind: string;
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
  gestureLastOffsetY: number;
  gesturePullStartOffsetY: number;
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
