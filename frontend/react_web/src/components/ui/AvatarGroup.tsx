import { Avatar } from './Avatar';
import './avatar-group.css';

interface AvatarGroupProps {
  users: Array<{ id: string; name: string; avatarUrl?: string | null; isClient?: boolean }>;
  max?: number;
  size?: number;
}

/** Stacked-overflowing avatar row with "+N" remainder. */
export function AvatarGroup({ users, max = 4, size = 28 }: AvatarGroupProps) {
  const shown = users.slice(0, max);
  const remainder = Math.max(0, users.length - shown.length);
  return (
    <span className="ag">
      {shown.map((u, i) => (
        <span key={u.id} className="ag__slot" style={{ zIndex: shown.length - i }}>
          <Avatar name={u.name} src={u.avatarUrl} isClient={u.isClient} size={size} />
        </span>
      ))}
      {remainder > 0 && (
        <span className="ag__more" style={{ width: size, height: size, fontSize: size * 0.35 }}>
          +{remainder}
        </span>
      )}
    </span>
  );
}
