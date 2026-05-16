import { io, Socket } from 'socket.io-client';
import { useAuthStore } from '@/store/auth';

let socket: Socket | null = null;

export function getSocket(): Socket | null {
  const token = useAuthStore.getState().accessToken;
  if (!token) return null;
  if (socket && socket.connected) return socket;
  const url = import.meta.env.VITE_SOCKET_URL || 'http://localhost:4000';
  socket = io(url, { auth: { token }, transports: ['websocket'], path: '/socket.io' });
  return socket;
}

export function disconnectSocket() {
  socket?.disconnect();
  socket = null;
}
