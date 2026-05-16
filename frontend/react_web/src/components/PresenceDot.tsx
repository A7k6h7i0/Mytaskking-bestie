import clsx from 'clsx';
import './presence-dot.css';

export type PresenceStatus = 'ACTIVE' | 'AWAY' | 'BUSY' | 'IN_MEETING' | 'INVISIBLE' | 'OFFLINE';

interface Props {
  status: PresenceStatus;
  size?: number;
  className?: string;
}

const TITLE: Record<PresenceStatus, string> = {
  ACTIVE: 'Active',
  AWAY: 'Away',
  BUSY: 'Busy',
  IN_MEETING: 'In a meeting',
  INVISIBLE: 'Invisible',
  OFFLINE: 'Offline',
};

export function PresenceDot({ status, size = 10, className }: Props) {
  return (
    <span
      className={clsx('pd', `pd--${status.toLowerCase()}`, className)}
      style={{ width: size, height: size }}
      title={TITLE[status]}
      aria-label={TITLE[status]}
    />
  );
}
