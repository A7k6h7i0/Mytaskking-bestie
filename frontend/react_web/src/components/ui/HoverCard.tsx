import { ReactNode, cloneElement, isValidElement, ReactElement, useEffect, useRef, useState } from 'react';
import './hover-card.css';

interface HoverCardProps {
  trigger: ReactElement;
  content: ReactNode;
  delay?: number;
  side?: 'top' | 'bottom' | 'left' | 'right';
}

/**
 * Rich hover-preview popover — heavier than `<Tooltip>`, lighter than
 * `<Popover>`. Designed for user mentions, file previews, link rich-previews,
 * task cards. Opens on hover/focus with a 350ms delay so it doesn't fire on
 * stray cursor sweeps.
 */
export function HoverCard({ trigger, content, delay = 350, side = 'bottom' }: HoverCardProps) {
  const [open, setOpen] = useState(false);
  const wrap = useRef<HTMLSpanElement>(null);
  const openTimer = useRef<number | null>(null);
  const closeTimer = useRef<number | null>(null);

  function scheduleOpen() {
    if (closeTimer.current) { window.clearTimeout(closeTimer.current); closeTimer.current = null; }
    openTimer.current = window.setTimeout(() => setOpen(true), delay);
  }
  function scheduleClose() {
    if (openTimer.current) { window.clearTimeout(openTimer.current); openTimer.current = null; }
    closeTimer.current = window.setTimeout(() => setOpen(false), 120);
  }
  useEffect(() => () => {
    if (openTimer.current) window.clearTimeout(openTimer.current);
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
  }, []);

  const t = isValidElement(trigger)
    ? cloneElement(trigger, {
        onMouseEnter: scheduleOpen,
        onMouseLeave: scheduleClose,
        onFocus: scheduleOpen,
        onBlur: scheduleClose,
      } as Partial<unknown>)
    : trigger;

  return (
    <span ref={wrap} className="hc-wrap">
      {t}
      {open && (
        <div
          className={`hc hc--${side} m-fade-up`}
          onMouseEnter={scheduleOpen}
          onMouseLeave={scheduleClose}
          role="dialog"
        >
          {content}
        </div>
      )}
    </span>
  );
}
