import { ReactNode } from 'react';
import clsx from 'clsx';
import './badge.css';

type Tone = 'neutral' | 'brand' | 'success' | 'warning' | 'danger' | 'info' | 'client' | 'accent';

interface BadgeProps {
  children: ReactNode;
  tone?: Tone;
  variant?: 'solid' | 'soft' | 'outline';
  size?: 'sm' | 'md';
  dot?: boolean;
  className?: string;
}

/** Compact status / category pill. The toolkit's go-to for chips, statuses, counts. */
export function Badge({ children, tone = 'neutral', variant = 'soft', size = 'sm', dot, className }: BadgeProps) {
  return (
    <span className={clsx('bd', `bd--${tone}`, `bd--${variant}`, `bd--${size}`, className)}>
      {dot && <span className="bd__dot" />}
      {children}
    </span>
  );
}

interface StatusBadgeProps {
  status: string;
  pulse?: boolean;
  className?: string;
}

/** Auto-toned by status string — maps common workflow words to consistent colors. */
export function StatusBadge({ status, pulse, className }: StatusBadgeProps) {
  const tone = toneFor(status);
  return (
    <Badge tone={tone} dot className={clsx(pulse && 'm-pulse', className)}>
      {status}
    </Badge>
  );
}

function toneFor(s: string): Tone {
  const k = s.toUpperCase();
  if (['ACTIVE', 'DONE', 'WON', 'SEEN', 'ACCEPTED'].includes(k)) return 'success';
  if (['IN_PROGRESS', 'REVIEW', 'CONTACTED', 'DELIVERED'].includes(k)) return 'info';
  if (['TODO', 'NEW', 'BACKLOG', 'RINGING'].includes(k)) return 'brand';
  if (['INTERESTED', 'FOLLOWUP', 'WARNING', 'SENDING'].includes(k)) return 'warning';
  if (['CANCELLED', 'LOST', 'FAILED', 'MISSED', 'DECLINED', 'EXPIRED', 'SUSPENDED'].includes(k)) return 'danger';
  if (k === 'CLIENT') return 'client';
  return 'neutral';
}
