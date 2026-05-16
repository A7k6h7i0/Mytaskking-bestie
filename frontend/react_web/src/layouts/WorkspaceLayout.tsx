import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import {
  LayoutDashboard, MessageSquare, KanbanSquare, Users, UserCog, Phone, Headphones, Settings, LogOut, Hash,
  Activity, Calendar, Bookmark, Search, BarChart3, ShieldCheck, Zap, Video, Flag, KeyRound,
} from 'lucide-react';
import clsx from 'clsx';
import { useAuthStore } from '@/store/auth';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { disconnectSocket } from '@/services/socket';
import { api } from '@/services/api';
import { AnnouncementBanner } from '@/components/AnnouncementBanner';
import { NotificationCenter } from '@/components/NotificationCenter';
import { PresenceMenu } from '@/components/PresenceMenu';
import { ThemeSwitcher } from '@/components/ThemeSwitcher';
import './workspace-layout.css';

type NavItem = { to: string; label: string; icon: React.ComponentType<{ size?: number }> };

const NAV: NavItem[] = [
  { to: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/chat', label: 'Chat', icon: MessageSquare },
  { to: '/channels', label: 'Channels', icon: Hash },
  { to: '/tasks', label: 'Tasks', icon: KanbanSquare },
  { to: '/calendar', label: 'Calendar', icon: Calendar },
  { to: '/calls', label: 'Calls', icon: Phone },
  { to: '/meetings', label: 'Meetings', icon: Video },
  { to: '/telecaller', label: 'Telecaller', icon: Headphones },
  { to: '/saved', label: 'Saved', icon: Bookmark },
  { to: '/employees', label: 'Employees', icon: Users },
  { to: '/clients', label: 'Clients', icon: UserCog },
  { to: '/analytics', label: 'Analytics', icon: BarChart3 },
  { to: '/activity', label: 'Activity', icon: Activity },
  { to: '/automations', label: 'Automations', icon: Zap },
  { to: '/flags', label: 'Feature flags', icon: Flag },
  { to: '/permissions', label: 'Permissions', icon: KeyRound },
  { to: '/sessions', label: 'My sessions', icon: ShieldCheck },
  { to: '/settings', label: 'Settings', icon: Settings },
];

// Per-role visibility. Anything not listed is hidden for that role.
const ALLOWED: Record<string, string[]> = {
  SUPER_ADMIN: NAV.map((n) => n.to),
  ADMIN: NAV.map((n) => n.to),
  EMPLOYEE: ['/dashboard', '/chat', '/channels', '/tasks', '/calendar', '/calls', '/meetings', '/saved', '/sessions'],
  TELECALLER: ['/dashboard', '/telecaller', '/chat', '/calendar', '/saved', '/sessions'],
  CLIENT: ['/dashboard', '/chat', '/channels', '/saved', '/sessions'],
};

export default function WorkspaceLayout() {
  const user = useAuthStore((s) => s.user);
  const clear = useAuthStore((s) => s.clear);
  const navigate = useNavigate();

  if (!user) return null;
  const allowed = ALLOWED[user.role] || [];
  const nav = NAV.filter((n) => allowed.includes(n.to));

  async function handleLogout() {
    const refreshToken = useAuthStore.getState().refreshToken;
    await api.post('/auth/logout', { refreshToken }).catch(() => {});
    disconnectSocket();
    clear();
    navigate('/login', { replace: true });
  }

  function openSearch() {
    // dispatch the same key shortcut so CommandPalette's listener picks it up
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', metaKey: true }));
  }

  return (
    <div className="ws">
      <aside className="ws__sidebar">
        <div className="ws__brand">
          <div className="ws__logo" />
          <div className="ws__brand-text">
            <span className="ws__brand-name">Bestie</span>
            <span className="ws__brand-tag">Workspace</span>
          </div>
        </div>

        <button className="ws__search-trigger" onClick={openSearch}>
          <Search size={14} /> <span>Search…</span> <kbd>⌘K</kbd>
        </button>

        <nav className="ws__nav">
          {nav.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              className={({ isActive }) => clsx('ws__nav-item', isActive && 'is-active')}
            >
              <n.icon size={18} />
              <span>{n.label}</span>
            </NavLink>
          ))}
        </nav>

        <div className="ws__sidebar-foot">
          <div className="ws__me">
            <Avatar name={user.name} src={user.avatarUrl} isClient={user.isClient} size={36} />
            <div className="ws__me-text">
              <UserName name={user.name} isClient={user.isClient} role={user.role} />
              <span className="ws__me-sub">{user.isClient ? user.clientCompany || 'Client' : user.role.replace('_', ' ')}</span>
            </div>
          </div>
          <button className="ws__icon-btn" onClick={handleLogout} title="Sign out">
            <LogOut size={16} />
          </button>
        </div>
      </aside>

      <main className="ws__main">
        <header className="ws__topbar">
          <div className="ws__topbar-title" />
          <div className="ws__topbar-actions">
            <ThemeSwitcher />
            <PresenceMenu />
            <button className="ws__icon-btn" title="Search (⌘K)" onClick={openSearch}><Search size={18} /></button>
            <NotificationCenter />
            <button className="ws__icon-btn" title="Settings" onClick={() => navigate('/settings')}><Settings size={18} /></button>
          </div>
        </header>
        <section className="ws__content fade-in">
          <AnnouncementBanner />
          <Outlet />
        </section>
      </main>
    </div>
  );
}
