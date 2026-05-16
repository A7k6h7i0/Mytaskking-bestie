import { useEffect, useRef, useState } from 'react';
import { Check, ChevronDown } from 'lucide-react';
import clsx from 'clsx';
import { api } from '@/services/api';
import { getSocket } from '@/services/socket';
import { PresenceDot, PresenceStatus } from './PresenceDot';
import { toast } from './Toast';
import './presence-menu.css';

const OPTIONS: { value: Exclude<PresenceStatus, 'OFFLINE'>; label: string; description: string }[] = [
  { value: 'ACTIVE', label: 'Active', description: 'Available for messages and calls' },
  { value: 'BUSY', label: 'Busy', description: 'Visible online, mutes pushes' },
  { value: 'IN_MEETING', label: 'In a meeting', description: 'Auto-clears after the call ends' },
  { value: 'AWAY', label: 'Away', description: 'You\'re online but distracted' },
  { value: 'INVISIBLE', label: 'Invisible', description: 'You appear offline' },
];

export function PresenceMenu({ initial = 'ACTIVE' }: { initial?: PresenceStatus }) {
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState<PresenceStatus>(initial);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    }
    if (open) document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, [open]);

  async function pick(next: typeof OPTIONS[number]['value']) {
    setStatus(next);
    setOpen(false);
    try {
      await api.put('/presence/me', { status: next });
      getSocket()?.emit('presence.set', { status: next });
    } catch {
      toast.error('Could not update status');
    }
  }

  return (
    <div className="pm" ref={ref}>
      <button className="pm__trigger" onClick={() => setOpen((v) => !v)}>
        <PresenceDot status={status} />
        <span className="pm__label">{labelFor(status)}</span>
        <ChevronDown size={12} />
      </button>

      {open && (
        <div className="pm__menu fade-in">
          {OPTIONS.map((opt) => (
            <button key={opt.value} className={clsx('pm__opt', status === opt.value && 'is-active')} onClick={() => pick(opt.value)}>
              <PresenceDot status={opt.value} />
              <div className="pm__opt-body">
                <span className="pm__opt-label">{opt.label}</span>
                <span className="pm__opt-desc">{opt.description}</span>
              </div>
              {status === opt.value && <Check size={14} />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function labelFor(s: PresenceStatus) {
  return OPTIONS.find((o) => o.value === s)?.label || 'Active';
}
