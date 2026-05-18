import clsx from 'clsx';
import './switch.css';

interface SwitchProps {
  checked: boolean;
  onChange: (next: boolean) => void;
  size?: 'sm' | 'md';
  disabled?: boolean;
  label?: string;
  className?: string;
}

/** iOS-style toggle. Uses a real <button role="switch"> for keyboard + a11y. */
export function Switch({ checked, onChange, size = 'md', disabled, label, className }: SwitchProps) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      className={clsx('sw', `sw--${size}`, checked && 'is-on', className)}
      onClick={() => !disabled && onChange(!checked)}
    >
      <span className="sw__knob" />
    </button>
  );
}
