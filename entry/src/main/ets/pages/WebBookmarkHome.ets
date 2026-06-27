import { unifiedDataChannel } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebBookmarkEntry } from '../wireguard/ConfigStore';
import {
  TEXT_PRIMARY
} from './PageStyle';

const DOMAIN = 0x0001;
const TAG = 'WebBookmarkHome';
const BOOKMARK_TILE_HEIGHT = 104;
const BOOKMARK_DOCK_HEIGHT = 132;
const BOOKMARK_DOCK_BUTTON_HEIGHT = 104;
const BOOKMARK_ICON_STACK_WIDTH = 70;
const BOOKMARK_ICON_STACK_HEIGHT = 62;
const BOOKMARK_BADGE_TOUCH_SIZE = 28;
const BOOKMARK_BADGE_CLEAR_DISTANCE = 28;
const BOOKMARK_HOME_BACKGROUND = '#F4F8FD';
const BOOKMARK_TILE_BACKGROUND = '#00000000';
const BOOKMARK_DROP_ACTION_NONE = '';
const BOOKMARK_DROP_ACTION_DESKTOP = 'desktop';
const BOOKMARK_DROP_ACTION_DELETE = 'delete';

interface BookmarkDropActionInnerGradient {
  angle: number;
  colors: Array<[ResourceColor, number]>;
}

@Component
export struct WebBookmarkHome {
  @Prop bookmarks: WebBookmarkEntry[] = [];
  @Prop loading: boolean = false;
  @Prop topPadding: number = 0;
  @Prop tabStateRevision: number = 0;
  @Prop homeTabBackCountValue: number = 0;
  @Prop homeTitle: string = 'Browser';
  @Prop homeIconSource: ResourceStr = $r('app.media.ic_browser_shortcut');
  iconSource: (url: string) => ResourceStr = () => $r('app.media.ic_browser_shortcut');
  tabBackCount: (bookmarkId: string) => number = () => 0;
  onOpenHome: () => void = () => {};
  onOpenBookmark: (bookmark: WebBookmarkEntry) => void = () => {};
  onCreateDesktopShortcut: (bookmark: WebBookmarkEntry) => void = () => {};
  onDeleteBookmark: (bookmark: WebBookmarkEntry) => void = () => {};
  onClearHomeTabStack: () => void = () => {};
  onClearAllBookmarkStacks: () => void = () => {};
  onCloseBookmarkInstance: (bookmark: WebBookmarkEntry) => void = () => {};
  onPullRefreshStart: () => void = () => {};
  onPullRefreshUpdate: (offsetY: number) => void = () => {};
  onPullRefreshEnd: () => void = () => {};
  @State private draggingBookmarkId: string = '';
  @State private bookmarkDragActive: boolean = false;
  @State private draggingBadgeId: string = '';
  @State private clearingBadgeId: string = '';
  @State private badgeTouchId: string = '';
  @State private badgeDragOffsetX: number = 0;
  @State private badgeDragOffsetY: number = 0;
  @State private bookmarkDropAction: string = BOOKMARK_DROP_ACTION_NONE;
  @State private suppressBookmarkClick: boolean = false;
  private badgeDragActive: boolean = false;
  private suppressBookmarkClickToken: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.buildHeader()

