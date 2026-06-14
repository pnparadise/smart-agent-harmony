import {
  CARD_BACKGROUND,
  CARD_RADIUS,
  DIVIDER_COLOR,
  PAGE_BACKGROUND,
  PRIMARY_BLUE,
  TEXT_PRIMARY,
  TEXT_SECONDARY
} from './PageStyle';

@Component
export struct RulesPage {
  @Prop appSplitEnabled: boolean = false;
  @Prop smartAgentEnabled: boolean = false;
  @Prop dohEnabled: boolean = true;
  @Prop dohProvider: string = '';
  @Prop selectedSplitAppCount: number = 0;
  onToggleAppSplit: () => void = () => {};
  onToggleSmartAgent: () => void = () => {};
  onToggleDoh: () => void = () => {};
  onRotateDohProvider: () => void = () => {};
  onOpenAppPicker: () => void = () => {};
  onOpenIssueReport: () => void = () => {};

  build() {
    Scroll() {
      Column() {
        this.buildAppSplitCard();
        this.buildSimpleRuleCard('Smart Agent', '按规则从上到下匹配隧道', 'smartAgent', () => {
          this.onToggleSmartAgent();
        });
        this.buildDohCard();
        this.buildNavigationRuleCard('Github Issue Report', '前往Github 反馈问题');

        Blank()
          .height(32)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 30, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAGE_BACKGROUND)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildAppSplitCard() {
    Column() {
      Row() {
        Column() {
          Text('App Split Tunneling')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
          Text('仅勾选的应用流量走隧道')
            .fontSize(13)
            .fontColor(TEXT_SECONDARY)
            .margin({ top: 10 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          this.buildRuleSwitchFace('appSplit');
        }
        .onClick(() => {
          this.onToggleAppSplit();
        })
      }
      .width('100%')

      if (this.appSplitEnabled) {
        Row() {
          Button() {
            Row() {
              Image($r('app.media.ic_list_check_blue'))
                .width(22)
                .height(22)
                .margin({ right: 10 })
              Text('已选 ' + String(this.selectedSplitAppCount) + ' 个应用')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(TEXT_PRIMARY)
                .maxLines(1)
            }
            .alignItems(VerticalAlign.Center)
          }
            .type(ButtonType.Normal)
            .height(50)
            .padding({ left: 18, right: 18 })
            .backgroundColor('#00000000')
            .border({ width: 1, color: '#E4E7EC', radius: 12 })
            .onClick(() => {
              this.onOpenAppPicker();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .margin({ top: 24 })
      }
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
  }

  @Builder
  private buildSimpleRuleCard(title: string, subtitle: string, switchKey: string, onToggle: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text(subtitle)
          .fontSize(13)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 10 })
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        this.buildRuleSwitchFace(switchKey);
      }
      .onClick(onToggle)
    }
    .width('100%')
    .height(100)
    .padding({ left: 22, right: 26 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
    .onClick(onToggle)
  }

  @Builder
  private buildDohCard() {
    Column() {
      Row() {
        Column() {
          Text('DNS over HTTPS')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
          Text('通过 DoH 解析隧道域名')
            .fontSize(13)
            .fontColor(TEXT_SECONDARY)
            .margin({ top: 10 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          this.buildRuleSwitchFace('doh');
        }
        .onClick(() => {
          this.onToggleDoh();
        })
      }
      .width('100%')

      Divider()
        .strokeWidth(1)
        .color(DIVIDER_COLOR)
        .margin({ top: 22, bottom: 20 })

      Row() {
        Text(this.dohProvider)
          .fontSize(14)
          .fontColor('#7B7F86')
          .maxLines(1)
          .layoutWeight(1)
        Divider()
          .vertical(true)
          .height(26)
          .strokeWidth(1)
          .color(DIVIDER_COLOR)
          .margin({ left: 10, right: 10 })
        Image($r('app.media.ic_chevron_down_gray'))
          .width(24)
          .height(24)
      }
      .height(52)
      .padding({ left: 16, right: 14 })
      .alignItems(VerticalAlign.Center)
      .border({ width: 1, color: '#E4E7EC', radius: 10 })
      .onClick(() => {
        this.onRotateDohProvider();
      })
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
  }

  @Builder
  private buildNavigationRuleCard(title: string, subtitle: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text(subtitle)
          .fontSize(13)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 10 })
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Image($r('app.media.ic_chevron_right_gray'))
        .width(26)
        .height(26)
    }
    .width('100%')
    .height(100)
    .padding({ left: 22, right: 24 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
    .onClick(() => {
      this.onOpenIssueReport();
    })
  }

  @Builder
  private buildRuleSwitchFace(switchKey: string) {
    Row() {
      if (this.isRuleSwitchOn(switchKey)) {
        Blank()
          .layoutWeight(1)
        Stack() {
          Circle()
            .width(30)
            .height(30)
            .fill(CARD_BACKGROUND)
          Image($r('app.media.ic_check_blue'))
            .width(17)
            .height(17)
        }
        .width(32)
        .height(32)
        .margin({ right: 4 })
      } else {
        Stack() {
          Circle()
            .width(30)
            .height(30)
            .fill(CARD_BACKGROUND)
        }
        .width(32)
        .height(32)
        .margin({ left: 4 })
        Blank()
          .layoutWeight(1)
      }
    }
    .width(62)
    .height(38)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.isRuleSwitchOn(switchKey) ? PRIMARY_BLUE : '#E6EAF0')
    .borderRadius(20)
  }

  private isRuleSwitchOn(switchKey: string): boolean {
    if (switchKey === 'appSplit') {
      return this.appSplitEnabled;
    }
    if (switchKey === 'smartAgent') {
      return this.smartAgentEnabled;
    }
    if (switchKey === 'doh') {
      return this.dohEnabled;
    }
    return false;
  }
}
