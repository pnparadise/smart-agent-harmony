import { AgentLogEntry } from '../wireguard/ConfigStore';
import { CARD_BACKGROUND, CARD_RADIUS, PAGE_BACKGROUND, PRIMARY_BLUE, TEXT_PRIMARY, TEXT_SECONDARY } from './PageStyle';

@Component
export struct LogsPage {
  @Prop logs: AgentLogEntry[] = [];
  @State private refreshing: boolean = false;
  onClearLogs: () => void = () => {};
  onRefreshLogs: () => Promise<void> = () => Promise.resolve();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            if (this.logs.length === 0) {
              this.buildEmptyLogState();
            } else {
              ForEach(this.logs, (entry: AgentLogEntry) => {
                this.buildLogCard(entry);
              }, (entry: AgentLogEntry) => entry.id)
            }

            Blank()
              .height(112)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Start)
          .padding({ left: 20, right: 20, top: 30, bottom: 20 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .onRefreshing(() => {
        this.refreshLogs();
      })

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

  private refreshLogs(): void {
    this.onRefreshLogs()
      .then(() => {
        this.refreshing = false;
      })
      .catch(() => {
        this.refreshing = false;
      });
  }

  @Builder
  private buildEmptyLogState() {
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
    .height(160)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildLogCard(entry: AgentLogEntry) {
    Column() {
      Row() {
        Text(entry.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(1)

        Text(this.formatLogTime(entry.createdAt))
          .fontSize(13)
          .fontColor('#7F838A')
          .maxLines(1)
          .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.formatLogSubtitle(entry.subtitle))
        .fontSize(14)
        .fontColor(TEXT_SECONDARY)
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(2)
        .margin({ top: 10 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24, top: 24, bottom: 26 })
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
  }

  private formatLogSubtitle(subtitle: string): string {
    const timeSeparator = subtitle.indexOf(' · 时间：');
    if (timeSeparator >= 0) {
      return subtitle.substring(0, timeSeparator);
    }
    return subtitle;
  }

  private formatLogTime(timestamp: number): string {
    if (timestamp <= 0 || Number.isNaN(timestamp)) {
      return '';
    }

    const date = new Date(timestamp);
    const year = String(date.getFullYear());
    const month = this.padTwoDigits(date.getMonth() + 1);
    const day = this.padTwoDigits(date.getDate());
    const hours = this.padTwoDigits(date.getHours());
    const minutes = this.padTwoDigits(date.getMinutes());
    const seconds = this.padTwoDigits(date.getSeconds());
    return year + '-' + month + '-' + day + ' ' + hours + ':' + minutes + ':' + seconds;
  }

  private padTwoDigits(value: number): string {
    if (value < 10) {
      return '0' + String(value);
    }
    return String(value);
  }
}
