import { ReactNode, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { X } from 'lucide-react';
import clsx from 'clsx';
import './drawer.css';

interface DrawerProps {
  open: boolean;
  onClose: () => void;
  side?: 'right' | 'left';
  title?: ReactNode;
  width?: number;
  children: ReactNode;
  footer?: ReactNode;
}

/**
 * Edge-anchored sliding panel. Perfect for task details, file previews,
 * inspector sidebars. Same backdrop + focus behavior as Modal.
 */
export function Drawer({ open, onClose, side = 'right', title, width = 440, children, footer }: DrawerProps) {
  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) { if (e.key === 'Escape') onClose(); }
    document.addEventListener('keydown', onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = prev;
    };
  }, [open, onClose]);

  if (!open) return null;

  return createPortal(
    <div className="dr m-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <aside
        className={clsx('dr__panel', `dr__panel--${side}`, side === 'right' ? 'm-slide-left' : 'm-slide-right')}
        style={{ width }}
        role="dialog"
        aria-modal="true"
      >
        <header className="dr__head">
          {title && <h2 className="dr__title">{title}</h2>}
          <button className="dr__close m-press" onClick={onClose} aria-label="Close"><X size={16} /></button>
        </header>
        <div className="dr__body">{children}</div>
        {footer && <footer className="dr__foot">{footer}</footer>}
      </aside>
    </div>,
    document.body
  );
}
