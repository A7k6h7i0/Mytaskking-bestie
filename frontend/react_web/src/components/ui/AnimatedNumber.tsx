import { useEffect, useRef, useState } from 'react';

interface AnimatedNumberProps {
  value: number;
  duration?: number;          // ms
  format?: (n: number) => string;
  className?: string;
}

/**
 * Smoothly tweens a number from its previous value to the new one. Uses
 * requestAnimationFrame with an ease-out cubic. Honors prefers-reduced-motion
 * (jumps straight to the target).
 */
export function AnimatedNumber({ value, duration = 800, format = (n) => Math.round(n).toLocaleString(), className }: AnimatedNumberProps) {
  const [display, setDisplay] = useState(value);
  const prev = useRef(value);
  const raf = useRef<number | null>(null);

  useEffect(() => {
    const start = performance.now();
    const from = prev.current;
    const to = value;
    if (from === to) return;

    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced) { setDisplay(to); prev.current = to; return; }

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      setDisplay(from + (to - from) * eased);
      if (t < 1) raf.current = requestAnimationFrame(tick);
      else prev.current = to;
    };
    raf.current = requestAnimationFrame(tick);
    return () => { if (raf.current) cancelAnimationFrame(raf.current); };
  }, [value, duration]);

  return <span className={className}>{format(display)}</span>;
}
