import { ReactNode, useState } from 'react';
import clsx from 'clsx';
import { Plus, X } from 'lucide-react';
import './fab.css';

interface FabAction {
  icon: ReactNode;
  label: string;
  onClick: () => void;
  tone?: 'brand' | 'success' | 'warning' | 'danger';
}

interface FabProps {
  /** Stack of secondary actions. When omitted, the FAB just fires `onPress`. */
  actions?: FabAction[];
  onPress?: () => void;
  icon?: ReactNode;
  label?: string;
  position?: 'bottom-right' | 'bottom-left';
  className?: string;
}

/**
 * Floating action button with an optional speed-dial of secondary actions.
 * Tap the FAB to fan out the stack with a staggered scale; tap again to
 * collapse. Each action has a label that slides in from the side.
 */
export function Fab({ actions, onPress, icon, label, position = 'bottom-right', className }: FabProps) {
  const [open, setOpen] = useState(false);
  const hasStack = actions && actions.length > 0;

  function onMain() {
    if (hasStack) setOpen((v) => !v);
    else onPress?.();
  }

  return (
    <div className={clsx('fab', `fab--${position}`, open && 'is-open', className)}>
      {hasStack && (
        <ul className="fab__stack">
          {actions!.map((a, i) => (
            <li
              key={a.label}
              className="fab__stack-item"
              style={{ ['--stack-i' as never]: i }}
            >
              <span className="fab__stack-label">{a.label}</span>
              <button
                className={clsx('fab__stack-btn', a.tone && `fab__stack-btn--${a.tone}`)}
                onClick={() => { a.onClick(); setOpen(false); }}
                title={a.label}
                aria-label={a.label}
              >
                {a.icon}
              </button>
            </li>
          ))}
        </ul>
      )}
      <button
        className="fab__main m-press"
        onClick={onMain}
        aria-label={label || 'Open actions'}
        aria-expanded={hasStack ? open : undefined}
      >
        <span className="fab__main-icon">
          {hasStack ? (open ? <X size={20} /> : (icon || <Plus size={20} />)) : (icon || <Plus size={20} />)}
        </span>
      </button>
    </div>
  );
}
