export const WEB_BROWSER_BACKGROUND_PIP_REVISION_KEY = 'webBrowserBackgroundPipRevision';

export function notifyWebBrowserBackgroundForPictureInPicture(): void {
  AppStorage.setOrCreate(WEB_BROWSER_BACKGROUND_PIP_REVISION_KEY, Date.now());
}
