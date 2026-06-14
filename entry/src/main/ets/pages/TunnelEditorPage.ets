import { DEFAULT_WG_CONFIG } from '../wireguard/WireGuardConfig';

@Component
export struct TunnelEditorPage {
  @Prop editingName: string = '';
  @Prop editingConfig: string = DEFAULT_WG_CONFIG;
  @Prop editingDisabled: boolean = false;
  onNameChange: (value: string) => void = () => {};
  onConfigChange: (value: string) => void = () => {};

  build() {
    Column() {
      TextInput({
        text: this.editingName,
        placeholder: 'Tunnel name'
      })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor('#111827')
        .backgroundColor('#FFFFFF')
        .enabled(!this.editingDisabled)
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 12 })
        .onChange((value: string) => {
          this.onNameChange(value);
        })

      TextArea({
        text: this.editingConfig,
        placeholder: DEFAULT_WG_CONFIG
      })
        .width('100%')
        .layoutWeight(1)
        .fontSize(13)
        .fontColor('#111827')
        .backgroundColor('#FFFFFF')
        .enabled(!this.editingDisabled)
        .padding(12)
        .margin({ bottom: 12 })
        .onChange((value: string) => {
          this.onConfigChange(value);
        })
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .padding({ left: 18, right: 18, top: 18 })
  }
}
