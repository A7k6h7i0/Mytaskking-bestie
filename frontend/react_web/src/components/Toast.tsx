import { create } from 'zustand';
import { useEffect, useRef, useState } from 'react';
import { CheckCircle2, AlertTriangle, XCircle, Info, X } from 'lucide-react';
import clsx from 'clsx';
import './toast.css';

type ToastKind = 'success' | 'error' | 'info' | 'warning';
type Toast = { id: string; kind: ToastKind; title: string; body?: string; ttl: number };

interface ToastStore {
  toasts: Toast[];
  push: (t: Omit<Toast, 'id' | 'ttl'> & { ttl?: number }) => string;
  dismiss: (id: string) => void;
}

export const useToast = create<ToastStore>((set, get) => ({
  toasts: [],
  push: (t) => {
    const id = Math.random().toString(36).slice(2);
    set({ toasts: [...get().toasts, { id, ttl: 4000, ...t }] });
    return id;
  },
  dismiss: (id) => set({ toasts: get().toasts.filter((t) => t.id !== id) }),
}));

// Convenience helpers used across pages.
export const toast = {
  success: (title: string, body?: string) => useToast.getState().push({ kind: 'success', title, body }),
  error:   (title: string, body?: string) => useToast.getState().push({ kind: 'error', title, body, ttl: 6000 }),
  info:    (title: string, body?: string) => useToast.getState().push({ kind: 'info', title, body }),
  warn:    (title: string, body?: string) => useToast.getState().push({ kind: 'warning', title, body }),
};

const ICONS = { success: CheckCircle2, error: XCircle, info: Info, warning: AlertTriangle };

export function ToastHost() {
  const toasts = useToast((s) => s.toasts);
  const dismiss = useToast((s) => s.dismiss);

  return (
    <div className="ts" role="region" aria-live="polite" aria-label="Notifications">
      {toasts.map((t) => (
        <ToastItem key={t.id} toast={t} onDismiss={() => dismiss(t.id)} />
      ))}
    </div>
  );
}

function ToastItem({ toast: t, onDismiss }: { toast: Toast; onDismiss: () => void }) {
  const Icon = ICONS[t.kind];
  const [paused, setPaused] = useState(false);
  const remainingRef = useRef(t.ttl);
  const startRef = useRef(Date.now());
  const timerRef = useRef<number | undefined>(undefined);

  useEffect(() => {
    if (paused) {
      if (timerRef.current) window.clearTimeout(timerRef.current);
      remainingRef.current -= Date.now() - startRef.current;
      return;
    }
    startRef.current = Date.now();
    timerRef.current = window.setTimeout(onDismiss, remainingRef.current);
    return () => {
      if (timerRef.current) window.clearTimeout(timerRef.current);
    };
  }, [paused, onDismiss]);

  return (
    <div
      className={clsx('ts__item', `ts__item--${t.kind}`)}
      role="status"
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onFocus={() => setPaused(true)}
      onBlur={() => setPaused(false)}
    >
      <span className="ts__icon"><Icon size={16} /></span>
      <div className="ts__body">
        <div className="ts__title">{t.title}</div>
        {t.body && <div className="ts__text">{t.body}</div>}
      </div>
      <button className="ts__close" onClick={onDismiss} aria-label="Dismiss notification"><X size={14} /></button>
    </div>
  );
}
