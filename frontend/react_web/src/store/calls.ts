import { create } from 'zustand';

export type IncomingCallPayload = {
  call: {
    id: string;
    kind: 'ONE_TO_ONE' | 'GROUP';
    status: string;
    channelName?: string;
    initiator?: { id: string; name: string; avatarUrl?: string | null };
    participants?: Array<{ userId: string; user?: { id: string; name: string; avatarUrl?: string | null; role?: string; isClient?: boolean } }>;
  };
  token?: {
    token: string;
    channelName: string;
    uid: string;
    expiresAt: number;
    appId: string;
  };
};

type CallState = {
  pending: IncomingCallPayload | null;
  currentCallId: string | null;
  setPending: (payload: IncomingCallPayload | null) => void;
  clearPending: () => void;
  setCurrentCall: (callId: string | null) => void;
};

export const useCallStore = create<CallState>((set) => ({
  pending: null,
  currentCallId: null,
  setPending: (pending) => set({ pending }),
  clearPending: () => set({ pending: null }),
  setCurrentCall: (currentCallId) => set({ currentCallId }),
}));
