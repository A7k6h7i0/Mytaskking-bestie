import { HTMLAttributes, ReactNode } from 'react';
import clsx from 'clsx';
import { useMouseTilt, useCursorGlow } from '@/hooks/useMotionFx';

interface TiltCardProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode;
  /** Peak rotation in degrees. */
  max?: number;
  /** Add a cursor-following glow on top of the tilt. */
  glow?: boolean;
}

/**
 * 3D-tilting card that rotates as the cursor sweeps across it. Pair with
 * children carrying `m-tilt-layer-1/2/3` to push them forward and get a real
 * parallax-on-tilt effect.
 *
 *   <TiltCard glow>
 *     <div className="m-tilt-layer-2"><h3>{title}</h3></div>
 *   </TiltCard>
 */
export function TiltCard({ children, className, max = 8, glow, ...rest }: TiltCardProps) {
  const tiltRef = useMouseTilt<HTMLDivElement>({ max });
  const glowRef = useCursorGlow<HTMLDivElement>();

  // Compose two refs — one for tilt math, one for cursor glow.
  function setRefs(el: HTMLDivElement | null) {
    (tiltRef as { current: HTMLDivElement | null }).current = el;
    (glowRef as { current: HTMLDivElement | null }).current = el;
  }

  return (
    <div
      ref={setRefs}
      className={clsx('m-tilt', glow && 'm-cursor-glow', className)}
      {...rest}
    >
      {children}
    </div>
  );
}
