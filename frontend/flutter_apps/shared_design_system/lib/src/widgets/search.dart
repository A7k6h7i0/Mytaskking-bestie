import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../colors.dart';
import '../tokens.dart';
import 'avatar.dart';
import 'user_name.dart';
import 'primitives.dart';

/// Premium dynamic-search screen — mirrors the React command palette.
///
/// Supports filter chips (All / People / Messages / Files / Channels / Tasks),
/// per-kind rich rows, recent-search persistence, and inline filter syntax
/// (`from:`, `in:`, `type:`). All visual decisions flow from BestieTokens so
/// the screen renders identically in light + dark.
///
/// Backend search is wired through callbacks so this widget stays decoupled
/// from a specific HTTP/Riverpod stack — `mytaskking_core` providers in the
/// mobile/desktop apps pass closures to fetch + scope-by-kind.
typedef BestieSearchFetcher = Future<Map<String, dynamic>> Function(String query, String? kind);

class BestieSearchScreen extends StatefulWidget {
  final BestieSearchFetcher fetcher;

  /// Called when the user opens a result. Receives the row's category
  /// (`users`, `messages`, `files`, `channels`, `tasks`, `leads`) and the
  /// raw JSON object from the search endpoint. The host app routes to the
  /// right screen (chat detail, file viewer, etc.).
  final void Function(String kind, Map<String, dynamic> item) onOpen;

  /// Optional initial query — useful for deep-linking.
  final String? initialQuery;

  /// Optional initial kind filter (`messages`, `files`, etc).
  final String? initialKind;

  /// Optional back-button handler. Defaults to `Navigator.maybePop` which
  /// doesn't always work when the search route was opened via go_router's
  /// top-level navigation — host apps should pass a go_router-aware
  /// closure so the back arrow always returns the user somewhere sane.
  final VoidCallback? onBack;

  const BestieSearchScreen({
    super.key,
    required this.fetcher,
    required this.onOpen,
    this.initialQuery,
    this.initialKind,
    this.onBack,
  });

  @override
  State<BestieSearchScreen> createState() => _BestieSearchScreenState();
}

