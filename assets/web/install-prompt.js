(function () {
  const dismissedKey = 'coriderly-install-dismissed-at';
  const snoozeMs = 7 * 24 * 60 * 60 * 1000;
  const isWebPage = location.protocol === 'http:' || location.protocol === 'https:';
  // The Android app embeds this page in a WebView, where installing makes no sense.
  const isInsideApp = !isWebPage || typeof window.PineLabsCheckout !== 'undefined';
  const isInstalled = window.matchMedia('(display-mode: standalone)').matches ||
    window.navigator.standalone === true;
  const userAgent = window.navigator.userAgent;
  const isIos = /iphone|ipad|ipod/i.test(userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isMobile = isIos || /android/i.test(userAgent);

  if (isWebPage && 'serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('sw.js').catch(() => {});
    });
  }
  if (isInsideApp || isInstalled || !isMobile) return;

  try {
    const dismissedAt = Number(localStorage.getItem(dismissedKey));
    if (dismissedAt && Date.now() - dismissedAt < snoozeMs) return;
  } catch (error) {
    // Show the prompt when browser storage is unavailable.
  }

  let installEvent = null;
  let banner = null;

  function dismiss() {
    try { localStorage.setItem(dismissedKey, String(Date.now())); } catch (error) { /* Ignore. */ }
    if (banner) banner.remove();
    banner = null;
  }

  function showBanner(instructions) {
    if (banner) return;
    banner = document.createElement('div');
    banner.className = 'install-banner';
    banner.setAttribute('role', 'dialog');
    banner.setAttribute('aria-label', 'Install the CoRiderly app');
    banner.innerHTML = `
      <img class="install-banner-icon" src="icons/Icon-192.png" alt="" width="44" height="44" />
      <div class="install-banner-copy">
        <strong>Install the CoRiderly app</strong>
        <span class="install-banner-text"></span>
      </div>
      <button class="install-banner-action" type="button"></button>
      <button class="install-banner-close" type="button" aria-label="Not now">&times;</button>`;
    const text = banner.querySelector('.install-banner-text');
    const action = banner.querySelector('.install-banner-action');
    if (instructions) {
      text.textContent = 'Tap Share, then “Add to Home Screen”.';
      action.textContent = 'Got it';
      action.addEventListener('click', dismiss);
    } else {
      text.textContent = 'Add it to your home screen for quick access.';
      action.textContent = 'Install';
      action.addEventListener('click', async () => {
        if (!installEvent) return;
        const promptEvent = installEvent;
        installEvent = null;
        promptEvent.prompt();
        await promptEvent.userChoice.catch(() => {});
        if (banner) banner.remove();
        banner = null;
      });
    }
    banner.querySelector('.install-banner-close').addEventListener('click', dismiss);
    document.body.append(banner);
  }

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    installEvent = event;
    showBanner(false);
  });
  window.addEventListener('appinstalled', () => {
    installEvent = null;
    if (banner) banner.remove();
    banner = null;
  });

  // iOS Safari has no install event, so show the manual steps.
  if (isIos && !/crios|fxios|edgios/i.test(userAgent)) {
    window.addEventListener('load', () => window.setTimeout(() => showBanner(true), 2500));
  }
})();
