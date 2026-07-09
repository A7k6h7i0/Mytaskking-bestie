import { useEffect, useState } from 'react';
import { Eye } from 'lucide-react';
import { api } from '@/services/api';

type Props = {
  sessionId: string;
  userName: string;
};

/** Loads login selfie through the authenticated API proxy (R2/Cloudinary URLs often block hotlinking). */
export function SessionSelfieThumb({ sessionId, userName }: Props) {
  const [src, setSrc] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let objectUrl: string | null = null;
    let cancelled = false;

    api
      .get(`/sessions/${sessionId}/selfie`, { responseType: 'blob' })
      .then((res) => {
        if (cancelled) return;
        objectUrl = URL.createObjectURL(res.data);
        setSrc(objectUrl);
        setFailed(false);
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [sessionId]);

  if (failed) {
    return <span className="la__none">Not captured</span>;
  }

  if (!src) {
    return <span className="la__none">Loading…</span>;
  }

  return (
    <a href={src} target="_blank" rel="noreferrer" download={`${userName}-login-selfie.jpg`}>
      <img src={src} alt={`${userName} login selfie`} />
      <Eye size={14} /> View
    </a>
  );
}
