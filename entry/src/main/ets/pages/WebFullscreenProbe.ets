const WEB_FULLSCREEN_PROBE_SCRIPT =
  'JSON.stringify((function(){' +
    'var doc=document;var win=window;' +
    'var vw=win.innerWidth||doc.documentElement.clientWidth||0;' +
    'var vh=win.innerHeight||doc.documentElement.clientHeight||0;' +
    'function cls(el){var c=el&&el.className;return typeof c==="string"?c:(c&&c.baseVal?c.baseVal:"");}' +
    'function text(el){return String(cls(el)+" "+(el.id||"")+" "+(el.getAttribute("fullscreen")||"")+" "+(el.getAttribute("data-fullscreen")||"")).toLowerCase();}' +
    'function marked(el){return /(ytp-fullscreen|vjs-fullscreen|xgplayer-is-fullscreen|dplayer-fulled|art-fullscreen|jw-flag-fullscreen|plyr--fullscreen|is-fullscreen|fullscreen-active|full[-_ ]?screen)/.test(text(el));}' +
    'function rect(el){var r=el.getBoundingClientRect();return {left:r.left,top:r.top,width:r.width,height:r.height};}' +
    'function large(r){return r.width>=vw*0.88&&r.height>=vh*0.62&&r.left<=vw*0.10&&r.top<=vh*0.14;}' +
    'function visible(r){return r.width>1&&r.height>1&&r.left<vw&&r.top<vh&&r.left+r.width>0&&r.top+r.height>0;}' +
    'var fsEl=doc.fullscreenElement||doc.webkitFullscreenElement||doc.mozFullScreenElement||doc.msFullscreenElement;' +
    'var videos=doc.querySelectorAll("video");var firstVideo=videos.length>0?videos[0]:null;' +
    'if(fsEl){return {fullScreen:true,source:"dom",videoWidth:firstVideo?(firstVideo.videoWidth||0):0,videoHeight:firstVideo?(firstVideo.videoHeight||0):0};}' +
    'var known=doc.querySelector(".html5-video-player.ytp-fullscreen,ytd-watch-flexy[fullscreen],ytm-app[fullscreen],ytm-watch[fullscreen],ytm-player[fullscreen],.vjs-fullscreen,.xgplayer-is-fullscreen,.dplayer-fulled,.art-fullscreen,.jw-flag-fullscreen,.plyr--fullscreen-fallback");' +
    'if(known){return {fullScreen:true,source:"known-player",videoWidth:firstVideo?(firstVideo.videoWidth||0):0,videoHeight:firstVideo?(firstVideo.videoHeight||0):0};}' +
    'for(var i=0;i<videos.length;i++){' +
      'var video=videos[i];var videoRect=rect(video);if(!visible(videoRect)){continue;}' +
      'var playing=!video.paused&&!video.ended&&video.readyState>1;' +
      'var el=video;var depth=0;' +
      'while(el&&el!==doc&&depth<8){' +
        'var r=rect(el);var style=win.getComputedStyle(el);' +
        'var positioned=(style.position==="fixed"||style.position==="absolute"||style.position==="sticky");' +
        'if(marked(el)){return {fullScreen:true,source:"marked",videoWidth:video.videoWidth||Math.round(videoRect.width),videoHeight:video.videoHeight||Math.round(videoRect.height)};}' +
        'if(positioned&&large(r)){return {fullScreen:true,source:"positioned",videoWidth:video.videoWidth||Math.round(videoRect.width),videoHeight:video.videoHeight||Math.round(videoRect.height)};}' +
        'if(playing&&large(r)){return {fullScreen:true,source:"large-video",videoWidth:video.videoWidth||Math.round(videoRect.width),videoHeight:video.videoHeight||Math.round(videoRect.height)};}' +
        'el=el.parentElement;depth++;' +
      '}' +
    '}' +
    'return {fullScreen:false,source:"",videoWidth:firstVideo?(firstVideo.videoWidth||0):0,videoHeight:firstVideo?(firstVideo.videoHeight||0):0};' +
  '})())';

const WEB_FULLSCREEN_EXIT_SCRIPT =
  '(function(){' +
    'try{' +
      'if(document.fullscreenElement&&document.exitFullscreen){document.exitFullscreen();return true;}' +
      'if(document.webkitFullscreenElement&&document.webkitExitFullscreen){document.webkitExitFullscreen();return true;}' +
      'var button=document.querySelector(".ytp-fullscreen-button,.vjs-fullscreen-control,.xgplayer-fullscreen,.dplayer-full-icon,.art-control-fullscreen,.jw-icon-fullscreen,.plyr__control[data-plyr=fullscreen]");' +
      'if(button&&typeof button.click==="function"){button.click();return true;}' +
    '}catch(e){}' +
    'return false;' +
  '})()';

interface WebFullScreenProbeResultRaw {
  fullScreen?: boolean;
  source?: string;
  videoWidth?: number;
  videoHeight?: number;
}

export interface WebFullScreenProbeResult {
  fullScreen: boolean;
  source: string;
  videoWidth: number;
  videoHeight: number;
}

export class WebFullscreenProbe {
  static probeScript(): string {
    return WEB_FULLSCREEN_PROBE_SCRIPT;
  }

  static exitScript(): string {
    return WEB_FULLSCREEN_EXIT_SCRIPT;
  }

  static parseResult(raw: string): WebFullScreenProbeResult {
    const empty: WebFullScreenProbeResult = {
      fullScreen: false,
      source: '',
      videoWidth: 0,
      videoHeight: 0
    };
    if (raw.length === 0 || raw === 'null' || raw === 'undefined') {
      return empty;
    }

    try {
      const parsed: WebFullScreenProbeResultRaw | string =
        JSON.parse(raw) as WebFullScreenProbeResultRaw | string;
      const value: WebFullScreenProbeResultRaw =
        typeof parsed === 'string' ? JSON.parse(parsed) as WebFullScreenProbeResultRaw : parsed;
      return {
        fullScreen: WebFullscreenProbe.booleanValue(value.fullScreen),
        source: WebFullscreenProbe.stringValue(value.source),
        videoWidth: WebFullscreenProbe.numberValue(value.videoWidth),
        videoHeight: WebFullscreenProbe.numberValue(value.videoHeight)
      };
    } catch (err) {
      return empty;
    }
  }

  private static booleanValue(value: boolean | undefined): boolean {
    if (typeof value === 'boolean') {
      return value;
    }
    return false;
  }

  private static stringValue(value: string | undefined): string {
    if (typeof value === 'string') {
      return value.trim();
    }
    return '';
  }

  private static numberValue(value: number | undefined): number {
    if (typeof value === 'number' && !isNaN(value)) {
      return value;
    }
    return 0;
  }
}
