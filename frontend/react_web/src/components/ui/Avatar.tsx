import clsx from 'clsx';
import './avatar.css';

interface AvatarProps {
  name: string;
  src?: string | null;
  size?: number;
  isClient?: boolean;
  className?: string;
}

function initials(name: string) {
  return name
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((s) => s[0]?.toUpperCase())
    .join('');
}

function hueFor(name: string) {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 360;
  return h;
}

export function Avatar({ name, src, size = 32, isClient, className }: AvatarProps) {
  const style: React.CSSProperties = {
    width: size,
    height: size,
    fontSize: size * 0.4,
    backgroundColor: src ? undefined : `hsl(${hueFor(name)}, 60%, 88%)`,
    color: src ? undefined : `hsl(${hueFor(name)}, 45%, 30%)`,
  };
  return (
    <span
      className={clsx('ba', isClient && 'ba--client', className)}
      style={style}
      data-is-client={isClient ? 'true' : undefined}
    >
      {src ? <img src={src} alt={name} /> : <span>{initials(name) || '?'}</span>}
    </span>
  );
}
