import { ButtonHTMLAttributes, forwardRef } from 'react';
import clsx from 'clsx';
import './button.css';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';
type Size = 'sm' | 'md' | 'lg';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  loading?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = 'primary', size = 'md', loading, className, children, disabled, ...rest },
  ref
) {
  return (
    <button
      ref={ref}
      disabled={disabled || loading}
      className={clsx('bb', `bb--${variant}`, `bb--${size}`, loading && 'bb--loading', className)}
      {...rest}
    >
      <span className="bb__content">{children}</span>
    </button>
  );
});
