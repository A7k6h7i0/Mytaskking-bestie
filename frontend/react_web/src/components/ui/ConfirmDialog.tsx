import { ReactNode, useState } from 'react';
import { AlertTriangle, Trash2 } from 'lucide-react';
import { Modal } from './Modal';
import { Button } from './Button';
import './confirm-dialog.css';

interface ConfirmDialogProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void | Promise<void>;
  title: ReactNode;
  description?: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: 'danger' | 'warning' | 'info';
  /** Type-to-confirm. When set, user must type this string to enable Confirm. */
  confirmText?: string;
}

const ICON = {
  danger: Trash2,
  warning: AlertTriangle,
  info: AlertTriangle,
};

/**
 * Friction layer for destructive actions. Supports type-to-confirm for the
 * really scary stuff ("delete client", "force-logout user").
 */
export function ConfirmDialog({
  open, onClose, onConfirm, title, description,
  confirmLabel = 'Confirm', cancelLabel = 'Cancel',
  variant = 'danger', confirmText,
}: ConfirmDialogProps) {
  const Icon = ICON[variant];
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);

  const canConfirm = confirmText ? typed === confirmText : true;

  async function handleConfirm() {
    setBusy(true);
    try { await onConfirm(); onClose(); setTyped(''); }
    finally { setBusy(false); }
  }

  return (
    <Modal
      open={open}
      onClose={() => { setTyped(''); onClose(); }}
      size="sm"
      title={
        <div className={`cd__title cd__title--${variant}`}>
          <span className="cd__icon m-pop"><Icon size={18} /></span>
          {title}
        </div>
      }
      description={description}
      footer={
        <>
          <Button variant="ghost" onClick={() => { setTyped(''); onClose(); }} disabled={busy}>{cancelLabel}</Button>
          <Button
            variant={variant === 'danger' ? 'danger' : 'primary'}
            disabled={!canConfirm}
            loading={busy}
            onClick={handleConfirm}
          >
            {confirmLabel}
          </Button>
        </>
      }
    >
      {confirmText && (
        <div className="cd__type-to-confirm">
          <label>
            Type <code>{confirmText}</code> to confirm
            <input
              autoFocus
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              placeholder={confirmText}
              className={typed === confirmText ? 'is-match' : ''}
            />
          </label>
        </div>
      )}
    </Modal>
  );
}

/** Hook helper — `const confirm = useConfirm(); await confirm({ title, ... })`. */
export function useConfirm() {
  const [state, setState] = useState<(ConfirmDialogProps & { resolve: (ok: boolean) => void }) | null>(null);

  const confirm = (opts: Omit<ConfirmDialogProps, 'open' | 'onClose' | 'onConfirm'>) =>
    new Promise<boolean>((resolve) => {
      setState({
        ...opts,
        open: true,
        onClose: () => { setState(null); resolve(false); },
        onConfirm: () => { resolve(true); },
        resolve,
      });
    });

  const node = state ? <ConfirmDialog {...state} /> : null;
  return { confirm, ConfirmRenderer: () => node };
}
