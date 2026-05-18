import { ReactNode } from 'react';
import clsx from 'clsx';
import { useScrollReveal } from '@/hooks/useMotionFx';

interface Props {
  children: ReactNode;
  variant?: 'up' | 'scale' | 'left' | 'right';
  delay?: number;
  className?: string;
}

/**
 * Wraps children in an element that fades + transforms into place the first
 * time it crosses the viewport threshold. Use to give long scroll regions a
 * polished "stuff arrives as you reach it" feel.
 */
export function ScrollReveal({ children, variant = 'up', delay = 0, className }: Props) {
  const ref = useScrollReveal<HTMLDivElement>();
  return (
    <div
      ref={ref}
      className={clsx('m-reveal', variant !== 'up' && `m-reveal--${variant}`, className)}
      style={delay ? { transitionDelay: `${delay}ms` } : undefined}
    >
      {children}
    </div>
  );
}
