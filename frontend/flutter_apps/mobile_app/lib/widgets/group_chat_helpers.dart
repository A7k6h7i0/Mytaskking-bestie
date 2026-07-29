import 'package:flutter/material.dart';

/// WhatsApp-style @mention highlighting in message bubbles.
class MentionText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color mentionColor;
  final FontWeight mentionWeight;

  const MentionText({
    super.key,
    required this.text,
    required this.style,
    required this.mentionColor,
    this.mentionWeight = FontWeight.w700,
  });

  static final _mentionPattern = RegExp(
    r'@[\w][\w\s.-]*?(?=\s@|\s|$|[.,!?;:])|@(everyone|here|channel)\b',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    if (!text.contains('@')) {
      return Text(text, style: style);
    }
    final spans = <TextSpan>[];
    var last = 0;
    for (final match in _mentionPattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start), style: style));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: style.copyWith(color: mentionColor, fontWeight: mentionWeight),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    if (spans.isEmpty) return Text(text, style: style);
    return RichText(text: TextSpan(children: spans));
  }
}

/// Opens a WhatsApp-style member picker when composing @mentions.
/// Closes automatically when [keepOpen] returns false (e.g. user deleted `@`).
Future<Map<String, dynamic>?> showGroupMentionPicker(
  BuildContext context, {
  required List<Map<String, dynamic>> members,
  String? currentUserId,
  String? filterQuery,
  TextEditingController? composer,
  bool Function()? keepOpen,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _GroupMentionPickerSheet(
      members: members,
      currentUserId: currentUserId,
      initialQuery: filterQuery ?? '',
      composer: composer,
      keepOpen: keepOpen,
    ),
  );
}

class _GroupMentionPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final String? currentUserId;
  final String initialQuery;
  final TextEditingController? composer;
  final bool Function()? keepOpen;

  const _GroupMentionPickerSheet({
    required this.members,
    this.currentUserId,
    this.initialQuery = '',
    this.composer,
    this.keepOpen,
  });

  @override
  State<_GroupMentionPickerSheet> createState() =>
      _GroupMentionPickerSheetState();
}

class _GroupMentionPickerSheetState extends State<_GroupMentionPickerSheet> {
  late final TextEditingController _search =
      TextEditingController(text: widget.initialQuery);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.composer?.addListener(_onComposerChanged);
  }

  void _onComposerChanged() {
    if (_closing) return;
    if (widget.keepOpen != null && !widget.keepOpen!()) {
      // Mention ended (@ removed or completed). Close sheet only if it is
      // still the top route — never pop the chat underneath after a pick.
      final route = ModalRoute.of(context);
      if (mounted &&
          route?.isCurrent == true &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    } else if (widget.composer != null) {
      final q = _composerMentionFragment();
      if (q != null && q != _search.text) {
        _search.text = q;
        _search.selection = TextSelection.collapsed(offset: q.length);
        setState(() {});
      }
    }
  }

  String? _composerMentionFragment() {
    final composer = widget.composer;
    if (composer == null) return null;
    final selection = composer.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursor = selection.start;
    if (cursor <= 0 || cursor > composer.text.length) return null;
    final upToCursor = composer.text.substring(0, cursor);
    final atIndex = upToCursor.lastIndexOf('@');
    if (atIndex < 0) return null;
    if (atIndex > 0) {
      final prev = upToCursor[atIndex - 1];
      if (prev != ' ' && prev != '\n') return null;
    }
    final fragment = upToCursor.substring(atIndex + 1);
    if (fragment.contains(' ') || fragment.contains('\n')) return null;
    return fragment;
  }

  @override
  void dispose() {
    widget.composer?.removeListener(_onComposerChanged);
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    final broadcast = [
      {'name': 'everyone', '_broadcast': true, '_desc': 'Notify everyone'},
      {'name': 'here', '_broadcast': true, '_desc': 'Notify active members'},
    ].where((b) => q.isEmpty || (b['name'] as String).startsWith(q));

    final people = widget.members
        .map((m) => (m['user'] as Map?)?.cast<String, dynamic>())
        .whereType<Map<String, dynamic>>()
        .where((u) {
      if (widget.currentUserId != null && u['id'] == widget.currentUserId) {
        return false;
      }
      final name = (u['name'] ?? '').toString().toLowerCase();
      return q.isEmpty || name.contains(q);
    });

    return [...broadcast, ...people];
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered.toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search members',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final u = items[i];
                final isBroadcast = u['_broadcast'] == true;
                final name = u['name']?.toString() ?? '';
                return ListTile(
                  leading: isBroadcast
                      ? const CircleAvatar(
                          child: Icon(Icons.campaign_outlined, size: 20),
                        )
                      : CircleAvatar(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                          ),
                        ),
                  title: Text(isBroadcast ? '@$name' : name),
                  subtitle: isBroadcast
                      ? Text(u['_desc']?.toString() ?? '')
                      : null,
                  onTap: () {
                    _closing = true;
                    widget.composer?.removeListener(_onComposerChanged);
                    Navigator.pop(context, u);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick teammates to add to an existing group.
Future<List<String>?> showAddGroupMemberPicker(
  BuildContext context, {
  required Future<List<Map<String, dynamic>>> Function(String query)
      fetchEmployees,
  required Set<String> excludeUserIds,
}) async {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _AddGroupMemberSheet(
      fetchEmployees: fetchEmployees,
      excludeUserIds: excludeUserIds,
    ),
  );
}

class _AddGroupMemberSheet extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function(String query)
      fetchEmployees;
  final Set<String> excludeUserIds;

  const _AddGroupMemberSheet({
    required this.fetchEmployees,
    required this.excludeUserIds,
  });

  @override
  State<_AddGroupMemberSheet> createState() => _AddGroupMemberSheetState();
}

class _AddGroupMemberSheetState extends State<_AddGroupMemberSheet> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _employees = const [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load('');
    _search.addListener(() => _load(_search.text));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.fetchEmployees(q);
      if (!mounted) return;
      setState(() {
        _employees = items
            .where((u) => !widget.excludeUserIds.contains(u['id']?.toString()))
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
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add members',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected.toList()),
                  child: Text('Add (${_selected.length})'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search teammates',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!)))
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _employees.length,
                itemBuilder: (_, i) {
                  final u = _employees[i];
                  final id = u['id']?.toString() ?? '';
                  final name = u['name']?.toString() ?? '—';
                  final picked = _selected.contains(id);
                  return CheckboxListTile(
                    value: picked,
                    onChanged: id.isEmpty
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                    title: Text(name),
                    secondary: CircleAvatar(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
