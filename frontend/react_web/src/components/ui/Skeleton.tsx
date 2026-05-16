import clsx from 'clsx';
import './skeleton.css';

interface Props {
  width?: number | string;
  height?: number | string;
  className?: string;
  circle?: boolean;
}

export function Skeleton({ width = '100%', height = 14, circle, className }: Props) {
  return (
    <span
      className={clsx('sk', circle && 'sk--circle', className)}
      style={{ width, height }}
      aria-hidden
    />
  );
}

export function SkeletonText({ lines = 3 }: { lines?: number }) {
  return (
    <div className="sk__text">
      {Array.from({ length: lines }).map((_, i) => (
        <Skeleton key={i} height={12} width={i === lines - 1 ? '60%' : '100%'} />
      ))}
    </div>
  );
}

export function SkeletonCard() {
  return (
    <div className="sk__card">
      <Skeleton height={18} width="40%" />
      <Skeleton height={30} width="70%" />
      <SkeletonText lines={2} />
    </div>
  );
}
