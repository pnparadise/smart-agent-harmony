import {
  CARD_BACKGROUND,
  PAGE_BACKGROUND,
  PRIMARY_BLUE,
  TEXT_PRIMARY,
  TEXT_SECONDARY
} from './PageStyle';
import { WebBrowserErrorState } from './WebBrowserTypes';

const TOOLBAR_HEIGHT = 52;
const TOOLBAR_ICON_SIZE = 21;
const PULL_REFRESH_INDICATOR_SIZE = 42;

@Component
export struct WebBrowserChrome {
  @Prop topRectHeight: number = 0;
  @Prop showToolbar: boolean = true;
  @Prop toolbarHidden: boolean = false;
  @Prop addressText: string = '';
  @Prop addressFocused: boolean = false;
  @Prop loading: boolean = false;
  @Prop progress: number = 100;
  @Prop canGoForward: boolean = false;
  @Prop bookmarkedUrls: string[] = [];
  @Prop notice: string = '';
  @Prop webError: WebBrowserErrorState = {
    visible: false,
    url: '',
    title: '',
    detail: '',
    code: 0,
    kind: ''
  };
  @Prop pullRefreshVisible: boolean = false;
  @Prop pullRefreshRotation: number = 0;
  @Prop pullRefreshOffset: number = 0;
  @Prop addBookmarkConfirmVisible: boolean = false;
  @Prop addBookmarkConfirmTitle: string = '';
  @Prop addBookmarkConfirmIcon: string = '';
  @Prop addBookmarkConfirmBusy: boolean = false;
  @Prop desktopShortcutConfirmVisible: boolean = false;
  @Prop desktopShortcutConfirmTitle: string = '';
  @Prop desktopShortcutConfirmIcon: string = '';
  @Prop desktopShortcutConfirmBusy: boolean = false;
  @Prop deleteBookmarkConfirmVisible: boolean = false;
  @Prop deleteBookmarkConfirmTitle: string = '';
  @Prop deleteBookmarkConfirmIcon: string = '';
  @Prop deleteBookmarkConfirmBusy: boolean = false;

