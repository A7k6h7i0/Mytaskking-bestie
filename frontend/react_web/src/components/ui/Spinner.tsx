import clsx from 'clsx';
import './spinner.css';

interface SpinnerProps {
  size?: number;
  variant?: 'ring' | 'dots' | 'bars';
  className?: string;
}

/** Three spinner styles — ring (default), dots, and bars. */
export function Spinner({ size = 18, variant = 'ring', className }: SpinnerProps) {
  if (variant === 'dots') {
    return (
      <span className={clsx('sp-dots', className)} style={{ fontSize: size * 0.4 }}>
        <span /><span /><span />
      </span>
    );
  }
  if (variant === 'bars') {
    return (
      <span className={clsx('sp-bars', className)} style={{ width: size, height: size }}>
        <span /><span /><span /><span />
      </span>
    );
  }
  return (
    <svg className={clsx('sp-ring m-spin', className)} width={size} height={size} viewBox="0 0 24 24" aria-label="Loading">
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeOpacity="0.18" strokeWidth="3"/>
      <path d="M21 12a9 9 0 0 0-9-9" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round"/>
    </svg>
  );
}
