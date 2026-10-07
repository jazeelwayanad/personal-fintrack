self.addEventListener('push', event => {
  let data = {}; try { data = event.data.json(); } catch { data = { body: 'Open FinTrack to review your payments.' }; }
  event.waitUntil(self.registration.showNotification(data.title || 'FinTrack', { body: data.body, icon: '/icons/icon-192.png', tag: 'fintrack-daily', data: { url: data.url || '/plans' } }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL(event.notification.data.url || '/plans', self.location.origin);
  if (target.origin !== self.location.origin) return;
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async windows => { for (const client of windows) { await client.navigate(target.href); return client.focus(); } return clients.openWindow(target.href); }));
});
