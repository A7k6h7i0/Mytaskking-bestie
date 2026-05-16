import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useKeyboardShortcuts } from '@/hooks/useKeyboardShortcuts';
import './shortcuts-overlay.css';

/**
 * Global shortcuts + their on-screen reference. Shift-? opens the panel.
 *
 * `mod-k` is handled inside CommandPalette directly (it owns its own listener
 * for legacy reasons). We register the same combo here as a no-op so it shows
 * up in the help list.
 */
export function ShortcutsOverlay() {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();

  const bindings = [
    { combo: 'mod-k', description: 'Open command palette', handler: () => {} },
    { combo: 'shift-?', description: 'Show keyboard shortcuts', handler: () => setOpen((v) => !v) },
    { combo: 'g-d', description: 'Go to dashboard', handler: () => navigate('/dashboard') },
    { combo: 'g-c', description: 'Go to chat', handler: () => navigate('/chat') },
    { combo: 'g-t', description: 'Go to tasks', handler: () => navigate('/tasks') },
    { combo: 'g-a', description: 'Go to calendar', handler: () => navigate('/calendar') },
    { combo: 'g-n', description: 'Go to channels', handler: () => navigate('/channels') },
    { combo: 'g-s', description: 'Go to saved', handler: () => navigate('/saved') },
    { combo: 'g-i', description: 'Go to activity', handler: () => navigate('/activity') },
  ];

  useKeyboardShortcuts(bindings);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false);
    }
    if (open) window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  if (!open) return null;

  return (
    <div className="ks" onMouseDown={(e) => { if (e.target === e.currentTarget) setOpen(false); }}>
      <div className="ks__panel fade-in">
        <header><h3>Keyboard shortcuts</h3><kbd>esc</kbd></header>
        <ul>
          {bindings.map((b) => (
            <li key={b.combo}>
              <span>{b.description}</span>
              <Combo combo={b.combo} />
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

function Combo({ combo }: { combo: string }) {
  const isMac = typeof navigator !== 'undefined' && navigator.platform.toLowerCase().includes('mac');
  const parts = combo.split('-').map((p) => {
    if (p === 'mod') return isMac ? '⌘' : 'Ctrl';
    if (p === 'shift') return '⇧';
    if (p === 'alt') return isMac ? '⌥' : 'Alt';
    return p.length === 1 ? p.toUpperCase() : p;
  });
  return (
    <span className="ks__combo">
      {parts.map((p, i) => (
        <kbd key={i}>{p}</kbd>
      ))}
    </span>
  );
}
