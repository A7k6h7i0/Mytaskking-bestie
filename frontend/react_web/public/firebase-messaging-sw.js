/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/12.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.13.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBuwRmtvS9gqkkcgIYDbhDXMwPi0h5oi-w',
  authDomain: 'mytaskking.firebaseapp.com',
  projectId: 'mytaskking',
  storageBucket: 'mytaskking.firebasestorage.app',
  messagingSenderId: '239833916361',
  appId: '1:239833916361:web:0a4d8c6b5f0381bb083e18',
  measurementId: 'G-NNBYG3DM5P',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};
  self.registration.showNotification(notification.title || 'MyTaskKing', {
    body: notification.body || 'New notification',
    icon: '/favicon.svg',
    badge: '/favicon.svg',
    data,
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const channelId = event.notification.data?.channelId;
  const targetUrl = channelId ? `/chat/${channelId}` : '/dashboard';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        const url = new URL(client.url);
        if (url.origin === self.location.origin) {
          return client.navigate(targetUrl).then(() => client.focus());
        }
      }
      return self.clients.openWindow(targetUrl);
    })
  );
});
