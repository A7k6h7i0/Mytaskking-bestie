import { ReactNode } from 'react';
import clsx from 'clsx';
import './kbd.css';

interface KbdProps {
  children: ReactNode;
  size?: 'sm' | 'md';
  className?: string;
}

/** Keyboard-cap-style chip for shortcuts. Use inside `<Combo>` for chord display. */
export function Kbd({ children, size = 'sm', className }: KbdProps) {
  return <kbd className={clsx('kb', `kb--${size}`, className)}>{children}</kbd>;
}

interface ComboProps {
  /** A combo string like "mod-k" or "shift-?" or "g-d". */
  combo: string;
  className?: string;
}

/** Renders a chord (e.g. `⌘ K`) with a Kbd per part. mod auto-resolves per platform. */
export function Combo({ combo, className }: ComboProps) {
  const isMac = typeof navigator !== 'undefined' && navigator.platform.toLowerCase().includes('mac');
  const parts = combo.split('-').map((p) => {
    if (p === 'mod')   return isMac ? '⌘' : 'Ctrl';
    if (p === 'shift') return '⇧';
    if (p === 'alt')   return isMac ? '⌥' : 'Alt';
    if (p === 'enter') return '↵';
    return p.length === 1 ? p.toUpperCase() : p;
  });
  return (
    <span className={clsx('kb-combo', className)}>
      {parts.map((p, i) => <Kbd key={i}>{p}</Kbd>)}
    </span>
  );
}
