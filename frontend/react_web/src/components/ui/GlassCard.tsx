import { HTMLAttributes, ReactNode } from 'react';
import clsx from 'clsx';
import './glass-card.css';

interface GlassCardProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode;
  variant?: 'soft' | 'strong';
  glow?: boolean;
  /** Adds a moving gradient border for emphasis. */
  gradientBorder?: boolean;
}

/**
 * Frosted-glass card — translucent surface + backdrop blur. Sits beautifully
 * over particle fields, gradients, hero imagery. Use sparingly; one or two
 * per page is plenty.
 */
export function GlassCard({ children, className, variant = 'soft', glow, gradientBorder, ...rest }: GlassCardProps) {
  return (
    <div
      {...rest}
      className={clsx(
        'gc',
        variant === 'strong' ? 'm-glass-strong' : 'm-glass',
        glow && 'gc--glow',
        gradientBorder && 'm-gradient-border',
        className
      )}
    >
      {children}
    </div>
  );
}
