import { ReactNode } from 'react';
import clsx from 'clsx';
import './empty-state.css';

interface EmptyStateProps {
  icon?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  illustration?: 'inbox' | 'search' | 'channels' | 'calendar' | 'tasks' | 'sparkle' | 'lock';
  className?: string;
}

/**
 * Premium empty state with a built-in SVG illustration set drawn from tokens.
 * Use one of the named illustrations or pass your own through `icon`.
 *
 *   <EmptyState illustration="tasks" title="No tasks yet" action={<Button…/>} />
 */
export function EmptyState({ icon, title, description, action, illustration, className }: EmptyStateProps) {
  return (
    <div className={clsx('es m-fade-up', className)}>
      <div className="es__art m-float">
        {icon || (illustration && <Illustration kind={illustration} />)}
      </div>
      <h3 className="es__title">{title}</h3>
      {description && <p className="es__desc">{description}</p>}
      {action && <div className="es__action">{action}</div>}
    </div>
  );
}

function Illustration({ kind }: { kind: NonNullable<EmptyStateProps['illustration']> }) {
  // Token-colored SVGs so they look right in light + dark mode automatically.
  switch (kind) {
    case 'inbox':
      return (
        <svg viewBox="0 0 96 96" width="96" height="96" aria-hidden>
          <defs><linearGradient id="g-i" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stopColor="var(--c-brand)"/><stop offset="100%" stopColor="var(--c-accent)"/></linearGradient></defs>
          <rect x="14" y="22" width="68" height="56" rx="10" fill="var(--c-brand-soft)" />
          <path d="M14 50h22a8 8 0 0 0 8-8h8a8 8 0 0 0 8 8h22" fill="none" stroke="url(#g-i)" strokeWidth="3" strokeLinecap="round"/>
          <rect x="22" y="14" width="52" height="6" rx="3" fill="var(--c-border-strong)"/>
        </svg>
      );
    case 'search':
      return (
        <svg viewBox="0 0 96 96" width="96" height="96" aria-hidden>
          <circle cx="42" cy="42" r="22" fill="var(--c-brand-soft)" stroke="var(--c-brand)" strokeWidth="3"/>
          <path d="M60 60l16 16" stroke="var(--c-brand-strong)" strokeWidth="6" strokeLinecap="round"/>
        </svg>
      );
    case 'channels':
      return (
        <svg viewBox="0 0 96 96" width="96" height="96" aria-hidden>
          <path d="M28 20l-4 56M48 20l-4 56M14 36h52M10 60h52" stroke="var(--c-brand)" strokeWidth="3" strokeLinecap="round" fill="none"/>
        </svg>
      );
    case 'calendar':
      return (
        <svg viewBox="0 0 96 96" width="96" height="96" aria-hidden>
          <rect x="14" y="20" width="68" height="60" rx="8" fill="var(--c-brand-soft)" stroke="var(--c-brand)" strokeWidth="3"/>
          <path d="M14 34h68" stroke="var(--c-brand)" strokeWidth="3"/>
          <rect x="28" y="12" width="6" height="14" rx="2" fill="var(--c-brand-strong)"/>
          <rect x="62" y="12" width="6" height="14" rx="2" fill="var(--c-brand-strong)"/>
          <circle cx="48" cy="56" r="6" fill="var(--c-accent)"/>
        </svg>
      );
    case 'tasks':
      return (
        <svg viewBox="0 0 96 96" width="96" height="96" aria-hidden>
          <rect x="16" y="18" width="64" height="20" rx="6" fill="var(--c-brand-soft)"/>
          <rect x="16" y="42" width="64" height="20" rx="6" fill="var(--c-surface-2)"/>
          <rect x="16" y="66" width="40" height="14" rx="5" fill="var(--c-surface-2)"/>
          <path d="M24 28l4 4 8-8" stroke="var(--c-brand-strong)" strokeWidth="3" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      );
    case 'sparkle':
      return (
        <svg viewBox="0 0 96 96" width="96" height="96" aria-hidden>
          <path d="M48 16l6 18 18 6-18 6-6 18-6-18-18-6 18-6z" fill="var(--c-accent)"/>
          <circle cx="22" cy="68" r="6" fill="var(--c-brand)"/>
          <circle cx="74" cy="74" r="4" fill="var(--c-brand-strong)"/>
        </svg>
      );
    case 'lock':
      return (
        <svg viewBox="0 0 96 96" width="96" height="96" aria-hidden>
          <rect x="22" y="40" width="52" height="40" rx="8" fill="var(--c-brand-soft)" stroke="var(--c-brand)" strokeWidth="3"/>
          <path d="M34 40v-8a14 14 0 0 1 28 0v8" stroke="var(--c-brand-strong)" strokeWidth="3" fill="none" strokeLinecap="round"/>
          <circle cx="48" cy="60" r="4" fill="var(--c-brand-strong)"/>
        </svg>
      );
  }
}
