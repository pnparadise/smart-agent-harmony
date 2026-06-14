import { TunnelConfig } from '../wireguard/ConfigStore';
import {
  ACTION_BUTTON_BACKGROUND,
  ACTION_BUTTON_RADIUS,
  CARD_BACKGROUND,
  CARD_RADIUS,
  DIVIDER_COLOR,
  PAGE_BACKGROUND,
  PRIMARY_BLUE,
  TEXT_PRIMARY,
  TEXT_SECONDARY
} from './PageStyle';

@Component
export struct TunnelsPage {
  @Prop tunnels: TunnelConfig[] = [];
  @Prop busy: boolean = false;
  @Prop runtimeRunning: boolean = false;
  @Prop activeTunnelId: string = '';
  @Prop runtimeTunnelId: string = '';
  @Prop runtimeTunnelName: string = '';
  @Prop runtimeTxBytes: number = 0;
  @Prop runtimeRxBytes: number = 0;
  @Prop runtimeLatestHandshakeSeconds: number = -1;
  @Prop startingTunnelId: string = '';
  @Prop startingTunnelName: string = '';
  onImportConfig: () => void = () => {};
  onOpenTunnel: (tunnel: TunnelConfig) => void = () => {};
  onToggleTunnel: (tunnel: TunnelConfig) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll() {
        Column() {
          this.buildConnectionSummaryCard();

          Text('AVAILABLE TUNNELS')
            .width('100%')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#8A8D93')
            .margin({ top: 28, bottom: 16 })

          if (this.tunnels.length === 0) {
            this.buildEmptyTunnelCard();
          } else {
            ForEach(this.tunnels, (tunnel: TunnelConfig) => {
              this.buildTunnelCard(tunnel);
            }, (tunnel: TunnelConfig) => this.tunnelCardKey(tunnel))
          }

          Blank()
            .height(96)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 30, bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      Button() {
        Text('+')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor(PRIMARY_BLUE)
          .height(48)
          .textAlign(TextAlign.Center)
      }
        .enabled(!this.busy)
        .type(ButtonType.Normal)
        .width(54)
        .height(54)
        .backgroundColor(CARD_BACKGROUND)
        .borderRadius(27)
        .shadow({ radius: 22, color: '#263478F6', offsetX: 0, offsetY: 8 })
        .margin({ right: 22, bottom: 28 })
        .onClick(() => {
          this.onImportConfig();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private buildConnectionSummaryCard() {
    Column() {
      Row() {
        Row() {
          Circle()
            .width(10)
            .height(10)
            .fill(this.isRuntimeActive() ? '#45B88A' : '#AEB4BE')
            .margin({ right: 12 })
          Text(this.isRuntimeActive() ? 'CONNECTED' : 'DISCONNECTED')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isRuntimeActive() ? '#45B88A' : '#8A8D93')
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        Text(this.isRuntimeActive() ? this.formatRuntimeHandshakeAge() : '--')
          .fontSize(14)
          .fontColor('#777A80')
      }
      .width('100%')
      .height(46)

      Divider()
        .strokeWidth(1)
        .color(DIVIDER_COLOR)
        .margin({ top: 16, bottom: 20 })

      Row() {
        this.buildTunnelSummaryMetric();
        this.buildUploadSummaryMetric();
        this.buildDownloadSummaryMetric();
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 22, bottom: 22 })
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 18, color: '#0A000000', offsetX: 0, offsetY: 6 })
  }

  @Builder
  private buildTunnelSummaryMetric() {
    Column() {
      Text('TUNNEL')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#8A8D93')
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
      Text(this.isRuntimeActive() ? this.runtimeTunnelLabel() : '直连')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(0.7)
    .padding({ right: 8 })
  }

  @Builder
  private buildUploadSummaryMetric() {
    Column() {
      Text('UPLOAD')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#8A8D93')
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
      Text(this.formatDesignBytes(this.runtimeTxBytes))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1.15)
  }

  @Builder
  private buildDownloadSummaryMetric() {
    Column() {
      Text('DOWNLOAD')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#8A8D93')
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
      Text(this.formatDesignBytes(this.runtimeRxBytes))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .margin({ top: 10 })
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1.15)
  }

  @Builder
  private buildEmptyTunnelCard() {
    Column() {
      Text('No tunnels')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
      Text('Tap + to import a WireGuard config')
        .fontSize(13)
        .fontColor(TEXT_SECONDARY)
        .margin({ top: 8 })
    }
    .width('100%')
    .height(100)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
  }

  @Builder
  private buildTunnelCard(tunnel: TunnelConfig) {
    Row() {
      Row() {
        Image($r('app.media.ic_tunnel_blue'))
          .width(36)
          .height(36)
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#F6F7F9')
      .borderRadius(12)
      .margin({ right: 20 })

      Column() {
        Text(tunnel.name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text(this.tunnelFileName(tunnel))
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.onOpenTunnel(tunnel);
      })

      this.buildTunnelSwitch(tunnel);
    }
    .width('100%')
    .height(100)
    .padding({ left: 24, right: 26 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
  }

  @Builder
  private buildTunnelSwitch(tunnel: TunnelConfig) {
    Button() {
      this.buildTunnelSwitchFace(tunnel);
    }
    .enabled(!this.busy)
    .type(ButtonType.Normal)
    .width(62)
    .height(38)
    .padding(0)
    .backgroundColor('#00000000')
    .borderRadius(20)
    .onClick(() => {
      this.onToggleTunnel(tunnel);
    })
  }

  @Builder
  private buildTunnelSwitchFace(tunnel: TunnelConfig) {
    Row() {
      if (this.isTunnelRunning(tunnel)) {
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
    .backgroundColor(this.isTunnelRunning(tunnel) ? PRIMARY_BLUE : '#E6EAF0')
    .borderRadius(20)
  }

  private isRuntimeActive(): boolean {
    return this.runtimeRunning || this.startingTunnelId.length > 0;
  }

  private isTunnelRunning(tunnel: TunnelConfig): boolean {
    if (this.startingTunnelId === tunnel.id) {
      return true;
    }
    if (!this.runtimeRunning) {
      return false;
    }
    if (this.activeTunnelId.length === 0) {
      return this.runtimeTunnelName.length > 0 && this.runtimeTunnelName === tunnel.name;
    }
    return this.activeTunnelId === tunnel.id;
  }

  private tunnelCardKey(tunnel: TunnelConfig): string {
    const runningState = this.isTunnelRunning(tunnel) ? 'running' : 'idle';
    const busyState = this.busy ? 'busy' : 'ready';
    return tunnel.id + '_' + runningState + '_' + busyState;
  }

  private runtimeTunnelLabel(): string {
    if (!this.isRuntimeActive()) {
      return 'No active tunnel';
    }
    if (this.runtimeTunnelName.length > 0) {
      return this.runtimeTunnelName;
    }
    if (this.startingTunnelName.length > 0) {
      return this.startingTunnelName;
    }
    if (this.runtimeTunnelId.length > 0) {
      const tunnelName = this.tunnelNameForId(this.runtimeTunnelId);
      return tunnelName.length > 0 ? tunnelName : this.runtimeTunnelId;
    }
    if (this.startingTunnelId.length > 0) {
      const tunnelName = this.tunnelNameForId(this.startingTunnelId);
      return tunnelName.length > 0 ? tunnelName : this.startingTunnelId;
    }
    return 'Active tunnel';
  }

  private tunnelNameForId(tunnelId: string): string {
    for (let index = 0; index < this.tunnels.length; index++) {
      const tunnel = this.tunnels[index];
      if (tunnel.id === tunnelId) {
        return tunnel.name;
      }
    }
    return '';
  }

  private tunnelFileName(tunnel: TunnelConfig): string {
    const name = tunnel.name.trim();
    if (name.length === 0) {
      return 'tunnel.conf';
    }
    const lowerName = name.toLowerCase();
    if (lowerName.endsWith('.conf')) {
      return name;
    }
    return name + '.conf';
  }

  private formatRuntimeHandshakeAge(): string {
    if (this.runtimeLatestHandshakeSeconds < 0) {
      return '--';
    }

    const ageSeconds = Math.max(0, Math.floor(this.runtimeLatestHandshakeSeconds));
    if (ageSeconds < 60) {
      return String(ageSeconds) + 's 前';
    }
    if (ageSeconds < 3600) {
      return String(Math.floor(ageSeconds / 60)) + 'm 前';
    }
    return String(Math.floor(ageSeconds / 3600)) + 'h 前';
  }

  private formatDesignBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0.00 B';
    }
    if (bytes < 1024) {
      return bytes.toFixed(2) + ' B';
    }
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toFixed(2) + ' KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return (bytes / (1024 * 1024)).toFixed(2) + ' MB';
    }
    return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
  }
}
