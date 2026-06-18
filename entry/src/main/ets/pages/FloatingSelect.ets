import { CARD_BACKGROUND, PRIMARY_BLUE, TEXT_PRIMARY, TEXT_SECONDARY } from './PageStyle';

export interface FloatingSelectOption {
  value: string;
  label: string;
}

@Component
export struct FloatingSelect {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop selectedValue: string = '';
  @Prop expanded: boolean = false;
  @Prop options: FloatingSelectOption[] = [];
  @Prop menuWidth: number = 220;
  @Prop menuAlign: string = 'left';
  @Prop menuTop: number = 64;
  @Prop optionHeight: number = 58;
  @Prop maxVisibleOptions: number = 5;
  @Prop showCheck: boolean = false;
  @Prop highlightSelected: boolean = true;
  @Prop valueFontSize: number = 16;
  @Prop valueColor: string = TEXT_PRIMARY;
  @Prop showFieldDivider: boolean = false;
  onToggle: () => void = () => {};
  onSelect: (value: string) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildField();

      if (this.expanded) {
        Row() {
          if (this.menuAlign === 'right') {
            Blank()
              .layoutWeight(1)
          }
          this.buildMenu();
          if (this.menuAlign !== 'right') {
            Blank()
              .layoutWeight(1)
          }
        }
        .width('100%')
        .height(this.menuHeight())
        .position({ x: 0, y: this.menuTop })
        .zIndex(100)
      }
    }
    .width('100%')
    .height(this.fieldStackHeight())
    .clip(false)
  }

  @Builder
  private buildField() {
    if (this.label.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildFieldFrame(56, 8)
        Text(this.label)
          .fontSize(12)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .padding({ left: 5, right: 5 })
          .backgroundColor(CARD_BACKGROUND)
          .margin({ left: 10 })
      }
      .width('100%')
      .height(64)
    } else {
      this.buildFieldFrame(52, 0)
    }
  }

  @Builder
  private buildFieldFrame(fieldHeight: number, topMargin: number) {
    Row() {
      Text(this.value)
        .fontSize(this.valueFontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.valueColor)
        .maxLines(1)
        .layoutWeight(1)
      if (this.showFieldDivider) {
        Divider()
          .vertical(true)
          .height(26)
          .strokeWidth(1)
          .color('#E4E7EC')
          .margin({ left: 10, right: 10 })
      }
      Image($r('app.media.ic_chevron_down_gray'))
        .width(22)
        .height(22)
        .margin({ left: this.showFieldDivider ? 0 : 8 })
        .rotate({ angle: this.expanded ? 180 : 0 })
    }
    .width('100%')
    .height(fieldHeight)
    .padding({ left: 14, right: 12 })
    .alignItems(VerticalAlign.Center)
    .border({ width: 1, color: this.expanded ? PRIMARY_BLUE : '#E4E7EC', radius: 10 })
    .backgroundColor(this.expanded ? '#F8FBFF' : CARD_BACKGROUND)
    .margin({ top: topMargin })
    .onClick(() => {
      this.onToggle();
    })
  }

  @Builder
  private buildMenu() {
    Scroll() {
      Column() {
        ForEach(this.options, (option: FloatingSelectOption) => {
          this.buildMenuOption(option);
        }, (option: FloatingSelectOption) => option.value)
      }
      .width('100%')
    }
    .width(this.menuWidth)
    .height(this.menuHeight())
    .scrollBar(BarState.Off)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(2)
    .shadow({ radius: 18, color: '#2A000000', offsetX: 0, offsetY: 8 })
  }

  @Builder
  private buildMenuOption(option: FloatingSelectOption) {
    Row() {
      Text(option.label)
        .fontSize(17)
        .fontColor(TEXT_PRIMARY)
        .maxLines(1)
        .layoutWeight(1)
      if (this.showCheck && this.selectedValue === option.value) {
        Image($r('app.media.ic_check_blue'))
          .width(20)
          .height(20)
          .margin({ left: 12 })
      }
    }
    .width('100%')
    .height(this.optionHeight)
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.highlightSelected && this.selectedValue === option.value ? '#E6E6E6' : CARD_BACKGROUND)
    .onClick(() => {
      this.onSelect(option.value);
    })
  }

  private fieldStackHeight(): number {
    if (this.label.length > 0) {
      return 64;
    }
    return 52;
  }

  private menuHeight(): number {
    let visibleCount = this.options.length;
    if (visibleCount > this.maxVisibleOptions) {
      visibleCount = this.maxVisibleOptions;
    }
    if (visibleCount <= 0) {
      visibleCount = 1;
    }
    return visibleCount * this.optionHeight;
  }
}
