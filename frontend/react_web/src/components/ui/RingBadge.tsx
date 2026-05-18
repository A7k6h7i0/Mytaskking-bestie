import { ReactNode } from 'react';
import clsx from 'clsx';
import './ring-badge.css';

interface RingBadgeProps {
  children: ReactNode;
  /** 0–100, fills the ring. */
  value?: number;
  tone?: 'brand' | 'success' | 'warning' | 'danger' | 'accent';
  size?: number;
  thickness?: number;
  pulse?: boolean;
  className?: string;
}

/**
 * Avatar/icon wrapped in a progress ring. Use for streaks, online presence
 * rings, profile completion meters, "energy" bars on telecaller cards.
 */
export function RingBadge({
  children,
  value = 100,
  tone = 'brand',
  size = 48,
  thickness = 3,
  pulse,
  className,
}: RingBadgeProps) {
  const r = (size - thickness) / 2;
  const c = 2 * Math.PI * r;
  const offset = c * (1 - Math.max(0, Math.min(100, value)) / 100);
  const color =
    tone === 'success' ? 'var(--c-success)' :
    tone === 'warning' ? 'var(--c-warning)' :
    tone === 'danger'  ? 'var(--c-danger)'  :
    tone === 'accent'  ? 'var(--c-accent)'  :
    'var(--c-brand)';

  return (
    <span
      className={clsx('rb', pulse && 'm-glow', className)}
      style={{ width: size, height: size }}
    >
      <svg className="rb__ring" width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--c-surface-2)" strokeWidth={thickness} />
        <circle
          cx={size / 2} cy={size / 2} r={r}
          fill="none"
          stroke={color}
          strokeWidth={thickness}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={offset}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
          style={{ transition: 'stroke-dashoffset var(--dur-slow) var(--ease)' }}
        />
      </svg>
      <span className="rb__slot">{children}</span>
    </span>
  );
}