class _BestieSearchScreenState extends State<BestieSearchScreen> {
  static const _recentKey = 'bestie.search.recents';
  static const _recentMax = 8;
  static const _kindOrder = ['users', 'messages', 'files', 'channels', 'tasks', 'leads'];

  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  String? _activeKind;
  String _term = '';
  Map<String, List<dynamic>> _results = const {};
  bool _loading = false;
  List<String> _recents = const [];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery ?? '');
    _activeKind = widget.initialKind;
    _term = _ctrl.text;
    _ctrl.addListener(_onTextChanged);
    _loadRecents();
    if (_ctrl.text.trim().isNotEmpty) _scheduleFetch();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    if (_term == _ctrl.text) return;
    setState(() => _term = _ctrl.text);
    _scheduleFetch();
  }

  void _scheduleFetch() {
    _debounce?.cancel();
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() { _results = const {}; _loading = false; });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final res = await widget.fetcher(q, _activeKind);
        if (!mounted) return;
        final raw = (res['results'] as Map?) ?? const {};
        final mapped = <String, List<dynamic>>{};
        raw.forEach((k, v) {
          mapped[k.toString()] = (v as List?)?.cast<dynamic>() ?? const [];
        });
        setState(() { _results = mapped; _loading = false; });
      } catch (_) {
        if (!mounted) return;
        setState(() { _results = const {}; _loading = false; });
      }
    });
  }

  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recentKey);
      if (raw == null) return;
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        setState(() => _recents = parsed.whereType<String>().take(_recentMax).toList());
      }
    } catch (_) { /* ignore corrupt cache */ }
  }

  Future<void> _pushRecent(String q) async {
    if (q.trim().isEmpty) return;
    final next = [q, ..._recents.where((r) => r != q)].take(_recentMax).toList();
    setState(() => _recents = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentKey, jsonEncode(next));
    } catch (_) { /* ignore quota */ }
  }

  Future<void> _clearRecents() async {
    setState(() => _recents = const []);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentKey);
    } catch (_) { /* ignore */ }
  }

  void _setKind(String? k) {
    if (_activeKind == k) return;
    setState(() => _activeKind = k);
    if (_term.trim().isNotEmpty) _scheduleFetch();
  }

  void _scopeToPerson(Map<String, dynamic> user) {
    final handle = (user['userId'] ?? '').toString().isNotEmpty
        ? user['userId'].toString()
        : (user['name'] ?? '').toString().split(' ').first;
    _ctrl.text = 'from:$handle ';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    _setKind('messages');
    _focus.requestFocus();
  }

  void _open(String kind, Map<String, dynamic> item) {
    _pushRecent(_term);
    widget.onOpen(kind, item);
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final flat = <_FlatHit>[];
    for (final kind in _kindOrder) {
      for (final item in _results[kind] ?? const []) {
        flat.add(_FlatHit(kind, item as Map<String, dynamic>));
      }
    }
    final showRecents = _term.trim().isEmpty && _recents.isNotEmpty;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _SearchBar(
        controller: _ctrl,
        focusNode: _focus,
        onClear: () { _ctrl.clear(); _focus.requestFocus(); },
        onClose: widget.onBack ?? () => Navigator.of(context).maybePop(),
      ),
      body: Column(
        children: [
          _Chips(active: _activeKind, results: _results, total: flat.length, onChange: _setKind),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _buildBody(
                key: ValueKey('${_term.isEmpty}-${_loading && flat.isEmpty}-${flat.length}'),
                flat: flat,
                showRecents: showRecents,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required Key key,
    required List<_FlatHit> flat,
    required bool showRecents,
  }) {
    if (_loading && flat.isEmpty) return _LoadingDots(key: key);
    if (_term.trim().isNotEmpty && flat.isEmpty) return _EmptyState(key: key);

    return ListView(
      key: key,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      children: [
        if (showRecents) _RecentSection(recents: _recents, onPick: (q) {
          _ctrl.text = q;
          _ctrl.selection = TextSelection.collapsed(offset: q.length);
          _focus.requestFocus();
        }, onClear: _clearRecents),
        ..._buildGroups(flat),
      ],
    );
  }

  List<Widget> _buildGroups(List<_FlatHit> flat) {
    final out = <Widget>[];
    for (final kind in _kindOrder) {
      final hits = flat.where((h) => h.kind == kind).toList();
      if (hits.isEmpty) continue;
      out.add(_GroupHeader(kind: kind));
      for (final h in hits) {
        out.add(_HitRow(
          kind: h.kind,
          item: h.item,
          term: _term,
          onOpen: () => _open(h.kind, h.item),
          onScopeToPerson: h.kind == 'users' ? () => _scopeToPerson(h.item) : null,
        ));
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Search bar (custom app bar)
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;
  final VoidCallback onClose;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClear,
    required this.onClose,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return SafeArea(
      bottom: false,
      child: Container(
        height: 64,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(bottom: BorderSide(color: c.border.withOpacity(0.7))),
        ),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            color: c.textSoft,
            tooltip: 'Back',
            onPressed: onClose,
          ),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (ctx, v, _) => TextField(
                controller: controller,
                focusNode: focusNode,
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: c.brand,
                textInputAction: TextInputAction.search,
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: BestieTokens.fwMedium,
                  letterSpacing: BestieTokens.lsNormal,
                  color: c.text,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  // Search glyph lives on the right now — either as a passive
                  // affordance when the field is empty or as the active
                  // "clear" button when there's text to wipe.
                  suffixIcon: v.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: c.textMuted,
                          tooltip: 'Clear',
                          onPressed: onClear,
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(Icons.search_rounded,
                              size: 20, color: c.textMuted),
                        ),
                  hintText: 'Search people, messages, files…',
                  hintStyle: TextStyle(
                    color: c.textMuted,
                    fontWeight: BestieTokens.fwRegular,
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(8, 12, 0, 12),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chips
// ---------------------------------------------------------------------------

class _Chip {
  final String? value;
  final String label;
  final IconData icon;
  const _Chip(this.value, this.label, this.icon);
}

const _chips = <_Chip>[
  _Chip(null,        'All',      Icons.search_rounded),
  _Chip('users',     'People',   Icons.alternate_email_rounded),
  _Chip('messages',  'Messages', Icons.chat_bubble_outline_rounded),
  _Chip('files',     'Files',    Icons.description_outlined),
  _Chip('channels',  'Channels', Icons.tag_rounded),
  _Chip('tasks',     'Tasks',    Icons.task_alt_outlined),
];

class _Chips extends StatelessWidget {
  final String? active;
  final Map<String, List<dynamic>> results;
  final int total;
  final ValueChanged<String?> onChange;

  const _Chips({required this.active, required this.results, required this.total, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border.withOpacity(0.7))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: _chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final chip = _chips[i];
          final isActive = active == chip.value;
          final count = chip.value == null ? total : (results[chip.value]?.length ?? 0);
          final showCount = total > 0 && count > 0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: BestieTokens.easeOut,
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.brand.withOpacity(0.18),
                        colors.accent.withOpacity(0.10),
                      ],
                    )
                  : null,
              color: isActive ? null : colors.surface2,
              borderRadius: BorderRadius.circular(BestieTokens.rPill),
              border: Border.all(
                color: isActive
                    ? colors.brand.withOpacity(0.30)
                    : colors.border.withOpacity(0.7),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
                onTap: () => onChange(chip.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(chip.icon, size: 14, color: isActive ? colors.brandStrong : colors.textSoft),
                      const SizedBox(width: 6),
                      Text(
                        chip.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: BestieTokens.fwSemibold,
                          color: isActive ? colors.brandStrong : colors.textSoft,
                          letterSpacing: BestieTokens.lsNormal,
                        ),
                      ),
                      if (showCount) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isActive
                                ? colors.brand.withOpacity(0.22)
                                : colors.text.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(BestieTokens.rPill),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: BestieTokens.fwBold,
                              color: isActive ? colors.brandStrong : colors.textSoft,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hint, recents, empty, loading
// ---------------------------------------------------------------------------

class _RecentSection extends StatelessWidget {
  final List<String> recents;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;

  const _RecentSection({required this.recents, required this.onPick, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
        child: Row(children: [
          Icon(Icons.history_rounded, size: 13, color: c.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('RECENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: BestieTokens.fwBold,
                  letterSpacing: BestieTokens.lsEyebrow,
                  color: c.textMuted,
                )),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: c.textMuted,
              textStyle: const TextStyle(fontSize: 10, fontWeight: BestieTokens.fwSemibold, letterSpacing: BestieTokens.lsWide),
            ),
            child: const Text('CLEAR'),
          ),
        ]),
      ),
      for (final r in recents)
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(BestieTokens.rSm),
            onTap: () => onPick(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Icon(Icons.search_rounded, size: 14, color: c.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: c.textSoft,
                      fontWeight: BestieTokens.fwMedium,
                    ),
                  ),
                ),
                Icon(Icons.north_west_rounded, size: 14, color: c.textFaint),
              ]),
            ),
          ),
        ),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BestieEmptyState(
        icon: Icons.filter_alt_outlined,
        title: 'No matches',
        description: 'Try a different word, or remove a from: / type: filter.',
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots({super.key});
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final t = _ctrl.value;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = ((t + i * 0.16) % 1.0);
              final opacity = (0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2)).clamp(0.2, 1.0);
              final brand = BestieColors.of(context).brand;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group header + hit row
// ---------------------------------------------------------------------------

class _FlatHit {
  final String kind;
  final Map<String, dynamic> item;
  const _FlatHit(this.kind, this.item);
}

class _GroupHeader extends StatelessWidget {
  final String kind;
  const _GroupHeader({required this.kind});

  static const _labels = {
    'users':    'PEOPLE',
    'channels': 'CHANNELS',
    'tasks':    'TASKS',
    'messages': 'MESSAGES',
    'files':    'FILES',
    'leads':    'LEADS',
  };
  static const _icons = {
    'users':    Icons.alternate_email_rounded,
    'channels': Icons.tag_rounded,
    'tasks':    Icons.task_alt_outlined,
    'messages': Icons.chat_bubble_outline_rounded,
    'files':    Icons.description_outlined,
    'leads':    Icons.headset_mic_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 6),
      child: Row(children: [
        Icon(_icons[kind] ?? Icons.tune_rounded, size: 13, color: c.textMuted),
        const SizedBox(width: 6),
        Text(
          _labels[kind] ?? kind.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: BestieTokens.fwBold,
            color: c.textMuted,
            letterSpacing: BestieTokens.lsEyebrow,
          ),
        ),
      ]),
    );
  }
}

