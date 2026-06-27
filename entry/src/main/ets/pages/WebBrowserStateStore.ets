import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { buffer } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebTabState } from './WebBrowserTypes';

const DOMAIN = 0x0001;
const TAG = 'WebBrowserStateStore';
const WEB_STATE_DIR = 'web_states';
const WEB_STATE_FILE = 'state.bin';
const WEB_STATE_META_FILE = 'meta.json';
const WEB_STATE_MAX_BYTES = 2 * 1024 * 1024;

interface WebTabStateRaw {
  ownerId?: string;
  url?: string;
  backCount?: number;
}

export class WebBrowserStateStore {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  readWebState(tabId: string): Uint8Array {
    const path = this.webStateFilePath(tabId);
    try {
      if (!fileIo.accessSync(path)) {
        return new Uint8Array();
      }

      const stat = fileIo.statSync(path);
      if (stat.size <= 0 || stat.size > WEB_STATE_MAX_BYTES) {
        return new Uint8Array();
      }

      const stateBuffer = new ArrayBuffer(stat.size);
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const bytesRead = fileIo.readSync(file.fd, stateBuffer, {
          offset: 0,
          length: stat.size
        });
        if (bytesRead <= 0) {
          return new Uint8Array();
        }
        return new Uint8Array(stateBuffer, 0, bytesRead);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'read web state failed: %{public}s', error.message ?? JSON.stringify(err));
      return new Uint8Array();
    }
  }

  writeControllerWebState(tabId: string, controller: webview.WebviewController): void {
    try {
      const state = controller.serializeWebState();
      if (state.byteLength <= 0) {
        return;
      }
      this.writeWebStateBytes(tabId, new Uint8Array(state));
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'persist web state failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private writeWebStateBytes(tabId: string, data: Uint8Array): void {
    try {
      const path = this.webStateFilePath(tabId);
      this.ensureDirectory(this.webStateDir(tabId));
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      try {
        fileIo.writeSync(file.fd, data.buffer, {
          offset: 0,
          length: data.byteLength
        });
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'persist web state failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  readTabStateMeta(tabId: string, fallbackUrl: string): WebTabState {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    const fallback: WebTabState = {
      id: id,
      url: fallbackUrl,
      backCount: 0
    };
    if (id.length === 0) {
      return fallback;
    }

    try {
      const path = this.webStateMetaFilePath(id);
      if (!fileIo.accessSync(path)) {
        return fallback;
      }
      const stat = fileIo.statSync(path);
      if (stat.size <= 0 || stat.size > 4096) {
        return fallback;
      }
      const rawBuffer = new ArrayBuffer(stat.size);
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const bytesRead = fileIo.readSync(file.fd, rawBuffer, {
          offset: 0,
          length: stat.size
        });
        if (bytesRead <= 0) {
          return fallback;
        }
        const raw = buffer.from(new Uint8Array(rawBuffer, 0, bytesRead)).toString('utf8');
        const parsed = JSON.parse(raw) as WebTabStateRaw;
        const url = this.stringValue(parsed.url).length > 0 ? this.stringValue(parsed.url) : fallbackUrl;
        const backCount = this.numberValue(parsed.backCount);
        const ownerId = this.stringValue(parsed.ownerId);
        if (ownerId.length > 0 && ownerId !== id) {
          return fallback;
        }
        return {
          id: id,
          url: url,
          backCount: Math.max(0, backCount)
        };
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      return fallback;
    }
  }

  persistTabState(state: WebTabState): void {
    const id = WebBrowserStateStore.safeFileSegment(state.id);
    if (id.length === 0) {
      return;
    }

    try {
      const dir = this.webStateDir(id);
      this.ensureDirectory(dir);
      const payload: WebTabStateRaw = {
        ownerId: id,
        url: state.url,
        backCount: Math.max(0, state.backCount)
      };
      const encoded = buffer.from(JSON.stringify(payload), 'utf8');
      const data = new Uint8Array(encoded.length);
      for (let index = 0; index < encoded.length; index++) {
        data[index] = encoded[index];
      }
      const file = fileIo.openSync(this.webStateMetaFilePath(id),
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      try {
        fileIo.writeSync(file.fd, data.buffer, {
          offset: 0,
          length: data.length
        });
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'persist web tab meta failed: %{public}s',
        error.message ?? JSON.stringify(err));
    }
  }

  hasValidWebStateOwner(tabId: string): boolean {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    if (id.length === 0) {
      return false;
    }
    try {
      const path = this.webStateMetaFilePath(id);
      if (!fileIo.accessSync(path)) {
        return false;
      }
      const stat = fileIo.statSync(path);
      if (stat.size <= 0 || stat.size > 4096) {
        return false;
      }
      const rawBuffer = new ArrayBuffer(stat.size);
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const bytesRead = fileIo.readSync(file.fd, rawBuffer, {
          offset: 0,
          length: stat.size
        });
        if (bytesRead <= 0) {
          return false;
        }
        const raw = buffer.from(new Uint8Array(rawBuffer, 0, bytesRead)).toString('utf8');
        const parsed = JSON.parse(raw) as WebTabStateRaw;
        return this.stringValue(parsed.ownerId) === id;
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      return false;
    }
  }

  truncateWebState(tabId: string): void {
    const id = WebBrowserStateStore.safeFileSegment(tabId);
    if (id.length === 0) {
      return;
    }
    try {
      const dir = this.webStateDir(id);
      this.ensureDirectory(dir);
      const file = fileIo.openSync(dir + '/' + WEB_STATE_FILE,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      fileIo.closeSync(file);
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'truncate web state failed: %{public}s',
        error.message ?? JSON.stringify(err));
    }
  }

  private webStateFilePath(tabId: string): string {
    return this.webStateDir(tabId) + '/' + WEB_STATE_FILE;
  }

  private webStateMetaFilePath(tabId: string): string {
    return this.webStateDir(tabId) + '/' + WEB_STATE_META_FILE;
  }

  private webStateDir(key: string): string {
    return this.context.filesDir + '/' + WEB_STATE_DIR + '/' + WebBrowserStateStore.safeFileSegment(key);
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
      hilog.warn(DOMAIN, TAG, 'create web state dir failed: %{public}s', error.message ?? JSON.stringify(err));
    }
  }

  private stringValue(value: string | undefined): string {
    if (typeof value === 'string') {
      return value.trim();
    }
    return '';
  }

  private numberValue(value: number | undefined): number {
    if (typeof value === 'number' && !isNaN(value)) {
      return value;
    }
    return 0;
  }

  static safeFileSegment(value: string): string {
    let result = '';
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      const char = value.charAt(index);
      const allowed = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) || char === '_' || char === '-';
      result += allowed ? char : '_';
    }
    return result;
  }

}
