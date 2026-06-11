import { common, Want } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';
import { fileIo, picker, ReadOptions } from '@kit.CoreFileKit';
import { vpnExtension } from '@kit.NetworkKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  clearActiveTunnel,
  createTunnelId,
  deleteTunnel,
  loadAppSplitEnabled,
  loadSelectedSplitApps,
  loadTunnelRuntimeStatus,
  loadTunnels,
  saveActiveTunnel,
  saveAppSplitEnabled,
  saveSelectedSplitApps,
  saveTunnelRuntimeStatus,
  saveTunnel,
  SplitAppInfo,
  TunnelConfig,
  TunnelRuntimeStatus
} from '../wireguard/ConfigStore';
import { startVpnDataTransferTask, stopVpnDataTransferTask } from '../wireguard/VpnBackgroundTask';
import { DEFAULT_WG_CONFIG, parseWireGuardConfig } from '../wireguard/WireGuardConfig';

const BUNDLE_NAME = 'com.smart.agent';
const MODULE_NAME = 'entry';
const VPN_ABILITY = 'WgVpnExtensionAbility';
const CONFIG_FILE_SUFFIX_FILTERS: string[] = ['WireGuard|.conf,.txt'];
const MAX_IMPORT_CONFIG_BYTES = 64 * 1024;
const TUNNEL_ROW_HEIGHT = 76;
const TUNNEL_DELETE_WIDTH = 72;
const TUNNEL_ROW_RADIUS = 8;
const ACTION_BUTTON_RADIUS = 12;
const ACTION_BUTTON_BACKGROUND = '#EEF5FF';
const STOP_BUTTON_BACKGROUND = '#FDECEC';
const RUNNING_TUNNEL_BACKGROUND = '#EEF1F5';
const RUNNING_STATUS_COLOR = '#4B5563';
const STATUS_REFRESH_INTERVAL_MS = 1000;
const STATUS_STALE_MS = 5000;
const CONTINUOUS_TASK_RETRY_MS = 30000;
const STATUS_CARD_RADIUS = 8;
const PRIMARY_BLUE = '#3478F6';
const PAGE_BACKGROUND = '#F4F6FA';
const CARD_BACKGROUND = '#FFFFFF';
const TEXT_PRIMARY = '#2D2F33';
const TEXT_SECONDARY = '#8C8F95';
const DIVIDER_COLOR = '#EEF0F4';
const CARD_RADIUS = 18;
const TAB_TUNNELS = 0;
const TAB_RULES = 1;
const TAB_LOGS = 2;
const DOMAIN = 0x0001;
const TAG = 'Index';

interface AgentLogEntry {
  id: string;
  time: string;
  badge: string;
  message: string;
}

