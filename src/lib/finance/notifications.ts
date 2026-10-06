export async function enableNotifications() {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) throw new Error('Push is unavailable here. On iPhone, add FinTrack to your Home Screen first.');
  const response = await fetch('/api/v1/devices'); const config = await response.json();
  if (!response.ok || !config.publicKey) throw new Error('Push notifications need server configuration. In-app reminders are available.');
  if (await Notification.requestPermission() !== 'granted') throw new Error('Notifications were not enabled. You can allow them in browser settings.');
  const registration = await navigator.serviceWorker.register('/sw.js'); await navigator.serviceWorker.ready;
  const key = Uint8Array.from(atob(config.publicKey.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
  const subscription = await registration.pushManager.getSubscription() ?? await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
  const id = localStorage.getItem('fintrack-device') ?? crypto.randomUUID(); localStorage.setItem('fintrack-device', id);
  const saved = await fetch('/api/v1/devices', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id, platform: 'web', subscription: subscription.toJSON() }) });
  if (!saved.ok) throw new Error('Could not register this device.');
}