  onAddressFocusChanged: (focused: boolean) => void = () => {};
  onAddressChange: (value: string) => void = () => {};
  onAddressSubmit: () => void = () => {};
  onClearAddress: () => void = () => {};
  onGoForward: () => void = () => {};
  onOpenBookmarks: () => void = () => {};
  onAddBookmark: () => void = () => {};
  onHideAddBookmarkConfirm: () => void = () => {};
  onSubmitAddBookmarkConfirm: () => void = () => {};
  onHideDesktopShortcutConfirm: () => void = () => {};
  onSubmitDesktopShortcutConfirm: () => void = () => {};
  onHideDeleteBookmarkConfirm: () => void = () => {};
  onSubmitDeleteBookmarkConfirm: () => void = () => {};
  onReloadWebError: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showToolbar) {
        this.buildToolbar();
      }

      if (this.pullRefreshVisible) {
        this.buildPullRefreshIndicator();
      }

      if (this.webError.visible) {
        this.buildWebError();
      }

      if (this.notice.length > 0) {
        this.buildNotice();
      }

      if (this.addBookmarkConfirmVisible) {
        this.buildAddBookmarkConfirm();
      }

      if (this.desktopShortcutConfirmVisible) {
        this.buildDesktopShortcutConfirm();
      }

      if (this.deleteBookmarkConfirmVisible) {
        this.buildDeleteBookmarkConfirm();
      }
    }
    .width('100%')
    .height(this.chromeRootHeight())
    .clip(false)
  }

  @Builder
  private buildToolbar() {
    Column() {
      Row() {
        Row() {
          Image($r('app.media.ic_globe_gray'))
            .width(18)
            .height(18)
            .margin({ left: 12, right: 8 })
          TextInput({
            text: this.addressText,
            placeholder: 'Search or type web address'
          })
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor(TEXT_PRIMARY)
            .placeholderColor(TEXT_SECONDARY)
            .backgroundColor('#00000000')
            .padding(0)
            .type(InputType.URL)
            .enterKeyType(EnterKeyType.Go)
            .onFocus(() => {
              this.onAddressFocusChanged(true);
            })
            .onBlur(() => {
              this.onAddressFocusChanged(false);
            })
            .onChange((value: string) => {
              this.onAddressChange(value);
            })
            .onSubmit((_enterKey: EnterKeyType) => {
              this.onAddressSubmit();
            })

          if (this.addressFocused && this.addressText !== 'https://') {
            Button() {
              Text('×')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_SECONDARY)
                .textAlign(TextAlign.Center)
            }
              .type(ButtonType.Normal)
              .width(28)
              .height(28)
              .padding(0)
              .backgroundColor('#DDE2EA')
              .borderRadius(14)
              .margin({ left: 6, right: 8 })
              .onClick(() => {
                this.onClearAddress();
              })
          }
        }
        .height(40)
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#F1F3F6')
        .borderRadius(20)
        .margin({ right: 6 })

        if (this.canGoForward) {
          this.buildIconButton('forward', true);
        }
        this.buildIconButton('bookmarks', true);
        this.buildAddBookmarkButton();
      }
      .width('100%')
      .height(this.toolbarContentHeight())
      .padding({ left: 10, right: 10, top: this.statusBarPadding() + 5, bottom: 5 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(CARD_BACKGROUND)

      Progress({ value: this.loading ? this.progress : 100, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(2)
        .color(PRIMARY_BLUE)
        .backgroundColor('#00000000')
        .opacity(this.loading ? 1 : 0)
    }
    .width('100%')
    .height(this.toolbarHeight())
    .backgroundColor(CARD_BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .translate({ x: 0, y: this.toolbarHidden ? -this.toolbarHeight() : 0, z: 0 })
    .opacity(this.toolbarHidden ? 0 : 1)
    .animation({ duration: 180, curve: Curve.EaseInOut })
    .zIndex(20)
  }

  @Builder
  private buildIconButton(action: string, enabled: boolean) {
    Button() {
      if (action === 'forward') {
        Image($r('app.media.ic_web_forward_gray'))
          .width(TOOLBAR_ICON_SIZE)
          .height(TOOLBAR_ICON_SIZE)
      } else if (action === 'bookmarks') {
        Image($r('app.media.ic_bookmark_bar_gray'))
          .width(TOOLBAR_ICON_SIZE)
          .height(TOOLBAR_ICON_SIZE)
      } else {
        Image($r('app.media.ic_shortcut_gray'))
          .width(TOOLBAR_ICON_SIZE)
          .height(TOOLBAR_ICON_SIZE)
      }
    }
      .enabled(enabled)
      .type(ButtonType.Normal)
      .width(38)
      .height(40)
      .padding(0)
      .backgroundColor('#00000000')
      .borderRadius(12)
      .margin({ left: 2 })
      .opacity(enabled ? 1 : 0.36)
      .onClick(() => {
        if (!enabled) {
          return;
        }
        if (action === 'forward') {
          this.onGoForward();
          return;
        }
        if (action === 'bookmarks') {
          this.onOpenBookmarks();
          return;
        }
        this.onAddBookmark();
      })
  }

  @Builder
  private buildAddBookmarkButton() {
    if (this.canAddAddressBookmark()) {
      this.buildActiveAddBookmarkButton();
    } else {
      this.buildInactiveAddBookmarkButton();
    }
  }

  @Builder
  private buildActiveAddBookmarkButton() {
    Button() {
      Image($r('app.media.ic_shortcut_gray'))
        .width(TOOLBAR_ICON_SIZE)
        .height(TOOLBAR_ICON_SIZE)
    }
      .type(ButtonType.Normal)
      .width(38)
      .height(40)
      .padding(0)
      .backgroundColor('#00000000')
      .borderRadius(12)
      .margin({ left: 2 })
      .opacity(1)
      .onClick(() => {
        this.onAddBookmark();
      })
  }

  @Builder
  private buildInactiveAddBookmarkButton() {
    Button() {
      Image($r('app.media.ic_shortcut_gray'))
        .width(TOOLBAR_ICON_SIZE)
        .height(TOOLBAR_ICON_SIZE)
    }
      .type(ButtonType.Normal)
      .width(38)
      .height(40)
      .padding(0)
      .backgroundColor('#00000000')
      .borderRadius(12)
      .margin({ left: 2 })
      .opacity(0.36)
      .onClick(() => {
        this.onAddBookmark();
      })
  }

  private canAddAddressBookmark(): boolean {
    const url = this.addressText.trim();
    if (!this.isHttpUrl(url)) {
      return false;
    }
    const normalized = this.normalizeUrl(url);
    for (let index = 0; index < this.bookmarkedUrls.length; index++) {
      if (this.normalizeUrl(this.bookmarkedUrls[index]) === normalized) {
        return false;
      }
    }
    return true;
  }

  private isHttpUrl(url: string): boolean {
    const value = url.trim();
    return value.startsWith('http://') || value.startsWith('https://');
  }

  private normalizeUrl(url: string): string {
    return url.trim();
  }

  @Builder
  private buildPullRefreshIndicator() {
    Stack() {
      Image($r('app.media.ic_pull_refresh_gray'))
        .width(24)
        .height(24)
        .rotate({ angle: this.pullRefreshRotation })
    }
    .width(PULL_REFRESH_INDICATOR_SIZE)
    .height(PULL_REFRESH_INDICATOR_SIZE)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(PULL_REFRESH_INDICATOR_SIZE / 2)
    .shadow({ radius: 14, color: '#24000000', offsetX: 0, offsetY: 5 })
    .position({
      x: '50%',
      y: this.pullRefreshTopPosition()
    })
    .translate({ x: -PULL_REFRESH_INDICATOR_SIZE / 2, y: 0, z: 0 })
    .opacity(this.pullRefreshVisible ? 1 : 0)
    .animation({ duration: 120, curve: Curve.EaseOut })
    .zIndex(18)
  }

  @Builder
  private buildNotice() {
    Row() {
      Row() {
        Text(this.notice)
          .fontSize(13)
          .fontColor(TEXT_PRIMARY)
          .maxLines(2)
          .layoutWeight(1)
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(CARD_BACKGROUND)
      .borderRadius(14)
      .shadow({ radius: 18, color: '#24000000', offsetX: 0, offsetY: 8 })
      .alignItems(VerticalAlign.Center)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .position({ x: 0, y: this.showToolbar && !this.toolbarHidden ? this.toolbarHeight() + 10 :
      this.statusBarPadding() + 16 })
    .animation({ duration: 180, curve: Curve.EaseInOut })
    .zIndex(30)
  }

  @Builder
  private buildAddBookmarkConfirm() {
    WebBrowserConfirmDialog({
      heading: '添加到书签栏',
      title: this.addBookmarkConfirmTitle,
      icon: this.addBookmarkConfirmIcon,
      busy: this.addBookmarkConfirmBusy,
      submitText: this.addBookmarkConfirmBusy ? '添加中' : '添加',
      submitColor: PRIMARY_BLUE,
      zIndexValue: 45,
      onCancel: (): void => {
        this.onHideAddBookmarkConfirm();
      },
      onSubmit: (): void => {
        this.onSubmitAddBookmarkConfirm();
      }
    });
  }

  @Builder
  private buildDesktopShortcutConfirm() {
    WebBrowserConfirmDialog({
      heading: '添加到桌面',
      title: this.desktopShortcutConfirmTitle,
      icon: this.desktopShortcutConfirmIcon,
      busy: this.desktopShortcutConfirmBusy,
      submitText: this.desktopShortcutConfirmBusy ? '处理中' : '添加',
      submitColor: PRIMARY_BLUE,
      zIndexValue: 46,
      onCancel: (): void => {
        this.onHideDesktopShortcutConfirm();
      },
      onSubmit: (): void => {
        this.onSubmitDesktopShortcutConfirm();
      }
    });
  }

  @Builder
  private buildDeleteBookmarkConfirm() {
    WebBrowserConfirmDialog({
      heading: '删除书签',
      title: this.deleteBookmarkConfirmTitle,
      icon: this.deleteBookmarkConfirmIcon,
      busy: this.deleteBookmarkConfirmBusy,
      submitText: this.deleteBookmarkConfirmBusy ? '删除中' : '删除',
      submitColor: '#D94848',
      zIndexValue: 47,
      onCancel: (): void => {
        this.onHideDeleteBookmarkConfirm();
      },
      onSubmit: (): void => {
        this.onSubmitDeleteBookmarkConfirm();
      }
    });
  }

  @Builder
  private buildWebError() {
    Column() {
      Blank()
        .layoutWeight(1)

      Column() {
        Text(this.webError.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .maxLines(2)

        Text(this.webError.detail)
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .maxLines(4)
          .margin({ top: 10 })

        Text(this.webError.url)
          .fontSize(12)
          .fontColor(TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .margin({ top: 12 })

        Button() {
          Text('重新加载')
            .fontSize(15)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
        }
          .type(ButtonType.Normal)
          .height(42)
          .padding({ left: 22, right: 22 })
          .backgroundColor(PRIMARY_BLUE)
          .borderRadius(21)
          .margin({ top: 22 })
          .onClick(() => {
            this.onReloadWebError();
          })
      }
      .width('100%')
      .padding({ left: 28, right: 28 })
      .alignItems(HorizontalAlign.Center)

      Blank()
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.showToolbar && !this.toolbarHidden ? this.toolbarHeight() : this.statusBarPadding() })
    .backgroundColor(PAGE_BACKGROUND)
    .zIndex(10)
  }

  private toolbarHeight(): number {
    return TOOLBAR_HEIGHT + this.statusBarPadding();
  }

  private chromeRootHeight(): Length {
    if (this.hasBlockingOverlay()) {
      return '100%';
    }
    if (!this.showToolbar) {
      return 0;
    }
    return this.toolbarHidden ? 0 : this.toolbarHeight();
  }

  private pullRefreshTopOffset(): number {
    if (!this.showToolbar || this.toolbarHidden) {
      return this.statusBarPadding();
    }
    return this.toolbarHeight();
  }

  private pullRefreshTopPosition(): number {
    const position = this.pullRefreshTopOffset() + this.pullRefreshOffset;
    if (!this.showToolbar || this.toolbarHidden) {
      return Math.max(this.statusBarPadding(), position);
    }
    return position;
  }

  private hasBlockingOverlay(): boolean {
    return this.pullRefreshVisible || this.webError.visible ||
      this.addBookmarkConfirmVisible || this.desktopShortcutConfirmVisible || this.deleteBookmarkConfirmVisible;
  }

  private toolbarContentHeight(): number {
    return 50 + this.statusBarPadding();
  }

  private statusBarPadding(): number {
    if (this.topRectHeight <= 0) {
      return 0;
    }
    return this.getUIContext().px2vp(this.topRectHeight);
  }
}

@Component
struct WebBrowserConfirmDialog {
  @Prop heading: string = '';
  @Prop title: string = '';
  @Prop icon: string = '';
  @Prop busy: boolean = false;
  @Prop submitText: string = '';
  @Prop submitColor: ResourceColor = PRIMARY_BLUE;
  @Prop zIndexValue: number = 45;
  onCancel: () => void = () => {};
  onSubmit: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
      }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          if (!this.busy) {
            this.onCancel();
          }
        })

      Column() {
        Image(this.confirmIconSource(this.icon))
          .objectFit(ImageFit.Cover)
          .width(58)
          .height(58)
          .borderRadius(14)
          .margin({ bottom: 14 })

        Text(this.heading)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        Text(this.title)
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .margin({ top: 8 })

        Row() {
          Button() {
            Text('取消')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(TEXT_SECONDARY)
          }
            .type(ButtonType.Normal)
            .height(42)
            .layoutWeight(1)
            .backgroundColor('#F1F3F6')
            .borderRadius(8)
            .enabled(!this.busy)
            .onClick(() => {
              this.onCancel();
            })

          Button() {
            Text(this.submitText)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
            .type(ButtonType.Normal)
            .height(42)
            .layoutWeight(1)
            .backgroundColor(this.submitColor)
            .borderRadius(8)
            .enabled(!this.busy)
            .margin({ left: 10 })
            .onClick(() => {
              this.onSubmit();
            })
        }
        .width('100%')
        .margin({ top: 22 })
      }
      .width('82%')
      .padding({ left: 22, right: 22, top: 24, bottom: 18 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .shadow({ radius: 24, color: '#30000000', offsetX: 0, offsetY: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(this.zIndexValue)
  }

  private confirmIconSource(icon: string): ResourceStr {
    return icon.length > 0 ? icon : $r('app.media.ic_browser_shortcut');
  }
}
