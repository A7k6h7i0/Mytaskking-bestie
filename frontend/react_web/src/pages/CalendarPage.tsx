import { useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { ChevronLeft, ChevronRight, CalendarDays, Coffee, LogIn, LogOut, Mic, Square, Volume2 } from 'lucide-react';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { toast } from '@/components/Toast';
import './calendar.css';

type Event = {
  id: string;
  title: string;
  startsAt: string;
  endsAt: string | null;
  kind: string;
  location?: string | null;
};

type WorkdayEntry = {
  id: string;
  localDate: string;
  timezone: string;
  status: 'PENDING' | 'CHECKED_IN' | 'AT_LUNCH' | 'CHECKED_OUT';
  lunchState: 'NOT_STARTED' | 'ON_BREAK' | 'COMPLETED';
  checkInAt: string | null;
  checkInPlan: string | null;
  checkInWordCount: number | null;
  lunchStartedAt: string | null;
  lunchEndedAt: string | null;
  lunchNote: string | null;
  checkOutAt: string | null;
  checkOutReport: string | null;
  checkOutWordCount: number | null;
};

type AttendanceToday = {
  timezone: string;
  today: string;
  opensAt: { hour: number; minute: number };
  lunchWindow: { startHour: number; endHour: number };
  checkOutAt: { hour: number; minute: number };
  currentLocalTime: string;
  minRequiredWords: number;
  entry: WorkdayEntry | null;
};

type AttendanceRange = {
  timezone: string;
  from: string;
  to: string;
  minRequiredWords: number;
  items: WorkdayEntry[];
};

const MIN_REQUIRED_WORDS = 10;

function countWords(text: string) {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

function formatTime(value?: string | null) {
  return value ? dayjs(value).format('HH:mm') : null;
}

export default function CalendarPage() {
  const qc = useQueryClient();
  const recognitionRef = useRef<any>(null);
  const [cursor, setCursor] = useState(dayjs().startOf('week'));
  const [checkInPlan, setCheckInPlan] = useState('');
  const [lunchNote, setLunchNote] = useState('');
  const [checkOutReport, setCheckOutReport] = useState('');
  const [activeDictation, setActiveDictation] = useState<'checkin' | 'lunch' | 'checkout' | null>(null);
  const timezone = useMemo(() => Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Kolkata', []);
  const from = cursor.startOf('week');
  const to = cursor.endOf('week');

  const { data, isLoading } = useQuery<{ items: Event[] }>({
    queryKey: ['calendar.range', from.toISOString(), to.toISOString()],
    queryFn: async () =>
      (await api.get('/calendar', { params: { from: from.toISOString(), to: to.toISOString(), view: 'week' } })).data,
  });

  const attendanceToday = useQuery<AttendanceToday>({
    queryKey: ['attendance.today', timezone],
    queryFn: async () => (await api.get('/attendance/today', { params: { timezone } })).data,
    refetchInterval: 60_000,
  });

  const attendanceWeek = useQuery<AttendanceRange>({
    queryKey: ['attendance.range', from.toISOString(), to.toISOString(), timezone],
    queryFn: async () => (await api.get('/attendance/range', { params: { from: from.toISOString(), to: to.toISOString(), timezone } })).data,
  });

  const checkInMut = useMutation({
    mutationFn: async () => (await api.post('/attendance/check-in', { plan: checkInPlan, timezone })).data,
    onSuccess: () => {
      toast.success('Check-in approved', 'Your morning plan has been saved.');
      setCheckInPlan('');
      qc.invalidateQueries({ queryKey: ['attendance.today'] });
      qc.invalidateQueries({ queryKey: ['attendance.range'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not check in'),
  });

  const lunchMut = useMutation({
    mutationFn: async () => (await api.post('/attendance/lunch', { note: lunchNote, timezone })).data,
    onSuccess: (result) => {
      const onBreak = result?.entry?.lunchState === 'ON_BREAK';
      toast.success(onBreak ? 'Lunch break started' : 'Lunch break ended');
      if (!onBreak) setLunchNote('');
      qc.invalidateQueries({ queryKey: ['attendance.today'] });
      qc.invalidateQueries({ queryKey: ['attendance.range'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not update lunch status'),
  });

  const checkOutMut = useMutation({
    mutationFn: async () => (await api.post('/attendance/check-out', { report: checkOutReport, timezone })).data,
    onSuccess: () => {
      toast.success('Logout report saved', 'You are checked out for today.');
      setCheckOutReport('');
      qc.invalidateQueries({ queryKey: ['attendance.today'] });
      qc.invalidateQueries({ queryKey: ['attendance.range'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not check out'),
  });

  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => from.add(i, 'day')), [from]);
  const attendanceByDay = useMemo(() => {
    const map = new Map<string, WorkdayEntry>();
    (attendanceWeek.data?.items || []).forEach((item) => map.set(item.localDate, item));
    return map;
  }, [attendanceWeek.data?.items]);
  const todayEntry = attendanceToday.data?.entry;
  const currentTimeText = attendanceToday.data?.currentLocalTime || '--:--';
  const minRequiredWords = attendanceToday.data?.minRequiredWords || MIN_REQUIRED_WORDS;
  const checkInWords = countWords(checkInPlan);
  const checkOutWords = countWords(checkOutReport);
  const recognitionApi = typeof window !== 'undefined' ? ((window as any).SpeechRecognition || (window as any).webkitSpeechRecognition) : null;
  const canSpeak = typeof window !== 'undefined' && 'speechSynthesis' in window;

  useEffect(() => {
    return () => {
      if (recognitionRef.current) {
        recognitionRef.current.onend = null;
        recognitionRef.current.stop?.();
      }
      if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  function startDictation(target: 'checkin' | 'lunch' | 'checkout') {
    if (!recognitionApi) {
      toast.warn('Speech-to-text is not supported in this browser');
      return;
    }
    if (recognitionRef.current) {
      recognitionRef.current.stop?.();
      recognitionRef.current = null;
    }
    const recognition = new recognitionApi();
    recognition.lang = 'en-IN';
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;
    recognition.onresult = (event: any) => {
      const transcript = String(event.results?.[0]?.[0]?.transcript || '').trim();
      if (!transcript) return;
      if (target === 'checkin') setCheckInPlan((prev) => `${prev} ${transcript}`.trim());
      if (target === 'lunch') setLunchNote((prev) => `${prev} ${transcript}`.trim());
      if (target === 'checkout') setCheckOutReport((prev) => `${prev} ${transcript}`.trim());
    };
    recognition.onerror = () => toast.error('Dictation failed', 'Please allow microphone access and try again.');
    recognition.onend = () => {
      setActiveDictation((current) => (current === target ? null : current));
      recognitionRef.current = null;
    };
    recognitionRef.current = recognition;
    setActiveDictation(target);
    recognition.start();
  }

  function stopDictation() {
    recognitionRef.current?.stop?.();
    recognitionRef.current = null;
    setActiveDictation(null);
  }

  function speakText(text: string) {
    const value = text.trim();
    if (!value) {
      toast.warn('Add some text first so we have something to read aloud.');
      return;
    }
    if (!canSpeak) {
      toast.warn('Text-to-speech is not supported in this browser');
      return;
    }
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(value);
    utterance.lang = 'en-IN';
    window.speechSynthesis.speak(utterance);
  }

  function renderSpeechTools(target: 'checkin' | 'lunch' | 'checkout', text: string) {
    const listening = activeDictation === target;
    return (
      <div className="cal__speech-tools">
        <Button size="sm" variant={listening ? 'danger' : 'ghost'} onClick={() => (listening ? stopDictation() : startDictation(target))}>
          {listening ? <Square size={14} /> : <Mic size={14} />} {listening ? 'Stop dictation' : 'Speak to text'}
        </Button>
        <Button size="sm" variant="ghost" onClick={() => speakText(text)}>
          <Volume2 size={14} /> Listen
        </Button>
      </div>
    );
  }

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

      <section className="cal__attendance-card">
        <div className="cal__attendance-head">
          <div>
            <h2>Daily work log</h2>
            <p>Local time {currentTimeText} · Check-in unlocks at 09:00 · Check-in and logout both require at least {MIN_REQUIRED_WORDS} words.</p>
          </div>
          <div className={`cal__attendance-status cal__attendance-status--${(todayEntry?.status || 'PENDING').toLowerCase()}`}>
            {todayEntry?.status || 'PENDING'}
          </div>
        </div>

        <div className="cal__attendance-grid">
          <article className="cal__attendance-block">
            <div className="cal__attendance-block-head"><LogIn size={16} /> Morning check-in</div>
            <textarea
              className="cal__textarea"
              rows={5}
              placeholder={`Write at least ${minRequiredWords} words about what you are going to do today.`}
              value={checkInPlan}
              onChange={(e) => setCheckInPlan(e.target.value)}
              disabled={!!todayEntry?.checkInAt}
            />
            <div className="cal__word-row">
              <span>{checkInWords} / {minRequiredWords} words</span>
              {todayEntry?.checkInAt && <span>Checked in at {formatTime(todayEntry.checkInAt)}</span>}
            </div>
            {renderSpeechTools('checkin', checkInPlan)}
            <Button onClick={() => checkInMut.mutate()} loading={checkInMut.isPending} disabled={!!todayEntry?.checkInAt || checkInWords < minRequiredWords}>
              <LogIn size={16} /> Approve login
            </Button>
          </article>

          <article className="cal__attendance-block">
            <div className="cal__attendance-block-head"><Coffee size={16} /> Lunch toggle</div>
            <textarea
              className="cal__textarea"
              rows={3}
              placeholder="Optional lunch note or handoff context."
              value={lunchNote}
              onChange={(e) => setLunchNote(e.target.value)}
              disabled={!todayEntry?.checkInAt || !!todayEntry?.checkOutAt}
            />
            {renderSpeechTools('lunch', lunchNote)}
            <div className="cal__word-row">
              <span>{todayEntry?.lunchState === 'ON_BREAK' ? 'Lunch break is active' : todayEntry?.lunchState === 'COMPLETED' ? 'Lunch completed' : `Lunch window ${String(attendanceToday.data?.lunchWindow.startHour || 13).padStart(2, '0')}:00-${String(attendanceToday.data?.lunchWindow.endHour || 14).padStart(2, '0')}:00`}</span>
              <span>
                {todayEntry?.lunchStartedAt ? `Start ${formatTime(todayEntry.lunchStartedAt)}` : '—'}
                {todayEntry?.lunchEndedAt ? ` · End ${formatTime(todayEntry.lunchEndedAt)}` : ''}
              </span>
            </div>
            <Button onClick={() => lunchMut.mutate()} loading={lunchMut.isPending} disabled={!todayEntry?.checkInAt || !!todayEntry?.checkOutAt}>
              <Coffee size={16} /> {todayEntry?.lunchState === 'ON_BREAK' ? 'End lunch' : 'Start lunch'}
            </Button>
          </article>

          <article className="cal__attendance-block">
            <div className="cal__attendance-block-head"><LogOut size={16} /> Evening logout report</div>
            <textarea
              className="cal__textarea"
              rows={5}
              placeholder={`Write at least ${minRequiredWords} words about what you finished today, blockers, and what moves forward next.`}
              value={checkOutReport}
              onChange={(e) => setCheckOutReport(e.target.value)}
              disabled={!todayEntry?.checkInAt || !!todayEntry?.checkOutAt}
            />
            <div className="cal__word-row">
              <span>{checkOutWords} / {minRequiredWords} words</span>
              {!todayEntry?.checkOutAt && <span>Logout opens at {String(attendanceToday.data?.checkOutAt.hour || 18).padStart(2, '0')}:00</span>}
              {todayEntry?.checkOutAt && <span>Checked out at {formatTime(todayEntry.checkOutAt)}</span>}
            </div>
            {renderSpeechTools('checkout', checkOutReport)}
            <Button onClick={() => checkOutMut.mutate()} loading={checkOutMut.isPending} disabled={!todayEntry?.checkInAt || !!todayEntry?.checkOutAt || checkOutWords < minRequiredWords}>
              <LogOut size={16} /> Submit logout report
            </Button>
          </article>
        </div>
      </section>

      <div className="cal__grid">
        {days.map((d) => {
          const dateKey = d.format('YYYY-MM-DD');
          const eventsToday = (data?.items || []).filter((e) => dayjs(e.startsAt).isSame(d, 'day'));
          const attendance = attendanceByDay.get(dateKey);
          const isToday = d.isSame(dayjs(), 'day');
          return (
            <div key={d.toString()} className={'cal__col' + (isToday ? ' is-today' : '')}>
              <header>
                <span className="cal__dow">{d.format('ddd')}</span>
                <span className="cal__dom">{d.format('D')}</span>
              </header>
              <div className="cal__col-body">
                {attendance && (
                  <div className={`cal__attendance-mini cal__attendance-mini--${attendance.status.toLowerCase()}`}>
                    <strong>{attendance.status.replace('_', ' ')}</strong>
                    <span>{attendance.checkInAt ? `In ${formatTime(attendance.checkInAt)}` : 'No check-in yet'}</span>
                    {attendance.lunchStartedAt && <span>Lunch {formatTime(attendance.lunchStartedAt)}{attendance.lunchEndedAt ? `–${formatTime(attendance.lunchEndedAt)}` : ''}</span>}
                    {attendance.checkOutAt && <span>Out {formatTime(attendance.checkOutAt)}</span>}
                  </div>
                )}
                {isLoading && <div className="cal__hint">Loading…</div>}
                {!isLoading && eventsToday.length === 0 && !attendance && <div className="cal__hint">No events</div>}
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

      {!isLoading && (data?.items.length ?? 0) === 0 && !(attendanceWeek.data?.items.length) && (
        <div className="cal__empty">
          <CalendarDays size={20} /> <span>Nothing scheduled this week.</span>
        </div>
      )}
    </div>
  );
}
