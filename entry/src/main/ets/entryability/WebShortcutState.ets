let currentUrl: string = '';
let currentShortcutId: string = '';

export function setCurrentWebShortcut(url: string, shortcutId: string): void {
  currentUrl = url;
  currentShortcutId = shortcutId;
}

export function currentWebShortcutUrl(): string {
  return currentUrl;
}

export function currentWebShortcutId(): string {
  return currentShortcutId;
}
