import { initializeApp, getApps } from 'firebase/app';
import { getMessaging, getToken, isSupported, onMessage, type MessagePayload } from 'firebase/messaging';
import { api } from '@/services/api';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID,
};

const vapidKey = import.meta.env.VITE_FIREBASE_VAPID_KEY;

function hasFirebaseConfig() {
  return Boolean(
    firebaseConfig.apiKey &&
      firebaseConfig.authDomain &&
      firebaseConfig.projectId &&
      firebaseConfig.messagingSenderId &&
      firebaseConfig.appId &&
      vapidKey
  );
}

function app() {
  return getApps()[0] || initializeApp(firebaseConfig);
}

async function messaging() {
  if (!hasFirebaseConfig()) return null;
  if (!(await isSupported().catch(() => false))) return null;
  return getMessaging(app());
}

export async function registerWebPush() {
  if (!('Notification' in window) || !('serviceWorker' in navigator)) return null;

  const client = await messaging();
  if (!client) return null;

  const permission =
    Notification.permission === 'granted'
      ? 'granted'
      : await Notification.requestPermission().catch(() => 'denied');

  if (permission !== 'granted') return null;

  const registration = await navigator.serviceWorker.register('/firebase-messaging-sw.js');
  const token = await getToken(client, {
    vapidKey,
    serviceWorkerRegistration: registration,
  }).catch(() => null);

  if (!token) return null;

  await api.post('/notifications/devices', { token, platform: 'WEB' }).catch(() => {});
  return token;
}

export async function onForegroundPush(handler: (payload: MessagePayload) => void) {
  const client = await messaging();
  if (!client) return () => {};
  return onMessage(client, handler);
}
