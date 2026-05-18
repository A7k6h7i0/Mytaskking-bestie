import { ReactNode, useLayoutEffect, useRef, useState } from 'react';
import clsx from 'clsx';
import './tabs.css';

interface TabsProps<T extends string> {
  value: T;
  onChange: (next: T) => void;
  tabs: Array<{ value: T; label: ReactNode; icon?: ReactNode; badge?: ReactNode }>;
  className?: string;
}

/** Animated-underline tabs with smooth slide between selections. */
export function Tabs<T extends string>({ value, onChange, tabs, className }: TabsProps<T>) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [bar, setBar] = useState({ x: 0, w: 0 });

  useLayoutEffect(() => {
    const active = trackRef.current?.querySelector<HTMLButtonElement>(`[data-value="${value}"]`);
    if (active && trackRef.current) {
      const tx = active.offsetLeft;
      const tw = active.offsetWidth;
      setBar({ x: tx, w: tw });
    }
  }, [value, tabs.length]);

  return (
    <div
      ref={trackRef}
      className={clsx('tb m-underline-track', className)}
      style={{ '--underline-x': `${bar.x}px`, '--underline-w': `${bar.w}px` } as React.CSSProperties}
    >
      {tabs.map((t) => (
        <button
          key={t.value}
          data-value={t.value}
          className={clsx('tb__tab m-press', value === t.value && 'is-active')}
          onClick={() => onChange(t.value)}
        >
          {t.icon}
          <span>{t.label}</span>
          {t.badge}
        </button>
      ))}
    </div>
  );
}
