import 'package:flutter/material.dart';
import 'rive_animation.dart';

/// Bestie — 36 premium Rive animation slots, mirroring the React catalog
/// (frontend/react_web/src/components/ui/RiveSlot.tsx).
///
/// Each entry maps a logical name to an asset key. Drop a `.riv` file at
/// `assets/rive/<key>.riv` in the consuming app and add it to the app's
/// `pubspec.yaml` under `flutter > assets`. Until then, [BestieRive] renders
/// its gradient-blob fallback automatically.
///
/// Use:
///   BestieRiveSlot(slot: BestieRiveSlots.taskCompleted, size: 120)
///   BestieRiveSlot(slot: 'empty.tasks')
///
/// The string form lets you pass the same key strings the web uses without
/// importing the enum on both sides.
class BestieRiveSlots {
  // ---- auth flow ----
  static const authLoginCelebrate = 'auth.login_celebrate';
  static const authLoginError     = 'auth.login_error';
  static const authWelcome        = 'auth.welcome';
  static const authOnboarding     = 'auth.onboarding';

  // ---- empty states ----
  static const emptyInbox         = 'empty.inbox';
  static const emptyTasks         = 'empty.tasks';
  static const emptyChannels      = 'empty.channels';
  static const emptySearch        = 'empty.search';
  static const emptyCalendar      = 'empty.calendar';
  static const emptyMeetings      = 'empty.meetings';
  static const emptyNotifications = 'empty.notifications';
  static const emptyFiles         = 'empty.files';
  static const emptyClients       = 'empty.clients';
  static const emptyLeaderboard   = 'empty.leaderboard';

  // ---- task lifecycle ----
  static const taskCreated        = 'task.created';
  static const taskAccepted       = 'task.accepted';
  static const taskCompleted      = 'task.completed';
  static const taskDeclined       = 'task.declined';
  static const taskOverdue        = 'task.overdue';

  // ---- score celebrations ----
  static const scorePerfect       = 'score.perfect';
  static const scoreGreat         = 'score.great';
  static const scoreGood          = 'score.good';
  static const scoreLate          = 'score.late';
  static const scoreStreak        = 'score.streak';

  // ---- leaderboard / gamification ----
  static const trophyGold         = 'trophy.gold';
  static const trophySilver       = 'trophy.silver';
  static const trophyBronze       = 'trophy.bronze';

  // ---- communication ----
  static const chatTyping         = 'chat.typing';
  static const chatSent           = 'chat.sent';
  static const chatReaction       = 'chat.reaction';
  static const notifyPing         = 'notify.ping';

  // ---- calls / meetings ----
  static const callRinging        = 'call.ringing';
  static const callConnected      = 'call.connected';
  static const callMuted          = 'call.muted';
  static const callScreenShare    = 'call.screen_share';

  // ---- presence ----
  static const presenceActive     = 'presence.active';
  static const presenceAway       = 'presence.away';
  static const presenceBusy       = 'presence.busy';
  static const presenceInMeeting  = 'presence.in_meeting';

  // ---- system / ambient ----
  static const loadingWorkspace   = 'loading.workspace';
  static const connectionOffline  = 'connection.offline';
  static const uploadInFlight     = 'upload.in_flight';
  static const aiThinking         = 'ai.thinking';
  static const confettiBurst      = 'confetti.burst';

  /// Maps a slot name to the asset path the [BestieRive] widget should load.
  static String assetPathFor(String slot) =>
      'assets/rive/${slot.replaceAll('.', '_')}.riv';

  /// Full list — handy when generating a sprite sheet preview or running
  /// integration tests that verify every asset ships.
  static const all = <String>[
    authLoginCelebrate, authLoginError, authWelcome, authOnboarding,
    emptyInbox, emptyTasks, emptyChannels, emptySearch, emptyCalendar,
    emptyMeetings, emptyNotifications, emptyFiles, emptyClients, emptyLeaderboard,
    taskCreated, taskAccepted, taskCompleted, taskDeclined, taskOverdue,
    scorePerfect, scoreGreat, scoreGood, scoreLate, scoreStreak,
    trophyGold, trophySilver, trophyBronze,
    chatTyping, chatSent, chatReaction, notifyPing,
    callRinging, callConnected, callMuted, callScreenShare,
    presenceActive, presenceAway, presenceBusy, presenceInMeeting,
    loadingWorkspace, connectionOffline, uploadInFlight, aiThinking, confettiBurst,
  ];
}

class BestieRiveSlot extends StatelessWidget {
  final String slot;
  final double size;
  final String? stateMachine;
  final Widget? fallback;
  const BestieRiveSlot({
    super.key,
    required this.slot,
    this.size = 160,
    this.stateMachine,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return BestieRive(
      asset: BestieRiveSlots.assetPathFor(slot),
      stateMachine: stateMachine,
      width: size,
      height: size,
      fallback: fallback,
    );
  }
}
