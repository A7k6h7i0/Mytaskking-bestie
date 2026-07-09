import { useCallback, useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { BrainCircuit, Loader2, Sparkles } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { toast } from '@/components/Toast';
import './ai-review.css';

type TelecallerRecording = {
  id: string;
  recordingUrl: string;
  fromNumber: string | null;
  toNumber: string;
  status: string | null;
  durationSec: number | null;
  startedAt: string | null;
  endedAt: string | null;
  createdAt: string;
  notes: string | null;
  lead: {
    id: string;
    name: string;
    phone: string;
    company: string | null;
  } | null;
  agent: {
    id: string;
    name: string;
    phone: string | null;
  } | null;
};

type VoiceReport = {
  text: string;
  intent: string;
  confidence: number;
};

type AnalysisPhase = 'idle' | 'uploading' | 'pending' | 'completed' | 'failed';

const INTENT_LABELS: Record<string, string> = {
  'interested in the product': 'Interested',
  'confirmed the deal': 'Deal Confirmed',
  'rejected the offer': 'Rejected',
  'needs follow up': 'Needs Follow Up',
};

function intentLabel(raw: string) {
  const key = raw.trim().toLowerCase();
  return INTENT_LABELS[key] || raw;
}

function formatDuration(sec: number | null) {
  if (sec == null || sec <= 0) return '—';
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function ConfidenceGauge({ value }: { value: number }) {
  const pct = Math.max(0, Math.min(100, value));
  const arcLength = 235.6;
  const offset = arcLength - (arcLength * pct) / 100;

  return (
    <div className="air-gauge-section">
      <div className="air-gauge-container">
        <svg className="air-gauge-svg" viewBox="0 0 180 100" aria-hidden>
          <path className="air-gauge-track" d="M 15,90 A 75,75 0 0,1 165,90" />
          <path
            className="air-gauge-fill"
            d="M 15,90 A 75,75 0 0,1 165,90"
            style={{ strokeDashoffset: offset }}
          />
        </svg>
        <div className="air-gauge-center">
          <span className="air-gauge-lbl">Score</span>
          <span className="air-gauge-val">{pct.toFixed(1)}%</span>
        </div>
        <div className="air-gauge-limits">
          <span>0%</span>
          <span>100%</span>
        </div>
      </div>
    </div>
  );
}

function recordingLabel(r: TelecallerRecording) {
  const leadName = r.lead?.name || 'Unknown lead';
  const leadPhone = r.lead?.phone || r.toNumber;
  const agent = r.agent?.name || 'Telecaller';
  const from = r.fromNumber || '—';
  const when = dayjs(r.createdAt).format('MMM D, HH:mm');
  return `${leadName} · ${leadPhone} · from ${from} · by ${agent} · ${when}`;
}

export default function AiReviewPage() {
  const [selectedId, setSelectedId] = useState('');
  const [phase, setPhase] = useState<AnalysisPhase>('idle');
  const [report, setReport] = useState<VoiceReport | null>(null);
  const [error, setError] = useState<string | null>(null);
  const pollRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const deadlineRef = useRef<number>(0);

  const { data, isLoading, isError } = useQuery<{ items: TelecallerRecording[] }>({
    queryKey: ['ai-review.recordings'],
    queryFn: async () => (await api.get('/ai-review/recordings')).data,
  });

  const recordings = data?.items ?? [];
  const selected = recordings.find((r) => r.id === selectedId) ?? null;

  const clearPoll = useCallback(() => {
    if (pollRef.current) {
      clearTimeout(pollRef.current);
      pollRef.current = null;
    }
  }, []);

  useEffect(() => () => clearPoll(), [clearPoll]);

  async function pollJob(jobId: string) {
    if (Date.now() > deadlineRef.current) {
      setPhase('failed');
      setError('Analysis timed out after 5 minutes');
      return;
    }
    try {
      const { data: job } = await api.get(`/ai-review/job/${jobId}`);
      if (job.status === 'completed' && job.output) {
        setReport({
          text: job.output.text ?? '',
          intent: job.output.intent ?? '',
          confidence: Number(job.output.confidence ?? 0),
        });
        setPhase('completed');
        clearPoll();
        return;
      }
      if (job.status === 'failed') {
        setPhase('failed');
        setError(job.error || 'Analysis failed');
        clearPoll();
        return;
      }
      setPhase('pending');
      pollRef.current = setTimeout(() => pollJob(jobId), 2000);
    } catch (e: unknown) {
      setPhase('failed');
      setError(e instanceof Error ? e.message : 'Could not check analysis status');
      clearPoll();
    }
  }

  async function handleAnalyse() {
    if (!selectedId) {
      toast.warn('Select a recording first');
      return;
    }
    clearPoll();
    setReport(null);
    setError(null);
    setPhase('uploading');
    deadlineRef.current = Date.now() + 5 * 60 * 1000;

    try {
      const { data: submitted } = await api.post('/ai-review/analyse', { callId: selectedId });
      const jobId = submitted.jobID as string;
      setPhase('pending');
      pollRef.current = setTimeout(() => pollJob(jobId), 2000);
    } catch (e: unknown) {
      setPhase('failed');
      const msg =
        (e as { response?: { data?: { error?: { message?: string } | string } } })?.response?.data
          ?.error &&
        (typeof (e as { response?: { data?: { error?: { message?: string } | string } } }).response
          ?.data?.error === 'object'
          ? (e as { response?: { data?: { error?: { message?: string } } } }).response?.data?.error
              ?.message
          : (e as { response?: { data?: { error?: string } } }).response?.data?.error) ||
        (e instanceof Error ? e.message : 'Analysis request failed');
      setError(msg);
      toast.error(msg);
    }
  }

  const busy = phase === 'uploading' || phase === 'pending';

  return (
    <div className="air">
      <header className="air__head">
        <div>
          <h1 className="air__title">
            <BrainCircuit size={26} style={{ verticalAlign: -4, marginRight: 8 }} />
            AI Review
          </h1>
          <p className="air__sub">
            Analyse telecaller recordings with Voice AI — transcript, intent, and confidence score.
          </p>
        </div>
      </header>

      <section className="air__panel">
        <label className="air__label" htmlFor="recording-select">
          Choose telecaller recording
        </label>
        <select
          id="recording-select"
          className="air__select"
          value={selectedId}
          onChange={(e) => {
            setSelectedId(e.target.value);
            setPhase('idle');
            setReport(null);
            setError(null);
            clearPoll();
          }}
          disabled={busy}
        >
          <option value="">— Select a recording —</option>
          {recordings.map((r) => (
            <option key={r.id} value={r.id}>
              {recordingLabel(r)}
            </option>
          ))}
        </select>

        {selected && (
          <div className="air__details">
            <div className="air__detail-row">
              <span className="air__detail-key">Lead</span>
              <span>{selected.lead?.name || '—'}</span>
            </div>
            <div className="air__detail-row">
              <span className="air__detail-key">Lead phone</span>
              <span>{selected.lead?.phone || selected.toNumber}</span>
            </div>
            {selected.lead?.company && (
              <div className="air__detail-row">
                <span className="air__detail-key">Company</span>
                <span>{selected.lead.company}</span>
              </div>
            )}
            <div className="air__detail-row">
              <span className="air__detail-key">Called from</span>
              <span>{selected.fromNumber || '—'}</span>
            </div>
            <div className="air__detail-row">
              <span className="air__detail-key">Called to</span>
              <span>{selected.toNumber}</span>
            </div>
            <div className="air__detail-row">
              <span className="air__detail-key">Telecaller</span>
              <span>{selected.agent?.name || '—'}</span>
            </div>
            <div className="air__detail-row">
              <span className="air__detail-key">Duration</span>
              <span>{formatDuration(selected.durationSec)}</span>
            </div>
            <div className="air__detail-row">
              <span className="air__detail-key">Date</span>
              <span>{dayjs(selected.createdAt).format('MMM D, YYYY · HH:mm')}</span>
            </div>
            {selected.recordingUrl && (
              <audio
                controls
                preload="none"
                src={selected.recordingUrl}
                className="air__audio"
              />
            )}
          </div>
        )}

        <button
          type="button"
          className="air__analyse-btn"
          onClick={handleAnalyse}
          disabled={!selectedId || busy}
        >
          {busy ? (
            <>
              <Loader2 size={18} className="air__spin" />
              {phase === 'uploading' ? 'Uploading & starting…' : 'Processing analysis…'}
            </>
          ) : (
            <>
              <Sparkles size={18} />
              Analyse
            </>
          )}
        </button>
      </section>

      {busy && (
        <section className="air__processing">
          <Loader2 size={28} className="air__spin" />
          <p className="air__processing-title">Voice AI Analysis in progress</p>
          <p className="air__processing-sub">
            {phase === 'uploading'
              ? 'Uploading recording to the AI server…'
              : 'Transcribing and detecting intent — this may take 30–60 seconds.'}
          </p>
        </section>
      )}

      {phase === 'failed' && error && (
        <section className="air__error">{error}</section>
      )}

      {phase === 'completed' && report && (
        <div className="air__report">
          <div className="air__header-banner">Voice AI Analysis Report</div>

          <div className="air__card">
            <span className="air__card-label">Analysis Details</span>

            <div className="air__data-row">
              <div className="air__bullet" />
              <div className="air__data-body">
                <div className="air__data-title">Detected Intent</div>
                <div className="air__intent">{intentLabel(report.intent)}</div>
              </div>
            </div>

            <div className="air__data-row">
              <div className="air__bullet" />
              <div className="air__data-body">
                <div className="air__data-title">Transcript Response</div>
                <p className="air__transcript">{report.text}</p>
              </div>
            </div>
          </div>

          <div className="air__card air__card--gauge">
            <span className="air__card-label air__card-label--center">
              Overall Analysis Confidence
            </span>
            <ConfidenceGauge value={report.confidence} />
          </div>
        </div>
      )}

      {isLoading && <p className="air__muted">Loading recordings…</p>}
      {isError && <p className="air__error">Could not load telecaller recordings.</p>}
      {!isLoading && !isError && recordings.length === 0 && (
        <p className="air__muted">No telecaller recordings with audio found yet.</p>
      )}
    </div>
  );
}
