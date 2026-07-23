import { useQuery } from '@tanstack/react-query';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import './people.css';

export default function FieldVisitsPage() {
  const { data, isLoading } = useQuery<{ items: any[] }>({
    queryKey: ['field-visits'],
    queryFn: async () => (await api.get('/marketing/visits')).data,
  });

  const items = data?.items ?? [];

  return (
    <div className="pp">
      <header className="pp__head">
        <div>
          <h1>Field visits</h1>
          <p>Team check-ins with selfie and GPS for your organisation.</p>
        </div>
      </header>
      {isLoading ? (
        <p>Loading visits…</p>
      ) : !items.length ? (
        <p>No field visits logged yet.</p>
      ) : (
        <div className="pp__grid">
          {items.map((v) => {
            const selfie = v.selfieUrl && v.selfieUrl !== 'auto-detected' ? v.selfieUrl : null;
            return (
              <article key={v.id} className="pp__card">
                <div className="pp__card-top">
                  <Avatar name={v.user?.name ?? 'Executive'} src={v.user?.avatarUrl} size={36} />
                  <div>
                    <strong>{v.outlet?.name ?? 'Outlet'}</strong>
                    <span className="pp__chip">{v.status}</span>
                  </div>
                </div>
                <p className="pp__meta">{v.user?.name ?? 'Executive'}</p>
                {selfie && (
                  <a href={selfie} target="_blank" rel="noreferrer">
                    <img src={selfie} alt="Visit selfie" style={{ maxWidth: '100%', borderRadius: 8, marginTop: 8 }} />
                  </a>
                )}
              </article>
            );
          })}
        </div>
      )}
    </div>
  );
}
