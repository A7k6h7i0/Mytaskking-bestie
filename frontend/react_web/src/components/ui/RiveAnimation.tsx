import { useEffect, useRef, useState } from 'react';
import clsx from 'clsx';
import './rive-animation.css';

interface RiveAnimationProps {
  /** Path or URL to a `.riv` file. Pass null to render the fallback. */
  src: string | null;
  /** Optional state machine name inside the .riv file. */
  stateMachine?: string;
  /** Optional artboard name. */
  artboard?: string;
  width?: number | string;
  height?: number | string;
  fallback?: React.ReactNode;
  className?: string;
  /** Pause the animation when out of view (default: true) for perf. */
  pauseOffscreen?: boolean;
}

/**
 * Wrapper around `@rive-app/canvas` that loads lazily and degrades gracefully
 * to a CSS-driven fallback when the package isn't installed or the asset
 * isn't shipped.
 *
 * Drop a real `.riv` file into `frontend/react_web/public/rive/` and pass the
 * URL (`/rive/cheer.riv`). Until then, the fallback renders the brand
 * gradient blob so layouts don't look broken.
 *
 * Why lazy: `@rive-app/canvas` is ~250 KB. We only pull it in on pages that
 * actually use a Rive asset, keeping the initial bundle tight.
 */
export function RiveAnimation({
  src, stateMachine, artboard, width = 160, height = 160, fallback, className, pauseOffscreen = true,
}: RiveAnimationProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState<'idle' | 'loading' | 'ready' | 'fallback'>('idle');

  useEffect(() => {
    if (!src) { setStatus('fallback'); return; }
    let cancelled = false;
    let riveInstance: any = null;

    setStatus('loading');
    (async () => {
      try {
        // Lazy import — fall back if the package isn't installed.
        const mod = await import(/* @vite-ignore */ '@rive-app/canvas').catch(() => null);
        if (!mod || cancelled || !canvasRef.current) { setStatus('fallback'); return; }

        riveInstance = new mod.Rive({
          src,
          canvas: canvasRef.current,
          autoplay: true,
          stateMachines: stateMachine ? [stateMachine] : undefined,
          artboard,
          onLoadError: () => setStatus('fallback'),
          onLoad: () => {
            riveInstance.resizeDrawingSurfaceToCanvas();
            setStatus('ready');
          },
        });
      } catch {
        setStatus('fallback');
      }
    })();

    return () => {
      cancelled = true;
      try { riveInstance?.cleanup?.(); } catch { /* noop */ }
    };
  }, [src, stateMachine, artboard]);

  // Pause when out of view to save battery / CPU.
  useEffect(() => {
    if (!pauseOffscreen || !wrapRef.current) return;
    const node = wrapRef.current;
    let isPlaying = true;
    const obs = new IntersectionObserver(([entry]) => {
      const visible = entry.isIntersecting;
      if (visible !== isPlaying) {
        isPlaying = visible;
        node.dataset.playing = visible ? 'true' : 'false';
      }
    });
    obs.observe(node);
    return () => obs.disconnect();
  }, [pauseOffscreen]);

  return (
    <div ref={wrapRef} className={clsx('riv', className)} style={{ width, height }} data-status={status} data-playing="true">
      {status !== 'fallback' && <canvas ref={canvasRef} className="riv__canvas" />}
      {status === 'fallback' && (fallback || <RiveFallback />)}
    </div>
  );
}

/** Default fallback — animated gradient blob in brand colors. */
function RiveFallback() {
  return (
    <div className="riv__fallback m-float" aria-hidden>
      <div className="riv__blob riv__blob--1" />
      <div className="riv__blob riv__blob--2" />
      <div className="riv__blob riv__blob--3" />
    </div>
  );
}
