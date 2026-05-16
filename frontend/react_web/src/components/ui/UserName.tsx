import clsx from 'clsx';

interface Props {
  name: string;
  isClient?: boolean;
  role?: string;
  className?: string;
}

export function UserName({ name, isClient, role, className }: Props) {
  const client = isClient || role === 'CLIENT';
  return (
    <span className={clsx(client && 'client-name', className)} data-is-client={client ? 'true' : undefined}>
      {name}
      {client && <span className="client-chip" style={{ marginLeft: 6 }}>CLIENT</span>}
    </span>
  );
}
