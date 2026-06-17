import { AgentRule, AgentRuleType, TunnelConfig } from '../wireguard/ConfigStore';
import { FloatingSelect, FloatingSelectOption } from './FloatingSelect';
import {
  CARD_BACKGROUND,
  CARD_RADIUS,
  DIVIDER_COLOR,
  PAGE_BACKGROUND,
  PRIMARY_BLUE,
  TEXT_PRIMARY,
  TEXT_SECONDARY
} from './PageStyle';

const CREATE_AGENT_RULE_ID = '__create_agent_rule__';
const AGENT_RULE_TYPES: AgentRuleType[] = ['wifiGateway', 'wifiSsid', 'ipv6Available', 'ipv4Available'];
const AGENT_RULE_DROPDOWN_NONE = '';
const AGENT_RULE_DROPDOWN_TYPE = 'type';
const AGENT_RULE_DROPDOWN_TARGET = 'target';
const DOH_PROVIDER_ALIYUN = 'https://dns.alidns.com/dns-query';
const DOH_PROVIDER_GOOGLE = 'https://dns.google/dns-query';
const DOH_PROVIDER_CLOUDFLARE = 'https://cloudflare-dns.com/dns-query';
const DOH_PROVIDER_TENCENT = 'https://doh.pub/dns-query';

@Component
export struct RulesPage {
  @Prop appSplitEnabled: boolean = false;
  @Prop smartAgentEnabled: boolean = false;
  @Prop agentRules: AgentRule[] = [];
  @Prop tunnels: TunnelConfig[] = [];
  @Prop dohEnabled: boolean = true;
  @Prop dohProvider: string = '';
  @Prop selectedSplitAppCount: number = 0;
  @State private editingAgentRuleId: string = '';
  @State private draftAgentRuleType: AgentRuleType = 'wifiGateway';
  @State private draftAgentRuleMatchValue: string = '';
  @State private draftAgentRuleTargetTunnelId: string = '';
  @State private draftAgentRuleTargetTunnelName: string = '直连';
  @State private draftAgentRuleEnabled: boolean = true;
  @State private agentRuleNotice: string = '';
  @State private draggingAgentRuleId: string = '';
  @State private dragHoverAgentRuleId: string = '';
  @State private dragAgentRuleOrderIds: string[] = [];
  @State private suppressAgentRuleCardClick: boolean = false;
  @State private agentRuleDropdown: string = AGENT_RULE_DROPDOWN_NONE;
  @State private dohDropdownExpanded: boolean = false;
  onToggleAppSplit: () => void = () => {};
  onToggleSmartAgent: () => void = () => {};
  onSaveAgentRule: (rule: AgentRule) => void = () => {};
  onDeleteAgentRule: (ruleId: string) => void = () => {};
  onReorderAgentRule: (ruleId: string, targetIndex: number) => void = () => {};
  onToggleDoh: () => void = () => {};
  onSelectDohProvider: (provider: string) => void = () => {};
  onOpenAppPicker: () => void = () => {};
  onOpenIssueReport: () => void = () => {};

