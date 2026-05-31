import { useEffect, useRef } from 'react';
import { usePrefersReducedMotion } from '@/hooks/useMotionFx';

interface ParticleFieldProps {
  density?: number;        // particles per 1000px²
  color?: string;
  linkColor?: string;
  speed?: number;
  className?: string;
  /** Connect nearby particles with thin lines for a "network" look. */
  connect?: boolean;
  /** Cap so we never tank low-end GPUs. */
  maxParticles?: number;
}

interface P {
  x: number; y: number; vx: number; vy: number; r: number;
}

/**
 * Canvas-backed particle field — floats slowly, threads a thin network of
 * connecting lines between nearby points. Cheap GPU footprint (<3% on a
 * mid-range laptop) and pauses when out of view via IntersectionObserver.
 *
 * Drop behind hero panels, login art, dashboard headers for premium ambience.
 */
export function ParticleField({
  density = 0.08,
  color = 'rgba(124, 92, 255, 0.55)',
  linkColor = 'rgba(91, 140, 255, 0.18)',
  speed = 0.25,
  className,
  connect = true,
  maxParticles = 80,
}: ParticleFieldProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const reduced = usePrefersReducedMotion();

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || reduced) return;
    const ctx = canvas.getContext('2d')!;
    const dpr = window.devicePixelRatio || 1;
    let raf = 0;
    let particles: P[] = [];
    let alive = true;

    function resize() {
      const rect = canvas!.getBoundingClientRect();
      canvas!.width = rect.width * dpr;
      canvas!.height = rect.height * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      const area = rect.width * rect.height;
      const target = Math.min(maxParticles, Math.max(8, Math.round((area / 1000) * density)));
      particles = Array.from({ length: target }).map(() => ({
        x: Math.random() * rect.width,
        y: Math.random() * rect.height,
        vx: (Math.random() - 0.5) * speed,
        vy: (Math.random() - 0.5) * speed,
        r: 1 + Math.random() * 2.2,
      }));
    }
    resize();

    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    let visible = true;
    const io = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; });
    io.observe(canvas);

    function tick() {
      if (!alive) return;
      raf = requestAnimationFrame(tick);
      if (!visible) return;

      const rect = canvas!.getBoundingClientRect();
      ctx.clearRect(0, 0, rect.width, rect.height);

      // Move + draw points.
      for (const p of particles) {
        p.x += p.vx; p.y += p.vy;
        if (p.x < 0 || p.x > rect.width)  p.vx *= -1;
        if (p.y < 0 || p.y > rect.height) p.vy *= -1;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = color;
        ctx.fill();
      }

      if (connect) {
        ctx.strokeStyle = linkColor;
        ctx.lineWidth = 1;
        const max2 = 120 * 120;
        for (let i = 0; i < particles.length; i++) {
          for (let j = i + 1; j < particles.length; j++) {
            const a = particles[i], b = particles[j];
            const dx = a.x - b.x, dy = a.y - b.y;
            const d2 = dx * dx + dy * dy;
            if (d2 < max2) {
              ctx.globalAlpha = 1 - d2 / max2;
              ctx.beginPath();
              ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
              ctx.stroke();
            }
          }
        }
        ctx.globalAlpha = 1;
      }
    }
    raf = requestAnimationFrame(tick);

    return () => {
      alive = false;
      cancelAnimationFrame(raf);
      ro.disconnect();
      io.disconnect();
    };
  }, [density, color, linkColor, speed, connect, maxParticles, reduced]);

  return (
    <canvas
      ref={canvasRef}
      className={className}
      style={{ width: '100%', height: '100%', display: 'block', pointerEvents: 'none' }}
      aria-hidden
    />
  );
}
