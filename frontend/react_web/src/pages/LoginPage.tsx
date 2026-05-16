import { FormEvent, useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { KeyRound, User } from 'lucide-react';
import { useAuthStore } from '@/store/auth';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import './login.css';

export default function LoginPage() {
  const token = useAuthStore((s) => s.accessToken);
  const setSession = useAuthStore((s) => s.setSession);
  const [userId, setUserId] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  if (token) return <Navigate to="/dashboard" replace />;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const { data } = await api.post('/auth/login', { userId, password });
      setSession({ user: data.user, accessToken: data.accessToken, refreshToken: data.refreshToken });
      navigate('/dashboard', { replace: true });
    } catch (err: any) {
      setError(err?.response?.data?.error?.message || 'Login failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login">
      <div className="login__panel fade-in">
        <div className="login__brand">
          <div className="login__logo" />
          <div>
            <div className="login__name">Bestie</div>
            <div className="login__tag">Premium workspace · enterprise</div>
          </div>
        </div>

        <h1 className="login__title">Welcome back</h1>
        <p className="login__sub">Sign in with the credentials your admin assigned.</p>

        <form onSubmit={onSubmit} className="login__form">
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
          {error && <div className="login__error">{error}</div>}
          <Button type="submit" size="lg" loading={loading}>Sign in</Button>
        </form>

        <div className="login__foot">
          No public registration. Contact your administrator for access.
        </div>
      </div>

      <div className="login__art" aria-hidden>
        <div className="login__bubble login__bubble--1" />
        <div className="login__bubble login__bubble--2" />
        <div className="login__bubble login__bubble--3" />
      </div>
    </div>
  );
}
