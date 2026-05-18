import { useQuery } from '@tanstack/react-query';
import { Trophy, Flame, Sparkles } from 'lucide-react';
import clsx from 'clsx';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Badge } from '@/components/ui/Badge';
import { ProgressRing } from '@/components/ui/Progress';
import { Skeleton } from '@/components/ui/Skeleton';
import { SegmentedControl } from '@/components/ui/SegmentedControl';
import { useState } from 'react';
import './leaderboard.css';

type Row = {
  user: { id: string; name: string; userId: string; avatarUrl?: string | null; isClient: boolean; role: string };
  avgScore: number;
  completed: number;
  onTimeRate: number;
  streak: number;
  lastCompletedAt: string;
};

/**
 * Performance leaderboard — per-employee average task score over a rolling
 * window. Top 3 get medals, the rest get rank chips. The score ring shows
 * average; on-time rate + streak hang on the right.
 *
 * `since` is days (7 / 30 / 90). Defaults to 30. The endpoint is also used
 * by the Flutter Dashboard's mini-leaderboard.
 */
export function Leaderboard() {
  const [since, setSince] = useState<7 | 30 | 90>(30);

  const { data, isLoading } = useQuery<{ items: Row[]; sinceDays: number }>({
    queryKey: ['tasks.leaderboard', since],
    queryFn: async () => (await api.get('/tasks/leaderboard', { params: { sinceDays: since, limit: 20 } })).data,
  });

  return (
    <section className="lb">
      <header className="lb__head">
        <div>
          <h3><Trophy size={16} /> Performance leaderboard</h3>
          <p>Average on-time score across completed tasks. Higher is better.</p>
        </div>
        <SegmentedControl
          value={String(since)}
          onChange={(v) => setSince(Number(v) as 7 | 30 | 90)}
          options={[
            { value: '7',  label: '7d' },
            { value: '30', label: '30d' },
            { value: '90', label: '90d' },
          ]}
        />
      </header>

      <div className="lb__list">
        {isLoading && Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} height={72} />)}

        {!isLoading && data?.items.map((row, i) => (
          <article key={row.user.id} className={clsx('lb__row', `lb__row--rank-${i + 1}`)}>
            <div className="lb__rank">
              {i < 3 ? <Medal place={i + 1} /> : <span className="lb__rank-num">#{i + 1}</span>}
            </div>
            <Avatar name={row.user.name} src={row.user.avatarUrl} isClient={row.user.isClient} size={40} />
            <div className="lb__person">
              <UserName name={row.user.name} isClient={row.user.isClient} role={row.user.role}
                className="lb__name" />
              <div className="lb__meta">
                <span>{row.completed} tasks</span>
                <span>· {row.onTimeRate}% on time</span>
                {row.streak > 0 && (
                  <span className="lb__streak">
                    <Flame size={11} /> {row.streak} streak
                  </span>
                )}
              </div>
            </div>
            <Badge tone={tone(row.avgScore)} variant="soft">
              {labelFor(row.avgScore)}
            </Badge>
            <ProgressRing
              value={row.avgScore}
              size={56}
              thickness={5}
              tone={tone(row.avgScore)}
              label={<><span className="lb__score">{row.avgScore}</span><span className="lb__suffix">/100</span></>}
            />
          </article>
        ))}

        {!isLoading && (data?.items.length ?? 0) === 0 && (
          <div className="lb__empty">
            <Sparkles size={20} /> No completed tasks in this window yet.
          </div>
        )}
      </div>
    </section>
  );
}

function Medal({ place }: { place: 1 | 2 | 3 }) {
  const colors = ['#FACC15', '#CBD5E1', '#D97706']; // gold / silver / bronze
  return (
    <span className="lb__medal" style={{ background: colors[place - 1] }} aria-label={`#${place}`}>
      {place}
    </span>
  );
}

function tone(score: number): 'success' | 'warning' | 'danger' | 'brand' {
  if (score >= 85) return 'success';
  if (score >= 65) return 'brand';
  if (score >= 45) return 'warning';
  return 'danger';
}
function labelFor(score: number) {
  if (score >= 95) return 'Stellar';
  if (score >= 85) return 'Great';
  if (score >= 70) return 'Solid';
  if (score >= 50) return 'Mixed';
  return 'Needs help';
}
