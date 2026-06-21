import { PullRefreshState } from './WebBrowserTypes';

const TOUCH_REFRESH_DISTANCE = 112;
const PULL_REFRESH_START_THRESHOLD = 24;
const PULL_REFRESH_MAX_DISTANCE = 128;
const PULL_REFRESH_INDICATOR_SIZE = 42;
const PULL_REFRESH_REFRESHING_OFFSET = 32;
const PULL_REFRESH_READY_PROGRESS = 100;

export class WebPullRefresh {
  static refreshDistance(): number {
    return TOUCH_REFRESH_DISTANCE;
  }

  static emptyState(): PullRefreshState {
    return {
      refreshing: false,
      tracking: false,
      visible: false,
      settling: false,
      ready: false,
      distance: 0,
      rotation: 0,
      spinTimer: -1,
      settleTimer: -1,
      browserRefreshEnabled: true,
      probeSerial: 0,
      gestureLastOffsetY: 0,
      gesturePullStartOffsetY: 0,
      gestureOverScrollActive: false
    };
  }

  static shouldShowIndicator(pullRefresh: PullRefreshState): boolean {
    return pullRefresh.visible || pullRefresh.refreshing || pullRefresh.settling;
  }

  static isRefreshing(pullRefresh: PullRefreshState): boolean {
    return pullRefresh.refreshing;
  }

  static activeRotation(pullRefresh: PullRefreshState): number {
    return pullRefresh.refreshing ? pullRefresh.rotation : WebPullRefresh.dragRotation(pullRefresh);
  }

  static indicatorOffset(pullRefresh: PullRefreshState): number {
    if (pullRefresh.refreshing) {
      return PULL_REFRESH_REFRESHING_OFFSET;
    }
    return Math.max(-PULL_REFRESH_INDICATOR_SIZE, pullRefresh.distance - PULL_REFRESH_INDICATOR_SIZE);
  }

  static distance(pullRefresh: PullRefreshState): number {
    return pullRefresh.distance;
  }

  static update(pullRefresh: PullRefreshState, deltaFromStart: number): void {
    const distance = Math.min(Math.max(0, deltaFromStart - PULL_REFRESH_START_THRESHOLD), PULL_REFRESH_MAX_DISTANCE);
    pullRefresh.distance = distance;
    pullRefresh.visible = distance > 6;
    pullRefresh.ready = pullRefresh.ready || distance >= TOUCH_REFRESH_DISTANCE;
  }

  static reset(pullRefresh: PullRefreshState): void {
    WebPullRefresh.stopSettle(pullRefresh);
    pullRefresh.tracking = false;
    pullRefresh.visible = false;
    pullRefresh.settling = false;
    pullRefresh.ready = false;
    pullRefresh.distance = 0;
    pullRefresh.rotation = 0;
    pullRefresh.gestureLastOffsetY = 0;
    pullRefresh.gesturePullStartOffsetY = 0;
    pullRefresh.gestureOverScrollActive = false;
  }

  static cancel(pullRefresh: PullRefreshState, onChanged: () => void): void {
    if (!pullRefresh.visible) {
      WebPullRefresh.reset(pullRefresh);
      onChanged();
      return;
    }
    pullRefresh.tracking = false;
    pullRefresh.visible = true;
    pullRefresh.settling = true;
    pullRefresh.ready = false;
    pullRefresh.distance = 0;
    WebPullRefresh.stopSettle(pullRefresh);
    pullRefresh.settleTimer = setTimeout(() => {
      pullRefresh.visible = false;
      pullRefresh.settling = false;
      pullRefresh.rotation = 0;
      pullRefresh.settleTimer = -1;
      onChanged();
    }, 180);
    onChanged();
  }

  static beginTracking(pullRefresh: PullRefreshState, pullStartOffsetY: number = 0): void {
    if (!pullRefresh.refreshing) {
      WebPullRefresh.reset(pullRefresh);
    }
    WebPullRefresh.stopSettle(pullRefresh);
    pullRefresh.settling = false;
    pullRefresh.tracking = true;
    pullRefresh.gestureLastOffsetY = pullStartOffsetY;
    pullRefresh.gesturePullStartOffsetY = pullStartOffsetY;
    pullRefresh.gestureOverScrollActive = true;
  }

  static markRefreshing(pullRefresh: PullRefreshState): void {
    pullRefresh.refreshing = true;
    pullRefresh.tracking = false;
    pullRefresh.visible = true;
    pullRefresh.settling = false;
    pullRefresh.ready = true;
    pullRefresh.distance = WebPullRefresh.refreshDistance();
  }

  static end(pullRefresh: PullRefreshState, onChanged: () => void): void {
    pullRefresh.refreshing = false;
    WebPullRefresh.stopSpin(pullRefresh, onChanged);
    WebPullRefresh.reset(pullRefresh);
    onChanged();
  }

  static startSpin(pullRefresh: PullRefreshState, onChanged: () => void): void {
    WebPullRefresh.stopSpin(pullRefresh, onChanged);
    pullRefresh.rotation = 0;
    pullRefresh.spinTimer = setInterval(() => {
      pullRefresh.rotation = (pullRefresh.rotation + 36) % 360;
      onChanged();
    }, 60);
    onChanged();
  }

  static stopSpin(pullRefresh: PullRefreshState, onChanged: () => void): void {
    if (pullRefresh.spinTimer >= 0) {
      clearInterval(pullRefresh.spinTimer);
      pullRefresh.spinTimer = -1;
      onChanged();
    }
  }

  private static stopSettle(pullRefresh: PullRefreshState): void {
    if (pullRefresh.settleTimer >= 0) {
      clearTimeout(pullRefresh.settleTimer);
      pullRefresh.settleTimer = -1;
    }
  }

  private static progress(pullRefresh: PullRefreshState): number {
    return Math.min(PULL_REFRESH_READY_PROGRESS,
      Math.floor(pullRefresh.distance / TOUCH_REFRESH_DISTANCE * PULL_REFRESH_READY_PROGRESS));
  }

  private static dragRotation(pullRefresh: PullRefreshState): number {
    return Math.floor(WebPullRefresh.progress(pullRefresh) * 1.8);
  }
}
