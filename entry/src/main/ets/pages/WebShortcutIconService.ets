import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';

const DOMAIN = 0x0001;
const TAG = 'WebShortcutIconService';
const WEB_SHORTCUT_ID_PREFIX = 'smart_agent_web_';
const SHORTCUT_ICON_DIR = 'web_shortcuts';
const SHORTCUT_FOREGROUND_ICON = 'foreground_v3.png';
const SHORTCUT_ICON_SIZE = 256;
const SHORTCUT_DEFAULT_ICON_COLOR = 0xFF2F7CF6;
const SHORTCUT_ICON_MAX_BYTES = 2 * 1024 * 1024;
const SHORTCUT_ICON_HTML_HEAD_MAX_BYTES = 256 * 1024;
const SHORTCUT_ICON_HTTP_TIMEOUT_MS = 8000;
const SHORTCUT_ICON_CANDIDATE_LOG_LIMIT = 40;
const SHORTCUT_ICON_MIN_WEB_SIZE = 96;
const SHORTCUT_ICON_VECTOR_SIZE = 512;

export interface ShortcutIconInfo {
  foregroundIcon: string;
}

export interface ShortcutIconCandidate {
  url: string;
  size: number;
  source: string;
}

export interface PageIconInfo {
  manifestUrl: string;
  icons: ShortcutIconCandidate[];
}

export interface PwaAppInfo {
  isPwa: boolean;
  manifestUrl: string;
  startUrl: string;
  scope: string;
  display: string;
  name: string;
}

interface WebManifestIcon {
  src?: string;
  sizes?: string;
  purpose?: string;
  type?: string;
}

interface WebManifest {
  icons?: WebManifestIcon[];
  startUrl?: string;
  scope?: string;
  display?: string;
  name?: string;
  shortName?: string;
}

interface WebManifestRaw {
  icons?: WebManifestIcon[];
  start_url?: string;
  scope?: string;
  display?: string;
  name?: string;
  short_name?: string;
}

interface PageIconInfoRaw {
  manifestUrl?: string;
  icons?: ShortcutIconCandidate[];
}

interface PagePwaInfoRaw {
  manifestUrl: string;
  hasServiceWorker: boolean;
  serviceWorkerScope: string;
}

interface UrlParts {
  scheme: string;
  origin: string;
  path: string;
}

interface HttpHeaders {
  Accept: string;
  'User-Agent': string;
  Range?: string;
  'Accept-Encoding'?: string;
}

