import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

/**
 * Bestie — motion behavior hooks.
 *
 * Each hook returns a ref to attach to an element plus (where useful) the
 * inline CSS variables that the matching utility class in motion-advanced.css
 * reads. Everything honors `prefers-reduced-motion: reduce` by collapsing to
 * a no-op so we never make accessibility-sensitive users sick.
 */

export function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(() =>
    typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches
  );
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    const onChange = () => setReduced(mq.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);
  return reduced;
}

/**
 * Magnetic hover — the element drifts toward the cursor as it nears.
 * Companion class: `.m-magnet`. Strength is the maximum pixel pull at the
 * element's edge; radius controls how far from the element the pull starts.
 */
export function useMagnetic<T extends HTMLElement = HTMLElement>(opts: { strength?: number; radius?: number } = {}) {
  const { strength = 14, radius = 110 } = opts;
  const ref = useRef<T | null>(null);
  const reduced = usePrefersReducedMotion();

  useEffect(() => {
    const el = ref.current;
    if (!el || reduced) return;

    let rafId = 0;
    let tx = 0, ty = 0;

    function onMove(e: MouseEvent) {
      const rect = el!.getBoundingClientRect();
      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;
      const dx = e.clientX - cx;
      const dy = e.clientY - cy;
      const dist = Math.hypot(dx, dy);
      if (dist > radius) {
        tx = 0; ty = 0;
      } else {
        const k = (1 - dist / radius) * strength;
        tx = (dx / dist) * k;
        ty = (dy / dist) * k;
      }
      if (!rafId) rafId = requestAnimationFrame(apply);
    }
    function apply() {
      rafId = 0;
      el!.style.setProperty('--tx', `${tx.toFixed(2)}px`);
      el!.style.setProperty('--ty', `${ty.toFixed(2)}px`);
    }
    function leave() {
      tx = 0; ty = 0;
      el!.style.setProperty('--tx', '0px');
      el!.style.setProperty('--ty', '0px');
    }

    window.addEventListener('mousemove', onMove);
    el.addEventListener('mouseleave', leave);
    return () => {
      window.removeEventListener('mousemove', onMove);
      el.removeEventListener('mouseleave', leave);
      if (rafId) cancelAnimationFrame(rafId);
    };
  }, [strength, radius, reduced]);

  return ref;
}

/**
 * 3D tilt — the element rotates as if the cursor were pressing a corner.
 * Companion class: `.m-tilt`. `max` is the peak rotation in degrees.
 */
export function useMouseTilt<T extends HTMLElement = HTMLElement>(opts: { max?: number } = {}) {
  const { max = 8 } = opts;
  const ref = useRef<T | null>(null);
  const reduced = usePrefersReducedMotion();

  useEffect(() => {
    const el = ref.current;
    if (!el || reduced) return;

    let rafId = 0;
    let rx = 0, ry = 0;

    function onMove(e: MouseEvent) {
      const rect = el!.getBoundingClientRect();
      const px = (e.clientX - rect.left) / rect.width;
      const py = (e.clientY - rect.top) / rect.height;
      // Range [-1, 1], then scaled. Vertical axis tilts X (lift), horizontal tilts Y.
      ry = (px - 0.5) * 2 * max;
      rx = -(py - 0.5) * 2 * max;
      if (!rafId) rafId = requestAnimationFrame(apply);
    }
    function apply() {
      rafId = 0;
      el!.style.setProperty('--rx', `${rx.toFixed(2)}deg`);
      el!.style.setProperty('--ry', `${ry.toFixed(2)}deg`);
    }
    function leave() {
      rx = 0; ry = 0;
      el!.style.setProperty('--rx', '0deg');
      el!.style.setProperty('--ry', '0deg');
    }

    el.addEventListener('mousemove', onMove);
    el.addEventListener('mouseleave', leave);
    return () => {
      el.removeEventListener('mousemove', onMove);
      el.removeEventListener('mouseleave', leave);
      if (rafId) cancelAnimationFrame(rafId);
    };
  }, [max, reduced]);

  return ref;
}

/**
 * Cursor glow / spotlight — sets `--mx` and `--my` on the element so the
 * `.m-cursor-glow` / `.m-spotlight` decorations follow the pointer.
 */
