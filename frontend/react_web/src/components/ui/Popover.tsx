import { ReactNode, useEffect, useRef, useState, cloneElement, ReactElement } from 'react';
import './popover.css';

interface PopoverProps {
  content: ReactNode;
  placement?: 'bottom-start' | 'bottom-end' | 'top-start' | 'top-end';
  trigger: ReactElement;
}

/**
 * Lightweight popover anchored to its trigger. Closes on outside click,
 * ESC, or scroll. Used by menu surfaces that don't justify a full Drawer.
 */
export function Popover({ content, placement = 'bottom-start', trigger }: PopoverProps) {
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (!open) return;
    function onClick(e: MouseEvent) {
      if (!wrapRef.current?.contains(e.target as Node)) setOpen(false);
    }
    function onKey(e: KeyboardEvent) { if (e.key === 'Escape') setOpen(false); }
    document.addEventListener('mousedown', onClick);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onClick);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const t = cloneElement(trigger, { onClick: (e: React.MouseEvent) => { trigger.props.onClick?.(e); setOpen((v) => !v); } });

  return (
    <span className="pv-wrap" ref={wrapRef}>
      {t}
      {open && (
        <div className={`pv pv--${placement} m-scale-in`}>
          {content}
        </div>
      )}
    </span>
  );
}
