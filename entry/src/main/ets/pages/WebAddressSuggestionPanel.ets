import {
  CARD_BACKGROUND,
  DIVIDER_COLOR,
  TEXT_PRIMARY,
  TEXT_SECONDARY
} from './PageStyle';
import { WebAddressSuggestionItem } from './WebBrowserTypes';

@Component
export struct WebAddressSuggestionPanel {
  @Prop items: WebAddressSuggestionItem[] = [];
  onSelect: (item: WebAddressSuggestionItem) => void = () => {};
  onDeleteHistory: (item: WebAddressSuggestionItem) => void = () => {};

  build() {
    Column() {
      ForEach(this.items, (item: WebAddressSuggestionItem, index: number) => {
        this.buildSuggestionItem(item, index);
      }, (item: WebAddressSuggestionItem) => item.id)
    }
    .width('100%')
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(18)
    .shadow({ radius: 18, color: '#20000000', offsetX: 0, offsetY: 8 })
    .clip(true)
  }

  @Builder
  private buildSuggestionItem(item: WebAddressSuggestionItem, index: number) {
    Column() {
      Row() {
        Column() {
          if (item.title.trim().length > 0) {
            Text(item.title)
              .width('100%')
              .fontSize(14)
              .fontColor(TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(item.subtitle)
              .width('100%')
              .fontSize(12)
              .fontColor(TEXT_SECONDARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
          } else {
            Text(item.subtitle)
              .width('100%')
              .fontSize(14)
              .fontColor(TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.onSelect(item);
        })

        if (item.kind === 'history') {
          Button() {
            Image($r('app.media.ic_delete_gray'))
              .width(18)
              .height(18)
          }
            .type(ButtonType.Normal)
            .width(30)
            .height(30)
            .padding(0)
            .margin({ left: 10 })
            .backgroundColor('#F1F3F6')
            .borderRadius(10)
            .onClick(() => {
              this.onDeleteHistory(item);
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(CARD_BACKGROUND)

    if (index < this.items.length - 1) {
      Divider()
        .strokeWidth(1)
        .color(DIVIDER_COLOR)
    }
  }
}
