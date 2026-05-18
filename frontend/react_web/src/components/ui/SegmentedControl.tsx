import clsx from 'clsx';
import './segmented-control.css';

interface SegmentedControlProps<T extends string> {
  value: T;
  onChange: (next: T) => void;
  options: Array<{ value: T; label: string; icon?: React.ReactNode }>;
  size?: 'sm' | 'md';
  className?: string;
}

/** iOS-style pill segmented switcher. Use for compact view toggles. */
export function SegmentedControl<T extends string>({ value, onChange, options, size = 'md', className }: SegmentedControlProps<T>) {
  return (
    <div className={clsx('sc', `sc--${size}`, className)} role="radiogroup">
      {options.map((o) => (
        <button
          key={o.value}
          role="radio"
          aria-checked={value === o.value}
          className={clsx('sc__opt', value === o.value && 'is-active')}
          onClick={() => onChange(o.value)}
        >
          {o.icon}
          <span>{o.label}</span>
        </button>
      ))}
    </div>
  );
}
