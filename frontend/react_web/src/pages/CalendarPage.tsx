import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import dayjs, { Dayjs } from 'dayjs';
import { ChevronLeft, ChevronRight, CalendarDays } from 'lucide-react';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import './calendar.css';

type Event = {
  id: string;
  title: string;
  startsAt: string;
  endsAt: string | null;
  kind: string;
  location?: string | null;
};

export default function CalendarPage() {
  const [cursor, setCursor] = useState(dayjs().startOf('week'));
  const from = cursor.startOf('week');
  const to = cursor.endOf('week');

  const { data, isLoading } = useQuery<{ items: Event[] }>({
    queryKey: ['calendar.range', from.toISOString(), to.toISOString()],
    queryFn: async () =>
      (await api.get('/calendar', { params: { from: from.toISOString(), to: to.toISOString(), view: 'week' } })).data,
  });

  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => from.add(i, 'day')), [from]);

  return (
    <div className="cal">
      <header className="cal__head">
        <div>
          <h1>Calendar</h1>
          <p>{from.format('MMM D')} – {to.format('MMM D, YYYY')}</p>
        </div>
        <div className="cal__nav">
          <Button variant="ghost" onClick={() => setCursor((c) => c.subtract(1, 'week'))}><ChevronLeft size={16} /></Button>
          <Button variant="secondary" onClick={() => setCursor(dayjs().startOf('week'))}>Today</Button>
          <Button variant="ghost" onClick={() => setCursor((c) => c.add(1, 'week'))}><ChevronRight size={16} /></Button>
        </div>
      </header>

      <div className="cal__grid">
        {days.map((d) => {
          const eventsToday = (data?.items || []).filter((e) => dayjs(e.startsAt).isSame(d, 'day'));
          const isToday = d.isSame(dayjs(), 'day');
          return (
            <div key={d.toString()} className={'cal__col' + (isToday ? ' is-today' : '')}>
              <header>
                <span className="cal__dow">{d.format('ddd')}</span>
                <span className="cal__dom">{d.format('D')}</span>
              </header>
              <div className="cal__col-body">
                {isLoading && <div className="cal__hint">Loading…</div>}
                {!isLoading && eventsToday.length === 0 && <div className="cal__hint">No events</div>}
                {eventsToday.map((e) => (
                  <div key={e.id} className={`cal__event cal__event--${e.kind.toLowerCase()}`}>
                    <div className="cal__event-time">{dayjs(e.startsAt).format('HH:mm')}</div>
                    <div className="cal__event-title">{e.title}</div>
                    {e.location && <div className="cal__event-loc">{e.location}</div>}
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>

      {!isLoading && (data?.items.length ?? 0) === 0 && (
        <div className="cal__empty">
          <CalendarDays size={20} /> <span>Nothing scheduled this week.</span>
        </div>
      )}
    </div>
  );
}