export class WebShortcutIconService {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async prepareShortcutIcons(
    url: string,
    preferWebIcon: boolean,
    favicon: image.PixelMap | undefined,
    faviconUrl: string,
    userAgent: string,
    pageIconInfoLoader: (url: string) => Promise<PageIconInfo>
  ): Promise<ShortcutIconInfo> {
    try {
      const iconDir = this.shortcutIconDir(url);
      this.ensureDirectory(iconDir);
      const foregroundIcon = iconDir + '/' + SHORTCUT_FOREGROUND_ICON;
      if (preferWebIcon && await this.writeBestWebIcon(url, foregroundIcon, userAgent, pageIconInfoLoader)) {
        return { foregroundIcon: foregroundIcon };
      }
      if (!preferWebIcon && this.fileExists(foregroundIcon)) {
        return { foregroundIcon: foregroundIcon };
      }
      if (!preferWebIcon && favicon !== undefined && faviconUrl === url) {
        await this.writePixelMapToPng(favicon, foregroundIcon);
      } else {
        await this.ensureDefaultShortcutIcon(foregroundIcon);
      }
      return { foregroundIcon: foregroundIcon };
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'prepare shortcut icon failed: %{public}s', error.message ?? JSON.stringify(err));
      throw new Error(error.message ?? JSON.stringify(err));
    }
  }

  foregroundIconPath(url: string): string {
    return this.shortcutIconDir(url) + '/' + SHORTCUT_FOREGROUND_ICON;
  }

  foregroundIconFileSource(url: string): string {
    const path = this.foregroundIconPath(url);
    try {
      if (fileIo.accessSync(path)) {
        return 'file://' + path;
      }
    } catch (err) {
    }
    return '';
  }

  async queryPwaAppInfo(
    pageUrl: string,
    userAgent: string,
    controller: webview.WebviewController
  ): Promise<PwaAppInfo> {
    const pageInfo = await WebShortcutIconService.queryPagePwaInfo(controller);
    if (pageInfo.manifestUrl.length === 0 || !pageInfo.hasServiceWorker) {
      return WebShortcutIconService.emptyPwaAppInfo();
    }

    const manifest = await this.loadWebManifest(pageInfo.manifestUrl, userAgent);
    const startUrl = WebShortcutIconService.resolveUrl(pageInfo.manifestUrl, manifest.startUrl ?? '');
    const scope = this.resolvePwaScope(pageInfo.manifestUrl, startUrl, manifest.scope ?? pageInfo.serviceWorkerScope);
    const display = (manifest.display ?? '').trim().toLowerCase();
    const name = (manifest.shortName ?? manifest.name ?? '').trim();
    if (startUrl.length === 0 || scope.length === 0 || name.length === 0 || !this.isPwaDisplayMode(display) ||
      !this.hasPwaIcon(manifest) || !this.isUrlInsideScope(pageUrl, scope)) {
      return WebShortcutIconService.emptyPwaAppInfo();
    }

    return {
      isPwa: true,
      manifestUrl: pageInfo.manifestUrl,
      startUrl: startUrl,
      scope: scope,
      display: display,
      name: name
    };
  }

  private shortcutIconDir(url: string): string {
    return this.context.filesDir + '/' + SHORTCUT_ICON_DIR + '/' + WebShortcutIconService.stableUrlKey(url);
  }

  private ensureDirectory(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        return;
      }
    } catch (err) {
    }

    try {
      fileIo.mkdirSync(path, true);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'create shortcut icon dir failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  private async writeBestWebIcon(
    url: string,
    path: string,
    userAgent: string,
    pageIconInfoLoader: (url: string) => Promise<PageIconInfo>
  ): Promise<boolean> {
    const candidates = await this.collectShortcutIconCandidates(url, userAgent, pageIconInfoLoader);
    if (candidates.length === 0) {
      return false;
    }
    this.logIconCandidates(candidates);

    for (let index = 0; index < candidates.length; index++) {
      const candidate = candidates[index];
      try {
        const data = await this.fetchArrayBuffer(candidate.url, false, userAgent);
        if (data.byteLength <= 0 || data.byteLength > SHORTCUT_ICON_MAX_BYTES) {
          continue;
        }
        const source = image.createImageSource(data);
        if (source === undefined) {
          continue;
        }
        try {
          const pixelMap = await source.createPixelMap({
            desiredSize: {
              width: SHORTCUT_ICON_SIZE,
              height: SHORTCUT_ICON_SIZE
            }
          });
          if (pixelMap === undefined) {
            continue;
          }
          try {
            await this.writePixelMapToPng(pixelMap, path);
            hilog.info(DOMAIN, TAG, 'shortcut icon picked source=%{public}s size=%{public}d url=%{public}s',
              candidate.source,
              candidate.size,
              candidate.url
            );
            return true;
          } finally {
            await pixelMap.release();
          }
        } finally {
          await source.release();
        }
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'shortcut icon candidate failed source=%{public}s url=%{public}s: %{public}s',
          candidate.source,
          candidate.url,
          error.message ?? JSON.stringify(err)
        );
      }
    }
    return false;
  }

  private logIconCandidates(candidates: ShortcutIconCandidate[]): void {
    let summary = '';
    const limit = Math.min(candidates.length, SHORTCUT_ICON_CANDIDATE_LOG_LIMIT);
    for (let index = 0; index < limit; index++) {
      const candidate = candidates[index];
      summary += '[' + String(index) + '] ' + candidate.source + ' ' + String(candidate.size) + ' ' +
        candidate.url + ' ';
    }
    hilog.info(DOMAIN, TAG, 'shortcut icon candidates %{public}s', summary);
  }

  private async collectShortcutIconCandidates(
    url: string,
    userAgent: string,
    pageIconInfoLoader: (url: string) => Promise<PageIconInfo>
  ): Promise<ShortcutIconCandidate[]> {
    const result: ShortcutIconCandidate[] = [];
    const pageIconInfo = await pageIconInfoLoader(url);
    if (pageIconInfo.manifestUrl.length > 0) {
      const manifest = await this.loadWebManifest(pageIconInfo.manifestUrl, userAgent);
      if (manifest.icons !== undefined) {
        for (let index = 0; index < manifest.icons.length; index++) {
          const icon = manifest.icons[index];
          const src = icon.src ?? '';
          const resolved = WebShortcutIconService.resolveUrl(pageIconInfo.manifestUrl, src);
          if (resolved.length === 0) {
            continue;
          }
          const purpose = icon.purpose ?? '';
          if (purpose.indexOf('monochrome') >= 0) {
            continue;
          }
          this.addIconCandidate(result, {
            url: resolved,
            size: WebShortcutIconService.iconCandidateSize(resolved, icon.sizes ?? '', icon.type ?? ''),
            source: 'manifest'
          });
        }
      }
    }

    for (let index = 0; index < pageIconInfo.icons.length; index++) {
      this.addIconCandidate(result, pageIconInfo.icons[index]);
    }
    await this.addHtmlIconCandidates(result, url, userAgent);
    result.sort((left: ShortcutIconCandidate, right: ShortcutIconCandidate) => {
      const sizeScore = this.iconSizeScore(right.size) - this.iconSizeScore(left.size);
      if (sizeScore !== 0) {
        return sizeScore;
      }
      const sourceScore = this.iconSourceScore(right.source) - this.iconSourceScore(left.source);
      if (sourceScore !== 0) {
        return sourceScore;
      }
      return right.size - left.size;
    });
    return result;
  }

  private async addHtmlIconCandidates(
    result: ShortcutIconCandidate[],
    url: string,
    userAgent: string
  ): Promise<void> {
    try {
      const html = await this.fetchHtmlHead(url, userAgent);
      if (html.length === 0) {
        return;
      }
      const added = this.collectHtmlIconCandidates(result, url, html);
      hilog.info(DOMAIN, TAG, 'html icon parse added=%{public}d url=%{public}s', added, url);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load page html icons failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private collectHtmlIconCandidates(result: ShortcutIconCandidate[], pageUrl: string, html: string): number {
    let searchStart = 0;
    let added = 0;
    while (searchStart < html.length) {
      const linkStart = WebShortcutIconService.indexOfIgnoreCase(html, '<link', searchStart);
      if (linkStart < 0) {
        return added;
      }
      const linkEnd = html.indexOf('>', linkStart + 5);
      if (linkEnd < 0) {
        return added;
      }
      const tag = html.substring(linkStart, linkEnd + 1);
      if (this.addHtmlLinkIconCandidate(result, pageUrl, tag)) {
        added++;
      }
      searchStart = linkEnd + 1;
    }
    return added;
  }

  private addHtmlLinkIconCandidate(result: ShortcutIconCandidate[], pageUrl: string, tag: string): boolean {
    const rel = WebShortcutIconService.htmlAttributeValue(tag, 'rel').toLowerCase();
    if (rel.length === 0) {
      return false;
    }
    const isAppleTouchIcon = rel.indexOf('apple-touch-icon') >= 0;
    const isIcon = WebShortcutIconService.hasRelToken(rel, 'icon') || rel.indexOf('shortcut icon') >= 0;
    if (!isAppleTouchIcon && !isIcon) {
      return false;
    }
    const href = WebShortcutIconService.htmlAttributeValue(tag, 'href');
    const resolved = WebShortcutIconService.resolveUrl(pageUrl, href);
    if (resolved.length === 0) {
      return false;
    }
    const sizes = WebShortcutIconService.htmlAttributeValue(tag, 'sizes');
    const type = WebShortcutIconService.htmlAttributeValue(tag, 'type');
    this.addIconCandidate(result, {
      url: resolved,
      size: WebShortcutIconService.iconCandidateSize(resolved, sizes, type),
      source: isAppleTouchIcon ? 'apple-touch-icon' : 'link-icon'
    });
    hilog.info(DOMAIN, TAG, 'html icon tag rel=%{public}s size=%{public}s href=%{public}s', rel, sizes, resolved);
    return true;
  }

  private async loadWebManifest(manifestUrl: string, userAgent: string): Promise<WebManifest> {
    try {
      const data = await this.fetchArrayBuffer(manifestUrl, true, userAgent);
      if (data.byteLength <= 0 || data.byteLength > SHORTCUT_ICON_MAX_BYTES) {
        return this.emptyWebManifest();
      }
      const text = buffer.from(new Uint8Array(data)).toString('utf8');
      return this.normalizeWebManifest(JSON.parse(text) as WebManifestRaw);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load web manifest failed: %{public}s', error.message ?? JSON.stringify(err));
      return this.emptyWebManifest();
    }
  }

  private emptyWebManifest(): WebManifest {
    return {
      icons: [],
      startUrl: '',
      scope: '',
      display: '',
      name: '',
      shortName: ''
    };
  }

  private normalizeWebManifest(raw: WebManifestRaw): WebManifest {
    const result: WebManifest = {
      icons: [],
      startUrl: WebShortcutIconService.stringValue(raw.start_url),
      scope: WebShortcutIconService.stringValue(raw.scope),
      display: WebShortcutIconService.stringValue(raw.display),
      name: WebShortcutIconService.stringValue(raw.name),
      shortName: WebShortcutIconService.stringValue(raw.short_name)
    };
    if (!Array.isArray(raw.icons) || result.icons === undefined) {
      return result;
    }
    for (let index = 0; index < raw.icons.length; index++) {
      const icon = raw.icons[index] as WebManifestIcon;
      const src = WebShortcutIconService.stringValue(icon.src);
      if (src.length === 0) {
        continue;
      }
      result.icons.push({
        src: src,
        sizes: WebShortcutIconService.stringValue(icon.sizes),
        purpose: WebShortcutIconService.stringValue(icon.purpose),
        type: WebShortcutIconService.stringValue(icon.type)
      });
    }
    return result;
  }

  private resolvePwaScope(manifestUrl: string, startUrl: string, scope: string): string {
    const resolvedScope = WebShortcutIconService.resolveUrl(manifestUrl, scope);
    if (resolvedScope.length > 0) {
      return resolvedScope;
    }
    const startParts = WebShortcutIconService.urlParts(startUrl);
    if (startParts.origin.length === 0) {
      return '';
    }
    const path = startParts.path;
    const queryIndex = path.indexOf('?');
    const cleanPath = queryIndex >= 0 ? path.substring(0, queryIndex) : path;
    const slashIndex = cleanPath.lastIndexOf('/');
    const dir = slashIndex >= 0 ? cleanPath.substring(0, slashIndex + 1) : '/';
    return startParts.origin + dir;
  }

  private isPwaDisplayMode(display: string): boolean {
    return display === 'standalone' || display === 'fullscreen' || display === 'minimal-ui' ||
      display === 'window-controls-overlay';
  }

  private hasPwaIcon(manifest: WebManifest): boolean {
    if (manifest.icons === undefined) {
      return false;
    }
    for (let index = 0; index < manifest.icons.length; index++) {
      if (WebShortcutIconService.parseLargestIconSize(manifest.icons[index].sizes ?? '') >= SHORTCUT_ICON_MIN_WEB_SIZE) {
        return true;
      }
    }
    return false;
  }

  private isUrlInsideScope(url: string, scope: string): boolean {
    const normalizedUrl = url.trim();
    const normalizedScope = scope.trim();
    return normalizedScope.length > 0 && normalizedUrl.startsWith(normalizedScope);
  }

  private async fetchHtmlHead(url: string, userAgent: string): Promise<string> {
    try {
      const data = await this.fetchArrayBuffer(
        url,
        true,
        userAgent,
        'bytes=0-' + String(SHORTCUT_ICON_HTML_HEAD_MAX_BYTES - 1),
        SHORTCUT_ICON_HTML_HEAD_MAX_BYTES,
        'text/html, application/xhtml+xml, application/xml;q=0.9, */*;q=0.8'
      );
      return WebShortcutIconService.htmlHeadOnly(buffer.from(new Uint8Array(data)).toString('utf8'));
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'load page html head range failed: %{public}s', error.message ?? JSON.stringify(err));
    }

    const data = await this.fetchArrayBuffer(
      url,
      true,
      userAgent,
      '',
      SHORTCUT_ICON_MAX_BYTES,
      'text/html, application/xhtml+xml, application/xml;q=0.9, */*;q=0.8'
    );
    if (data.byteLength <= 0 || data.byteLength > SHORTCUT_ICON_MAX_BYTES) {
      return '';
    }
    return WebShortcutIconService.htmlHeadOnly(buffer.from(new Uint8Array(data)).toString('utf8'));
  }

  private async fetchArrayBuffer(
    url: string,
    textLike: boolean,
    userAgent: string,
    rangeHeader: string = '',
    maxLimit: number = SHORTCUT_ICON_MAX_BYTES,
    acceptOverride: string = ''
  ): Promise<ArrayBuffer> {
    const request = http.createHttp();
    const accept = acceptOverride.length > 0 ? acceptOverride : (textLike ?
      'application/manifest+json, application/json, text/plain, */*' :
      'image/avif, image/webp, image/png, image/jpeg, image/svg+xml, image/*, */*');
    let headers: HttpHeaders = {
      Accept: accept,
      'User-Agent': userAgent
    };
    if (rangeHeader.length > 0) {
      headers = {
        Accept: accept,
        'User-Agent': userAgent,
        Range: rangeHeader,
        'Accept-Encoding': 'identity'
      };
    }
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: true,
        readTimeout: SHORTCUT_ICON_HTTP_TIMEOUT_MS,
        connectTimeout: SHORTCUT_ICON_HTTP_TIMEOUT_MS,
        maxLimit: maxLimit,
        header: headers
      };
      const response = await request.request(url, options);
      if (response.responseCode < http.ResponseCode.OK || response.responseCode >= 300) {
        throw new Error('HTTP ' + String(response.responseCode));
      }
      if (response.resultType === http.HttpDataType.ARRAY_BUFFER) {
        return response.result as ArrayBuffer;
      }
      return new ArrayBuffer(0);
    } finally {
      request.destroy();
    }
  }

  private addIconCandidate(candidates: ShortcutIconCandidate[], candidate: ShortcutIconCandidate): void {
    if (!candidate.url.startsWith('http://') && !candidate.url.startsWith('https://')) {
      return;
    }
    for (let index = 0; index < candidates.length; index++) {
      if (candidates[index].url === candidate.url) {
        if (candidate.size > candidates[index].size) {
          candidates[index].size = candidate.size;
        }
        return;
      }
    }
    candidates.push(candidate);
  }

  private iconSourceScore(source: string): number {
    if (source === 'manifest') {
      return 3;
    }
    if (source === 'apple-touch-icon') {
      return 2;
    }
    return 1;
  }

  private iconSizeScore(size: number): number {
    if (size >= SHORTCUT_ICON_SIZE) {
      return 4;
    }
    if (size >= 180) {
      return 3;
    }
    if (size >= SHORTCUT_ICON_MIN_WEB_SIZE) {
      return 2;
    }
    if (size > 0) {
      return 1;
    }
    return 0;
  }

  private async ensureDefaultShortcutIcon(path: string): Promise<void> {
    try {
      if (fileIo.accessSync(path)) {
        return;
      }
    } catch (err) {
    }

    const colors = new ArrayBuffer(SHORTCUT_ICON_SIZE * SHORTCUT_ICON_SIZE * 4);
    const values = new Uint32Array(colors);
    values.fill(SHORTCUT_DEFAULT_ICON_COLOR);
    const pixelMap = image.createPixelMapSync(colors, {
      size: {
        width: SHORTCUT_ICON_SIZE,
        height: SHORTCUT_ICON_SIZE
      },
      pixelFormat: image.PixelMapFormat.RGBA_8888
    });
    await this.writePixelMapToPng(pixelMap, path);
    await pixelMap.release();
  }

  private async writePixelMapToPng(pixelMap: image.PixelMap, path: string): Promise<void> {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
    try {
      const packer = image.createImagePacker();
      try {
        await packer.packToFile(pixelMap, file.fd, {
          format: 'image/png',
          quality: 100
        });
      } finally {
        await packer.release();
      }
    } finally {
      fileIo.closeSync(file);
    }
  }

  static shortcutId(url: string): string {
    return WEB_SHORTCUT_ID_PREFIX + WebShortcutIconService.stableUrlKey(url);
  }

  static stableUrlKey(url: string): string {
    let hash = 2166136261;
    for (let index = 0; index < url.length; index++) {
      hash ^= url.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  static hostFromUrl(url: string): string {
    const marker = '://';
    const schemeIndex = url.indexOf(marker);
    if (schemeIndex < 0) {
      return '';
    }
    const start = schemeIndex + marker.length;
    const slashIndex = url.indexOf('/', start);
    const host = slashIndex >= 0 ? url.substring(start, slashIndex) : url.substring(start);
    const atIndex = host.lastIndexOf('@');
    return atIndex >= 0 ? host.substring(atIndex + 1) : host;
  }

  static async queryPageIconInfo(controller: webview.WebviewController): Promise<PageIconInfo> {
    const empty: PageIconInfo = {
      manifestUrl: '',
      icons: []
    };

    try {
      const script =
        'JSON.stringify((function(){' +
          'function abs(v){try{return v?new URL(v,document.baseURI).href:"";}catch(e){return "";}}' +
          'function size(v){if(!v||v==="any")return 0;var m=String(v).match(/(\\d+)\\s*x\\s*(\\d+)/i);return m?Math.max(parseInt(m[1]),parseInt(m[2])):0;}' +
          'function pathSize(v){var m=String(v||"").match(/(?:^|[^0-9])(\\d{2,4})\\s*x\\s*(\\d{2,4})(?:[^0-9]|$)/i);return m?Math.max(parseInt(m[1]),parseInt(m[2])):0;}' +
          'function iconSize(link,href,rel){' +
            'var declared=size(link.getAttribute("sizes"));if(declared>0)return declared;' +
            'var sizes=String(link.getAttribute("sizes")||"").toLowerCase();' +
            'var type=String(link.getAttribute("type")||"").toLowerCase();' +
            'if(sizes==="any"||type.indexOf("svg")>=0||/\\.svg(?:[?#]|$)/i.test(href))return 512;' +
            'var named=pathSize(href);if(named>0)return named;' +
            'if(rel.indexOf("apple-touch-icon")>=0)return 180;' +
            'return 0;' +
          '}' +
          'var manifest="";var icons=[];' +
          'var links=document.querySelectorAll("link[rel][href]");' +
          'for(var i=0;i<links.length;i++){' +
            'var link=links[i];var rel=String(link.getAttribute("rel")||"").toLowerCase();var href=abs(link.getAttribute("href"));' +
            'if(!href)continue;' +
            'if(!manifest&&rel.split(/\\s+/).indexOf("manifest")>=0){manifest=href;continue;}' +
            'if(rel.indexOf("apple-touch-icon")>=0){icons.push({url:href,size:iconSize(link,href,rel),source:"apple-touch-icon"});continue;}' +
            'if(rel.split(/\\s+/).indexOf("icon")>=0||rel.indexOf("shortcut icon")>=0){icons.push({url:href,size:iconSize(link,href,rel),source:"link-icon"});}' +
          '}' +
          'return {manifestUrl:manifest,icons:icons};' +
        '})())';
      const raw = await controller.runJavaScript(script);
      return WebShortcutIconService.parsePageIconInfo(raw);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'query page icon info failed: %{public}s', error.message ?? JSON.stringify(err));
      return empty;
    }
  }

  static async queryPagePwaInfo(controller: webview.WebviewController): Promise<PagePwaInfoRaw> {
    const empty: PagePwaInfoRaw = {
      manifestUrl: '',
      hasServiceWorker: false,
      serviceWorkerScope: ''
    };

    try {
      const script =
        '(async function(){' +
          'function abs(v){try{return v?new URL(v,document.baseURI).href:"";}catch(e){return "";}}' +
          'var manifest="";var links=document.querySelectorAll("link[rel][href]");' +
          'for(var i=0;i<links.length;i++){' +
            'var link=links[i];var rel=String(link.getAttribute("rel")||"").toLowerCase();' +
            'if(rel.split(/\\s+/).indexOf("manifest")>=0){manifest=abs(link.getAttribute("href"));break;}' +
          '}' +
          'var result={manifestUrl:manifest,hasServiceWorker:false,serviceWorkerScope:""};' +
          'try{' +
            'if(navigator.serviceWorker&&navigator.serviceWorker.getRegistration){' +
              'var reg=await navigator.serviceWorker.getRegistration();' +
              'if(reg){result.hasServiceWorker=true;result.serviceWorkerScope=String(reg.scope||"");}' +
            '}' +
            'if(!result.hasServiceWorker&&navigator.serviceWorker&&navigator.serviceWorker.controller){' +
              'result.hasServiceWorker=true;' +
            '}' +
          '}catch(e){}' +
          'return JSON.stringify(result);' +
        '})()';
      const raw = await controller.runJavaScript(script);
      return WebShortcutIconService.parsePagePwaInfo(raw);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'query page pwa info failed: %{public}s', error.message ?? JSON.stringify(err));
      return empty;
    }
  }

  private static parsePageIconInfo(raw: string): PageIconInfo {
    const info = WebShortcutIconService.parseRunJavaScriptJson(raw);
    const result: PageIconInfo = {
      manifestUrl: WebShortcutIconService.stringValue(info.manifestUrl),
      icons: []
    };
    if (!Array.isArray(info.icons)) {
      return result;
    }
    for (let index = 0; index < info.icons.length; index++) {
      const candidate = info.icons[index] as ShortcutIconCandidate;
      const iconUrl = WebShortcutIconService.stringValue(candidate.url);
      if (iconUrl.length === 0) {
        continue;
      }
      result.icons.push({
        url: iconUrl,
        size: WebShortcutIconService.numberValue(candidate.size),
        source: WebShortcutIconService.stringValue(candidate.source)
      });
    }
    return result;
  }

  private static parseRunJavaScriptJson(raw: string): PageIconInfoRaw {
    const empty: PageIconInfoRaw = {
      manifestUrl: '',
      icons: []
    };
    if (raw.length === 0 || raw === 'null' || raw === 'undefined') {
      return empty;
    }

    try {
      const parsed: PageIconInfoRaw | string = JSON.parse(raw) as PageIconInfoRaw | string;
      if (typeof parsed === 'string') {
        return JSON.parse(parsed) as PageIconInfoRaw;
      }
      return parsed;
    } catch (err) {
      return empty;
    }
  }

  private static parsePagePwaInfo(raw: string): PagePwaInfoRaw {
    const empty: PagePwaInfoRaw = {
      manifestUrl: '',
      hasServiceWorker: false,
      serviceWorkerScope: ''
    };
    if (raw.length === 0 || raw === 'null' || raw === 'undefined') {
      return empty;
    }
    try {
      const parsed: PagePwaInfoRaw | string = JSON.parse(raw) as PagePwaInfoRaw | string;
      const info = typeof parsed === 'string' ? JSON.parse(parsed) as PagePwaInfoRaw : parsed;
      return {
        manifestUrl: WebShortcutIconService.stringValue(info.manifestUrl),
        hasServiceWorker: info.hasServiceWorker === true,
        serviceWorkerScope: WebShortcutIconService.stringValue(info.serviceWorkerScope)
      };
    } catch (err) {
      return empty;
    }
  }

  static emptyPwaAppInfo(): PwaAppInfo {
    return {
      isPwa: false,
      manifestUrl: '',
      startUrl: '',
      scope: '',
      display: '',
      name: ''
    };
  }

  private static parseLargestIconSize(value: string): number {
    if (value.trim().toLowerCase() === 'any') {
      return SHORTCUT_ICON_VECTOR_SIZE;
    }
    const parts = value.split(' ');
    let largest = 0;
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index].trim().toLowerCase();
      const separator = part.indexOf('x');
      if (separator <= 0) {
        continue;
      }
      const width = Number(part.substring(0, separator));
      const height = Number(part.substring(separator + 1));
      if (isNaN(width) || isNaN(height)) {
        continue;
      }
      largest = Math.max(largest, width, height);
    }
    return largest;
  }

  private static iconCandidateSize(url: string, sizes: string, type: string): number {
    const declared = WebShortcutIconService.parseLargestIconSize(sizes);
    if (declared > 0) {
      return declared;
    }
    const normalizedType = type.trim().toLowerCase();
    const normalizedUrl = url.trim().toLowerCase();
    if (normalizedType.indexOf('svg') >= 0 || normalizedUrl.indexOf('.svg') >= 0) {
      return SHORTCUT_ICON_VECTOR_SIZE;
    }
    return WebShortcutIconService.parseIconSizeFromUrl(url);
  }

  private static parseIconSizeFromUrl(url: string): number {
    const normalized = url.toLowerCase();
    const marker = 'x';
    let largest = 0;
    for (let index = 1; index < normalized.length - 1; index++) {
      if (normalized.charAt(index) !== marker) {
        continue;
      }
      const left = WebShortcutIconService.readNumberLeft(normalized, index - 1);
      const right = WebShortcutIconService.readNumberRight(normalized, index + 1);
      if (left >= 16 && right >= 16) {
        largest = Math.max(largest, left, right);
      }
    }
    return largest;
  }

  private static readNumberLeft(value: string, end: number): number {
    let start = end;
    while (start >= 0 && WebShortcutIconService.isDigit(value.charAt(start))) {
      start--;
    }
    const raw = value.substring(start + 1, end + 1);
    if (raw.length < 2 || raw.length > 4) {
      return 0;
    }
    const parsed = Number(raw);
    return isNaN(parsed) ? 0 : parsed;
  }

  private static readNumberRight(value: string, start: number): number {
    let end = start;
    while (end < value.length && WebShortcutIconService.isDigit(value.charAt(end))) {
      end++;
    }
    const raw = value.substring(start, end);
    if (raw.length < 2 || raw.length > 4) {
      return 0;
    }
    const parsed = Number(raw);
    return isNaN(parsed) ? 0 : parsed;
  }

  private static isDigit(value: string): boolean {
    return value >= '0' && value <= '9';
  }

  private static indexOfIgnoreCase(value: string, search: string, start: number): number {
    return value.toLowerCase().indexOf(search.toLowerCase(), start);
  }

  private static htmlHeadOnly(html: string): string {
    const headEnd = WebShortcutIconService.indexOfIgnoreCase(html, '</head>', 0);
    if (headEnd >= 0) {
      return html.substring(0, headEnd + 7);
    }
    const bodyStart = WebShortcutIconService.indexOfIgnoreCase(html, '<body', 0);
    if (bodyStart >= 0) {
      return html.substring(0, bodyStart);
    }
    return html;
  }

  private static htmlAttributeValue(tag: string, name: string): string {
    const lowerTag = tag.toLowerCase();
    const lowerName = name.toLowerCase();
    let searchStart = 0;
    while (searchStart < lowerTag.length) {
      const index = lowerTag.indexOf(lowerName, searchStart);
      if (index < 0) {
        return '';
      }
      const before = index > 0 ? lowerTag.charAt(index - 1) : ' ';
      const afterIndex = index + lowerName.length;
      const after = afterIndex < lowerTag.length ? lowerTag.charAt(afterIndex) : '';
      if (!WebShortcutIconService.isAttributeNameChar(before) &&
        !WebShortcutIconService.isAttributeNameChar(after)) {
        let cursor = afterIndex;
        while (cursor < tag.length && WebShortcutIconService.isWhitespace(tag.charAt(cursor))) {
          cursor++;
        }
        if (cursor < tag.length && tag.charAt(cursor) === '=') {
          return WebShortcutIconService.readHtmlAttributeValue(tag, cursor + 1);
        }
      }
      searchStart = afterIndex;
    }
    return '';
  }

  private static hasRelToken(rel: string, token: string): boolean {
    const normalizedRel = rel.toLowerCase();
    const normalizedToken = token.toLowerCase();
    let start = 0;
    while (start < normalizedRel.length) {
      while (start < normalizedRel.length && WebShortcutIconService.isWhitespace(normalizedRel.charAt(start))) {
        start++;
      }
      let end = start;
      while (end < normalizedRel.length && !WebShortcutIconService.isWhitespace(normalizedRel.charAt(end))) {
        end++;
      }
      if (end > start && normalizedRel.substring(start, end) === normalizedToken) {
        return true;
      }
      start = end + 1;
    }
    return false;
  }

  private static readHtmlAttributeValue(tag: string, start: number): string {
    let cursor = start;
    while (cursor < tag.length && WebShortcutIconService.isWhitespace(tag.charAt(cursor))) {
      cursor++;
    }
    if (cursor >= tag.length) {
      return '';
    }
    const quote = tag.charAt(cursor);
    if (quote === '"' || quote === '\'') {
      const end = tag.indexOf(quote, cursor + 1);
      if (end < 0) {
        return '';
      }
      return WebShortcutIconService.htmlDecode(tag.substring(cursor + 1, end));
    }
    let end = cursor;
    while (end < tag.length && !WebShortcutIconService.isWhitespace(tag.charAt(end)) && tag.charAt(end) !== '>') {
      end++;
    }
    return WebShortcutIconService.htmlDecode(tag.substring(cursor, end));
  }

  private static isWhitespace(value: string): boolean {
    return value === ' ' || value === '\n' || value === '\r' || value === '\t' || value === '\f';
  }

  private static isAttributeNameChar(value: string): boolean {
    return (value >= 'a' && value <= 'z') || (value >= '0' && value <= '9') ||
      value === '-' || value === '_' || value === ':';
  }

  private static htmlDecode(value: string): string {
    return value.replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, '\'')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>');
  }

  private static resolveUrl(baseUrl: string, value: string): string {
    const trimmed = value.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    const baseParts = WebShortcutIconService.urlParts(baseUrl);
    if (baseParts.origin.length === 0) {
      return '';
    }
    if (trimmed.startsWith('//')) {
      return baseParts.scheme + ':' + trimmed;
    }
    if (trimmed.startsWith('/')) {
      return baseParts.origin + WebShortcutIconService.normalizePath(trimmed);
    }
    const dir = baseParts.path.substring(0, baseParts.path.lastIndexOf('/') + 1);
    return baseParts.origin + WebShortcutIconService.normalizePath(dir + trimmed);
  }

  private static urlParts(url: string): UrlParts {
    const marker = '://';
    const schemeIndex = url.indexOf(marker);
    if (schemeIndex < 0) {
      return {
        scheme: '',
        origin: '',
        path: '/'
      };
    }
    const scheme = url.substring(0, schemeIndex);
    const hostStart = schemeIndex + marker.length;
    const slashIndex = url.indexOf('/', hostStart);
    const origin = slashIndex >= 0 ? url.substring(0, slashIndex) : url;
    const path = slashIndex >= 0 ? url.substring(slashIndex) : '/';
    return {
      scheme: scheme,
      origin: origin,
      path: path
    };
  }

  private static normalizePath(path: string): string {
    const queryIndex = path.indexOf('?');
    const hashIndex = path.indexOf('#');
    let end = path.length;
    if (queryIndex >= 0) {
      end = Math.min(end, queryIndex);
    }
    if (hashIndex >= 0) {
      end = Math.min(end, hashIndex);
    }
    const suffix = path.substring(end);
    const rawPath = path.substring(0, end);
    const parts = rawPath.split('/');
    const stack: string[] = [];
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      if (part.length === 0 || part === '.') {
        continue;
      }
      if (part === '..') {
        if (stack.length > 0) {
          stack.pop();
        }
        continue;
      }
      stack.push(part);
    }
    return '/' + stack.join('/') + suffix;
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
