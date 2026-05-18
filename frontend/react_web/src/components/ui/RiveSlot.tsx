import { RiveAnimation } from './RiveAnimation';

/**
 * Named Rive animation slots — 36 premium animations the design system can
 * call into by name. Each slot maps to a path under `public/rive/`. Until a
 * `.riv` file is dropped at that path, the gradient-blob fallback from
 * `<RiveAnimation>` renders so layouts stay intentional.
 *
 * Adding a new slot: append it to `RIVE_SLOTS`, then save the file to
 * `frontend/react_web/public/rive/<slot-name>.riv`. Same name → it lights
 * up automatically.
 *
 * Use:
 *   <RiveSlot name="task.completed" size={120} />
 *   <RiveSlot name="empty.tasks" />
 *
 * The Flutter app (frontend/flutter_apps/shared_design_system/lib/src/widgets/rive_slots.dart)
 * mirrors this catalog name-for-name so the same animation works everywhere.
 */
export const RIVE_SLOTS = {
  // ---- auth flow ----
  'auth.login_celebrate':   '/rive/auth_login_celebrate.riv',
  'auth.login_error':       '/rive/auth_login_error.riv',
  'auth.welcome':           '/rive/auth_welcome.riv',
  'auth.onboarding':        '/rive/auth_onboarding.riv',

  // ---- empty states ----
  'empty.inbox':            '/rive/empty_inbox.riv',
  'empty.tasks':            '/rive/empty_tasks.riv',
  'empty.channels':         '/rive/empty_channels.riv',
  'empty.search':           '/rive/empty_search.riv',
  'empty.calendar':         '/rive/empty_calendar.riv',
  'empty.meetings':         '/rive/empty_meetings.riv',
  'empty.notifications':    '/rive/empty_notifications.riv',
  'empty.files':            '/rive/empty_files.riv',
  'empty.clients':          '/rive/empty_clients.riv',
  'empty.leaderboard':      '/rive/empty_leaderboard.riv',

  // ---- task lifecycle ----
  'task.created':           '/rive/task_created.riv',
  'task.accepted':          '/rive/task_accepted.riv',
  'task.completed':         '/rive/task_completed.riv',
  'task.declined':          '/rive/task_declined.riv',
  'task.overdue':           '/rive/task_overdue.riv',

  // ---- score celebrations ----
  'score.perfect':          '/rive/score_perfect.riv',    // 100
  'score.great':            '/rive/score_great.riv',      // 80–99
  'score.good':             '/rive/score_good.riv',       // 60–79
  'score.late':             '/rive/score_late.riv',       // <60
  'score.streak':           '/rive/score_streak.riv',     // streak milestone

  // ---- leaderboard / gamification ----
  'trophy.gold':            '/rive/trophy_gold.riv',
  'trophy.silver':          '/rive/trophy_silver.riv',
  'trophy.bronze':          '/rive/trophy_bronze.riv',

  // ---- communication ----
  'chat.typing':            '/rive/chat_typing.riv',
  'chat.sent':              '/rive/chat_sent.riv',
  'chat.reaction':          '/rive/chat_reaction.riv',
  'notify.ping':            '/rive/notify_ping.riv',

  // ---- calls / meetings ----
  'call.ringing':           '/rive/call_ringing.riv',
  'call.connected':         '/rive/call_connected.riv',
  'call.muted':             '/rive/call_muted.riv',
  'call.screen_share':      '/rive/call_screen_share.riv',

  // ---- presence ----
  'presence.active':        '/rive/presence_active.riv',
  'presence.away':          '/rive/presence_away.riv',
  'presence.busy':          '/rive/presence_busy.riv',
  'presence.in_meeting':    '/rive/presence_in_meeting.riv',

  // ---- system / ambient ----
  'loading.workspace':      '/rive/loading_workspace.riv',
  'connection.offline':     '/rive/connection_offline.riv',
  'upload.in_flight':       '/rive/upload_in_flight.riv',
  'ai.thinking':            '/rive/ai_thinking.riv',
  'confetti.burst':         '/rive/confetti_burst.riv',
} as const;

export type RiveSlotName = keyof typeof RIVE_SLOTS;

interface RiveSlotProps {
  name: RiveSlotName;
  size?: number;
  stateMachine?: string;
  /** Custom fallback when the .riv file isn't shipped yet. */
  fallback?: React.ReactNode;
  className?: string;
}

/**
 * One-line component: `<RiveSlot name="task.completed" />`. Resolves the
 * path from the catalog and hands off to `<RiveAnimation>`. Designers can
 * drop a new .riv file into `public/rive/` and it lights up everywhere
 * the slot is used.
 */
export function RiveSlot({ name, size = 160, stateMachine, fallback, className }: RiveSlotProps) {
  return (
    <RiveAnimation
      src={RIVE_SLOTS[name]}
      width={size}
      height={size}
      stateMachine={stateMachine}
      fallback={fallback}
      className={className}
    />
  );
}
