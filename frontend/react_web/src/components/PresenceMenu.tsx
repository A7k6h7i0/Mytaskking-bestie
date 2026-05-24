import { useEffect, useRef, useState } from 'react';
import { Check, ChevronDown, Loader2 } from 'lucide-react';
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
  const [pending, setPending] = useState<PresenceStatus | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false);
    }
    if (open) {
      document.addEventListener('mousedown', onClick);
      document.addEventListener('keydown', onKey);
    }
    return () => {
      document.removeEventListener('mousedown', onClick);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  async function pick(next: typeof OPTIONS[number]['value']) {
    if (pending) return;
    const previous = status;
    setPending(next);
    setStatus(next);
    try {
      await api.put('/presence/me', { status: next });
      getSocket()?.emit('presence.set', { status: next });
      setOpen(false);
    } catch {
      setStatus(previous);
      toast.error('Could not update status', 'Please try again in a moment.');
    } finally {
      setPending(null);
    }
  }

  return (
    <div className="pm" ref={ref}>
      <button
        className={clsx('pm__trigger', open && 'is-open')}
        onClick={() => setOpen((v) => !v)}
        disabled={!!pending}
        aria-haspopup="menu"
        aria-expanded={open}
      >
        <PresenceDot status={status} />
        <span className="pm__label">{labelFor(status)}</span>
        {pending ? <Loader2 size={12} className="m-spin" /> : <ChevronDown size={12} />}
      </button>

      {open && (
        <div className="pm__menu" role="menu">
          {OPTIONS.map((opt) => {
            const isLoading = pending === opt.value;
            return (
              <button
                key={opt.value}
                role="menuitemradio"
                aria-checked={status === opt.value}
                className={clsx('pm__opt', status === opt.value && 'is-active')}
                onClick={() => pick(opt.value)}
                disabled={!!pending}
              >
                <PresenceDot status={opt.value} />
                <div className="pm__opt-body">
                  <span className="pm__opt-label">{opt.label}</span>
                  <span className="pm__opt-desc">{opt.description}</span>
                </div>
                {isLoading ? <Loader2 size={14} className="m-spin" /> : status === opt.value && <Check size={14} />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

function labelFor(s: PresenceStatus) {
  return OPTIONS.find((o) => o.value === s)?.label || 'Active';
}
