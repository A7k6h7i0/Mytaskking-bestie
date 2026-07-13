import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../colors.dart';
import '../tokens.dart';
import 'avatar.dart';
import 'user_name.dart';
import 'primitives.dart';

/// Mode of the picker — single person → DM, multiple people + name → group.
enum BestieNewChatMode { dm, group }

/// Callbacks that surface user actions back to the host (which talks to the
/// API and routes). Stays decoupled from Riverpod/Dio so the sheet ships in
/// the shared design system.
typedef BestieEmployeeFetcher =
    Future<List<Map<String, dynamic>>> Function(String query);
typedef BestieStartDm = Future<Map<String, dynamic>?> Function(String userId);
typedef BestieStartGroup =
    Future<Map<String, dynamic>?> Function(
      String name,
      List<String> memberIds, {
      String? iconUrl,
    });
typedef BestiePickGroupIcon = Future<String?> Function();
typedef BestieStartCall =
    Future<void> Function(Map<String, dynamic> user, String mode);

/// Premium new-chat composer. Surfaces a tabbed bottom sheet that lets the
/// user start a 1:1 DM or assemble a group chat with multiple teammates.
/// All channel kinds for *external clients* live elsewhere — this sheet is
/// scoped to internal employee conversations.
Future<Map<String, dynamic>?> showBestieNewChatSheet(
  BuildContext context, {
  required BestieEmployeeFetcher fetchEmployees,
  required BestieStartDm onStartDm,
  required BestieStartGroup onStartGroup,
  BestieStartCall? onStartCall,
  String? currentUserId,
  int initialTabIndex = 0,
  BestiePickGroupIcon? pickGroupIcon,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _NewChatSheet(
      fetchEmployees: fetchEmployees,
      onStartDm: onStartDm,
      onStartGroup: onStartGroup,
      onStartCall: onStartCall,
      currentUserId: currentUserId,
      initialTabIndex: initialTabIndex,
      pickGroupIcon: pickGroupIcon,
    ),
  );
}

class _NewChatSheet extends StatefulWidget {
  final BestieEmployeeFetcher fetchEmployees;
  final BestieStartDm onStartDm;
  final BestieStartGroup onStartGroup;
  final BestieStartCall? onStartCall;
  final String? currentUserId;
  final int initialTabIndex;
  final BestiePickGroupIcon? pickGroupIcon;

