import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BuilderNode, NodeController, PiPWindow, typeNode } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'VpnPipManager';
const PIP_CONTENT_WIDTH = 160;
const PIP_CONTENT_HEIGHT = 90;
const PIP_ICON_SIZE = 22;

class VpnPipViewParams {
  icon: Resource = $r('app.media.app_icon');
  hint: Resource = $r('app.string.vpn_pip_drag_hint');
}

@Builder
function VpnPipViewBuilder(params: VpnPipViewParams) {
  Row({ space: 8 }) {
    Image(params.icon)
      .width(PIP_ICON_SIZE)
      .height(PIP_ICON_SIZE)
      .objectFit(ImageFit.Contain)
    Text(params.hint)
      .fontSize(11)
      .fontColor('#3F4654')
      .fontWeight(FontWeight.Medium)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
  .width('100%')
  .height('100%')
  .padding({ left: 12, right: 12 })
  .justifyContent(FlexAlign.Center)
  .alignItems(VerticalAlign.Center)
  .backgroundColor('#F4F6FA')
}

class VpnPipNodeController extends NodeController {
  private node: BuilderNode<[VpnPipViewParams]> | null = null;
  private builder: WrappedBuilder<[VpnPipViewParams]> = wrapBuilder(VpnPipViewBuilder);

  makeNode(uiContext: UIContext): FrameNode {
    if (this.node === null) {
      this.node = new BuilderNode(uiContext);
      this.node.build(this.builder, new VpnPipViewParams());
    }
    return this.node.getFrameNode()!;
  }
}

export class VpnPictureInPictureManager {
  private static instance: VpnPictureInPictureManager = new VpnPictureInPictureManager();
  private pipController?: PiPWindow.PiPController;
  private xComponent: typeNode.XComponent | null = null;
  private initializing: boolean = false;
  private desiredEnabled: boolean = false;
  private pipStarted: boolean = false;
  private unsupported: boolean = false;

  static getInstance(): VpnPictureInPictureManager {
    return VpnPictureInPictureManager.instance;
  }

  configure(context: common.UIAbilityContext, uiContext: UIContext, enabled: boolean): void {
    this.desiredEnabled = enabled;
    if (!enabled) {
      this.unsupported = false;
      this.disableController();
      return;
    }

    if (this.pipController !== undefined) {
      this.pipController.updateContentSize(PIP_CONTENT_WIDTH, PIP_CONTENT_HEIGHT);
      this.setAutoStartEnabled(true);
      return;
    }
    if (this.initializing || this.unsupported) {
      return;
    }
    if (!PiPWindow.isPiPEnabled()) {
      this.unsupported = true;
      hilog.warn(DOMAIN, TAG, 'picture in picture is not supported or is disabled by the system');
      return;
    }

    this.ensureTypeNode(uiContext);
    const sourceNode = this.xComponent;
    if (sourceNode === null) {
      return;
    }

    const config: PiPWindow.PiPConfiguration = {
      context: context,
      componentController: new XComponentController(),
      templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
      contentWidth: PIP_CONTENT_WIDTH,
      contentHeight: PIP_CONTENT_HEIGHT,
      defaultWindowSizeType: 1,
      customUIController: new VpnPipNodeController()
    };
    this.initializing = true;
    PiPWindow.create(config, sourceNode).then((controller: PiPWindow.PiPController) => {
      this.initializing = false;
      this.pipController = controller;
      controller.updateContentSize(PIP_CONTENT_WIDTH, PIP_CONTENT_HEIGHT);
      controller.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
        this.handleStateChange(state, reason);
      });
      if (this.desiredEnabled) {
        this.setAutoStartEnabled(true);
      } else {
        this.disableController();
      }
      hilog.info(DOMAIN, TAG, 'vpn picture in picture controller created');
    }).catch((err: BusinessError) => {
      this.initializing = false;
      hilog.warn(DOMAIN, TAG, 'create vpn picture in picture failed: %{public}s', this.formatError(err));
    });
  }

  onForeground(): void {
    if (!this.pipStarted || this.pipController === undefined) {
      return;
    }
    this.pipController.stopPiP().catch((err: BusinessError) => {
      hilog.info(DOMAIN, TAG, 'stop foreground picture in picture skipped: %{public}s', this.formatError(err));
    });
  }

  release(): void {
    this.desiredEnabled = false;
    this.disableController();
    this.pipController?.off('stateChange');
    this.pipController = undefined;
    this.xComponent = null;
    this.initializing = false;
    this.pipStarted = false;
    this.unsupported = false;
  }

  private ensureTypeNode(uiContext: UIContext): void {
    if (this.xComponent !== null) {
      return;
    }
    const options: XComponentOptions = {
      type: XComponentType.SURFACE,
      controller: new XComponentController()
    };
    this.xComponent = typeNode.createNode(uiContext, 'XComponent', options);
  }

  private disableController(): void {
    this.setAutoStartEnabled(false);
    if (!this.pipStarted || this.pipController === undefined) {
      return;
    }
    this.pipController.stopPiP().catch((err: BusinessError) => {
      hilog.info(DOMAIN, TAG, 'stop disabled picture in picture skipped: %{public}s', this.formatError(err));
    });
  }

  private setAutoStartEnabled(enabled: boolean): void {
    try {
      this.pipController?.setAutoStartEnabled(enabled);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'set picture in picture auto start failed: %{public}s', this.formatError(error));
    }
  }

  private handleStateChange(state: PiPWindow.PiPState, reason: string): void {
    if (state === PiPWindow.PiPState.STARTED) {
      this.pipStarted = true;
    } else if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
      this.pipStarted = false;
    }
    hilog.info(DOMAIN, TAG, 'vpn picture in picture state=%{public}d reason=%{public}s', state, reason);
  }

  private formatError(error: BusinessError): string {
    return 'code=' + String(error.code) + ', message=' + (error.message ?? JSON.stringify(error));
  }
}
