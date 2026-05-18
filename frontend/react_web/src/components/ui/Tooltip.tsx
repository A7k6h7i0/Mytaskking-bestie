import { cloneElement, ReactElement, ReactNode, useRef, useState } from 'react';
import './tooltip.css';

interface TooltipProps {
  label: ReactNode;
  placement?: 'top' | 'bottom' | 'left' | 'right';
  delay?: number;
  children: ReactElement;
}

/**
 * Tiny tooltip with pointer-events: none, automatic placement flip, and a
 * 250ms open delay so it doesn't fire on quick mouse-overs. Anchors itself
 * by cloning its single child and attaching mouseenter/mouseleave/focus.
 */
export function Tooltip({ label, placement = 'top', delay = 250, children }: TooltipProps) {
  const [visible, setVisible] = useState(false);
  const timer = useRef<number | null>(null);

  function show() {
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setVisible(true), delay);
  }
  function hide() {
    if (timer.current) window.clearTimeout(timer.current);
    setVisible(false);
  }

  const trigger = cloneElement(children, {
    onMouseEnter: show,
    onMouseLeave: hide,
    onFocus: show,
    onBlur: hide,
  });

  return (
    <span className="tt-wrap">
      {trigger}
      {visible && (
        <span className={`tt tt--${placement} m-fade-up`} role="tooltip">
          {label}
        </span>
      )}
    </span>
  );
}
