/**
 * Realtime collaboration scaffolding.
 *
 * Today this is a thin wrapper around the Socket.IO connection that knows how
 * to send + receive presence updates on a per-document basis (a task, a note,
 * a whiteboard). The shape is intentionally yjs-shaped so swapping the
 * transport for `y-websocket` or `y-webrtc` later doesn't change call sites.
 *
 *   const room = joinCollabRoom('task:abc');
 *   room.onPresence((peers) => …);
 *   room.publishCursor({ x, y });
 *   room.publishOp(op);    // op = anything; opaque to the transport
 *   room.leave();
 *
 * When you wire up yjs:
 *   - replace `joinCollabRoom` with a `new Y.Doc()` + `new WebsocketProvider`
 *   - keep the same exported function signature
 *   - delete the manual op/cursor relays here
 */

import { getSocket } from './socket';
import { useAuthStore } from '@/store/auth';

type CursorPayload = { x: number; y: number; selection?: unknown };
type OpPayload = unknown;
type PresencePeer = { userId: string; name: string; cursor?: CursorPayload };

type Listeners = {
  presence: ((peers: PresencePeer[]) => void)[];
  ops: ((op: OpPayload, from: string) => void)[];
};

export interface CollabRoom {
  id: string;
  publishCursor(c: CursorPayload): void;
  publishOp(op: OpPayload): void;
  onPresence(fn: (peers: PresencePeer[]) => void): () => void;
  onOp(fn: (op: OpPayload, from: string) => void): () => void;
  leave(): void;
}

const rooms = new Map<string, { listeners: Listeners; peers: Map<string, PresencePeer> }>();

export function joinCollabRoom(roomId: string): CollabRoom {
  const socket = getSocket();
  const me = useAuthStore.getState().user;
  if (!socket || !me) {
    return noopRoom(roomId);
  }

  const state = rooms.get(roomId) || {
    listeners: { presence: [], ops: [] },
    peers: new Map<string, PresencePeer>(),
  };
  rooms.set(roomId, state);

  socket.emit('collab.join', { roomId, user: { id: me.id, name: me.name } });

  const onPresence = (p: { roomId: string; peers: PresencePeer[] }) => {
    if (p.roomId !== roomId) return;
    state.peers = new Map(p.peers.map((x) => [x.userId, x]));
    state.listeners.presence.forEach((fn) => fn(p.peers));
  };
  const onOp = (p: { roomId: string; from: string; op: OpPayload }) => {
    if (p.roomId !== roomId) return;
    state.listeners.ops.forEach((fn) => fn(p.op, p.from));
  };
  socket.on('collab.presence', onPresence);
  socket.on('collab.op', onOp);

  return {
    id: roomId,
    publishCursor: (c) => socket.emit('collab.cursor', { roomId, cursor: c }),
    publishOp: (op) => socket.emit('collab.op', { roomId, op }),
    onPresence: (fn) => { state.listeners.presence.push(fn); return () => state.listeners.presence.splice(state.listeners.presence.indexOf(fn), 1); },
    onOp: (fn) => { state.listeners.ops.push(fn); return () => state.listeners.ops.splice(state.listeners.ops.indexOf(fn), 1); },
    leave: () => {
      socket.emit('collab.leave', { roomId });
      socket.off('collab.presence', onPresence);
      socket.off('collab.op', onOp);
      rooms.delete(roomId);
    },
  };
}

function noopRoom(roomId: string): CollabRoom {
  return {
    id: roomId,
    publishCursor: () => {},
    publishOp: () => {},
    onPresence: () => () => {},
    onOp: () => () => {},
    leave: () => {},
  };
}