@Entry
@Component
struct Index {
  @State private tunnels: TunnelConfig[] = [];
  @State private statusText: string = 'Idle';
  @State private busy: boolean = false;
  @State private vpnEnabled: boolean = false;
  @State private activeTunnelId: string = '';
  @State private swipingTunnelId: string = '';
  @State private swipeDeleteWidth: number = 0;
  @State private editingTunnelId: string = '';
  @State private editingName: string = '';
  @State private editingConfig: string = DEFAULT_WG_CONFIG;
  @State private runtimeRunning: boolean = false;
  @State private runtimeTunnelId: string = '';
  @State private runtimeTunnelName: string = '';
  @State private runtimeTxBytes: number = 0;
  @State private runtimeRxBytes: number = 0;
  @State private runtimeLatestHandshakeSeconds: number = -1;
  @State private runtimeLatestPacketSentSeconds: number = -1;
  @State private runtimeRttMillis: number = -1;
  @State private runtimeUpdatedAt: number = 0;
  @State private startingTunnelId: string = '';
  @State private startingTunnelName: string = '';
  @State private currentTabIndex: number = TAB_TUNNELS;
  @State private appSplitEnabled: boolean = false;
  @State private smartAgentEnabled: boolean = false;
  @State private dohEnabled: boolean = true;
  @State private persistentProtectionEnabled: boolean = true;
  @State private dohProvider: string = 'https://dns.alidns.com/dns-query';
  @State private selectedSplitApps: SplitAppInfo[] = [];
  @State private appPickerOpen: boolean = false;
  @State private availableSplitApps: SplitAppInfo[] = [];
  @State private draftSelectedBundleNames: string[] = [];
  @State private appPickerLoading: boolean = false;
  @State private appPickerError: string = '';
  @State private appBundleNameInput: string = '';
  @State private appPickerNotice: string = '';
  @State private logs: AgentLogEntry[] = [];
  @State private tabBarWidth: number = 0;
  @State private tabIndicatorProgress: number = TAB_TUNNELS;
  @State private tabIndicatorAnimationDuration: number = 240;
  @State private highlightedTabIndex: number = TAB_TUNNELS;
  private statusRefreshTimer: number = -1;
  private swipeStartDeleteWidth: number = 0;
  private continuousTaskRunning: boolean = false;
  private continuousTaskStartFailedAt: number = 0;

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'aboutToAppear');
    this.loadTunnelList();
    this.loadAppSplitSettings();
    this.refreshRuntimeStatus();
    this.startStatusRefresh();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'aboutToDisappear');
    this.stopStatusRefresh();
  }

  build() {
    Column() {
      if (this.editingTunnelId.length > 0) {
        this.buildEditorHeader();
        this.buildTunnelEditor();
      } else if (this.appPickerOpen) {
        this.buildAppPickerHeader();
        this.buildAppPickerPage();
      } else {
        this.buildMainHeader();
        this.buildMainTabs();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private buildEditorHeader() {
    Row() {
      Button() {
        Image($r('app.media.ic_back_blue'))
          .width(22)
          .height(22)
      }
        .enabled(!this.busy)
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ right: 12 })
        .onClick(() => {
          this.closeEditor();
        })

      Row() {
        Image($r('app.media.ic_key_blue'))
          .width(22)
          .height(22)
          .margin({ right: 12 })
        Text('SmartAgent')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Button() {
        Image($r('app.media.ic_delete_blue'))
          .width(22)
          .height(22)
      }
        .enabled(!this.busy && !this.isEditingActiveTunnel())
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ left: 8 })
        .onClick(() => {
          this.deleteTunnelById(this.editingTunnelId);
        })

      Button() {
        Image($r('app.media.ic_check_blue'))
          .width(22)
          .height(22)
      }
        .enabled(!this.busy && !this.isEditingActiveTunnel())
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ left: 8 })
        .onClick(() => {
          this.saveEditingTunnel();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    .backgroundColor(CARD_BACKGROUND)
    .shadow({ radius: 14, color: '#10000000', offsetX: 0, offsetY: 2 })
    .zIndex(2)
  }

  @Builder
  private buildAppPickerHeader() {
    Row() {
      Button() {
        Image($r('app.media.ic_back_blue'))
          .width(22)
          .height(22)
      }
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ right: 12 })
        .onClick(() => {
          this.closeAppPicker();
        })

      Column() {
        Text('选择应用')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text('仅选中的应用流量走 VPN')
          .fontSize(12)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        Image($r('app.media.ic_check_blue'))
          .width(22)
          .height(22)
      }
        .enabled(!this.appPickerLoading)
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .backgroundColor(ACTION_BUTTON_BACKGROUND)
        .borderRadius(ACTION_BUTTON_RADIUS)
        .borderWidth(0)
        .margin({ left: 8 })
        .onClick(() => {
          this.saveAppPickerSelection().catch((err: BusinessError) => {
            this.appPickerError = err.message ?? JSON.stringify(err);
          });
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    .backgroundColor(CARD_BACKGROUND)
    .shadow({ radius: 14, color: '#10000000', offsetX: 0, offsetY: 2 })
    .zIndex(2)
  }

  @Builder
  private buildMainHeader() {
    Row() {
      Image($r('app.media.ic_key_blue'))
        .width(24)
        .height(24)
        .margin({ right: 12 })
      Text('SmartAgent')
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .maxLines(1)
    }
    .width('100%')
    .height(76)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 22, right: 22, top: 16 })
    .backgroundColor(CARD_BACKGROUND)
  }

  @Builder
  private buildMainTabs() {
    Column() {
      this.buildAnimatedTabBar();

      Tabs({ barPosition: BarPosition.Start, index: this.currentTabIndex }) {
        TabContent() {
          this.buildTunnelsPage();
        }

        TabContent() {
          this.buildRulesPage();
        }

        TabContent() {
          this.buildLogsPage();
        }
      }
      .barHeight(0)
      .vertical(false)
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        this.updateTabIndicatorFromSwipe(index, event.currentOffset);
      })
      .onAnimationStart((index: number, targetIndex: number) => {
        this.animateTabIndicatorTo(targetIndex);
      })
      .onAnimationEnd((index: number) => {
        this.completeTabIndicator(index);
      })
      .onChange((index: number) => {
        this.setCurrentTab(index);
      })
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(PAGE_BACKGROUND)
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private buildAnimatedTabBar() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row() {
        this.buildTabButton('Tunnels', TAB_TUNNELS);
        this.buildTabButton('Rules', TAB_RULES);
        this.buildTabButton('Logs', TAB_LOGS);
      }
      .width('100%')
      .height(54)

      Row() {
      }
        .width(48)
        .height(4)
        .backgroundColor(PRIMARY_BLUE)
        .borderRadius(3)
        .offset({ x: this.tabIndicatorOffset(), y: 0 })
        .animation({ duration: this.tabIndicatorAnimationDuration, curve: Curve.EaseInOut })
    }
    .width('100%')
    .height(54)
    .backgroundColor(CARD_BACKGROUND)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.tabBarWidth = Number(newValue.width);
    })
  }

  @Builder
  private buildTabButton(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.highlightedTabIndex === index ? PRIMARY_BLUE : '#777A80')
        .height(44)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .height(54)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.setCurrentTab(index);
    })
  }

  @Builder
  private buildTunnelsPage() {
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
          this.importConfig();
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
        this.openTunnel(tunnel);
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
      this.toggleTunnel(tunnel);
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

  @Builder
  private buildAppPickerPage() {
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
              this.loadAvailableSplitApps();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 28, right: 28 })
      } else {
        this.buildAppBundleInput()

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
            this.appBundleNameInput = value;
            this.appPickerNotice = '';
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
            this.addSplitAppByBundleName().catch((err: BusinessError) => {
              this.appPickerNotice = err.message ?? JSON.stringify(err);
            });
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
      this.toggleDraftSplitApp(app.bundleName);
    })
  }

  @Builder
  private buildRulesPage() {
    Scroll() {
      Column() {
        this.buildAppSplitCard();
        this.buildSimpleRuleCard('Smart Agent', '按规则从上到下匹配隧道', 'smartAgent', () => {
          this.smartAgentEnabled = !this.smartAgentEnabled;
        });
        this.buildDohCard();
        this.buildSimpleRuleCard('Persistent Protection', '关闭电池优化 避免数据断连', 'persistentProtection', () => {
          this.persistentProtectionEnabled = !this.persistentProtectionEnabled;
        });
        this.buildNavigationRuleCard('Disable Power Guard', '允许自启与后台活动 保持连接稳定');

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
          this.toggleAppSplit().catch((err: BusinessError) => {
            this.statusText = err.message ?? JSON.stringify(err);
          });
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
              Text('已选 ' + String(this.selectedSplitApps.length) + ' 个应用')
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
              this.openAppPicker().catch((err: BusinessError) => {
                this.statusText = err.message ?? JSON.stringify(err);
              });
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
          this.dohEnabled = !this.dohEnabled;
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
        this.rotateDohProvider();
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
  }

  @Builder
  private buildLogsPage() {
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
            this.logs = [];
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
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
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

  @Builder
  private buildTunnelList() {
    Column() {
      this.buildStatusCard();

      if (this.tunnels.length === 0) {
        Column() {
          Text('No tunnels')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
          Text('Import a WireGuard config')
            .fontSize(13)
            .fontColor('#6B7280')
            .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.tunnels, (tunnel: TunnelConfig) => {
            ListItem() {
              Row() {
                this.buildTunnelRowContent(tunnel);
                this.buildDeleteSwipeAction(tunnel);
              }
              .width('100%')
              .height(TUNNEL_ROW_HEIGHT)
              .gesture(
                PanGesture({ direction: PanDirection.Horizontal })
                  .onActionStart(() => {
                    this.beginTunnelSwipe(tunnel);
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.updateTunnelSwipe(tunnel, event);
                  })
                  .onActionEnd(() => {
                    this.endTunnelSwipe(tunnel);
                  })
              )
            }
            .margin({ bottom: 10 })
          }, (tunnel: TunnelConfig) => this.tunnelCardKey(tunnel))
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 18, right: 18, bottom: 18 })
  }

  @Builder
  private buildStatusCard() {
    Column() {
      Row() {
        Column() {
          Text(this.runtimeRunning ? 'Connected' : 'Disconnected')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
          Text(this.runtimeTunnelLabel())
            .fontSize(12)
            .fontColor('#6B7280')
            .maxLines(1)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(this.runtimeRunning ? '#1A7F37' : '#9CA3AF')
          Text(this.runtimeRunning ? 'Running' : 'Idle')
            .fontSize(12)
            .fontColor(this.runtimeRunning ? '#1A7F37' : '#6B7280')
            .margin({ left: 6 })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')

      Row() {
        this.buildUploadMetric();
        this.buildDownloadMetric();
        this.buildRttMetric();
      }
      .width('100%')
      .margin({ top: 14 })

      Row() {
        this.buildHandshakeMetric();
        this.buildLastPacketMetric();
        this.buildMetricSpacer();
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(STATUS_CARD_RADIUS)
    .margin({ bottom: 12 })
  }

  @Builder
  private buildUploadMetric() {
    Column() {
      Text('Upload')
        .fontSize(11)
        .fontColor('#6B7280')
        .maxLines(1)
      Text(this.formatBytes(this.runtimeTxBytes))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .maxLines(1)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  private buildDownloadMetric() {
    Column() {
      Text('Download')
        .fontSize(11)
        .fontColor('#6B7280')
        .maxLines(1)
      Text(this.formatBytes(this.runtimeRxBytes))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .maxLines(1)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  private buildHandshakeMetric() {
    Column() {
      Text('Handshake')
        .fontSize(11)
        .fontColor('#6B7280')
        .maxLines(1)
      Text(this.formatHandshake(this.runtimeLatestHandshakeSeconds))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .maxLines(1)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  private buildLastPacketMetric() {
    Column() {
      Text('Last packet')
        .fontSize(11)
        .fontColor('#6B7280')
        .maxLines(1)
      Text(this.formatAge(this.runtimeLatestPacketSentSeconds))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .maxLines(1)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  private buildRttMetric() {
    Column() {
      Text('RTT')
        .fontSize(11)
        .fontColor('#6B7280')
        .maxLines(1)
      Text(this.formatRtt(this.runtimeRttMillis))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .maxLines(1)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  private buildMetricSpacer() {
    Blank()
      .layoutWeight(1)
  }

  @Builder
  private buildTunnelEditor() {
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
        .enabled(!this.isEditingActiveTunnel())
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 12 })
        .onChange((value: string) => {
          this.editingName = value;
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
        .enabled(!this.isEditingActiveTunnel())
        .padding(12)
        .margin({ bottom: 12 })
        .onChange((value: string) => {
          this.editingConfig = value;
        })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 18, right: 18, top: 18 })
  }

  @Builder
  private buildTunnelRowContent(tunnel: TunnelConfig) {
    Row() {
      Column() {
        Text(tunnel.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .maxLines(1)
        Text(this.isTunnelRunning(tunnel) ? 'Running' : 'Saved')
          .fontSize(12)
          .fontColor(this.isTunnelRunning(tunnel) ? RUNNING_STATUS_COLOR : '#6B7280')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        if (this.isTunnelSwipeOpen(tunnel)) {
          this.closeTunnelSwipe();
          return;
        }
        if (!this.isTunnelRunning(tunnel)) {
          this.openTunnel(tunnel);
        }
      })

      this.buildPowerButton(tunnel);
    }
      .layoutWeight(1)
      .padding(14)
      .height(TUNNEL_ROW_HEIGHT)
      .backgroundColor(this.isTunnelRunning(tunnel) ? RUNNING_TUNNEL_BACKGROUND : '#FFFFFF')
      .borderRadius(this.buildTunnelContentRadius(tunnel))
  }

  @Builder
  private buildDeleteSwipeAction(tunnel: TunnelConfig) {
    Row() {
      Image($r('app.media.ic_delete_red'))
        .width(22)
        .height(22)
        .opacity(this.deleteWidthForTunnel(tunnel) >= 44 ? 1 : 0)
    }
      .width(this.deleteWidthForTunnel(tunnel))
      .height(TUNNEL_ROW_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#FDECEC')
      .borderRadius(this.buildDeleteActionRadius())
      .clip(true)
      .enabled(!this.busy)
      .onClick(() => {
        this.deleteTunnelById(tunnel.id);
      })
  }

  @Builder
  private buildPowerButton(tunnel: TunnelConfig) {
    Button() {
      if (this.isTunnelRunning(tunnel)) {
        Image($r('app.media.ic_power_off_red'))
          .width(24)
          .height(24)
      } else {
        Image($r('app.media.ic_power_blue'))
          .width(24)
          .height(24)
      }
    }
      .enabled(!this.busy)
      .type(ButtonType.Normal)
      .width(52)
      .height(44)
      .backgroundColor(this.isTunnelRunning(tunnel) ? STOP_BUTTON_BACKGROUND : ACTION_BUTTON_BACKGROUND)
      .borderRadius(ACTION_BUTTON_RADIUS)
      .onClick(() => {
        this.toggleTunnel(tunnel);
      })
  }

  private buildTunnelContentRadius(tunnel: TunnelConfig): BorderRadiuses {
    if (this.isTunnelSwipeOpen(tunnel)) {
      const swipingRadius: BorderRadiuses = {
        topLeft: TUNNEL_ROW_RADIUS,
        bottomLeft: TUNNEL_ROW_RADIUS,
        topRight: 0,
        bottomRight: 0
      };
      return swipingRadius;
    }

    const normalRadius: BorderRadiuses = {
      topLeft: TUNNEL_ROW_RADIUS,
      bottomLeft: TUNNEL_ROW_RADIUS,
      topRight: TUNNEL_ROW_RADIUS,
      bottomRight: TUNNEL_ROW_RADIUS
    };
    return normalRadius;
  }

  private buildDeleteActionRadius(): BorderRadiuses {
    const radius: BorderRadiuses = {
      topLeft: 0,
      bottomLeft: 0,
      topRight: TUNNEL_ROW_RADIUS,
      bottomRight: TUNNEL_ROW_RADIUS
    };
    return radius;
  }

  private beginTunnelSwipe(tunnel: TunnelConfig): void {
    if (this.isTunnelRunning(tunnel)) {
      this.closeTunnelSwipe();
      return;
    }

    if (this.swipingTunnelId !== tunnel.id) {
      this.swipingTunnelId = tunnel.id;
      this.swipeDeleteWidth = 0;
    }
    this.swipeStartDeleteWidth = this.swipeDeleteWidth;
  }

  private updateTunnelSwipe(tunnel: TunnelConfig, event: GestureEvent): void {
    if (this.isTunnelRunning(tunnel)) {
      return;
    }
    if (this.swipingTunnelId !== tunnel.id) {
      this.swipingTunnelId = tunnel.id;
    }

    this.swipeDeleteWidth = this.clampDeleteWidth(this.swipeStartDeleteWidth - event.offsetX);
  }

  private endTunnelSwipe(tunnel: TunnelConfig): void {
    if (this.swipingTunnelId !== tunnel.id) {
      return;
    }
    if (this.swipeDeleteWidth >= TUNNEL_DELETE_WIDTH / 2) {
      this.swipeDeleteWidth = TUNNEL_DELETE_WIDTH;
    } else {
      this.closeTunnelSwipe();
    }
  }

  private closeTunnelSwipe(): void {
    this.swipingTunnelId = '';
    this.swipeDeleteWidth = 0;
    this.swipeStartDeleteWidth = 0;
  }

  private isTunnelSwipeOpen(tunnel: TunnelConfig): boolean {
    return this.swipingTunnelId === tunnel.id && this.swipeDeleteWidth > 0;
  }

  private deleteWidthForTunnel(tunnel: TunnelConfig): number {
    if (this.swipingTunnelId !== tunnel.id || this.isTunnelRunning(tunnel)) {
      return 0;
    }
    return this.swipeDeleteWidth;
  }

  private clampDeleteWidth(width: number): number {
    if (width < 0) {
      return 0;
    }
    if (width > TUNNEL_DELETE_WIDTH) {
      return TUNNEL_DELETE_WIDTH;
    }
    return width;
  }

  private async loadTunnelList(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.tunnels = await loadTunnels(context);
      if (this.tunnels.length === 0) {
        this.statusText = 'No tunnels';
      }
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    }
  }

  private openTunnel(tunnel: TunnelConfig): void {
    this.editingTunnelId = tunnel.id;
    this.editingName = tunnel.name;
    this.editingConfig = tunnel.configText;
  }

  private closeEditor(): void {
    this.editingTunnelId = '';
    this.editingName = '';
    this.editingConfig = DEFAULT_WG_CONFIG;
  }

  private closeAppPicker(): void {
    this.appPickerOpen = false;
    this.appPickerLoading = false;
    this.appPickerError = '';
    this.appBundleNameInput = '';
    this.appPickerNotice = '';
    this.availableSplitApps = [];
    this.draftSelectedBundleNames = [];
  }

  private async loadAppSplitSettings(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.appSplitEnabled = await loadAppSplitEnabled(context, true);
      this.selectedSplitApps = await loadSelectedSplitApps(context, true);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load app split settings failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private async toggleAppSplit(): Promise<void> {
    const nextEnabled = !this.appSplitEnabled;
    this.appSplitEnabled = nextEnabled;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await saveAppSplitEnabled(context, nextEnabled);
      await this.restartVpnIfRunning('app split toggle');
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    }
  }

  private async openAppPicker(): Promise<void> {
    if (!this.appSplitEnabled) {
      return;
    }

    this.appPickerOpen = true;
    this.draftSelectedBundleNames = this.bundleNamesForApps(this.selectedSplitApps);
    await this.loadAvailableSplitApps();
  }

  private async loadAvailableSplitApps(): Promise<void> {
    this.appPickerLoading = true;
    this.appPickerError = '';
    this.availableSplitApps = this.mergeSelectedSplitApps([]);
    this.appPickerLoading = false;
    hilog.info(DOMAIN, TAG, 'loaded manual split app list count=%{public}d', this.availableSplitApps.length);
  }

  private async addSplitAppByBundleName(): Promise<void> {
    const bundleName = this.normalizeBundleName(this.appBundleNameInput);
    if (bundleName.length === 0) {
      this.appPickerNotice = '请输入应用包名';
      return;
    }
    if (bundleName === BUNDLE_NAME) {
      this.appPickerNotice = '不能选择当前 VPN 应用';
      return;
    }
    if (this.hasSplitApp(this.availableSplitApps, bundleName)) {
      this.toggleDraftBundleOn(bundleName);
      this.appBundleNameInput = '';
      this.appPickerNotice = '已在列表中';
      return;
    }

    const app: SplitAppInfo = {
      bundleName: bundleName,
      label: bundleName
    };
    this.availableSplitApps = this.appendAndSortSplitApp(this.availableSplitApps, app);
    this.toggleDraftBundleOn(app.bundleName);
    this.appBundleNameInput = '';
    this.appPickerNotice = '已添加 ' + app.bundleName;
  }

  private appendAndSortSplitApp(apps: SplitAppInfo[], app: SplitAppInfo): SplitAppInfo[] {
    const nextApps: SplitAppInfo[] = [];
    let exists = false;
    for (let index = 0; index < apps.length; index++) {
      const existing = apps[index];
      if (existing.bundleName === app.bundleName) {
        nextApps.push(app);
        exists = true;
      } else {
        nextApps.push(existing);
      }
    }
    if (!exists) {
      nextApps.push(app);
    }
    nextApps.sort((left: SplitAppInfo, right: SplitAppInfo) => left.label.localeCompare(right.label));
    return nextApps;
  }

  private hasSplitApp(apps: SplitAppInfo[], bundleName: string): boolean {
    for (let index = 0; index < apps.length; index++) {
      if (apps[index].bundleName === bundleName) {
        return true;
      }
    }
    return false;
  }

  private mergeSelectedSplitApps(apps: SplitAppInfo[]): SplitAppInfo[] {
    const merged: SplitAppInfo[] = [];
    const bundleNames: string[] = [];
    for (let index = 0; index < apps.length; index++) {
      const app = apps[index];
      merged.push(app);
      bundleNames.push(app.bundleName);
    }

    for (let index = 0; index < this.selectedSplitApps.length; index++) {
      const app = this.selectedSplitApps[index];
      if (!this.hasString(bundleNames, app.bundleName)) {
        merged.push(app);
        bundleNames.push(app.bundleName);
      }
    }
    return merged;
  }

  private async saveAppPickerSelection(): Promise<void> {
    const selectedApps: SplitAppInfo[] = [];
    for (let index = 0; index < this.availableSplitApps.length; index++) {
      const app = this.availableSplitApps[index];
      if (this.isDraftAppSelected(app.bundleName)) {
        selectedApps.push(app);
      }
    }

    const context = getContext(this) as common.UIAbilityContext;
    await saveSelectedSplitApps(context, selectedApps);
    this.selectedSplitApps = selectedApps;
    this.closeAppPicker();
    await this.restartVpnIfRunning('app split apps');
  }

  private async restartVpnIfRunning(reason: string): Promise<void> {
    if (!this.runtimeRunning && !this.vpnEnabled) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'restart vpn for rule change reason=%{public}s', reason);
    await vpnExtension.startVpnExtensionAbility(this.buildWant());
    this.statusText = 'Rules updated';
  }

  private bundleNamesForApps(apps: SplitAppInfo[]): string[] {
    const bundleNames: string[] = [];
    for (let index = 0; index < apps.length; index++) {
      bundleNames.push(apps[index].bundleName);
    }
    return bundleNames;
  }

  private isDraftAppSelected(bundleName: string): boolean {
    return this.hasString(this.draftSelectedBundleNames, bundleName);
  }

  private toggleDraftSplitApp(bundleName: string): void {
    const nextBundleNames: string[] = [];
    let removed = false;
    for (let index = 0; index < this.draftSelectedBundleNames.length; index++) {
      const value = this.draftSelectedBundleNames[index];
      if (value === bundleName) {
        removed = true;
      } else {
        nextBundleNames.push(value);
      }
    }

    if (!removed) {
      nextBundleNames.push(bundleName);
    }
    this.draftSelectedBundleNames = nextBundleNames;
  }

  private toggleDraftBundleOn(bundleName: string): void {
    if (this.hasString(this.draftSelectedBundleNames, bundleName)) {
      return;
    }

    const nextBundleNames: string[] = [];
    for (let index = 0; index < this.draftSelectedBundleNames.length; index++) {
      nextBundleNames.push(this.draftSelectedBundleNames[index]);
    }
    nextBundleNames.push(bundleName);
    this.draftSelectedBundleNames = nextBundleNames;
  }

  private normalizeBundleName(value: string): string {
    return value.trim();
  }

  private hasString(values: string[], value: string): boolean {
    for (let index = 0; index < values.length; index++) {
      if (values[index] === value) {
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

  private async saveEditingTunnel(): Promise<void> {
    if (this.editingTunnelId.length === 0) {
      return;
    }
    if (this.isEditingActiveTunnel()) {
      this.statusText = 'Stop VPN before editing';
      return;
    }

    this.busy = true;
    try {
      parseWireGuardConfig(this.editingConfig);
      const context = getContext(this) as common.UIAbilityContext;
      const name = this.normalizedTunnelName(this.editingName);
      const tunnel: TunnelConfig = {
        id: this.editingTunnelId,
        name: name,
        configText: this.editingConfig
      };
      await saveTunnel(context, tunnel);
      this.tunnels = await loadTunnels(context);
      this.closeEditor();
      this.statusText = 'Saved';
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    } finally {
      this.busy = false;
    }
  }

  private async importConfig(): Promise<void> {
    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = CONFIG_FILE_SUFFIX_FILTERS;
      options.maxSelectNumber = 1;

      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        this.statusText = 'Import canceled';
        return;
      }

      const importedConfig = await this.readImportedText(uris[0]);
      parseWireGuardConfig(importedConfig);
      const tunnel: TunnelConfig = {
        id: createTunnelId(),
        name: this.nextTunnelName(),
        configText: importedConfig
      };
      await saveTunnel(context, tunnel);
      this.tunnels = await loadTunnels(context);
      this.openTunnel(tunnel);
      this.statusText = 'Imported';
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    } finally {
      this.busy = false;
    }
  }

  private async readImportedText(uri: string): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(MAX_IMPORT_CONFIG_BYTES);
      const readOptions: ReadOptions = {
        length: MAX_IMPORT_CONFIG_BYTES
      };
      const bytesRead = await fileIo.read(file.fd, data, readOptions);
      if (bytesRead <= 0) {
        return '';
      }
      if (bytesRead >= MAX_IMPORT_CONFIG_BYTES) {
        throw new Error('Config file is too large');
      }

      const bytes = new Uint8Array(data, 0, bytesRead);
      return buffer.from(bytes).toString('utf8');
    } finally {
      await fileIo.close(file);
    }
  }

  private async toggleTunnel(tunnel: TunnelConfig): Promise<void> {
    this.busy = true;
    try {
      if (this.isTunnelRunning(tunnel)) {
        await this.stopActiveVpn();
        return;
      }

      await this.startTunnel(tunnel);
    } catch (err) {
      const error = err as BusinessError;
      if (this.startingTunnelId === tunnel.id) {
        this.clearRequestedRuntimeTunnel();
      }
      this.statusText = error.message ?? JSON.stringify(err);
    } finally {
      this.busy = false;
    }
  }

  private async startTunnel(tunnel: TunnelConfig): Promise<void> {
    hilog.info(DOMAIN, TAG, 'start tunnel requested id=%{public}s name=%{public}s', tunnel.id, tunnel.name);
    parseWireGuardConfig(tunnel.configText);
    this.markRequestedRuntimeTunnel(tunnel);
    const context = getContext(this) as common.UIAbilityContext;
    const notificationEnabled = await this.ensureNotificationEnabled(context);
    const switching = this.runtimeRunning || this.vpnEnabled;

    await saveActiveTunnel(context, tunnel);
    hilog.info(DOMAIN, TAG, 'active tunnel saved id=%{public}s name=%{public}s', tunnel.id, tunnel.name);
    await saveTunnelRuntimeStatus(context, this.buildPendingRuntimeStatus(tunnel));
    await vpnExtension.startVpnExtensionAbility(this.buildWant());
    const continuousTaskStarted = await this.ensureVpnContinuousTask(context, switching ? 'switch tunnel' : 'start tunnel');
    this.vpnEnabled = true;
    this.activeTunnelId = tunnel.id;
    this.runtimeRunning = true;
    this.runtimeTunnelId = tunnel.id;
    this.runtimeTunnelName = tunnel.name;
    this.runtimeTxBytes = 0;
    this.runtimeRxBytes = 0;
    this.runtimeLatestHandshakeSeconds = -1;
    this.runtimeLatestPacketSentSeconds = -1;
    this.runtimeRttMillis = -1;
    this.runtimeUpdatedAt = Date.now();
    if (!continuousTaskStarted) {
      this.statusText = 'Enabled, background task failed';
    } else if (switching) {
      this.statusText = notificationEnabled ? 'Switched: ' + tunnel.name : 'Switched, notification disabled';
    } else {
      this.statusText = notificationEnabled ? 'Enabled: ' + tunnel.name : 'Enabled, notification disabled';
    }
    hilog.info(
      DOMAIN,
      TAG,
      'start vpn extension returned id=%{public}s name=%{public}s switching=%{public}s',
      tunnel.id,
      tunnel.name,
      String(switching)
    );
  }

  private async stopActiveVpn(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'stop active vpn requested activeId=%{public}s runtimeRunning=%{public}s', this.activeTunnelId, String(this.runtimeRunning));
    const context = getContext(this) as common.UIAbilityContext;
    await vpnExtension.stopVpnExtensionAbility(this.buildWant());
    await this.stopVpnContinuousTask(context, 'stop vpn');
    await clearActiveTunnel(context);
    await saveTunnelRuntimeStatus(context, this.buildStoppedRuntimeStatus());
    this.vpnEnabled = false;
    this.activeTunnelId = '';
    this.runtimeRunning = false;
    this.runtimeTunnelId = '';
    this.runtimeTunnelName = '';
    this.runtimeTxBytes = 0;
    this.runtimeRxBytes = 0;
    this.runtimeLatestHandshakeSeconds = -1;
    this.runtimeLatestPacketSentSeconds = -1;
    this.runtimeRttMillis = -1;
    this.runtimeUpdatedAt = Date.now();
    this.clearRequestedRuntimeTunnel();
    this.statusText = 'Stopped';
    hilog.info(DOMAIN, TAG, 'stop active vpn finished');
  }

  private async ensureVpnContinuousTask(context: common.UIAbilityContext, reason: string): Promise<boolean> {
    if (this.continuousTaskRunning) {
      return true;
    }

    const now = Date.now();
    if (this.continuousTaskStartFailedAt > 0 && now - this.continuousTaskStartFailedAt < CONTINUOUS_TASK_RETRY_MS) {
      return false;
    }

    try {
      await startVpnDataTransferTask(context);
      this.continuousTaskRunning = true;
      this.continuousTaskStartFailedAt = 0;
      hilog.info(DOMAIN, TAG, 'continuous task started reason=%{public}s', reason);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      this.continuousTaskStartFailedAt = Date.now();
      hilog.warn(
        DOMAIN,
        TAG,
        'start continuous task failed reason=%{public}s code=%{public}d message=%{public}s',
        reason,
        error.code,
        error.message ?? JSON.stringify(err)
      );
      return false;
    }
  }

  private async stopVpnContinuousTask(context: common.UIAbilityContext, reason: string): Promise<void> {
    try {
      await stopVpnDataTransferTask(context);
      hilog.info(DOMAIN, TAG, 'continuous task stopped reason=%{public}s', reason);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'stop continuous task failed reason=%{public}s code=%{public}d message=%{public}s',
        reason,
        error.code,
        error.message ?? JSON.stringify(err)
      );
    } finally {
      this.continuousTaskRunning = false;
      this.continuousTaskStartFailedAt = 0;
    }
  }

  private async deleteTunnelById(tunnelId: string): Promise<void> {
    if (tunnelId.length === 0) {
      return;
    }
    if (this.vpnEnabled && this.activeTunnelId === tunnelId) {
      this.statusText = 'Stop VPN before deleting';
      return;
    }

    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await deleteTunnel(context, tunnelId);
      this.tunnels = await loadTunnels(context);
      this.closeTunnelSwipe();
      if (this.editingTunnelId === tunnelId) {
        this.closeEditor();
      }
      this.statusText = 'Deleted';
    } catch (err) {
      const error = err as BusinessError;
      this.statusText = error.message ?? JSON.stringify(err);
    } finally {
      this.busy = false;
    }
  }

  private markRequestedRuntimeTunnel(tunnel: TunnelConfig): void {
    this.closeTunnelSwipe();
    this.startingTunnelId = tunnel.id;
    this.startingTunnelName = tunnel.name;
    this.runtimeUpdatedAt = Date.now();
  }

  private clearRequestedRuntimeTunnel(): void {
    this.startingTunnelId = '';
    this.startingTunnelName = '';
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
    if (switchKey === 'persistentProtection') {
      return this.persistentProtectionEnabled;
    }
    return false;
  }

  private isEditingActiveTunnel(): boolean {
    if (this.startingTunnelId.length > 0 && this.startingTunnelId === this.editingTunnelId) {
      return true;
    }
    if (!this.runtimeRunning) {
      return false;
    }
    if (this.activeTunnelId.length === 0) {
      return this.runtimeTunnelName.length > 0 && this.runtimeTunnelName === this.editingName;
    }
    return this.activeTunnelId === this.editingTunnelId;
  }

  private startStatusRefresh(): void {
    this.stopStatusRefresh();
    hilog.info(DOMAIN, TAG, 'start runtime status refresh interval=%{public}d', STATUS_REFRESH_INTERVAL_MS);
    this.statusRefreshTimer = setInterval(() => {
      this.refreshRuntimeStatus();
    }, STATUS_REFRESH_INTERVAL_MS);
  }

  private stopStatusRefresh(): void {
    if (this.statusRefreshTimer >= 0) {
      clearInterval(this.statusRefreshTimer);
      this.statusRefreshTimer = -1;
      hilog.info(DOMAIN, TAG, 'stop runtime status refresh');
    }
  }

  private async refreshRuntimeStatus(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const status = await loadTunnelRuntimeStatus(context, true);
      const wasRunning = this.runtimeRunning;
      const fresh = this.isRuntimeStatusFresh(status);
      const running = status.running && fresh;
      const hasRuntimeStats = running;

      hilog.info(
        DOMAIN,
        TAG,
        'refresh runtime rawRunning=%{public}s fresh=%{public}s showStats=%{public}s statusId=%{public}s statusName=%{public}s activeId=%{public}s updatedAt=%{public}s ageMs=%{public}s tx=%{public}s rx=%{public}s handshake=%{public}s packetSent=%{public}s rtt=%{public}s',
        String(status.running),
        String(fresh),
        String(hasRuntimeStats),
        status.tunnelId,
        status.tunnelName,
        this.activeTunnelId,
        String(status.updatedAt),
        String(this.runtimeStatusAge(status)),
        String(status.txBytes),
        String(status.rxBytes),
        String(status.latestHandshakeSeconds),
        String(status.latestPacketSentSeconds),
        String(status.rttMillis)
      );

      const resolvedTunnelId = running ? this.resolveRuntimeTunnelId(status) : '';
      const resolvedTunnelName = running ? this.resolveRuntimeTunnelName(status, resolvedTunnelId) : '';
      this.runtimeRunning = running;
      this.runtimeTunnelId = hasRuntimeStats ? resolvedTunnelId : '';
      this.runtimeTunnelName = hasRuntimeStats ? resolvedTunnelName : '';
      this.runtimeTxBytes = hasRuntimeStats ? status.txBytes : 0;
      this.runtimeRxBytes = hasRuntimeStats ? status.rxBytes : 0;
      this.runtimeLatestHandshakeSeconds = hasRuntimeStats ? status.latestHandshakeSeconds : -1;
      this.runtimeLatestPacketSentSeconds = hasRuntimeStats ? status.latestPacketSentSeconds : -1;
      this.runtimeRttMillis = hasRuntimeStats ? status.rttMillis : -1;
      this.runtimeUpdatedAt = status.updatedAt;
      this.vpnEnabled = running;
      this.activeTunnelId = resolvedTunnelId;
      if (running) {
        await this.ensureVpnContinuousTask(context, 'runtime refresh');
      }
      if (running) {
        this.closeTunnelSwipe();
        this.startingTunnelId = resolvedTunnelId;
        this.startingTunnelName = resolvedTunnelName;
      } else {
        this.clearRequestedRuntimeTunnel();
      }

      if (wasRunning && !running && !this.busy) {
        await this.stopVpnContinuousTask(context, 'runtime stopped');
        this.statusText = 'Stopped';
        hilog.info(DOMAIN, TAG, 'runtime transitioned to stopped');
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'refresh runtime status failed: %{public}s', error.message ?? JSON.stringify(err));
      if (!this.busy) {
        this.statusText = error.message ?? JSON.stringify(err);
      }
    }
  }

  private isRuntimeStatusFresh(status: TunnelRuntimeStatus): boolean {
    if (status.updatedAt <= 0) {
      return false;
    }
    return Date.now() - status.updatedAt <= STATUS_STALE_MS;
  }

  private runtimeStatusAge(status: TunnelRuntimeStatus): number {
    if (status.updatedAt <= 0) {
      return -1;
    }
    return Date.now() - status.updatedAt;
  }

  private resolveRuntimeTunnelId(status: TunnelRuntimeStatus): string {
    if (status.tunnelId.length > 0) {
      return status.tunnelId;
    }
    if (this.startingTunnelId.length > 0) {
      return this.startingTunnelId;
    }
    if (this.runtimeTunnelId.length > 0) {
      return this.runtimeTunnelId;
    }
    return this.activeTunnelId;
  }

  private resolveRuntimeTunnelName(status: TunnelRuntimeStatus, tunnelId: string): string {
    if (status.tunnelName.length > 0) {
      return status.tunnelName;
    }
    if (this.startingTunnelName.length > 0) {
      return this.startingTunnelName;
    }
    if (this.runtimeTunnelName.length > 0) {
      return this.runtimeTunnelName;
    }
    return this.tunnelNameForId(tunnelId);
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

  private setCurrentTab(index: number): void {
    if (index === this.currentTabIndex) {
      return;
    }
    this.currentTabIndex = index;
    this.highlightedTabIndex = index;
    this.animateTabIndicatorTo(index);
  }

  private updateTabIndicatorFromSwipe(index: number, currentOffset: number): void {
    if (this.tabBarWidth <= 0) {
      return;
    }

    this.tabIndicatorAnimationDuration = 0;
    this.tabIndicatorProgress = this.clampTabIndicatorProgress(index - currentOffset / this.tabBarWidth);
    this.highlightedTabIndex = this.targetTabIndexForSwipe(index, currentOffset);
  }

  private animateTabIndicatorTo(index: number): void {
    this.tabIndicatorAnimationDuration = 220;
    this.highlightedTabIndex = this.clampTabIndex(index);
    this.tabIndicatorProgress = this.clampTabIndicatorProgress(index);
  }

  private completeTabIndicator(index: number): void {
    this.currentTabIndex = index;
    this.highlightedTabIndex = index;
    this.tabIndicatorAnimationDuration = 220;
    this.tabIndicatorProgress = this.clampTabIndicatorProgress(index);
  }

  private targetTabIndexForSwipe(index: number, currentOffset: number): number {
    if (Math.abs(currentOffset) < 1) {
      return this.clampTabIndex(index);
    }
    if (currentOffset < 0) {
      return this.clampTabIndex(index + 1);
    }
    return this.clampTabIndex(index - 1);
  }

  private clampTabIndex(index: number): number {
    if (index < TAB_TUNNELS) {
      return TAB_TUNNELS;
    }
    if (index > TAB_LOGS) {
      return TAB_LOGS;
    }
    return index;
  }

  private clampTabIndicatorProgress(progress: number): number {
    if (Number.isNaN(progress)) {
      return this.currentTabIndex;
    }
    if (progress < TAB_TUNNELS) {
      return TAB_TUNNELS;
    }
    if (progress > TAB_LOGS) {
      return TAB_LOGS;
    }
    return progress;
  }

  private tabIndicatorOffset(): number {
    if (this.tabBarWidth <= 0) {
      return 0;
    }
    const tabWidth = this.tabBarWidth / 3;
    return tabWidth * this.tabIndicatorProgress + (tabWidth - 48) / 2;
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

  private rotateDohProvider(): void {
    if (this.dohProvider === 'https://dns.alidns.com/dns-query') {
      this.dohProvider = 'https://cloudflare-dns.com/dns-query';
    } else if (this.dohProvider === 'https://cloudflare-dns.com/dns-query') {
      this.dohProvider = 'https://dns.google/dns-query';
    } else {
      this.dohProvider = 'https://dns.alidns.com/dns-query';
    }
  }

  private buildStoppedRuntimeStatus(): TunnelRuntimeStatus {
    const status: TunnelRuntimeStatus = {
      running: false,
      tunnelId: '',
      tunnelName: '',
      txBytes: 0,
      rxBytes: 0,
      latestHandshakeSeconds: -1,
      latestPacketSentSeconds: -1,
      loss: 0,
      rttMillis: -1,
      updatedAt: Date.now()
    };
    return status;
  }

  private buildPendingRuntimeStatus(tunnel: TunnelConfig): TunnelRuntimeStatus {
    const status: TunnelRuntimeStatus = {
      running: true,
      tunnelId: tunnel.id,
      tunnelName: tunnel.name,
      txBytes: 0,
      rxBytes: 0,
      latestHandshakeSeconds: -1,
      latestPacketSentSeconds: -1,
      loss: 0,
      rttMillis: -1,
      updatedAt: Date.now()
    };
    return status;
  }

  private formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return String(Math.floor(bytes)) + ' B';
    }
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toFixed(1) + ' KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }
    return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
  }

  private formatHandshake(seconds: number): string {
    return this.formatAge(seconds);
  }

  private formatAge(seconds: number): string {
    if (seconds < 0) {
      return '-';
    }
    if (seconds < 60) {
      return String(Math.floor(seconds)) + 's ago';
    }
    if (seconds < 3600) {
      return String(Math.floor(seconds / 60)) + 'm ago';
    }
    return String(Math.floor(seconds / 3600)) + 'h ago';
  }

  private formatRtt(rttMillis: number): string {
    if (rttMillis < 0) {
      return '-';
    }
    return rttMillis.toFixed(0) + ' ms';
  }

  private normalizedTunnelName(name: string): string {
    const normalized = name.trim();
    if (normalized.length > 0) {
      return normalized;
    }
    return 'Tunnel';
  }

  private nextTunnelName(): string {
    return 'Tunnel ' + String(this.tunnels.length + 1);
  }

  private async ensureNotificationEnabled(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }

      await notificationManager.requestEnableNotification(context);
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      return false;
    }
  }

  private buildWant(): Want {
    const want: Want = {
      deviceId: '',
      bundleName: BUNDLE_NAME,
      moduleName: MODULE_NAME,
      abilityName: VPN_ABILITY
    };
    return want;
  }
}
