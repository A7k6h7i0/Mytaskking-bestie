import clsx from 'clsx';
import './success-check.css';

interface Props {
  size?: number;
  tone?: 'success' | 'brand';
  className?: string;
}

/**
 * Drawn check-mark with a circle that strokes itself in. Use in confirmation
 * dialogs, post-submit states, and onboarding completion moments.
 */
export function SuccessCheck({ size = 64, tone = 'success', className }: Props) {
  const color = tone === 'brand' ? 'var(--c-brand)' : 'var(--c-success)';
  return (
    <svg
      className={clsx('sk-mark', className)}
      width={size}
      height={size}
      viewBox="0 0 64 64"
      aria-hidden
    >
      <circle
        className="sk-mark__ring"
        cx="32" cy="32" r="28"
        fill="none"
        stroke={color}
        strokeWidth="4"
        strokeLinecap="round"
        strokeDasharray="176"
      />
      <path
        className="sk-mark__tick"
        d="M20 33l9 9 16-18"
        fill="none"
        stroke={color}
        strokeWidth="5"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeDasharray="48"
      />
    </svg>
  );
}
