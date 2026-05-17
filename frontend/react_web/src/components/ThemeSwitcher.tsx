import { useEffect } from 'react';
import { Sun, Moon, Monitor, type LucideIcon } from 'lucide-react';
import clsx from 'clsx';
import { applyTheme, useThemeStore, type ThemeMode } from '@/store/theme';
import './theme-switcher.css';

const OPTIONS: { value: ThemeMode; icon: LucideIcon; label: string }[] = [
  { value: 'light', icon: Sun, label: 'Light' },
  { value: 'dark', icon: Moon, label: 'Dark' },
  { value: 'system', icon: Monitor, label: 'System' },
];

export function ThemeSwitcher() {
  const mode = useThemeStore((s) => s.mode);
  const setMode = useThemeStore((s) => s.setMode);

  useEffect(() => {
    applyTheme(mode);
    if (mode === 'system') {
      const mq = window.matchMedia('(prefers-color-scheme: dark)');
      const onChange = () => applyTheme('system');
      mq.addEventListener('change', onChange);
      return () => mq.removeEventListener('change', onChange);
    }
  }, [mode]);

  return (
    <div className="th" role="radiogroup" aria-label="Theme">
      {OPTIONS.map((o) => (
        <button
          key={o.value}
          className={clsx('th__opt', mode === o.value && 'is-active')}
          onClick={() => setMode(o.value)}
          title={o.label}
          aria-pressed={mode === o.value}
        >
          <o.icon size={14} />
        </button>
      ))}
    </div>
  );
}
