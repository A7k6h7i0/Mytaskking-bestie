import { useEffect } from 'react';

/**
 * Global keyboard-shortcut bindings.
 *
 * Each binding is `{ combo, handler, description, when? }`. Combo strings are
 * dash-separated, e.g. `"mod-k"` (mod = ⌘ on mac, Ctrl elsewhere), `"shift-?"`,
 * `"g-d"` for the two-key g-d sequence (Vim-style "go to dashboard").
 *
 * Bindings registered through this hook should be UI-affordances (open the
 * palette, jump to a section, toggle help). Editor-style keystrokes still
 * belong inside the input components themselves.
 */

export type Binding = {
  combo: string;
  handler: (e: KeyboardEvent) => void;
  description: string;
  when?: () => boolean;
};

let pending: { key: string; at: number } | null = null;
const SEQUENCE_WINDOW_MS = 1000;

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName.toLowerCase();
  if (tag === 'input' || tag === 'textarea' || tag === 'select') return true;
  if (target.isContentEditable) return true;
  return false;
}

function matches(combo: string, e: KeyboardEvent): boolean {
  const parts = combo.toLowerCase().split('-');

  // Sequence (e.g. "g-d")
  if (parts.length === 2 && !['mod', 'shift', 'alt'].includes(parts[0]) && parts[0].length === 1) {
    const [first, second] = parts;
    if (pending && pending.key === first && Date.now() - pending.at < SEQUENCE_WINDOW_MS) {
      if (e.key.toLowerCase() === second) {
        pending = null;
        return true;
      }
    }
    if (e.key.toLowerCase() === first) {
      pending = { key: first, at: Date.now() };
      return false;
    }
    return false;
  }

  const wantMod = parts.includes('mod');
  const wantShift = parts.includes('shift');
  const wantAlt = parts.includes('alt');
  const key = parts.filter((p) => !['mod', 'shift', 'alt'].includes(p)).pop();

  const isMac = navigator.platform.toLowerCase().includes('mac');
  const modPressed = isMac ? e.metaKey : e.ctrlKey;

  return (
    wantMod === modPressed &&
    wantShift === e.shiftKey &&
    wantAlt === e.altKey &&
    e.key.toLowerCase() === key
  );
}

export function useKeyboardShortcuts(bindings: Binding[]) {
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (isTypingTarget(e.target)) return;
      for (const b of bindings) {
        if (b.when && !b.when()) continue;
        if (matches(b.combo, e)) {
          e.preventDefault();
          b.handler(e);
          return;
        }
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [bindings]);
}
