import { ReactNode } from 'react';
import { Check } from 'lucide-react';
import clsx from 'clsx';
import './stepper.css';

interface Step {
  label: string;
  description?: ReactNode;
}

interface StepperProps {
  steps: Step[];
  current: number;            // zero-indexed
  variant?: 'horizontal' | 'vertical';
  className?: string;
}

/**
 * Multi-step progress indicator. The connecting line between steps fills in
 * smoothly as `current` advances, and the active circle pulses.
 */
export function Stepper({ steps, current, variant = 'horizontal', className }: StepperProps) {
  return (
    <ol className={clsx('st', `st--${variant}`, className)}>
      {steps.map((s, i) => {
        const state = i < current ? 'done' : i === current ? 'active' : 'pending';
        return (
          <li key={i} className={`st__item st__item--${state}`}>
            <span className={clsx('st__dot', state === 'active' && 'm-glow')}>
              {state === 'done' ? <Check size={14} /> : <span>{i + 1}</span>}
            </span>
            <span className="st__body">
              <span className="st__label">{s.label}</span>
              {s.description && <span className="st__desc">{s.description}</span>}
            </span>
            {i < steps.length - 1 && <span className="st__line" aria-hidden />}
          </li>
        );
      })}
    </ol>
  );
}