  build() {
    Scroll() {
      Column() {
        this.buildAppSplitCard();
        this.buildSmartAgentCard();
        if (this.smartAgentEnabled) {
          this.buildAgentRuleList();
        }
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
  private buildSmartAgentCard() {
    Row() {
      Column() {
        Text('Smart Agent')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text('按规则从上到下匹配隧道')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 10 })
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        this.buildRuleSwitchFace('smartAgent');
      }
    }
    .width('100%')
    .height(100)
    .padding({ left: 22, right: 26 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
    .onClick(() => {
      this.toggleSmartAgentFromCard();
    })
  }

  @Builder
  private buildAgentRuleList() {
    Column() {
      ForEach(this.displayedAgentRules(), (rule: AgentRule) => {
        this.buildAgentRuleCard(rule);
      }, (rule: AgentRule) => rule.id)

      if (this.editingAgentRuleId === CREATE_AGENT_RULE_ID) {
        this.buildAgentRuleFormCard(true);
      } else {
        this.buildAddAgentRuleCard();
      }
    }
    .width('100%')
    .animation({ duration: 240, curve: Curve.EaseInOut })
  }

  @Builder
  private buildAgentRuleCard(rule: AgentRule) {
    if (this.editingAgentRuleId === rule.id) {
      this.buildAgentRuleFormCard(false);
    } else {
      this.buildAgentRuleSummaryCard(rule);
    }
  }

  @Builder
  private buildAgentRuleSummaryCard(rule: AgentRule) {
    Row() {
      Row() {
        this.buildAgentRuleIcon(rule.type);
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#F6F7F9')
      .borderRadius(12)
      .margin({ right: 20 })

      Column() {
        Text(this.agentRuleTitle(rule))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text('Target: ' + this.agentRuleTargetLabel(rule))
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        Image($r('app.media.ic_edit_gray'))
          .width(24)
          .height(24)
      }
        .type(ButtonType.Normal)
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor('#00000000')
        .borderRadius(10)
        .margin({ left: 6 })

      Row() {
        Image($r('app.media.ic_drag_gray'))
          .width(24)
          .height(24)
      }
      .width(34)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ left: 2 })
      .draggable(true)
      .onDragStart(() => {
        this.startAgentRuleDrag(rule.id);
      })
      .onDragEnd(() => {
        this.endAgentRuleDrag();
      })
    }
    .width('100%')
    .height(100)
    .padding({ left: 24, right: 20 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
    .opacity(this.draggingAgentRuleId === rule.id ? 0.55 : 1)
    .border({
      width: this.dragHoverAgentRuleId === rule.id && this.draggingAgentRuleId !== rule.id ? 1 : 0,
      color: PRIMARY_BLUE,
      radius: CARD_RADIUS
    })
    .onClick(() => {
      if (this.suppressAgentRuleCardClick || this.draggingAgentRuleId.length > 0) {
        return;
      }
      this.openAgentRuleEditor(rule);
    })
    .onDragEnter(() => {
      this.previewAgentRuleDrop(rule.id);
    })
    .onDragMove(() => {
      this.previewAgentRuleDrop(rule.id);
    })
    .onDrop(() => {
      this.commitAgentRuleDrop();
    })
  }

  @Builder
  private buildAddAgentRuleCard() {
    Row() {
      Row() {
        Image($r('app.media.ic_add_rule_blue'))
          .width(30)
          .height(30)
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#F6F7F9')
      .borderRadius(12)
      .margin({ right: 20 })

      Column() {
        Text('Add Tunnel Rule')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
        Text('新增隧道匹配规则')
          .fontSize(14)
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(100)
    .padding({ left: 24, right: 26 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
    .onClick(() => {
      this.openCreateAgentRuleEditor();
    })
  }

  @Builder
  private buildAgentRuleFormCard(isCreate: boolean) {
    Column() {
      Row() {
        Row() {
          this.buildAgentRuleIcon(this.draftAgentRuleType);
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#F6F7F9')
        .borderRadius(12)
        .margin({ right: 20 })
        .onClick(() => {
          this.cancelAgentRuleEdit();
        })

        Column() {
          Text(isCreate ? 'Add Tunnel Rule' : this.draftAgentRuleTitle())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
            .onClick(() => {
              this.cancelAgentRuleEdit();
            })
          Text('Target: ' + this.draftTargetTunnelLabel())
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .maxLines(1)
            .margin({ top: 8 })
            .onClick(() => {
              this.cancelAgentRuleEdit();
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.cancelAgentRuleEdit();
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(1)
        .color(DIVIDER_COLOR)
        .margin({ top: 22, bottom: 20 })

      this.buildAgentRuleSelectRow();

      if (this.agentRuleNeedsMatch(this.draftAgentRuleType)) {
        Row() {
          Column() {
            Text(this.agentRuleMatchLabel(this.draftAgentRuleType))
              .fontSize(12)
              .fontColor(TEXT_SECONDARY)
              .maxLines(1)
              .margin({ left: 10, bottom: 6 })
            TextInput({
              text: this.draftAgentRuleMatchValue,
              placeholder: this.agentRuleMatchPlaceholder(this.draftAgentRuleType)
            })
              .width('100%')
              .height(52)
              .fontSize(16)
              .fontColor(TEXT_PRIMARY)
              .backgroundColor(CARD_BACKGROUND)
              .padding({ left: 14, right: 14 })
              .border({ width: 1, color: '#E4E7EC', radius: 10 })
              .onChange((value: string) => {
                this.draftAgentRuleMatchValue = value;
                this.agentRuleNotice = '';
              })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button() {
            Image($r('app.media.ic_wifi_blue'))
              .width(24)
              .height(24)
          }
            .type(ButtonType.Normal)
            .width(54)
            .height(52)
            .padding(0)
            .backgroundColor('#F6F7F9')
            .borderRadius(12)
            .margin({ left: 12, top: 18 })
            .onClick(() => {
              this.fillDraftRuleMatchHint();
            })
        }
        .width('100%')
        .margin({ top: 18 })
      } else {
        Row() {
          Text(this.agentRuleNoInputDescription(this.draftAgentRuleType))
            .fontSize(13)
            .fontColor(TEXT_SECONDARY)
            .maxLines(2)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .backgroundColor('#F8FAFC')
        .borderRadius(10)
        .margin({ top: 18 })
      }

      if (this.agentRuleNotice.length > 0) {
        Text(this.agentRuleNotice)
          .fontSize(12)
          .fontColor('#D14343')
          .maxLines(2)
          .width('100%')
          .margin({ top: 12 })
      }

      Row() {
        if (!isCreate) {
          Button() {
            Image($r('app.media.ic_delete_red'))
              .width(22)
              .height(22)
          }
            .type(ButtonType.Normal)
            .width(48)
            .height(48)
            .padding(0)
            .backgroundColor('#FDECEC')
            .borderRadius(12)
            .onClick(() => {
              this.deleteEditingAgentRule();
            })
        }

        Blank()
          .layoutWeight(1)

        Button() {
          Text('取消')
            .fontSize(16)
            .fontColor('#7B7F86')
        }
          .type(ButtonType.Normal)
          .height(48)
          .padding({ left: 18, right: 18 })
          .backgroundColor('#00000000')
          .borderRadius(12)
          .margin({ right: 10 })
          .onClick(() => {
            this.cancelAgentRuleEdit();
          })

        Button() {
          Text('保存')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(CARD_BACKGROUND)
        }
          .type(ButtonType.Normal)
          .height(48)
          .padding({ left: 28, right: 28 })
          .backgroundColor(PRIMARY_BLUE)
          .borderRadius(12)
          .onClick(() => {
            this.saveEditingAgentRule();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 22 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 22, bottom: 24 })
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
    .zIndex(this.agentRuleDropdown === AGENT_RULE_DROPDOWN_NONE ? 1 : 120)
    .animation({ duration: 240, curve: Curve.EaseInOut })
  }

  @Builder
  private buildAgentRuleSelectRow() {
    Row() {
      Column() {
        FloatingSelect({
          label: '条件类型',
          value: this.agentRuleTypeLabel(this.draftAgentRuleType),
          selectedValue: this.draftAgentRuleType,
          expanded: this.agentRuleDropdown === AGENT_RULE_DROPDOWN_TYPE,
          options: this.agentRuleTypeOptions(),
          menuWidth: 230,
          menuAlign: 'left',
          menuTop: 64,
          optionHeight: 58,
          maxVisibleOptions: 4,
          showCheck: false,
          highlightSelected: true,
          onToggle: () => {
            this.toggleAgentRuleDropdown(AGENT_RULE_DROPDOWN_TYPE);
          },
          onSelect: (value: string) => {
            this.selectDraftAgentRuleType(this.agentRuleTypeFromValue(value));
          }
        })
      }
      .layoutWeight(1)

      Blank()
        .width(12)

      Column() {
        FloatingSelect({
          label: '目标隧道',
          value: this.draftTargetTunnelLabel(),
          selectedValue: this.draftAgentRuleTargetTunnelId,
          expanded: this.agentRuleDropdown === AGENT_RULE_DROPDOWN_TARGET,
          options: this.agentRuleTargetOptions(),
          menuWidth: 230,
          menuAlign: 'right',
          menuTop: 64,
          optionHeight: 58,
          maxVisibleOptions: 5,
          showCheck: false,
          highlightSelected: true,
          onToggle: () => {
            this.toggleAgentRuleDropdown(AGENT_RULE_DROPDOWN_TARGET);
          },
          onSelect: (value: string) => {
            this.selectDraftTargetTunnel(value, this.targetTunnelLabelForValue(value));
          }
        })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .zIndex(80)
  }

  @Builder
  private buildAgentRuleIcon(ruleType: AgentRuleType) {
    if (ruleType === 'wifiGateway' || ruleType === 'wifiSsid') {
      Image($r('app.media.ic_wifi_blue'))
        .width(32)
        .height(32)
    } else {
      Image($r('app.media.ic_globe_gray'))
        .width(32)
        .height(32)
    }
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

      FloatingSelect({
        value: this.dohProvider,
        selectedValue: this.dohProvider,
        expanded: this.dohDropdownExpanded,
        options: this.dohProviderOptions(),
        menuWidth: 150,
        menuAlign: 'right',
        menuTop: 52,
        optionHeight: 52,
        maxVisibleOptions: 4,
        showCheck: true,
        highlightSelected: false,
        valueFontSize: 14,
        valueColor: '#7B7F86',
        showFieldDivider: true,
        onToggle: () => {
          this.toggleDohDropdown();
        },
        onSelect: (value: string) => {
          this.selectDohProvider(value);
        }
      })
      .zIndex(90)
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .backgroundColor(CARD_BACKGROUND)
    .borderRadius(CARD_RADIUS)
    .shadow({ radius: 16, color: '#08000000', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 18 })
    .zIndex(this.dohDropdownExpanded ? 110 : 1)
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

  private toggleSmartAgentFromCard(): void {
    this.runAgentRuleAnimation(() => {
      if (this.smartAgentEnabled) {
        this.resetAgentRuleEditState();
      }
      this.onToggleSmartAgent();
    });
  }

  private openCreateAgentRuleEditor(): void {
    this.runAgentRuleAnimation(() => {
      this.editingAgentRuleId = CREATE_AGENT_RULE_ID;
      this.draftAgentRuleType = 'wifiGateway';
      this.draftAgentRuleMatchValue = '';
      this.applyDefaultDraftTargetTunnel();
      this.draftAgentRuleEnabled = true;
      this.agentRuleNotice = '';
      this.agentRuleDropdown = AGENT_RULE_DROPDOWN_NONE;
      this.dohDropdownExpanded = false;
    });
  }

  private openAgentRuleEditor(rule: AgentRule): void {
    this.runAgentRuleAnimation(() => {
      this.editingAgentRuleId = rule.id;
      this.draftAgentRuleType = rule.type;
      this.draftAgentRuleMatchValue = rule.matchValue;
      this.draftAgentRuleTargetTunnelId = rule.targetTunnelId;
      this.draftAgentRuleTargetTunnelName = this.agentRuleTargetLabel(rule);
      this.draftAgentRuleEnabled = rule.enabled;
      this.agentRuleNotice = '';
      this.agentRuleDropdown = AGENT_RULE_DROPDOWN_NONE;
      this.dohDropdownExpanded = false;
    });
  }

  private cancelAgentRuleEdit(): void {
    this.runAgentRuleAnimation(() => {
      this.resetAgentRuleEditState();
    });
  }

  private saveEditingAgentRule(): void {
    if (this.editingAgentRuleId.length === 0) {
      return;
    }
    if (this.agentRuleNeedsMatch(this.draftAgentRuleType) && this.draftAgentRuleMatchValue.trim().length === 0) {
      this.agentRuleNotice = '请输入' + this.agentRuleMatchLabel(this.draftAgentRuleType);
      return;
    }

    const rule: AgentRule = {
      id: this.editingAgentRuleId === CREATE_AGENT_RULE_ID ? '' : this.editingAgentRuleId,
      type: this.draftAgentRuleType,
      matchValue: this.agentRuleNeedsMatch(this.draftAgentRuleType) ? this.draftAgentRuleMatchValue.trim() : '',
      targetTunnelId: this.draftAgentRuleTargetTunnelId,
      targetTunnelName: this.draftTargetTunnelLabel(),
      enabled: this.draftAgentRuleEnabled
    };
    this.onSaveAgentRule(rule);
    this.cancelAgentRuleEdit();
  }

  private deleteEditingAgentRule(): void {
    if (this.editingAgentRuleId.length === 0 || this.editingAgentRuleId === CREATE_AGENT_RULE_ID) {
      return;
    }
    const ruleId = this.editingAgentRuleId;
    this.cancelAgentRuleEdit();
    this.onDeleteAgentRule(ruleId);
  }

  private applyDefaultDraftTargetTunnel(): void {
    if (this.tunnels.length > 0) {
      this.draftAgentRuleTargetTunnelId = this.tunnels[0].id;
      this.draftAgentRuleTargetTunnelName = this.tunnels[0].name;
      return;
    }
    this.draftAgentRuleTargetTunnelId = '';
    this.draftAgentRuleTargetTunnelName = '直连';
  }

  private toggleAgentRuleDropdown(dropdown: string): void {
    this.runAgentRuleAnimation(() => {
      this.agentRuleDropdown = this.agentRuleDropdown === dropdown ? AGENT_RULE_DROPDOWN_NONE : dropdown;
      this.dohDropdownExpanded = false;
      this.agentRuleNotice = '';
    });
  }

  private selectDraftAgentRuleType(ruleType: AgentRuleType): void {
    this.runAgentRuleAnimation(() => {
      this.draftAgentRuleType = ruleType;
      if (!this.agentRuleNeedsMatch(this.draftAgentRuleType)) {
        this.draftAgentRuleMatchValue = '';
      }
      this.agentRuleNotice = '';
      this.agentRuleDropdown = AGENT_RULE_DROPDOWN_NONE;
    });
  }

  private selectDraftTargetTunnel(tunnelId: string, tunnelName: string): void {
    this.runAgentRuleAnimation(() => {
      this.draftAgentRuleTargetTunnelId = tunnelId;
      this.draftAgentRuleTargetTunnelName = tunnelName;
      this.agentRuleDropdown = AGENT_RULE_DROPDOWN_NONE;
    });
  }

  private toggleDohDropdown(): void {
    this.runAgentRuleAnimation(() => {
      this.dohDropdownExpanded = !this.dohDropdownExpanded;
      this.agentRuleDropdown = AGENT_RULE_DROPDOWN_NONE;
    });
  }

  private selectDohProvider(provider: string): void {
    this.runAgentRuleAnimation(() => {
      this.dohDropdownExpanded = false;
    });
    this.onSelectDohProvider(provider);
  }

  private fillDraftRuleMatchHint(): void {
    if (this.draftAgentRuleType === 'wifiGateway') {
      this.draftAgentRuleMatchValue = '192.168.0.1';
    } else if (this.draftAgentRuleType === 'wifiSsid') {
      this.draftAgentRuleMatchValue = 'Home WiFi';
    }
    this.agentRuleNotice = '';
  }

  private startAgentRuleDrag(ruleId: string): void {
    this.resetAgentRuleEditState();
    this.draggingAgentRuleId = ruleId;
    this.dragHoverAgentRuleId = '';
    this.dragAgentRuleOrderIds = this.currentAgentRuleIds();
    this.suppressAgentRuleCardClick = true;
  }

  private previewAgentRuleDrop(targetRuleId: string): void {
    if (this.draggingAgentRuleId.length === 0 || this.draggingAgentRuleId === targetRuleId) {
      return;
    }

    const orderIds = this.activeDragAgentRuleOrderIds();
    const fromIndex = this.agentRuleIdIndexIn(this.draggingAgentRuleId, orderIds);
    const toIndex = this.agentRuleIdIndexIn(targetRuleId, orderIds);
    if (fromIndex < 0 || toIndex < 0 || fromIndex === toIndex) {
      return;
    }

    const nextOrderIds: string[] = [];
    for (let index = 0; index < orderIds.length; index++) {
      if (index !== fromIndex) {
        nextOrderIds.push(orderIds[index]);
      }
    }
    if (toIndex >= nextOrderIds.length) {
      nextOrderIds.push(this.draggingAgentRuleId);
    } else {
      const reorderedIds: string[] = [];
      for (let index = 0; index < nextOrderIds.length; index++) {
        if (index === toIndex) {
          reorderedIds.push(this.draggingAgentRuleId);
        }
        reorderedIds.push(nextOrderIds[index]);
      }
      nextOrderIds.length = 0;
      for (let index = 0; index < reorderedIds.length; index++) {
        nextOrderIds.push(reorderedIds[index]);
      }
    }

    this.runAgentRuleAnimation(() => {
      this.dragHoverAgentRuleId = targetRuleId;
      this.dragAgentRuleOrderIds = nextOrderIds;
    });
  }

  private commitAgentRuleDrop(): void {
    if (this.draggingAgentRuleId.length === 0) {
      this.endAgentRuleDrag();
      return;
    }

    const originalIndex = this.agentRuleIndex(this.draggingAgentRuleId);
    const targetIndex = this.agentRuleIdIndexIn(this.draggingAgentRuleId, this.activeDragAgentRuleOrderIds());
    if (originalIndex >= 0 && targetIndex >= 0 && originalIndex !== targetIndex) {
      this.onReorderAgentRule(this.draggingAgentRuleId, targetIndex);
    }

    this.endAgentRuleDrag();
  }

  private endAgentRuleDrag(): void {
    this.draggingAgentRuleId = '';
    this.dragHoverAgentRuleId = '';
    this.dragAgentRuleOrderIds = [];
    this.suppressAgentRuleCardClick = true;
    setTimeout(() => {
      this.suppressAgentRuleCardClick = false;
    }, 120);
  }

  private resetAgentRuleEditState(): void {
    this.editingAgentRuleId = '';
    this.draftAgentRuleType = 'wifiGateway';
    this.draftAgentRuleMatchValue = '';
    this.draftAgentRuleTargetTunnelId = '';
    this.draftAgentRuleTargetTunnelName = '直连';
    this.draftAgentRuleEnabled = true;
    this.agentRuleNotice = '';
    this.agentRuleDropdown = AGENT_RULE_DROPDOWN_NONE;
    this.dohDropdownExpanded = false;
    this.draggingAgentRuleId = '';
    this.dragHoverAgentRuleId = '';
    this.dragAgentRuleOrderIds = [];
    this.suppressAgentRuleCardClick = false;
  }

  private agentRuleIndex(ruleId: string): number {
    for (let index = 0; index < this.agentRules.length; index++) {
      if (this.agentRules[index].id === ruleId) {
        return index;
      }
    }
    return -1;
  }

  private displayedAgentRules(): AgentRule[] {
    if (!this.hasValidDragAgentRuleOrderIds()) {
      return this.agentRules;
    }

    const orderedRules: AgentRule[] = [];
    for (let orderIndex = 0; orderIndex < this.dragAgentRuleOrderIds.length; orderIndex++) {
      const ruleId = this.dragAgentRuleOrderIds[orderIndex];
      for (let ruleIndex = 0; ruleIndex < this.agentRules.length; ruleIndex++) {
        const rule = this.agentRules[ruleIndex];
        if (rule.id === ruleId) {
          orderedRules.push(rule);
          break;
        }
      }
    }
    if (orderedRules.length !== this.agentRules.length) {
      return this.agentRules;
    }
    return orderedRules;
  }

  private currentAgentRuleIds(): string[] {
    const ruleIds: string[] = [];
    for (let index = 0; index < this.agentRules.length; index++) {
      ruleIds.push(this.agentRules[index].id);
    }
    return ruleIds;
  }

  private activeDragAgentRuleOrderIds(): string[] {
    if (this.hasValidDragAgentRuleOrderIds()) {
      return this.dragAgentRuleOrderIds;
    }
    return this.currentAgentRuleIds();
  }

  private hasValidDragAgentRuleOrderIds(): boolean {
    if (this.dragAgentRuleOrderIds.length !== this.agentRules.length || this.dragAgentRuleOrderIds.length === 0) {
      return false;
    }
    for (let index = 0; index < this.agentRules.length; index++) {
      if (this.agentRuleIdIndexIn(this.agentRules[index].id, this.dragAgentRuleOrderIds) < 0) {
        return false;
      }
    }
    return true;
  }

  private agentRuleIdIndexIn(ruleId: string, ruleIds: string[]): number {
    for (let index = 0; index < ruleIds.length; index++) {
      if (ruleIds[index] === ruleId) {
        return index;
      }
    }
    return -1;
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

  private agentRuleTitle(rule: AgentRule): string {
    if (rule.type === 'wifiGateway') {
      return 'WiFi: ' + this.fallbackRuleValue(rule.matchValue, '网关');
    }
    if (rule.type === 'wifiSsid') {
      return 'SSID: ' + this.fallbackRuleValue(rule.matchValue, '未设置');
    }
    if (rule.type === 'ipv6Available') {
      return 'IPv6 可用';
    }
    return 'IPv4 可用';
  }

  private draftAgentRuleTitle(): string {
    const rule: AgentRule = {
      id: this.editingAgentRuleId,
      type: this.draftAgentRuleType,
      matchValue: this.draftAgentRuleMatchValue,
      targetTunnelId: this.draftAgentRuleTargetTunnelId,
      targetTunnelName: this.draftAgentRuleTargetTunnelName,
      enabled: this.draftAgentRuleEnabled
    };
    return this.agentRuleTitle(rule);
  }

  private agentRuleTypeLabel(ruleType: AgentRuleType): string {
    if (ruleType === 'wifiGateway') {
      return 'WiFi 网关';
    }
    if (ruleType === 'wifiSsid') {
      return 'WiFi SSID';
    }
    if (ruleType === 'ipv6Available') {
      return 'IPv6 可用';
    }
    return 'IPv4 可用';
  }

  private agentRuleTypeOptions(): FloatingSelectOption[] {
    const options: FloatingSelectOption[] = [];
    for (let index = 0; index < AGENT_RULE_TYPES.length; index++) {
      const ruleType = AGENT_RULE_TYPES[index];
      options.push({
        value: ruleType,
        label: this.agentRuleTypeMenuLabel(ruleType)
      });
    }
    return options;
  }

  private agentRuleTargetOptions(): FloatingSelectOption[] {
    const options: FloatingSelectOption[] = [{
      value: '',
      label: '直连'
    }];
    for (let index = 0; index < this.tunnels.length; index++) {
      const tunnel = this.tunnels[index];
      options.push({
        value: tunnel.id,
        label: tunnel.name
      });
    }
    return options;
  }

  private dohProviderOptions(): FloatingSelectOption[] {
    const options: FloatingSelectOption[] = [{
      value: DOH_PROVIDER_ALIYUN,
      label: 'Aliyun'
    }, {
      value: DOH_PROVIDER_GOOGLE,
      label: 'Google'
    }, {
      value: DOH_PROVIDER_CLOUDFLARE,
      label: 'Cloudflare'
    }, {
      value: DOH_PROVIDER_TENCENT,
      label: 'Tencent'
    }];
    return options;
  }

  private agentRuleTypeFromValue(value: string): AgentRuleType {
    if (value === 'wifiSsid') {
      return 'wifiSsid';
    }
    if (value === 'ipv6Available') {
      return 'ipv6Available';
    }
    if (value === 'ipv4Available') {
      return 'ipv4Available';
    }
    return 'wifiGateway';
  }

  private agentRuleTypeMenuLabel(ruleType: AgentRuleType): string {
    if (ruleType === 'wifiGateway') {
      return 'WiFi Gateway';
    }
    if (ruleType === 'wifiSsid') {
      return 'WiFi SSID';
    }
    if (ruleType === 'ipv6Available') {
      return 'IPv6 Available';
    }
    return 'IPv4 Available';
  }

  private targetTunnelLabelForValue(tunnelId: string): string {
    if (tunnelId.length === 0) {
      return '直连';
    }
    for (let index = 0; index < this.tunnels.length; index++) {
      const tunnel = this.tunnels[index];
      if (tunnel.id === tunnelId) {
        return tunnel.name;
      }
    }
    return '未知隧道';
  }

  private agentRuleMatchLabel(ruleType: AgentRuleType): string {
    if (ruleType === 'wifiSsid') {
      return 'WiFi SSID';
    }
    return '网关 IPv4 地址';
  }

  private agentRuleMatchPlaceholder(ruleType: AgentRuleType): string {
    if (ruleType === 'wifiSsid') {
      return '输入 WiFi 名称';
    }
    return '例如 192.168.0.1';
  }

  private agentRuleNoInputDescription(ruleType: AgentRuleType): string {
    if (ruleType === 'ipv6Available') {
      return '检测到当前网络可用 IPv6 时匹配该规则';
    }
    return '检测到当前网络可用 IPv4 时匹配该规则';
  }

  private agentRuleNeedsMatch(ruleType: AgentRuleType): boolean {
    return ruleType === 'wifiGateway' || ruleType === 'wifiSsid';
  }

  private agentRuleTargetLabel(rule: AgentRule): string {
    if (rule.targetTunnelId.length === 0) {
      return '直连';
    }
    for (let index = 0; index < this.tunnels.length; index++) {
      const tunnel = this.tunnels[index];
      if (tunnel.id === rule.targetTunnelId) {
        return tunnel.name;
      }
    }
    if (rule.targetTunnelName.length > 0) {
      return rule.targetTunnelName;
    }
    return '未知隧道';
  }

  private draftTargetTunnelLabel(): string {
    const rule: AgentRule = {
      id: this.editingAgentRuleId,
      type: this.draftAgentRuleType,
      matchValue: this.draftAgentRuleMatchValue,
      targetTunnelId: this.draftAgentRuleTargetTunnelId,
      targetTunnelName: this.draftAgentRuleTargetTunnelName,
      enabled: this.draftAgentRuleEnabled
    };
    return this.agentRuleTargetLabel(rule);
  }

  private fallbackRuleValue(value: string, fallback: string): string {
    const normalized = value.trim();
    if (normalized.length > 0) {
      return normalized;
    }
    return fallback;
  }

  private runAgentRuleAnimation(action: () => void): void {
    animateTo({ duration: 240, curve: Curve.EaseInOut }, action);
  }
}