export function useCursorGlow<T extends HTMLElement = HTMLElement>() {
  const ref = useRef<T | null>(null);
  const reduced = usePrefersReducedMotion();
  useEffect(() => {
    const el = ref.current;
    if (!el || reduced) return;
    function onMove(e: MouseEvent) {
      const rect = el!.getBoundingClientRect();
      el!.style.setProperty('--mx', `${e.clientX - rect.left}px`);
      el!.style.setProperty('--my', `${e.clientY - rect.top}px`);
    }
    el.addEventListener('mousemove', onMove);
    return () => el.removeEventListener('mousemove', onMove);
  }, [reduced]);
  return ref;
}

/**
 * Scroll reveal — adds `.is-in` to the element when it scrolls into view.
 * Companion class: `.m-reveal` (variants: `--scale`, `--left`, `--right`).
 * Threshold is the visibility fraction at which the reveal triggers.
 */
export function useScrollReveal<T extends HTMLElement = HTMLElement>(opts: { threshold?: number; once?: boolean } = {}) {
  const { threshold = 0.15, once = true } = opts;
  const ref = useRef<T | null>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (typeof IntersectionObserver === 'undefined') {
      el.classList.add('is-in');
      return;
    }
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          el.classList.add('is-in');
          if (once) obs.disconnect();
        } else if (!once) {
          el.classList.remove('is-in');
        }
      },
      { threshold }
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, [threshold, once]);

  return ref;
}

/**
 * Parallax — sets `--py` to a fraction of the page scroll delta from the
 * element's "anchor" position so children with `.m-parallax` shift at
 * different depths. Cheap & smooth — no scroll-jank because all the work is
 * inside a rAF, and the CSS does the transform.
 */
export function useParallax<T extends HTMLElement = HTMLElement>() {
  const ref = useRef<T | null>(null);
  const reduced = usePrefersReducedMotion();

  useEffect(() => {
    const el = ref.current;
    if (!el || reduced) return;
    let raf = 0;
    function tick() {
      raf = 0;
      const rect = el!.getBoundingClientRect();
      const center = rect.top + rect.height / 2;
      const offset = center - window.innerHeight / 2;
      el!.style.setProperty('--py', `${-offset.toFixed(0)}px`);
    }
    function onScroll() { if (!raf) raf = requestAnimationFrame(tick); }
    tick();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      if (raf) cancelAnimationFrame(raf);
    };
  }, [reduced]);

  return ref;
}

/**
 * Confetti — call `burst({ origin, count, colors })` to throw a fountain of
 * particles. Renders into a single shared portal layer so multiple bursts
 * coexist. Disabled when reduce-motion is on.
 *
 *   const { burst, ConfettiHost } = useConfetti();
 *   burst({ origin: { x: 200, y: 100 } });
 *   return <>...<ConfettiHost /></>;
 */
export interface BurstOptions {
  origin?: { x: number; y: number };
  count?: number;
  colors?: string[];
  spread?: number;
}

export function useConfetti() {
  const [bits, setBits] = useState<Array<{
    id: number; left: number; top: number; cx: number; cy: number; cr: number; color: string;
  }>>([]);
  const idRef = useRef(0);
  const reduced = usePrefersReducedMotion();

  const burst = useCallback((opts: BurstOptions = {}) => {
    if (reduced) return;
    const {
      origin = { x: window.innerWidth / 2, y: window.innerHeight / 3 },
      count = 36,
      colors = ['#7c5cff', '#5b8cff', '#3aa1ff', '#10b981', '#f59e0b', '#ef4444', '#ff7ac6'],
      spread = 200,
    } = opts;

    const next = Array.from({ length: count }).map(() => {
      const angle = Math.random() * Math.PI * 2;
      const dist = spread * (0.4 + Math.random() * 0.8);
      return {
        id: ++idRef.current,
        left: origin.x,
        top: origin.y,
        cx: Math.cos(angle) * dist,
        cy: Math.sin(angle) * dist + 220 + Math.random() * 220,
        cr: (Math.random() - 0.5) * 720,
        color: colors[Math.floor(Math.random() * colors.length)],
      };
    });
    setBits((prev) => [...prev, ...next]);
    setTimeout(() => {
      setBits((prev) => prev.filter((b) => !next.find((n) => n.id === b.id)));
    }, 1500);
  }, [reduced]);

  const ConfettiHost = useMemo(() => () => (
    <div className="m-confetti" aria-hidden>
      {bits.map((b) => (
        <span
          key={b.id}
          className="m-confetti__bit"
          style={{
            left: b.left,
            top: b.top,
            background: b.color,
            ['--cx' as never]: `${b.cx}px`,
            ['--cy' as never]: `${b.cy}px`,
            ['--cr' as never]: `${b.cr}deg`,
          }}
        />
      ))}
    </div>
  ), [bits]);

  return { burst, ConfettiHost };
}
