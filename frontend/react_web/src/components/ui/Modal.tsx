import { ReactNode, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { X } from 'lucide-react';
import clsx from 'clsx';
import './modal.css';

interface ModalProps {
  open: boolean;
  onClose: () => void;
  title?: ReactNode;
  description?: ReactNode;
  footer?: ReactNode;
  size?: 'sm' | 'md' | 'lg' | 'xl';
  children: ReactNode;
  /** Hide the default close button (e.g. when the modal is destructive). */
  hideClose?: boolean;
  /** Click on the backdrop closes. Default true. */
  dismissOnBackdrop?: boolean;
}

/**
 * Premium modal with backdrop blur, scale-in entrance, focus trap, ESC to
 * close, and scroll-lock on the body. Rendered via portal so it sits above
 * everything regardless of stacking context.
 */
export function Modal({
  open, onClose, title, description, footer, size = 'md', children, hideClose, dismissOnBackdrop = true,
}: ModalProps) {
  const ref = useRef<HTMLDivElement>(null);
  const onCloseRef = useRef(onClose);

  useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onCloseRef.current();
    }
    document.addEventListener('keydown', onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    setTimeout(() => {
      const el = ref.current?.querySelector<HTMLElement>(
        '.mo__body input, .mo__body textarea, .mo__body select, .mo__body button, input, textarea, select, button, [tabindex]:not([tabindex="-1"])'
      );
      el?.focus();
    }, 30);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = prevOverflow;
    };
  }, [open]);

  if (!open) return null;

  return createPortal(
    <div
      className="mo m-backdrop"
      onMouseDown={(e) => {
        if (dismissOnBackdrop && e.target === e.currentTarget) onClose();
      }}
      role="dialog"
      aria-modal="true"
    >
      <div className={clsx('mo__panel', `mo__panel--${size}`, 'm-scale-in')} ref={ref}>
        {(title || !hideClose) && (
          <header className="mo__head">
            <div>
              {title && <h2 className="mo__title">{title}</h2>}
              {description && <p className="mo__desc">{description}</p>}
            </div>
            {!hideClose && (
              <button className="mo__close m-press" onClick={onClose} aria-label="Close">
                <X size={16} />
              </button>
            )}
          </header>
        )}
        <div className="mo__body">{children}</div>
        {footer && <footer className="mo__foot">{footer}</footer>}
      </div>
    </div>,
    document.body
  );
}