class _HitRow extends StatelessWidget {
  final String kind;
  final Map<String, dynamic> item;
  final String term;
  final VoidCallback onOpen;
  final VoidCallback? onScopeToPerson;

  const _HitRow({
    required this.kind,
    required this.item,
    required this.term,
    required this.onOpen,
    this.onScopeToPerson,
  });

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    Widget child;
    switch (kind) {
      case 'users':    child = _personRow(c); break;
      case 'messages': child = _messageRow(c); break;
      case 'files':    child = _fileRow(c);    break;
      case 'channels': child = _compactRow(c, Icons.tag_rounded,
        (item['name'] ?? 'Direct message').toString(),
        item['description']?.toString() ?? (item['kind']?.toString() ?? ''),
        isClient: item['isClientChannel'] == true);
        break;
      case 'tasks':    child = _compactRow(c, Icons.task_alt_outlined,
        (item['title'] ?? '').toString(),
        (item['status'] ?? '').toString(),
        meta: item['dueAt'] != null ? _ago(DateTime.tryParse(item['dueAt'].toString())) : null);
        break;
      case 'leads':    child = _compactRow(c, Icons.headset_mic_outlined,
        (item['name'] ?? '').toString(),
        '${item['company'] ?? 'No company'} · ${item['phone'] ?? ''}',
        meta: item['status']?.toString());
        break;
      default:         child = _compactRow(c, Icons.search_rounded, item.toString(), null);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BestieTokens.rSm),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  // ----- person row -----
  Widget _personRow(BestieColors c) {
    final name = (item['name'] ?? '').toString();
    final role = (item['customTitle'] ?? '').toString().isNotEmpty
        ? item['customTitle'].toString()
        : (item['role'] ?? '').toString().replaceAll('_', ' ').toLowerCase();
    final isClient = item['isClient'] == true;
    final lastSeen = item['lastSeenAt'] != null
        ? 'active ${_ago(DateTime.tryParse(item['lastSeenAt'].toString()))}'
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BestieAvatar(
          name: name,
          imageUrl: item['avatarUrl']?.toString(),
          isClient: isClient,
          size: 36,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              BestieUserName(
                name: name,
                isClient: isClient,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: BestieTokens.fwSemibold,
                  letterSpacing: BestieTokens.lsSnug,
                ),
              ),
              if (role.isNotEmpty)
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: c.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (lastSeen != null) ...[
          const SizedBox(width: 8),
          Text(lastSeen,
              style: TextStyle(fontSize: 11, color: c.textFaint)),
        ],
        if (onScopeToPerson != null) ...[
          const SizedBox(width: 8),
          _ScopeButton(onPressed: onScopeToPerson!),
        ],
      ],
    );
  }

  // ----- message row -----
  Widget _messageRow(BestieColors c) {
    final author = (item['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    final channel = (item['channel'] as Map?)?.cast<String, dynamic>() ?? const {};
    final attachments = (item['attachments'] as List?) ?? const [];
    final body = (item['body'] ?? (attachments.isNotEmpty ? '(attachment)' : '')).toString();
    final time = _ago(DateTime.tryParse(item['createdAt']?.toString() ?? ''));
    final authorName = (author['name'] ?? 'Unknown').toString();
    final isClientAuthor = author['isClient'] == true;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BestieAvatar(
          name: authorName,
          imageUrl: author['avatarUrl']?.toString(),
          isClient: isClientAuthor,
          size: 32,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Flexible(
                  child: BestieUserName(
                    name: authorName,
                    isClient: isClientAuthor,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: BestieTokens.fwBold,
                      letterSpacing: BestieTokens.lsSnug,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '#${channel['name'] ?? 'dm'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.brand,
                      fontWeight: BestieTokens.fwSemibold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (time.isNotEmpty) ...[
                  const Spacer(),
                  Text(time,
                      style: TextStyle(fontSize: 11, color: c.textFaint)),
                ],
              ]),
              const SizedBox(height: 3),
              _Snippet(text: body, term: term, maxLines: 2),
              if (attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(BestieTokens.rPill),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.attach_file_rounded, size: 11, color: c.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        '${attachments.length}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: BestieTokens.fwBold,
                          color: c.textMuted,
                        ),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ----- file row -----
  Widget _fileRow(BestieColors c) {
    final mime = (item['mimeType'] ?? '').toString();
    final name = (item['originalName'] ?? 'file').toString();
    final size = (item['size'] as num?)?.toInt();
    final uploader = (item['uploadedBy'] as Map?)?.cast<String, dynamic>() ?? const {};
    final firstMsg = ((item['messages'] as List?) ?? const []).cast<dynamic>().isEmpty
        ? null
        : ((item['messages'] as List).first as Map?)?.cast<String, dynamic>();
    final channel = firstMsg != null
        ? (firstMsg['channel'] as Map?)?.cast<String, dynamic>() ?? const {}
        : const {};
    final isImage = mime.startsWith('image/');
    final thumb = item['previewUrl']?.toString() ?? (isImage ? item['url']?.toString() : null);
    final icon = _fileIcon(mime);

    final subParts = <String>[];
    if (uploader['name'] != null) subParts.add('shared by ${uploader['name']}');
    if (channel['name'] != null)  subParts.add('in #${channel['name']}');
    final sub = subParts.isEmpty ? mime : subParts.join(' · ');
    final metaParts = <String>[
      if (mime.isNotEmpty) mime,
      if (size != null) _formatBytes(size),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(BestieTokens.rSm),
          ),
          clipBehavior: Clip.antiAlias,
          child: thumb != null
              ? Image.network(thumb, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(icon, size: 18, color: c.textSoft))
              : Icon(icon, size: 18, color: c.textSoft),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HighlightedText(
                text: name,
                term: term,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: BestieTokens.fwSemibold,
                  color: c.text,
                  letterSpacing: BestieTokens.lsSnug,
                ),
                maxLines: 1,
              ),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.textMuted)),
            ],
          ),
        ),
        if (metaParts.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(BestieTokens.rXs),
            ),
            child: Text(
              metaParts.join(' · '),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: c.textSoft,
                fontWeight: BestieTokens.fwSemibold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _compactRow(BestieColors c, IconData icon, String label, String? sub, {String? meta, bool isClient = false}) {
    return Row(children: [
      Icon(icon, size: 16, color: c.textSoft),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HighlightedText(
              text: label,
              term: term,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: BestieTokens.fwSemibold,
                color: isClient ? c.client : c.text,
                letterSpacing: BestieTokens.lsSnug,
              ),
              maxLines: 1,
            ),
            if (sub != null && sub.isNotEmpty)
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.textMuted)),
          ],
        ),
      ),
      if (meta != null && meta.isNotEmpty) ...[
        const SizedBox(width: 8),
        Text(meta, style: TextStyle(fontSize: 11, color: c.textFaint)),
      ],
    ]);
  }
}

