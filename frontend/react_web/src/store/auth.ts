import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export type Role = 'SUPER_ADMIN' | 'ADMIN' | 'MANAGER' | 'PROJECT_COORDINATOR_MANAGER' | 'EMPLOYEE' | 'TELECALLER' | 'CLIENT';

export interface User {
  id: string;
  userId: string;
  name: string;
  role: Role;
  isClient: boolean;
  avatarUrl?: string | null;
  customTitle?: string | null;
  clientCompany?: string | null;
  accessEndsAt?: string | null;
  status: 'ACTIVE' | 'SUSPENDED' | 'EXPIRED';
}

interface Session {
  user: User;
  accessToken: string;
  refreshToken: string;
}

interface AuthState {
  user: User | null;
  accessToken: string | null;
  refreshToken: string | null;
  setSession: (s: Session) => void;
  setUser: (u: User) => void;
  clear: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      user: null,
      accessToken: null,
      refreshToken: null,
      setSession: ({ user, accessToken, refreshToken }) => set({ user, accessToken, refreshToken }),
      setUser: (user) => set({ user }),
      clear: () => set({ user: null, accessToken: null, refreshToken: null }),
    }),
    { name: 'bestie-auth' }
  )
);
