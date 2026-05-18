import clsx from 'clsx';
import './progress.css';

interface ProgressBarProps {
  value?: number;             // 0–100; undefined → indeterminate
  tone?: 'brand' | 'success' | 'warning' | 'danger';
  height?: number;
  className?: string;
}

/** Linear progress bar. Pass `value` for determinate, omit for an animated stripe. */
export function ProgressBar({ value, tone = 'brand', height = 6, className }: ProgressBarProps) {
  const determinate = typeof value === 'number';
  return (
    <div className={clsx('pg', `pg--${tone}`, className)} style={{ height }}>
      <div
        className={clsx('pg__fill', !determinate && 'pg__fill--indet')}
        style={determinate ? { width: `${Math.max(0, Math.min(100, value!))}%` } : undefined}
      />
    </div>
  );
}

interface ProgressRingProps {
  value: number;              // 0–100
  size?: number;
  thickness?: number;
  tone?: 'brand' | 'success' | 'warning' | 'danger';
  label?: React.ReactNode;
}

/** Circular progress ring with a smoothly-animated stroke. */
export function ProgressRing({ value, size = 64, thickness = 6, tone = 'brand', label }: ProgressRingProps) {
  const r = (size - thickness) / 2;
  const c = 2 * Math.PI * r;
  const offset = c * (1 - Math.max(0, Math.min(100, value)) / 100);
  const color =
    tone === 'success' ? 'var(--c-success)' :
    tone === 'warning' ? 'var(--c-warning)' :
    tone === 'danger'  ? 'var(--c-danger)'  :
    'var(--c-brand)';

  return (
    <span className="pr" style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--c-surface-2)" strokeWidth={thickness} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          strokeWidth={thickness}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={offset}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
          style={{ transition: 'stroke-dashoffset var(--dur) var(--ease)' }}
        />
      </svg>
      {(label || label === 0) && <span className="pr__label">{label}</span>}
    </span>
  );
}
