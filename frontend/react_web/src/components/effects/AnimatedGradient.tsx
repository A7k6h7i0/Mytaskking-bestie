import clsx from 'clsx';

interface Props {
  className?: string;
  /** Render 4 blobs (default) or fewer for a calmer look. */
  blobs?: 2 | 3 | 4;
}

/**
 * Mesh-gradient backdrop — four blurred gradient blobs drifting against each
 * other. Pure CSS (motion-advanced.css `.m-mesh`), so it costs nothing on the
 * main thread and pauses for reduce-motion users automatically.
 */
export function AnimatedGradient({ className, blobs = 4 }: Props) {
  return (
    <div className={clsx('m-mesh', className)} aria-hidden>
      {Array.from({ length: blobs }).map((_, i) => (
        <span key={i} className="m-mesh__blob" />
      ))}
    </div>
  );
}
