import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { toast } from '@/components/Toast';
import { useAuthStore } from '@/store/auth';
import './settings.css';

export default function SettingsPage() {
  const user = useAuthStore((s) => s.user)!;
  const qc = useQueryClient();
  const isAdmin = user.role === 'SUPER_ADMIN' || user.role === 'ADMIN';
  const [passwords, setPasswords] = useState({
    currentPassword: '',
    newPassword: '',
    confirmPassword: '',
  });

  const { data: settings } = useQuery<Record<string, Record<string, any>>>({
    queryKey: ['settings.all'],
    queryFn: async () => (await api.get('/settings')).data,
  });

  const [branding, setBranding] = useState({
    name: settings?.branding?.name ?? 'Bestie',
    tagline: settings?.branding?.tagline ?? 'Premium workspace · enterprise',
    primaryColor: settings?.branding?.primaryColor ?? '#5b8cff',
    logoUrl: settings?.branding?.logoUrl ?? '',
  });

  const [retention, setRetention] = useState({
    messagesDays: settings?.retention?.messagesDays ?? 365,
    callRecordingsDays: settings?.retention?.callRecordingsDays ?? 180,
  });

  const saveMut = useMutation({
    mutationFn: async ({ scope, key, value }: { scope: string; key: string; value: any }) =>
      (await api.put(`/settings/${scope}/${key}`, { value })).data,
    onSuccess: () => {
      toast.success('Saved');
      qc.invalidateQueries({ queryKey: ['settings.all'] });
    },
    onError: () => toast.error('Could not save', 'Check your permissions and try again.'),
  });

  const passwordMut = useMutation({
    mutationFn: async () =>
      (await api.post('/auth/change-password', {
        currentPassword: passwords.currentPassword,
        newPassword: passwords.newPassword,
      })).data,
    onSuccess: () => {
      toast.success('Password changed');
      setPasswords({ currentPassword: '', newPassword: '', confirmPassword: '' });
      qc.invalidateQueries({ queryKey: ['auth.me'] });
    },
    onError: (err: any) => {
      toast.error(err?.response?.data?.error?.message || 'Could not change password');
    },
  });

  const passwordMismatch =
    passwords.confirmPassword.length > 0 && passwords.newPassword !== passwords.confirmPassword;
  const passwordTooShort =
    passwords.newPassword.length > 0 && passwords.newPassword.length < 8;

  return (
    <div className="st">
      <header className="st__head">
        <div>
          <h1>Workspace settings</h1>
          <p>Branding, policies, retention, and notification defaults.</p>
        </div>
      </header>

      {!isAdmin && (
        <div className="st__note">You can view settings here. Only admins can change them.</div>
      )}

      <section className="st__section">
        <h2>Change password</h2>
        <p className="st__subtle">Update your login password for this workspace account.</p>
        <div className="st__grid">
          <Input
            label="Current password"
            type="password"
            value={passwords.currentPassword}
            onChange={(e) => setPasswords({ ...passwords, currentPassword: e.target.value })}
          />
          <Input
            label="New password"
            type="password"
            hint={passwordTooShort ? 'Use at least 8 characters.' : undefined}
            value={passwords.newPassword}
            onChange={(e) => setPasswords({ ...passwords, newPassword: e.target.value })}
          />
          <Input
            label="Confirm new password"
            type="password"
            error={passwordMismatch ? 'Passwords do not match.' : undefined}
            value={passwords.confirmPassword}
            onChange={(e) => setPasswords({ ...passwords, confirmPassword: e.target.value })}
          />
        </div>
        <div className="st__actions">
          <Button
            onClick={() => passwordMut.mutate()}
            loading={passwordMut.isPending}
            disabled={
              !passwords.currentPassword ||
              !passwords.newPassword ||
              !passwords.confirmPassword ||
              passwordMismatch ||
              passwordTooShort
            }
          >
            Change password
          </Button>
        </div>
      </section>

      <section className="st__section">
        <h2>Branding</h2>
        <div className="st__grid">
          <Input label="Workspace name" value={branding.name} onChange={(e) => setBranding({ ...branding, name: e.target.value })} />
          <Input label="Tagline" value={branding.tagline} onChange={(e) => setBranding({ ...branding, tagline: e.target.value })} />
          <Input label="Primary color (hex)" value={branding.primaryColor} onChange={(e) => setBranding({ ...branding, primaryColor: e.target.value })} />
          <Input label="Logo URL" value={branding.logoUrl} onChange={(e) => setBranding({ ...branding, logoUrl: e.target.value })} />
        </div>
        {isAdmin && (
          <Button onClick={() => Object.entries(branding).forEach(([k, v]) => saveMut.mutate({ scope: 'branding', key: k, value: v }))}>
            Save branding
          </Button>
        )}
      </section>

      <section className="st__section">
        <h2>Retention</h2>
        <p className="st__subtle">How long to keep messages and call recordings (days). Set to 0 to disable retention.</p>
        <div className="st__grid">
          <Input
            label="Messages (days)" type="number"
            value={String(retention.messagesDays)}
            onChange={(e) => setRetention({ ...retention, messagesDays: parseInt(e.target.value || '0', 10) })}
          />
          <Input
            label="Call recordings (days)" type="number"
            value={String(retention.callRecordingsDays)}
            onChange={(e) => setRetention({ ...retention, callRecordingsDays: parseInt(e.target.value || '0', 10) })}
          />
        </div>
        {isAdmin && (
          <Button
            onClick={() => {
              saveMut.mutate({ scope: 'retention', key: 'messagesDays', value: retention.messagesDays });
              saveMut.mutate({ scope: 'retention', key: 'callRecordingsDays', value: retention.callRecordingsDays });
            }}
          >
            Save retention
          </Button>
        )}
      </section>
    </div>
  );
}
