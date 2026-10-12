{{flutter_js}}
{{flutter_build_config}}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('service-worker.js', { scope: './', updateViaCache: 'none' })
    .catch(error => console.warn('Offline loading is unavailable:', error));
}

_flutter.loader.load({
  onEntrypointLoaded: async engineInitializer => {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
      document.getElementById('loading')?.remove();
    } catch (error) {
      console.error('Personal Todo could not start:', error);
      const loading = document.getElementById('loading');
      if (loading) {
        loading.textContent = '앱을 열 수 없습니다. Safari의 일반 모드에서 다시 열어 주세요. / Please reopen in a regular Safari window.';
        const retry = document.createElement('button');
        retry.textContent = '새로고침 / Reload';
        retry.onclick = () => location.reload();
        loading.appendChild(retry);
      }
    }
  }
});