class _ScopeButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ScopeButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rPill),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.borderStrong),
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.filter_alt_outlined, size: 12, color: c.textSoft),
            const SizedBox(width: 4),
            Text(
              'messages',
              style: TextStyle(
                fontSize: 11,
                fontWeight: BestieTokens.fwSemibold,
                color: c.textSoft,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Snippet extends StatelessWidget {
  final String text;
  final String term;
  final int maxLines;
  const _Snippet({required this.text, required this.term, required this.maxLines});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return _HighlightedText(
      text: text,
      term: term,
      style: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: c.textSoft,
      ),
      maxLines: maxLines,
    );
  }
}

/// Inline highlight — finds the term inside text and wraps the match in a
/// brand-tinted underline span. Safe (no HTML / interpolation).
class _HighlightedText extends StatelessWidget {
  final String text;
  final String term;
  final TextStyle style;
  final int maxLines;

  const _HighlightedText({
    required this.text,
    required this.term,
    required this.style,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final cleanedTerm = _termWithoutFilters(term).trim();
    if (cleanedTerm.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final lc = text.toLowerCase();
    final lcTerm = cleanedTerm.toLowerCase();
    final idx = lc.indexOf(lcTerm);
    if (idx == -1) {
      return Text(text, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: style, children: [
        TextSpan(text: text.substring(0, idx)),
        TextSpan(
          text: text.substring(idx, idx + cleanedTerm.length),
          style: style.copyWith(
            background: Paint()
              ..color = c.warning.withOpacity(0.35)
              ..strokeWidth = 0,
            fontWeight: BestieTokens.fwBold,
            color: c.text,
          ),
        ),
        TextSpan(text: text.substring(idx + cleanedTerm.length)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

String _termWithoutFilters(String raw) {
  return raw.replaceAll(RegExp(r'(?:from|in|type):(?:"[^"]+"|\S+)\s*', caseSensitive: false), '').trim();
}

String _formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
}

IconData _fileIcon(String mime) {
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (mime.contains('pdf'))      return Icons.picture_as_pdf_outlined;
  if (mime.contains('sheet') || mime.contains('csv') || mime.contains('excel')) {
    return Icons.table_chart_outlined;
  }
  if (mime.contains('zip') || mime.contains('rar') || mime.contains('compressed')) {
    return Icons.folder_zip_outlined;
  }
  return Icons.description_outlined;
}

const _monthAbbrev = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

String _ago(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24)   return '${diff.inHours}h ago';
  if (diff.inDays < 7)     return '${diff.inDays}d ago';
  return '${_monthAbbrev[dt.month - 1]} ${dt.day}';
}
