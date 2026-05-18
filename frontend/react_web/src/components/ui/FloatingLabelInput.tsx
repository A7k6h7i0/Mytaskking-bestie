import { InputHTMLAttributes, forwardRef, ReactNode, useId } from 'react';
import clsx from 'clsx';
import './floating-label-input.css';

interface Props extends Omit<InputHTMLAttributes<HTMLInputElement>, 'placeholder'> {
  label: string;
  leading?: ReactNode;
  trailing?: ReactNode;
  error?: string;
  hint?: string;
}

/**
 * Material-style floating-label input. The label rests inside the field at
 * rest, then springs up + shrinks into the border on focus / when filled.
 * Pairs with our token system so it inherits dark mode + brand colors.
 */
export const FloatingLabelInput = forwardRef<HTMLInputElement, Props>(function FloatingLabelInput(
  { label, leading, trailing, error, hint, className, value, defaultValue, id, ...rest },
  ref
) {
  const reactId = useId();
  const inputId = id || `fli-${reactId}`;
  const filled = value != null && String(value).length > 0;

  return (
    <label
      className={clsx('fli', filled && 'is-filled', error && 'is-error', className)}
      htmlFor={inputId}
    >
      <span className="fli__field">
        {leading && <span className="fli__leading">{leading}</span>}
        <input
          ref={ref}
          id={inputId}
          className="fli__input"
          placeholder=" "
          value={value}
          defaultValue={defaultValue}
          {...rest}
        />
        <span className="fli__label">{label}</span>
        {trailing && <span className="fli__trailing">{trailing}</span>}
      </span>
      {(error || hint) && <span className="fli__hint">{error || hint}</span>}
    </label>
  );
});
