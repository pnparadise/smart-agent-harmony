import { AgentLogEntry } from './PageModels';
import { CARD_BACKGROUND, CARD_RADIUS, PAGE_BACKGROUND, PRIMARY_BLUE, TEXT_PRIMARY, TEXT_SECONDARY } from './PageStyle';

@Component
export struct LogsPage {
  @Prop logs: AgentLogEntry[] = [];
  onClearLogs: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column() {
          if (this.logs.length === 0) {
            this.buildEmptyLogCard();
          } else {
            ForEach(this.logs, (entry: AgentLogEntry) => {
              this.buildLogCard(entry);
            }, (entry: AgentLogEntry) => entry.id)
          }

          Blank()
            .height(112)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 30, bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      Row() {
        Button() {
          Text('清空日志')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(CARD_BACKGROUND)
        }
          .type(ButtonType.Normal)
          .width('100%')
          .height(54)
          .backgroundColor(PRIMARY_BLUE)
          .borderRadius(12)
          .onClick(() => {
            this.onClearLogs();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 28 })
      .backgroundColor('#00FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private buildEmptyLogCard() {
    Column() {
      Text('暂无日志')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
      Text('隧道切换和规则变更会显示在这里')
        .fontSize(14)
        .fontColor(TEXT_SECONDARY)
        .margin({ top: 8 })
    }
    .width('100%')
    .height(100)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .padding({ top: 22 })
  }

  @Builder
  private buildLogCard(entry: AgentLogEntry) {
    Column() {
      Row() {
        Text(entry.time)
          .fontSize(16)
          .fontColor('#7F838A')
          .maxLines(1)
          .layoutWeight(1)
        Text(entry.badge)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY_BLUE)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor('#EEF5FF')
          .borderRadius(6)
          .maxLines(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(entry.message)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .maxLines(2)
        .margin({ top: 20 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 26 })
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
  }
}