  const _NewChatSheet({
    required this.fetchEmployees,
    required this.onStartDm,
    required this.onStartGroup,
    this.onStartCall,
    this.currentUserId,
    this.initialTabIndex = 0,
    this.pickGroupIcon,
  });

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTabIndex.clamp(0, 1),
  );
  final _searchCtrl = TextEditingController();
  final _groupNameCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _employees = const [];
  final Set<String> _selected = {};
  bool _submitting = false;
  String? _groupIconUrl;

  @override
  void initState() {
    super.initState();
    _fetch('');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _groupNameCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetch(String q) async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final res = await widget.fetchEmployees(q);
        if (!mounted) return;
        setState(() {
          _employees = res
              .where(
                (e) =>
                    widget.currentUserId == null ||
                    e['id'] != widget.currentUserId,
              )
              .toList();
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    });
  }

  Future<void> _startDm(Map<String, dynamic> user) async {
    setState(() => _submitting = true);
    try {
      final channel = await widget.onStartDm(user['id'] as String);
      if (!mounted) return;
      Navigator.of(context).pop(channel);
    } catch (e) {
      if (!mounted) return;
      bestieToast(
        context,
        'Could not start chat',
        body: e.toString(),
        kind: BestieToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _startGroup() async {
    if (_selected.isEmpty) return;
    final name = _groupNameCtrl.text.trim();
    if (name.isEmpty) {
      bestieToast(
        context,
        'Group needs a name',
        body: 'Give it a short, descriptive title.',
        kind: BestieToastKind.warning,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final channel = await widget.onStartGroup(
        name,
        _selected.toList(),
        iconUrl: _groupIconUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop(channel);
    } catch (e) {
      if (!mounted) return;
      bestieToast(
        context,
        'Could not create group',
        body: e.toString(),
        kind: BestieToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(BestieTokens.rXl),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // drag handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.borderStrong,
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'New chat',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: BestieTokens.fwBold,
                        letterSpacing: BestieTokens.lsTight,
                        color: c.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded, color: c.textMuted),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: c.brand,
              unselectedLabelColor: c.textMuted,
              indicatorColor: c.brand,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: c.border,
              labelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: BestieTokens.fwSemibold,
                letterSpacing: BestieTokens.lsSnug,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  text: 'Direct message',
                ),
                Tab(
                  icon: Icon(Icons.groups_outlined, size: 18),
                  text: 'New group',
                ),
              ],
            ),
            _SearchField(controller: _searchCtrl, onChanged: _fetch, colors: c),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _PeopleList(
                    scrollCtrl: scrollCtrl,
                    loading: _loading,
                    error: _error,
                    employees: _employees,
                    selectable: false,
                    selected: _selected,
                    onTap: _submitting ? null : _startDm,
                    onCall: widget.onStartCall,
                  ),
                  _PeopleList(
                    scrollCtrl: scrollCtrl,
                    loading: _loading,
                    error: _error,
                    employees: _employees,
                    selectable: true,
                    selected: _selected,
                    onToggle: (id) => setState(() {
                      _selected.contains(id)
                          ? _selected.remove(id)
                          : _selected.add(id);
                    }),
                  ),
                ],
              ),
            ),
            if (_tabs.index == 1 || _selected.isNotEmpty)
              AnimatedBuilder(
                animation: _tabs,
                builder: (ctx, _) => _tabs.index == 1
                    ? _GroupFooter(
                        colors: c,
                        nameCtrl: _groupNameCtrl,
                        selectedCount: _selected.length,
                        submitting: _submitting,
                        iconUrl: _groupIconUrl,
                        onPickIcon: widget.pickGroupIcon == null
                            ? null
                            : () async {
                                final url = await widget.pickGroupIcon!();
                                if (url != null && mounted) {
                                  setState(() => _groupIconUrl = url);
                                }
                              },
                        onSubmit: _startGroup,
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final BestieColors colors;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [LengthLimitingTextInputFormatter(120)],
        style: TextStyle(color: colors.text, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colors.textMuted,
            size: 18,
          ),
          hintText: 'Search teammates by name or @userid',
          hintStyle: TextStyle(
            color: colors.textMuted,
            fontWeight: BestieTokens.fwRegular,
          ),
          filled: true,
          fillColor: colors.surface2,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BestieTokens.rSm),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BestieTokens.rSm),
            borderSide: const BorderSide(
              color: BestieTokens.cBrand,
              width: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _PeopleList extends StatelessWidget {
  final ScrollController scrollCtrl;
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> employees;
  final bool selectable;
  final Set<String> selected;
  final void Function(Map<String, dynamic>)? onTap;
  final void Function(String id)? onToggle;
  final BestieStartCall? onCall;

  const _PeopleList({
    required this.scrollCtrl,
    required this.loading,
    required this.error,
    required this.employees,
    required this.selectable,
    required this.selected,
    this.onTap,
    this.onToggle,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    if (loading && employees.isEmpty) {
      return ListView(
        controller: scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120, child: Center(child: BestieSpinner())),
        ],
      );
    }
    if (error != null && employees.isEmpty) {
      return ListView(
        controller: scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          BestieEmptyState(
            icon: Icons.error_outline_rounded,
            iconColor: c.danger,
            title: 'Could not load teammates',
            description: error,
          ),
        ],
      );
    }
    if (employees.isEmpty) {
      return ListView(
        controller: scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        children: const [
          BestieEmptyState(
            icon: Icons.person_search_rounded,
            title: 'No teammates match',
            description: 'Try a different name or @userid.',
          ),
        ],
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      itemCount: employees.length,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemBuilder: (ctx, i) {
        final u = employees[i];
        final id = u['id'] as String;
        final name = (u['name'] ?? '—').toString();
        final isClient = u['isClient'] == true;
        final role = (u['customTitle'] ?? u['role'] ?? '')
            .toString()
            .replaceAll('_', ' ');
        final isSelected = selected.contains(id);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(BestieTokens.rSm),
            onTap: selectable ? () => onToggle?.call(id) : () => onTap?.call(u),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  BestieAvatar(
                    name: name,
                    imageUrl: u['avatarUrl']?.toString(),
                    isClient: isClient,
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BestieUserName(
                          name: name,
                          isClient: isClient,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: BestieTokens.fwSemibold,
                            color: c.text,
                          ),
                        ),
                        if (role.isNotEmpty)
                          Text(
                            role.toLowerCase(),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: c.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selectable)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? BestieTokens.cBrand
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? BestieTokens.cBrand
                              : c.borderStrong,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    )
                  else ...[
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: c.textMuted,
                    ),
                    if (onCall != null) ...[
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'Call $name',
                        icon: Icon(
                          Icons.call_outlined,
                          size: 19,
                          color: c.brand,
                        ),
                        onSelected: (mode) => onCall!(u, mode),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'voice',
                            child: ListTile(
                              leading: Icon(Icons.call_outlined),
                              title: Text('Voice call'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'video',
                            child: ListTile(
                              leading: Icon(Icons.videocam_outlined),
                              title: Text('Video call'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GroupFooter extends StatelessWidget {
  final BestieColors colors;
  final TextEditingController nameCtrl;
  final int selectedCount;
  final bool submitting;
  final String? iconUrl;
  final VoidCallback? onPickIcon;
  final VoidCallback onSubmit;

  const _GroupFooter({
    required this.colors,
    required this.nameCtrl,
    required this.selectedCount,
    required this.submitting,
    this.iconUrl,
    this.onPickIcon,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            if (onPickIcon != null) ...[
              InkWell(
                onTap: submitting ? null : onPickIcon,
                borderRadius: BorderRadius.circular(BestieTokens.rSm),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(BestieTokens.rSm),
                    border: Border.all(color: colors.border),
                    image: iconUrl != null
                        ? DecorationImage(
                            image: NetworkImage(iconUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: iconUrl == null
                      ? Icon(Icons.add_a_photo_outlined,
                          color: colors.textMuted, size: 20)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: nameCtrl,
                maxLength: 80,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  hintText: 'Group name',
                  hintStyle: TextStyle(
                    color: colors.textMuted,
                    fontWeight: BestieTokens.fwRegular,
                  ),
                  filled: true,
                  fillColor: colors.surface2,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rSm),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rSm),
                    borderSide: const BorderSide(
                      color: BestieTokens.cBrand,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: selectedCount == 0 || submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: BestieTokens.cBrand,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rSm),
                ),
              ),
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: BestieSpinner(size: 16),
                    )
                  : const Icon(Icons.group_add_rounded, size: 16),
              label: Text(
                selectedCount > 0 ? 'Create · $selectedCount' : 'Create',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
