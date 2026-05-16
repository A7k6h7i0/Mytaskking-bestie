import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export type ThemeMode = 'light' | 'dark' | 'system';

interface ThemeState {
  mode: ThemeMode;
  setMode: (m: ThemeMode) => void;
}

export const useThemeStore = create<ThemeState>()(
  persist(
    (set) => ({ mode: 'system', setMode: (mode) => set({ mode }) }),
    { name: 'bestie-theme' }
  )
);

/** Resolves a stored preference into the actual `light` | `dark` value. */
export function resolveMode(mode: ThemeMode): 'light' | 'dark' {
  if (mode !== 'system') return mode;
  if (typeof window === 'undefined') return 'light';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

/** Applies the resolved theme to <html> by toggling `.theme-dark`. */
export function applyTheme(mode: ThemeMode) {
  const resolved = resolveMode(mode);
  document.documentElement.classList.toggle('theme-dark', resolved === 'dark');
  document.documentElement.dataset.theme = resolved;
}
