import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import {
  LayoutDashboard, MessageSquare, KanbanSquare, Users, UserCog, Phone, Headphones, Settings, LogOut, LogIn, Hash,
  Activity, Calendar, Bookmark, Search, BarChart3, ShieldCheck, Zap, Video, Flag, KeyRound, Radio, PhoneIncoming, PhoneCall, Minimize2, Menu, FileText, Disc3, Building2, Trash2, type LucideIcon,
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
import { getSocket } from '@/services/socket';
import { playNotificationSound } from '@/services/notificationSound';
import { useCallStore } from '@/store/calls';
import { toast } from '@/components/Toast';
import { useEffect, useState } from 'react';
import { PageTransition } from '@/components/PageTransition';
import { Logo } from '@/components/Logo';
import './workspace-layout.css';

type NavItem = { to: string; label: string; icon: LucideIcon; platformOnly?: boolean };
type ChatMessageEvent = {
  id: string;
  channelId: string;
  authorId: string;
  body?: string | null;
  attachments?: unknown[];
  author?: { name?: string | null };
};
type ChannelListData = { items: Array<{ id: string; unreadCount?: number }> };
type MeetingParticipantJoinedEvent = {
  slug: string;
  name: string;
  participant?: { displayName?: string | null; userId?: string | null };
};

const NAV: NavItem[] = [
  { to: '/chat', label: 'Chat', icon: MessageSquare },
  { to: '/tasks', label: 'Tasks', icon: KanbanSquare },
  { to: '/reports', label: 'Reports', icon: FileText },
  { to: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/channels', label: 'Channels', icon: Hash },
  { to: '/calendar', label: 'Calendar', icon: Calendar },
  { to: '/calls', label: 'Calls', icon: Phone },
  { to: '/meetings', label: 'Meetings', icon: Video },
  { to: '/recordings', label: 'Recordings', icon: Disc3 },
  { to: '/deleted-chats', label: 'Deleted chats', icon: Trash2 },
  { to: '/organizations', label: 'Organisations', icon: Building2, platformOnly: true },
  { to: '/telecaller', label: 'Telecaller', icon: Headphones },
  { to: '/saved', label: 'Saved', icon: Bookmark },
  { to: '/employees', label: 'Employees', icon: Users },
  { to: '/clients', label: 'Clients', icon: UserCog },
  { to: '/analytics', label: 'Analytics', icon: BarChart3 },
  { to: '/talk-time', label: 'Talk time', icon: PhoneCall },
  { to: '/login-activity', label: 'Login activity', icon: LogIn },
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
  ADMIN: NAV.filter((n) => !n.platformOnly).map((n) => n.to),
  MANAGER: ['/dashboard', '/chat', '/channels', '/tasks', '/reports', '/calendar', '/calls', '/meetings', '/saved', '/employees', '/sessions'],
  PROJECT_COORDINATOR_MANAGER: ['/dashboard', '/chat', '/channels', '/tasks', '/reports', '/calendar', '/calls', '/meetings', '/saved', '/employees', '/sessions'],
  EMPLOYEE: ['/dashboard', '/chat', '/channels', '/tasks', '/reports', '/calendar', '/calls', '/meetings', '/saved', '/employees', '/sessions'],
  TELECALLER: ['/dashboard', '/telecaller', '/chat', '/reports', '/calendar', '/saved', '/employees', '/sessions'],
  CLIENT: ['/dashboard', '/channels', '/saved', '/sessions'],
};

export default function WorkspaceLayout() {
  const user = useAuthStore((s) => s.user);
  const clear = useAuthStore((s) => s.clear);
  const navigate = useNavigate();
  const location = useLocation();
  const pendingCall = useCallStore((s) => s.pending);
  const currentCallId = useCallStore((s) => s.currentCallId);
  const setPendingCall = useCallStore((s) => s.setPending);
  const clearPendingCall = useCallStore((s) => s.clearPending);
  const qc = useQueryClient();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const userId = user?.id;

  useEffect(() => {
    setSidebarOpen(false);
  }, [location.pathname]);

  useEffect(() => {
    if (!sidebarOpen) return undefined;
    const onKeyDown = (event: globalThis.KeyboardEvent) => {
      if (event.key === 'Escape') setSidebarOpen(false);
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [sidebarOpen]);

  useEffect(() => {
    const s = getSocket();
    if (!s) return;
    const onIncoming = (payload: any) => {
      const caller = payload?.call?.initiator?.name || 'A teammate';
      setPendingCall(payload);
      toast.info(`Incoming call from ${caller}`, 'Answer from the call banner or open Calls.');
    };
    const onDeclined = (payload: any) => {
      if (pendingCall?.call?.id && payload?.callId === pendingCall.call.id) clearPendingCall();
      toast.warn('Call was declined', payload?.status === 'MISSED' ? 'Marked as missed.' : undefined);
    };
    s.on('call.incoming', onIncoming);
    s.on('call.invited', onIncoming);
    s.on('call.declined', onDeclined);
    return () => {
      s.off('call.incoming', onIncoming);
      s.off('call.invited', onIncoming);
      s.off('call.declined', onDeclined);
    };
  }, [clearPendingCall, pendingCall?.call?.id, setPendingCall]);

  useEffect(() => {
    const s = getSocket();
    if (!s || !userId) return;

    const onNotification = () => {
      qc.invalidateQueries({ queryKey: ['notifications.grouped'] });
    };
    const onMeetingParticipantJoined = (payload: MeetingParticipantJoinedEvent) => {
      if (payload?.participant?.userId === userId) return;
      qc.invalidateQueries({ queryKey: ['meetings.mine'] });
      qc.invalidateQueries({ queryKey: ['meeting.public.lobby', payload.slug] });
      toast.info(
        `${payload.participant?.displayName || 'Someone'} joined ${payload.name || 'your meeting'}`,
        'Open the room to see who is connected.'
      );
      playNotificationSound();
    };
    const onChatMessage = (message: ChatMessageEvent) => {
      if (!message?.channelId) return;
      const isMine = message.authorId === userId;
      const isActiveChat = location.pathname === `/chat/${message.channelId}`;

      qc.setQueryData<ChannelListData>(['channels.mine'], (prev) => {
        if (!prev?.items) return prev;
        return {
          ...prev,
          items: prev.items.map((channel) => {
            if (channel.id !== message.channelId) return channel;
            if (isMine || isActiveChat) return { ...channel, unreadCount: channel.unreadCount || 0 };
            return { ...channel, unreadCount: (channel.unreadCount || 0) + 1 };
          }),
        };
      });

      if (!isMine && !isActiveChat) {
        toast.info(
          message.author?.name ? `New message from ${message.author.name}` : 'New message',
          message.body || (message.attachments?.length ? 'Sent an attachment' : 'Open chat to read it')
        );
        playNotificationSound();
      }
    };

    s.on('notification.created', onNotification);
    s.on('meeting.participant.joined', onMeetingParticipantJoined);
    s.on('chat.message.created', onChatMessage);
    return () => {
      s.off('notification.created', onNotification);
      s.off('meeting.participant.joined', onMeetingParticipantJoined);
      s.off('chat.message.created', onChatMessage);
    };
  }, [location.pathname, qc, userId]);

  if (!user) return null;
  const allowed = ALLOWED[user.role] || [];
  const nav = NAV.filter((n) => allowed.includes(n.to));
  const activeNav = nav.find((n) => location.pathname === n.to || location.pathname.startsWith(`${n.to}/`));

  function answerPendingCall() {
    if (!pendingCall?.call?.id) return;
    navigate(`/calls/live/${pendingCall.call.id}`);
  }

  async function declinePendingCall() {
    if (!pendingCall?.call?.id) return;
    await api.post(`/calls/${pendingCall.call.id}/decline`).catch(() => {});
    clearPendingCall();
    toast.info('Call declined');
  }

  async function handleLogout() {
    const refreshToken = useAuthStore.getState().refreshToken;
    await api.post('/auth/logout', { refreshToken }).catch(() => {});
    disconnectSocket();
    clear();
    // Drop all cached queries so the next user on this machine never briefly
    // sees the previous account's channels/tasks/dashboard data.
    qc.clear();
    navigate('/login', { replace: true });
  }

  function openSearch() {
    // dispatch the same key shortcut so CommandPalette's listener picks it up
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', metaKey: true }));
  }

  const callerName = pendingCall?.call?.initiator?.name || 'A teammate';
  const callModeLabel = pendingCall?.call?.kind === 'GROUP' ? 'Group voice room' : 'Direct voice call';
  const inLiveCallRoute = location.pathname.startsWith('/calls/live/');

  return (
    <div className={clsx('ws', sidebarOpen && 'is-sidebar-open')}>
      <aside className={clsx('ws__sidebar', sidebarOpen && 'is-open')} aria-label="Workspace navigation">
        <div className="ws__brand">
          <Logo size={32} withWordmark onClick={() => navigate('/dashboard')} title="MyTaskKing · Home" />
        </div>

        <button className="ws__search-trigger" onClick={openSearch}>
          <Search size={14} /> <span>Search…</span> <kbd>⌘K</kbd>
        </button>

        <nav className="ws__nav">
          {nav.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              onClick={() => setSidebarOpen(false)}
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
              <span className="ws__me-sub">{user.isClient ? user.clientCompany || 'Client' : user.customTitle || user.role.replace(/_/g, ' ')}</span>
            </div>
          </div>
          <button className="ws__icon-btn" onClick={handleLogout} title="Sign out">
            <LogOut size={16} />
          </button>
        </div>
      </aside>
      <button
        type="button"
        className="ws__scrim"
        aria-label="Close navigation menu"
        onClick={() => setSidebarOpen(false)}
        tabIndex={-1}
      />

      <main className="ws__main">
        {pendingCall?.call && (
          <div className="ws__incoming-modal" role="dialog" aria-modal="true" aria-label="Incoming call">
            <div className="ws__incoming-card">
              <div className="ws__incoming-badge"><Radio size={14} /> Secure live call</div>
              <div className="ws__incoming-avatar">
                <Avatar name={callerName} src={pendingCall.call.initiator?.avatarUrl} isClient={false} size={64} />
              </div>
              <h2>{callerName} is calling</h2>
              <p>{callModeLabel} · Answer to jump straight into the live browser room.</p>
              <div className="ws__incoming-meta">
                <span><PhoneIncoming size={14} /> Incoming now</span>
                <span><ShieldCheck size={14} /> Secure team session</span>
              </div>
              <div className="ws__incoming-modal-actions">
                <button className="bb bb--ghost bb--md" onClick={declinePendingCall}>Decline</button>
                <button className="bb bb--primary bb--md" onClick={answerPendingCall}>Answer call</button>
              </div>
            </div>
          </div>
        )}
        <header className="ws__topbar">
          <button
            type="button"
            className="ws__mobile-menu"
            aria-label="Open navigation menu"
            aria-expanded={sidebarOpen}
            onClick={() => setSidebarOpen(true)}
          >
            <Menu size={20} />
          </button>
          <div className="ws__topbar-title">{activeNav?.label || 'Workspace'}</div>
          <div className="ws__topbar-actions">
            <ThemeSwitcher />
            <PresenceMenu />
            <button className="ws__icon-btn" title="Search (⌘K)" onClick={openSearch}><Search size={18} /></button>
            <NotificationCenter />
            <button className="ws__icon-btn" title="Settings" onClick={() => navigate('/settings')}><Settings size={18} /></button>
          </div>
        </header>
        <section className="ws__content">
          <AnnouncementBanner />
          {pendingCall?.call && (
            <div className="ws__incoming-call">
              <div className="ws__incoming-copy">
                <strong>Incoming call from {callerName}</strong>
                <span>{callModeLabel} · Answer to join the live browser room.</span>
              </div>
              <div className="ws__incoming-actions">
                <button className="bb bb--primary bb--sm" onClick={answerPendingCall}>Answer</button>
                <button className="bb bb--ghost bb--sm" onClick={declinePendingCall}>Decline</button>
              </div>
            </div>
          )}
          {!pendingCall?.call && currentCallId && !inLiveCallRoute && (
            <button className="ws__call-widget" onClick={() => navigate(`/calls/live/${currentCallId}`)} title="Return to live call">
              <span className="ws__call-widget-icon"><PhoneCall size={18} /></span>
              <span className="ws__call-widget-copy">
                <strong>Call in progress</strong>
                <span>Return to the live call</span>
              </span>
              <span className="ws__call-widget-badge"><Minimize2 size={14} /> Live</span>
            </button>
          )}
          <PageTransition variant="fade">
            <Outlet />
          </PageTransition>
        </section>
      </main>
    </div>
  );
}
