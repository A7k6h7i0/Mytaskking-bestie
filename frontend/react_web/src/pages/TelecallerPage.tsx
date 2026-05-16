import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Phone, Plus, Search } from 'lucide-react';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import './telecaller.css';

type Lead = {
  id: string; name: string; phone: string; company?: string | null;
  status: string; nextFollowAt?: string | null; notes?: string | null;
  owner?: { name: string; avatarUrl?: string | null } | null;
};

export default function TelecallerPage() {
  const qc = useQueryClient();
  const [q, setQ] = useState('');
  const [selected, setSelected] = useState<Lead | null>(null);

  const { data } = useQuery<{ items: Lead[] }>({
    queryKey: ['telecaller.leads', q],
    queryFn: async () => (await api.get('/telecaller/leads', { params: { q } })).data,
  });

  const callMut = useMutation({
    mutationFn: async (leadId: string) => (await api.post(`/telecaller/leads/${leadId}/call`)).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['telecaller.leads'] }),
  });

  return (
    <div className="tc">
      <aside className="tc__list">
        <header className="tc__list-head">
          <h2>Leads</h2>
          <Button size="sm" variant="secondary"><Plus size={14}/> Add lead</Button>
        </header>
        <div className="tc__search">
          <Input leading={<Search size={14} />} placeholder="Search by name, phone, company" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
        <ul>
          {data?.items.map((l) => (
            <li key={l.id} className={selected?.id === l.id ? 'is-active' : ''} onClick={() => setSelected(l)}>
              <Avatar name={l.name} size={32} />
              <div className="tc__lead-text">
                <div className="tc__lead-name">{l.name}</div>
                <div className="tc__lead-meta">{l.company || l.phone}</div>
              </div>
              <span className={`tc__status tc__status--${l.status.toLowerCase()}`}>{l.status}</span>
            </li>
          ))}
          {!data?.items.length && <li className="tc__empty">No leads. Add one to get started.</li>}
        </ul>
      </aside>

      <section className="tc__panel">
        {selected ? (
          <>
            <header className="tc__panel-head">
              <div>
                <h2>{selected.name}</h2>
                <p>{selected.company} · {selected.phone}</p>
              </div>
              <Button onClick={() => callMut.mutate(selected.id)} loading={callMut.isPending}>
                <Phone size={16}/> Click to call
              </Button>
            </header>

            <div className="tc__details">
              <div className="tc__detail">
                <label>Status</label>
                <div className={`tc__status tc__status--${selected.status.toLowerCase()}`}>{selected.status}</div>
              </div>
              <div className="tc__detail">
                <label>Next follow up</label>
                <div>{selected.nextFollowAt ? new Date(selected.nextFollowAt).toLocaleString() : '—'}</div>
              </div>
              <div className="tc__detail tc__detail--full">
                <label>Notes</label>
                <div>{selected.notes || 'No notes yet.'}</div>
              </div>
            </div>
          </>
        ) : (
          <div className="tc__empty-center">Select a lead to see details.</div>
        )}
      </section>
    </div>
  );
}
