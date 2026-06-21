import AbilityStage from '@ohos.app.ability.AbilityStage';
import Want from '@ohos.app.ability.Want';

const WEB_SHORTCUT_ABILITY = 'WebShortcutAbility';
const WEB_SHORTCUT_URL_KEY = 'webUrl';
const WEB_SHORTCUT_ID_KEY = 'webShortcutId';
const WEB_SHORTCUT_ID_PREFIX = 'smart_agent_web_';
const DEFAULT_WEB_SHORTCUT_INSTANCE = 'smart_agent_web_default';

export default class EntryAbilityStage extends AbilityStage {
  onAcceptWant(want: Want): string {
    if (want.abilityName !== WEB_SHORTCUT_ABILITY) {
      return '';
    }

    const shortcutId = this.stringParameter(want, WEB_SHORTCUT_ID_KEY);
    if (shortcutId.length > 0) {
      return shortcutId;
    }

    const url = this.stringParameter(want, WEB_SHORTCUT_URL_KEY);
    if (url.length > 0) {
      return WEB_SHORTCUT_ID_PREFIX + this.stableUrlKey(url);
    }
    return DEFAULT_WEB_SHORTCUT_INSTANCE;
  }

  private stringParameter(want: Want, key: string): string {
    const parameters = want.parameters;
    if (parameters === undefined) {
      return '';
    }
    const value = parameters[key];
    if (typeof value === 'string') {
      return value.trim();
    }
    return '';
  }

  private stableUrlKey(url: string): string {
    let hash = 2166136261;
    for (let index = 0; index < url.length; index++) {
      hash ^= url.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }
}
