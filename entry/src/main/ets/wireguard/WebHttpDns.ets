import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DohSettings, loadDohSettings } from './ConfigStore';

const DOMAIN = 0x0001;
const TAG = 'WebHttpDns';
const HTTPS_PREFIX = 'https://';
const HTTPDNS_OFF_CONFIG = 'https://example.invalid';

type StoreContext = common.UIAbilityContext | common.VpnExtensionContext;

export async function syncWebHttpDnsFromDohSettings(context: StoreContext): Promise<void> {
  const settings = await loadDohSettings(context, true);
  applyWebHttpDnsFromDohSettings(settings);
}

export function applyWebHttpDnsFromDohSettings(settings: DohSettings): boolean {
  const provider = normalizeHttpDnsProvider(settings.provider);
  if (!settings.enabled || provider.length === 0) {
    return clearWebHttpDns();
  }

  try {
    webview.WebviewController.setHttpDns(webview.SecureDnsMode.AUTO, provider);
    hilog.info(DOMAIN, TAG, 'web httpdns set provider=%{public}s', provider);
    return true;
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'set web httpdns failed: %{public}s', formatError(error));
    return false;
  }
}

export function clearWebHttpDns(): boolean {
  try {
    webview.WebviewController.setHttpDns(webview.SecureDnsMode.OFF, HTTPDNS_OFF_CONFIG);
    hilog.info(DOMAIN, TAG, 'web httpdns cleared');
    return true;
  } catch (err) {
    const error = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'clear web httpdns failed: %{public}s', formatError(error));
    return false;
  }
}

function normalizeHttpDnsProvider(value: string): string {
  const provider = value.trim();
  if (provider.indexOf(HTTPS_PREFIX) !== 0) {
    return '';
  }
  return provider;
}

function formatError(error: BusinessError): string {
  const message = error.message ?? '';
  if (message.length > 0) {
    return 'code=' + String(error.code) + ', message=' + message;
  }
  return 'code=' + String(error.code) + ', error=' + JSON.stringify(error);
}
