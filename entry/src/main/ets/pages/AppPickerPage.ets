import { SplitAppInfo } from '../wireguard/ConfigStore';
import { CARD_BACKGROUND, PAGE_BACKGROUND, PRIMARY_BLUE, TEXT_PRIMARY, TEXT_SECONDARY } from './PageStyle';

@Component
export struct AppPickerPage {
  @Prop appPickerLoading: boolean = false;
  @Prop appPickerError: string = '';
  @Prop appPickerNotice: string = '';
  @Prop appBundleNameInput: string = '';
  @Prop availableSplitApps: SplitAppInfo[] = [];
  @Prop draftSelectedBundleNames: string[] = [];
  onRetry: () => void = () => {};
  onBundleNameInputChange: (value: string) => void = () => {};
  onAddBundleName: () => void = () => {};
  onToggleApp: (bundleName: string) => void = () => {};

  build() {
    Column() {
      if (this.appPickerLoading) {
        Column() {
          Text('加载应用中')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
          Text('正在校验已添加应用')
            .fontSize(13)
            .fontColor(TEXT_SECONDARY)
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.appPickerError.length > 0) {
        Column() {
          Text('无法读取应用列表')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
          Text(this.appPickerError)
            .fontSize(13)
            .fontColor(TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
          Button() {
            Text('重试')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(CARD_BACKGROUND)
          }
            .type(ButtonType.Normal)
            .height(44)
            .padding({ left: 24, right: 24 })
            .backgroundColor(PRIMARY_BLUE)
            .borderRadius(10)
            .margin({ top: 18 })
            .onClick(() => {
              this.onRetry();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 28, right: 28 })
      } else {
        this.buildAppBundleInput();

        Row() {
          Text('已选 ' + String(this.draftSelectedBundleNames.length) + ' 个应用')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#8A8D93')
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .height(42)
        .padding({ left: 20, right: 20 })

        if (this.availableSplitApps.length === 0) {
          Column() {
            Text('输入包名添加应用')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
            Text('例如 com.example.app')
              .fontSize(13)
              .fontColor(TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 28, right: 28 })
        } else {
          List() {
            ForEach(this.availableSplitApps, (app: SplitAppInfo) => {
              ListItem() {
                this.buildAppPickerRow(app);
              }
              .margin({ bottom: 10 })
            }, (app: SplitAppInfo) => app.bundleName)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 20 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private buildAppBundleInput() {
    Column() {
      Row() {
        TextInput({
          text: this.appBundleNameInput,
          placeholder: '输入应用包名'
        })
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .fontColor(TEXT_PRIMARY)
          .backgroundColor(CARD_BACKGROUND)
          .padding({ left: 12, right: 12 })
          .border({ width: 1, color: '#E4E7EC', radius: 10 })
          .onChange((value: string) => {
            this.onBundleNameInputChange(value);
          })

        Button() {
          Text('添加')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(CARD_BACKGROUND)
        }
          .type(ButtonType.Normal)
          .height(44)
          .padding({ left: 18, right: 18 })
          .backgroundColor(PRIMARY_BLUE)
          .borderRadius(10)
          .margin({ left: 10 })
          .onClick(() => {
            this.onAddBundleName();
          })
      }
      .width('100%')

      if (this.appPickerNotice.length > 0) {
        Text(this.appPickerNotice)
          .fontSize(12)
          .fontColor(TEXT_SECONDARY)
          .maxLines(2)
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 8 })
  }

  @Builder
  private buildAppPickerRow(app: SplitAppInfo) {
    Row() {
      Row() {
        Text(this.appInitial(app))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY_BLUE)
          .textAlign(TextAlign.Center)
      }
      .width(46)
      .height(46)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#EEF5FF')
      .borderRadius(12)
      .margin({ right: 14 })

      Column() {
        Text(app.label)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text(app.bundleName)
          .fontSize(12)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .margin({ top: 5 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Stack() {
        Circle()
          .width(26)
          .height(26)
          .fill(this.isDraftAppSelected(app.bundleName) ? PRIMARY_BLUE : '#FFFFFF')
          .stroke(this.isDraftAppSelected(app.bundleName) ? PRIMARY_BLUE : '#CBD5E1')
        if (this.isDraftAppSelected(app.bundleName)) {
          Text('✓')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
      }
      .width(30)
      .height(30)
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(12)
    .onClick(() => {
      this.onToggleApp(app.bundleName);
    })
  }

  private isDraftAppSelected(bundleName: string): boolean {
    for (let index = 0; index < this.draftSelectedBundleNames.length; index++) {
      if (this.draftSelectedBundleNames[index] === bundleName) {
        return true;
      }
    }
    return false;
  }

  private appInitial(app: SplitAppInfo): string {
    if (app.label.length > 0) {
      return app.label.substring(0, 1);
    }
    if (app.bundleName.length > 0) {
      return app.bundleName.substring(0, 1).toUpperCase();
    }
    return '?';
  }
}
