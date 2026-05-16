import { InputHTMLAttributes, forwardRef, ReactNode } from 'react';
import clsx from 'clsx';
import './input.css';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  hint?: string;
  error?: string;
  leading?: ReactNode;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { label, hint, error, leading, className, ...rest },
  ref
) {
  return (
    <label className={clsx('bi', error && 'bi--error', className)}>
      {label && <span className="bi__label">{label}</span>}
      <span className="bi__field">
        {leading && <span className="bi__leading">{leading}</span>}
        <input ref={ref} className="bi__input" {...rest} />
      </span>
      {(error || hint) && <span className="bi__hint">{error || hint}</span>}
    </label>
  );
});