        Grid() {
          ForEach([this.homeGridKey()], (key: string) => {
            GridItem() {
              this.buildHomeTile()
            }
          }, (key: string) => key)
          if (this.bookmarks.length > 0) {
            ForEach(this.bookmarks, (bookmark: WebBookmarkEntry) => {
              GridItem() {
                this.buildBookmarkTile(bookmark);
              }
            }, (bookmark: WebBookmarkEntry) => bookmark.id + '_' + this.tabStateRevision.toString())
          }
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(14)
        .columnsGap(8)
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 18, right: 18, top: this.topPadding + 22, bottom: 18 })
      .backgroundColor(BOOKMARK_HOME_BACKGROUND)

      if (this.bookmarkDragActive) {
        this.buildBookmarkDropActions();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BOOKMARK_HOME_BACKGROUND)
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 1 })
        .onActionStart(() => {
          this.handlePullRefreshStart();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.handlePullRefreshUpdate(event.offsetY);
        })
        .onActionEnd(() => {
          this.handlePullRefreshEnd();
        })
        .onActionCancel(() => {
          this.handlePullRefreshEnd();
        })
    )
    .zIndex(8)
  }

  @Builder
  private buildHeader() {
    Row() {
      Text('书签栏')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#515151')

      Blank()
        .layoutWeight(1)

      this.buildClearAllButton()
    }
    .width('100%')
    .height(36)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 18 })
  }

  @Builder
  private buildClearAllButton() {
    Button() {
      Image($r('app.media.ic_sweep_gray'))
        .width(20)
        .height(20)
    }
      .type(ButtonType.Normal)
      .width(36)
      .height(36)
      .padding(0)
      .backgroundColor('#EAF0F8')
      .borderRadius(12)
      .opacity(this.canClearAllBookmarkStacks() ? 1 : 0.36)
      .onClick(() => {
        hilog.info(DOMAIN, TAG,
          'clear all button clicked canClear=%{public}s homeBackCount=%{public}d bookmarkClearCount=%{public}d dragActive=%{public}s',
          String(this.canClearAllBookmarkStacks()),
          this.homeTabBackCountForRender(),
          this.clearableBookmarkStackCount(),
          String(this.isInteractiveDragActive()));
        if (!this.canClearAllBookmarkStacks()) {
          return;
        }
        this.onClearAllBookmarkStacks();
      })
  }

  @Builder
  private buildHomeTile() {
    Column() {
      this.buildTileVisual(this.homeTitle, this.homeIconSource, this.homeTabBackCountForRender(), false, 'home', undefined)
    }
    .id('home_tile_' + String(this.tabStateRevision) + '_' + String(this.homeTabBackCountForRender()))
    .width('100%')
    .height(BOOKMARK_TILE_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 4, right: 4 })
    .backgroundColor(BOOKMARK_TILE_BACKGROUND)
    .borderRadius(8)
    .onClick(() => {
      if (this.suppressBookmarkClick || this.draggingBookmarkId.length > 0) {
        return;
      }
      this.onOpenHome();
    })
  }

  @Builder
  private buildBookmarkTile(bookmark: WebBookmarkEntry) {
    Column() {
      this.buildTileVisual(bookmark.title, this.iconSource(bookmark.url), this.tabBackCountForRender(bookmark.id),
        this.draggingBookmarkId === bookmark.id, bookmark.id, bookmark)
    }
    .id('bookmark_tile_' + bookmark.id + '_' + String(this.tabStateRevision) + '_' +
      String(this.tabBackCountForRender(bookmark.id)))
    .width('100%')
    .height(BOOKMARK_TILE_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 4, right: 4 })
    .backgroundColor(BOOKMARK_TILE_BACKGROUND)
    .borderRadius(8)
    .scale(this.draggingBookmarkId === bookmark.id ? { x: 0.92, y: 0.92 } : { x: 1, y: 1 })
    .animation({ duration: 150, curve: Curve.EaseOut })
    .draggable(this.badgeTouchId.length === 0)
    .dragPreviewOptions({ mode: [DragPreviewMode.ENABLE_DRAG_ITEM_GRAY_EFFECT] })
    .parallelGesture(LongPressGesture({ duration: 480 })
      .onAction(() => {
        this.prepareBookmarkDrag(bookmark.id);
      }))
    .onPreDrag((status: PreDragStatus) => {
      this.handleBookmarkPreDrag(bookmark.id, status);
    })
    .onDragStart((event?: DragEvent) => {
      if (this.badgeTouchId.length > 0 || this.draggingBadgeId.length > 0) {
        return;
      }
      this.startBookmarkDrag(bookmark.id);
      this.setBookmarkDragData(bookmark, event);
    })
    .onDragEnd(() => {
      this.finishBookmarkDrag();
    })
    .onClick(() => {
      if (this.suppressBookmarkClick || this.draggingBookmarkId.length > 0) {
        return;
      }
      this.onOpenBookmark(bookmark);
    })
  }

  @Builder
  private buildTileVisual(
    title: string,
    icon: ResourceStr,
    backCount: number,
    dimmed: boolean,
    badgeId: string,
    bookmark?: WebBookmarkEntry
  ) {
    Stack({ alignContent: Alignment.Center }) {
      Image(icon)
        .objectFit(ImageFit.Cover)
        .width(48)
        .height(48)
        .borderRadius(12)
        .opacity(dimmed ? 0.2 : 1)

      if (backCount > 0) {
        this.buildBadge(backCount, dimmed, badgeId, bookmark)
      }
    }
    .width(BOOKMARK_ICON_STACK_WIDTH)
    .height(BOOKMARK_ICON_STACK_HEIGHT)
    .margin({ bottom: 2 })

    Text(title)
      .fontSize(12)
      .fontColor(TEXT_PRIMARY)
      .fontWeight(FontWeight.Medium)
      .textAlign(TextAlign.Center)
      .maxLines(2)
      .height(42)
      .opacity(dimmed ? 0.36 : 1)
  }

  @Builder
  private buildBadge(backCount: number, dimmed: boolean, badgeId: string, bookmark?: WebBookmarkEntry) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Text(this.badgeText(backCount))
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(this.badgeWidth(backCount))
        .height(18)
        .backgroundColor('#F04444')
        .borderRadius(9)
        .draggable(false)
    }
      .width(Math.max(28, this.badgeWidth(backCount)))
      .height(BOOKMARK_BADGE_TOUCH_SIZE)
      .backgroundColor('#00000000')
      .position({ x: this.badgeLeft(backCount), y: 0 })
      .opacity(this.badgeOpacity(dimmed, badgeId))
      .scale(this.clearingBadgeId === badgeId ? { x: 0.28, y: 0.28 } :
        (this.draggingBadgeId === badgeId ? { x: 1.08, y: 1.08 } : { x: 1, y: 1 }))
      .translate(this.draggingBadgeId === badgeId || this.clearingBadgeId === badgeId ?
        { x: this.badgeDragOffsetX, y: this.badgeDragOffsetY } : { x: 0, y: 0 })
      .zIndex(this.draggingBadgeId === badgeId ? 20 : 1)
      .id('badge_' + badgeId + '_' + String(this.tabStateRevision) + '_' + String(backCount))
      .animation({ duration: 180, curve: Curve.EaseOut })
      .draggable(false)
      .priorityGesture(
        PanGesture({ distance: 1 })
          .onActionStart(() => {
            this.startBadgeDrag(badgeId);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.updateBadgeDrag(badgeId, event.offsetX, event.offsetY);
          })
          .onActionEnd(() => {
            this.releaseBadgeDrag(badgeId, backCount, bookmark);
          })
          .onActionCancel(() => {
            this.finishBadgeDragOnly();
          })
      )
      .onTouch((event?: TouchEvent) => {
        this.handleBadgeTouch(badgeId, event);
      })
      .onClick(() => {
        if (this.draggingBadgeId.length > 0 || this.clearingBadgeId === badgeId) {
          return;
        }
        if (badgeId === 'home') {
          this.onOpenHome();
          return;
        }
        if (bookmark !== undefined) {
          this.onOpenBookmark(bookmark);
        }
      })
  }

  @Builder
  private buildBookmarkDropActions() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')
      .onDragLeave((event?: DragEvent) => {
        if (event) {
          event.setResult(DragResult.DROP_DISABLED);
        }
        this.finishBookmarkDrag();
      })
      .onDrop((event?: DragEvent) => {
        if (event) {
          event.setResult(DragResult.DROP_DISABLED);
        }
        this.finishBookmarkDrag();
      })
      .onClick(() => {
        this.finishBookmarkDrag();
      })

      Stack({ alignContent: Alignment.Bottom }) {
        Row() {
          this.buildBookmarkDropAction(BOOKMARK_DROP_ACTION_DESKTOP);
          this.buildBookmarkDropAction(BOOKMARK_DROP_ACTION_DELETE);
        }
        .width('100%')
        .height(BOOKMARK_DOCK_BUTTON_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(BOOKMARK_DOCK_HEIGHT)
      .padding({ left: 18, right: 18, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .zIndex(36)
  }

  @Builder
  private buildBookmarkDropAction(action: string) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.isBookmarkDropActionActive(action)) {
          Column()
            .width(58)
            .height(58)
            .linearGradient(this.bookmarkDropActionInnerGradient(action))
            .borderRadius(29)
            .shadow({
              radius: 14,
              color: action === BOOKMARK_DROP_ACTION_DELETE ? '#30EF3B2D' : '#303478F6',
              offsetX: 0,
              offsetY: 5
            })
            .scale({ x: 1, y: 1 })
            .animation({ duration: 150, curve: Curve.EaseOut })
        }

        if (action === BOOKMARK_DROP_ACTION_DELETE) {
          Image(this.isBookmarkDropActionActive(action) ? $r('app.media.ic_delete_white') :
            $r('app.media.ic_delete_gray'))
            .width(29)
            .height(29)
        } else {
          Image(this.isBookmarkDropActionActive(action) ? $r('app.media.ic_shortcut_blue') :
            $r('app.media.ic_shortcut_gray'))
            .width(31)
            .height(31)
        }
      }
      .width(64)
      .height(64)

      Text(action === BOOKMARK_DROP_ACTION_DELETE ? '删除' : '添加桌面')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.bookmarkDropActionTextColor(action))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height(BOOKMARK_DOCK_BUTTON_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .scale(this.isBookmarkDropActionActive(action) ? { x: 1.05, y: 1.05 } : { x: 1, y: 1 })
    .opacity(this.isBookmarkDropActionInactive(action) ? 0.62 : 1)
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onDragEnter((event?: DragEvent) => {
      this.updateBookmarkDropTarget(action, event);
    })
    .onDragMove((event?: DragEvent) => {
      this.updateBookmarkDropTarget(action, event);
    })
    .onDragLeave((event?: DragEvent) => {
      if (event) {
        event.setResult(DragResult.DROP_DISABLED);
      }
      if (this.bookmarkDropAction === action) {
        this.bookmarkDropAction = BOOKMARK_DROP_ACTION_NONE;
      }
    })
    .onDrop((event?: DragEvent) => {
      if (event) {
        event.setResult(DragResult.DRAG_SUCCESSFUL);
      }
      this.dropBookmark(action);
    })
  }

  private startBookmarkDrag(bookmarkId: string): void {
    if (this.badgeTouchId.length > 0 || this.draggingBadgeId.length > 0) {
      return;
    }
    this.prepareBookmarkDrag(bookmarkId);
    this.bookmarkDragActive = true;
  }

  private prepareBookmarkDrag(bookmarkId: string): void {
    if (this.badgeTouchId.length > 0 || this.draggingBadgeId.length > 0) {
      return;
    }
    this.draggingBookmarkId = bookmarkId;
    this.bookmarkDragActive = true;
    this.bookmarkDropAction = BOOKMARK_DROP_ACTION_NONE;
    this.suppressBookmarkClickToken++;
    this.suppressBookmarkClick = true;
  }

  private updateBookmarkDropTarget(action: string, event?: DragEvent): void {
    if (this.draggingBookmarkId.length === 0 || !this.bookmarkDragActive) {
      return;
    }
    if (event) {
      event.setResult(DragResult.DROP_ENABLED);
      event.dragBehavior = DragBehavior.MOVE;
    }
    this.bookmarkDropAction = action;
  }

  private handleBookmarkPreDrag(bookmarkId: string, status: PreDragStatus): void {
    if (this.badgeTouchId.length > 0 || this.draggingBadgeId.length > 0) {
      return;
    }
    if (status === PreDragStatus.PREVIEW_LIFT_STARTED ||
      status === PreDragStatus.PREVIEW_LIFT_FINISHED) {
      this.prepareBookmarkDrag(bookmarkId);
      return;
    }
    if (status === PreDragStatus.PREVIEW_LANDING_STARTED ||
      status === PreDragStatus.ACTION_CANCELED_BEFORE_DRAG ||
      status === PreDragStatus.PREVIEW_LANDING_FINISHED) {
      if (this.draggingBookmarkId === bookmarkId) {
        this.finishBookmarkDrag();
      }
    }
  }

  private dropBookmark(action: string): void {
    const bookmark = this.bookmarkById(this.draggingBookmarkId);
    this.finishBookmarkDrag();
    if (bookmark === null) {
      return;
    }
    if (action === BOOKMARK_DROP_ACTION_DESKTOP) {
      this.onCreateDesktopShortcut(bookmark);
      return;
    }
    if (action === BOOKMARK_DROP_ACTION_DELETE) {
      this.onDeleteBookmark(bookmark);
    }
  }

  private handlePullRefreshStart(): void {
    if (this.isInteractiveDragActive()) {
      return;
    }
    this.onPullRefreshStart();
  }

  private handlePullRefreshUpdate(offsetY: number): void {
    if (this.isInteractiveDragActive()) {
      return;
    }
    this.onPullRefreshUpdate(offsetY);
  }

  private handlePullRefreshEnd(): void {
    this.onPullRefreshEnd();
  }

  private isInteractiveDragActive(): boolean {
    return this.bookmarkDragActive || this.draggingBookmarkId.length > 0 || this.badgeTouchId.length > 0 ||
      this.draggingBadgeId.length > 0 || this.badgeDragActive;
  }

  private setBookmarkDragData(bookmark: WebBookmarkEntry, event?: DragEvent): void {
    if (!event) {
      return;
    }
    const icon = this.iconSource(bookmark.url);
    const data: unifiedDataChannel.Image = new unifiedDataChannel.Image();
    data.imageUri = typeof icon === 'string' ? icon : bookmark.url;
    event.setData(new unifiedDataChannel.UnifiedData(data));
  }

  private bookmarkById(bookmarkId: string): WebBookmarkEntry | null {
    for (let index = 0; index < this.bookmarks.length; index++) {
      if (this.bookmarks[index].id === bookmarkId) {
        return this.bookmarks[index];
      }
    }
    return null;
  }

  private canClearAllBookmarkStacks(): boolean {
    if (this.homeTabBackCountForRender() > 0) {
      return true;
    }
    for (let index = 0; index < this.bookmarks.length; index++) {
      if (this.tabBackCountForRender(this.bookmarks[index].id) > 0) {
        return true;
      }
    }
    return false;
  }

  private clearableBookmarkStackCount(): number {
    let count = 0;
    for (let index = 0; index < this.bookmarks.length; index++) {
      if (this.tabBackCountForRender(this.bookmarks[index].id) > 0) {
        count++;
      }
    }
    return count;
  }

  private homeTabBackCountForRender(): number {
    const revision = this.tabStateRevision;
    if (revision < 0) {
      return 0;
    }
    return Math.max(0, this.homeTabBackCountValue);
  }

  private homeGridKey(): string {
    return 'home_' + String(this.tabStateRevision) + '_' + String(this.homeTabBackCountForRender());
  }

  private tabBackCountForRender(bookmarkId: string): number {
    const revision = this.tabStateRevision;
    if (revision < 0) {
      return 0;
    }
    return Math.max(0, this.tabBackCount(bookmarkId));
  }

  private badgeText(count: number): string {
    if (count > 99) {
      return '99+';
    }
    return String(count);
  }

  private badgeWidth(count: number): number {
    return count > 99 ? 28 : 18;
  }

  private badgeLeft(count: number): number {
    return BOOKMARK_ICON_STACK_WIDTH - Math.max(BOOKMARK_BADGE_TOUCH_SIZE, this.badgeWidth(count));
  }

  private badgeOpacity(dimmed: boolean, badgeId: string): number {
    if (this.isBadgeHidden(badgeId)) {
      return 0;
    }
    return dimmed ? 0.25 : 1;
  }

  private isBadgeHidden(badgeId: string): boolean {
    return this.clearingBadgeId === badgeId;
  }

  private handleBadgeTouch(badgeId: string, event?: TouchEvent): void {
    if (!event) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.badgeTouchId = badgeId;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.badgeTouchId === badgeId) {
        this.badgeTouchId = '';
      }
    }
  }

  private startBadgeDrag(badgeId: string): void {
    this.badgeDragActive = true;
    this.badgeTouchId = badgeId;
    this.draggingBadgeId = badgeId;
    this.badgeDragOffsetX = 0;
    this.badgeDragOffsetY = 0;
    this.draggingBookmarkId = '';
    this.bookmarkDragActive = false;
    this.bookmarkDropAction = BOOKMARK_DROP_ACTION_NONE;
    this.suppressBookmarkClick = true;
    this.suppressBookmarkClickToken++;
  }

  private updateBadgeDrag(badgeId: string, offsetX: number, offsetY: number): void {
    if (this.draggingBadgeId !== badgeId || !this.badgeDragActive) {
      return;
    }
    this.badgeDragOffsetX = offsetX;
    this.badgeDragOffsetY = offsetY;
  }

  private releaseBadgeDrag(badgeId: string, backCount: number, bookmark?: WebBookmarkEntry): void {
    hilog.info(DOMAIN, TAG, 'release badge drag id=%{public}s backCount=%{public}d offset=(%{public}f,%{public}f)',
      badgeId, backCount, this.badgeDragOffsetX, this.badgeDragOffsetY);
    if (!this.isBadgeReleasedOutside(backCount)) {
      hilog.info(DOMAIN, TAG, 'badge drag not outside id=%{public}s', badgeId);
      this.finishBadgeDragOnly();
      return;
    }
    hilog.info(DOMAIN, TAG, 'badge drag clear accepted id=%{public}s', badgeId);
    this.clearBadgeStack(badgeId, bookmark);
  }

  private isBadgeReleasedOutside(backCount: number): boolean {
    const touchWidth = Math.max(BOOKMARK_BADGE_TOUCH_SIZE, this.badgeWidth(backCount));
    const startCenterX = this.badgeLeft(backCount) + touchWidth / 2;
    const startCenterY = BOOKMARK_BADGE_TOUCH_SIZE / 2;
    const centerX = startCenterX + this.badgeDragOffsetX;
    const centerY = startCenterY + this.badgeDragOffsetY;
    const distance = Math.sqrt(this.badgeDragOffsetX * this.badgeDragOffsetX +
      this.badgeDragOffsetY * this.badgeDragOffsetY);
    if (distance < BOOKMARK_BADGE_CLEAR_DISTANCE) {
      return false;
    }
    if (centerX < 0 || centerX > BOOKMARK_ICON_STACK_WIDTH ||
      centerY < 0 || centerY > BOOKMARK_ICON_STACK_HEIGHT) {
      return true;
    }
    const iconCenterX = BOOKMARK_ICON_STACK_WIDTH / 2;
    const iconCenterY = BOOKMARK_ICON_STACK_HEIGHT / 2;
    const startRadius = Math.sqrt((startCenterX - iconCenterX) * (startCenterX - iconCenterX) +
      (startCenterY - iconCenterY) * (startCenterY - iconCenterY));
    const currentRadius = Math.sqrt((centerX - iconCenterX) * (centerX - iconCenterX) +
      (centerY - iconCenterY) * (centerY - iconCenterY));
    return currentRadius >= startRadius + BOOKMARK_BADGE_CLEAR_DISTANCE / 2;
  }

  private clearBadgeStack(badgeId: string, bookmark?: WebBookmarkEntry): void {
    if (badgeId.length === 0) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'clear badge stack id=%{public}s bookmark=%{public}s',
      badgeId, bookmark !== undefined ? bookmark.id : '');
    this.badgeDragActive = false;
    this.badgeTouchId = '';
    this.draggingBadgeId = '';
    this.clearingBadgeId = badgeId;
    const token = ++this.suppressBookmarkClickToken;
    this.performBadgeClearAction(badgeId, bookmark);
    setTimeout(() => {
      if (this.clearingBadgeId === badgeId) {
        this.clearingBadgeId = '';
        this.badgeDragOffsetX = 0;
        this.badgeDragOffsetY = 0;
      }
      if (token === this.suppressBookmarkClickToken) {
        this.suppressBookmarkClick = false;
      }
    }, 180);
  }

  private performBadgeClearAction(badgeId: string, bookmark?: WebBookmarkEntry): void {
    if (badgeId === 'home') {
      hilog.info(DOMAIN, TAG, 'perform home badge clear action homeBackCount=%{public}d',
        this.homeTabBackCountForRender());
      this.onClearHomeTabStack();
      return;
    }
    if (bookmark !== undefined) {
      hilog.info(DOMAIN, TAG, 'perform bookmark badge clear action id=%{public}s', bookmark.id);
      this.onCloseBookmarkInstance(bookmark);
      return;
    }
    const matched = this.bookmarkById(badgeId);
    if (matched !== null) {
      hilog.info(DOMAIN, TAG, 'perform matched bookmark badge clear action id=%{public}s', matched.id);
      this.onCloseBookmarkInstance(matched);
    }
  }

  private finishBadgeDragOnly(): void {
    this.badgeDragActive = false;
    this.badgeTouchId = '';
    this.draggingBadgeId = '';
    this.badgeDragOffsetX = 0;
    this.badgeDragOffsetY = 0;
    const token = ++this.suppressBookmarkClickToken;
    this.suppressBookmarkClick = true;
    setTimeout(() => {
      if (token === this.suppressBookmarkClickToken) {
        this.suppressBookmarkClick = false;
      }
    }, 140);
  }

  private isBookmarkDropActionActive(action: string): boolean {
    return this.bookmarkDropAction === action;
  }

  private isBookmarkDropActionInactive(action: string): boolean {
    return this.bookmarkDropAction !== BOOKMARK_DROP_ACTION_NONE && this.bookmarkDropAction !== action;
  }

  private bookmarkDropActionInnerGradient(action: string): BookmarkDropActionInnerGradient {
    if (action === BOOKMARK_DROP_ACTION_DELETE) {
      return {
        angle: 135,
        colors: [['#FF5A5A', 0.0], ['#D92D20', 1.0]]
      };
    }
    return {
      angle: 135,
      colors: [['#D8EAFF', 0.0], ['#7EB6FF', 1.0]]
    };
  }

  private bookmarkDropActionTextColor(action: string): string {
    if (action === BOOKMARK_DROP_ACTION_DELETE) {
      return this.isBookmarkDropActionActive(action) ? '#D92D20' : '#7F8896';
    }
    return this.isBookmarkDropActionActive(action) ? '#1F6FEB' : '#7F8896';
  }

  private finishBookmarkDrag(): void {
    this.draggingBookmarkId = '';
    this.bookmarkDragActive = false;
    this.bookmarkDropAction = BOOKMARK_DROP_ACTION_NONE;
    const token = ++this.suppressBookmarkClickToken;
    this.suppressBookmarkClick = true;
    setTimeout(() => {
      if (token === this.suppressBookmarkClickToken) {
        this.suppressBookmarkClick = false;
      }
    }, 140);
  }
}
