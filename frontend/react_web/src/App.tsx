import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuthStore } from '@/store/auth';
import LoginPage from '@/pages/LoginPage';
import WorkspaceLayout from '@/layouts/WorkspaceLayout';
import DashboardPage from '@/pages/DashboardPage';
import ChatPage from '@/pages/ChatPage';
import ChannelsPage from '@/pages/ChannelsPage';
import TasksPage from '@/pages/TasksPage';
import CallsPage from '@/pages/CallsPage';
import TelecallerPage from '@/pages/TelecallerPage';
import EmployeesPage from '@/pages/EmployeesPage';
import ClientsPage from '@/pages/ClientsPage';
import ActivityPage from '@/pages/ActivityPage';
import CalendarPage from '@/pages/CalendarPage';
import SettingsPage from '@/pages/SettingsPage';
import SavedPage from '@/pages/SavedPage';
import SessionsPage from '@/pages/SessionsPage';
import AnalyticsPage from '@/pages/AnalyticsPage';
import MeetingsPage from '@/pages/MeetingsPage';
import FlagsPage from '@/pages/FlagsPage';
import PermissionsPage from '@/pages/PermissionsPage';
import { ToastHost } from '@/components/Toast';
import { CommandPalette } from '@/components/CommandPalette';
import { ShortcutsOverlay } from '@/components/ShortcutsOverlay';

function RequireAuth({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.accessToken);
  if (!token) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

function RoleGate({ allow, children }: { allow: string[]; children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user);
  if (!user) return <Navigate to="/login" replace />;
  if (!allow.includes(user.role)) return <Navigate to="/dashboard" replace />;
  return <>{children}</>;
}

export default function App() {
  return (
    <>
      <Routes>
        <Route path="/login" element={<LoginPage />} />

        <Route element={<RequireAuth><WorkspaceLayout /></RequireAuth>}>
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<DashboardPage />} />
          <Route path="/chat" element={<ChatPage />} />
          <Route path="/chat/:channelId" element={<ChatPage />} />
          <Route path="/channels" element={<ChannelsPage />} />
          <Route path="/tasks" element={<TasksPage />} />
          <Route path="/calls" element={<CallsPage />} />
          <Route path="/calendar" element={<CalendarPage />} />
          <Route path="/saved" element={<SavedPage />} />
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="/sessions" element={<SessionsPage />} />
          <Route path="/meetings" element={<MeetingsPage />} />
          <Route
            path="/activity"
            element={<RoleGate allow={['SUPER_ADMIN', 'ADMIN']}><ActivityPage /></RoleGate>}
          />
          <Route
            path="/flags"
            element={<RoleGate allow={['SUPER_ADMIN', 'ADMIN']}><FlagsPage /></RoleGate>}
          />
          <Route
            path="/permissions"
            element={<RoleGate allow={['SUPER_ADMIN', 'ADMIN']}><PermissionsPage /></RoleGate>}
          />
          <Route
            path="/analytics"
            element={<RoleGate allow={['SUPER_ADMIN', 'ADMIN']}><AnalyticsPage /></RoleGate>}
          />
          <Route
            path="/telecaller"
            element={<RoleGate allow={['SUPER_ADMIN', 'ADMIN', 'TELECALLER']}><TelecallerPage /></RoleGate>}
          />
          <Route
            path="/employees"
            element={<RoleGate allow={['SUPER_ADMIN', 'ADMIN']}><EmployeesPage /></RoleGate>}
          />
          <Route
            path="/clients"
            element={<RoleGate allow={['SUPER_ADMIN', 'ADMIN']}><ClientsPage /></RoleGate>}
          />
        </Route>

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>

      <CommandPalette />
      <ShortcutsOverlay />
      <ToastHost />
    </>
  );
}
