import { FormEvent, useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { KeyRound, User, ArrowRight, Building2 } from 'lucide-react';
import { useAuthStore } from '@/store/auth';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { SuccessCheck } from '@/components/ui/SuccessCheck';
import { RiveAnimation } from '@/components/ui/RiveAnimation';
import { Logo } from '@/components/Logo';
import { AnimatedGradient } from '@/components/effects/AnimatedGradient';
import { ParticleField } from '@/components/effects/ParticleField';
import { useConfetti } from '@/hooks/useMotionFx';
import './login.css';

// Drop a Rive file at `frontend/react_web/public/rive/login.riv` and the
// canvas takes over from the gradient-blob fallback automatically.
const RIVE_LOGIN = '/rive/login.riv';

export default function LoginPage() {
  const token = useAuthStore((s) => s.accessToken);
  const setSession = useAuthStore((s) => s.setSession);
  const [tenantSlug, setTenantSlug] = useState('');
  const [userId, setUserId] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const navigate = useNavigate();
  const { burst, ConfettiHost } = useConfetti();

  if (token) return <Navigate to="/dashboard" replace />;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    const form = e.currentTarget as HTMLFormElement;
    try {
      const { data } = await api.post('/auth/login', {
        tenantSlug: tenantSlug.trim() || undefined,
        userId,
        password,
      });
      // Celebrate, then route.
      setSuccess(true);
      burst({ origin: { x: window.innerWidth * 0.25, y: window.innerHeight * 0.45 }, count: 50 });
      setTimeout(() => {
        setSession({ user: data.user, accessToken: data.accessToken, refreshToken: data.refreshToken });
        navigate('/dashboard', { replace: true });
      }, 800);
    } catch (err: any) {
      setError(err?.response?.data?.error?.message || 'Login failed');
      // Tickle the form with a shake — re-trigger by toggling the class.
      form.classList.remove('m-shake');
      void form.offsetWidth;
      form.classList.add('m-shake');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login">
      <div className="login__panel m-fade-up">
        <div className="login__brand">
          <Logo size={44} withWordmark animateKey="login" />
        </div>

        {success ? (
          <div className="login__success m-fade-up">
            <SuccessCheck size={88} />
            <h1 className="m-gradient-text">Welcome back</h1>
            <p>Loading your workspace…</p>
          </div>
        ) : (
          <>
            <h1 className="login__title m-fade-up" style={{ animationDelay: '40ms' }}>
              Welcome <span className="m-gradient-text">back</span>
            </h1>
            <p className="login__sub m-fade-up" style={{ animationDelay: '80ms' }}>
              Sign in with the credentials your admin assigned.
            </p>

            <form
              onSubmit={onSubmit}
              className="login__form m-stagger"
              style={{ ['--stagger' as never]: '70ms' }}
            >
              <Input
                label="Organisation ID"
                placeholder="default (MyTaskKing) or e.g. digital-links"
                autoComplete="organization"
                leading={<Building2 size={16} />}
                value={tenantSlug}
                onChange={(e) => setTenantSlug(e.target.value)}
              />
              <Input
                label="User ID"
                placeholder="e.g. priya.k"
                autoFocus
                autoComplete="username"
                leading={<User size={16} />}
                value={userId}
                onChange={(e) => setUserId(e.target.value)}
              />
              <Input
                label="Password"
                type="password"
                autoComplete="current-password"
                leading={<KeyRound size={16} />}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
              {error && <div className="login__error m-shake">{error}</div>}
              <Button type="submit" size="lg" loading={loading} className="m-press m-sheen">
                Sign in <ArrowRight size={16} />
              </Button>
            </form>

            <div className="login__foot m-fade-up" style={{ animationDelay: '260ms' }}>
              No public registration. Contact your administrator for access.
            </div>
          </>
        )}
      </div>

      <div className="login__art" aria-hidden>
        {/* Layered art panel: mesh gradient base, particle field overlay,
            optional Rive canvas on top, caption + brand mark in the corners. */}
        <AnimatedGradient className="login__art-mesh" />
        <ParticleField
          className="login__art-particles"
          density={0.05}
          color="rgba(255, 255, 255, 0.55)"
          linkColor="rgba(255, 255, 255, 0.18)"
        />
        <RiveAnimation src={RIVE_LOGIN} width="100%" height="100%" className="login__rive" />
        <div className="login__bubble login__bubble--1 m-float" />
        <div className="login__bubble login__bubble--2 m-float" style={{ animationDelay: '0.8s' }} />
        <div className="login__bubble login__bubble--3 m-pulse" />

        <div className="login__art-logo m-fade-up" style={{ animationDelay: '500ms' }}>
          <Logo size={56} ambient />
        </div>

        <div className="login__caption m-fade-up" style={{ animationDelay: '600ms' }}>
          <span className="m-typewriter" style={{ width: '17ch' }}>Your team, one workspace.</span>
        </div>
      </div>

      <ConfettiHost />
    </div>
  );
}
