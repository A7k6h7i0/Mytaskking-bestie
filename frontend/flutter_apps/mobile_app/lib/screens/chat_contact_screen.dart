import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state.dart';
import '../widgets/profile_avatar_viewer.dart';

/// WhatsApp-style contact / group info screen opened from chat ⋮ menu.
class ChatContactScreen extends StatefulWidget {
  final Map<String, dynamic> channel;
  final String title;
  final String subtitle;
  final String? avatarUrl;
  final String? groupIconUrl;
  final bool isClient;
  final bool isDm;
  final bool canEditGroupPhoto;
  final Map<String, dynamic>? contactUser;
  final List<Map<String, dynamic>> members;
  final VoidCallback? onMediaLinksDocs;
  final VoidCallback? onSearch;
  final VoidCallback? onMute;
  final bool muted;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final bool canCall;
  final Future<String?> Function()? onPickGroupIcon;
  final Future<void> Function()? onRemoveGroupIcon;

  const ChatContactScreen({
    super.key,
    required this.channel,
    required this.title,
    required this.subtitle,
    this.avatarUrl,
    this.groupIconUrl,
    this.isClient = false,
    this.isDm = false,
    this.canEditGroupPhoto = false,
    this.contactUser,
    this.members = const [],
    this.onMediaLinksDocs,
    this.onSearch,
    this.onMute,
    this.muted = false,
    this.onVoiceCall,
    this.onVideoCall,
    this.canCall = false,
    this.onPickGroupIcon,
    this.onRemoveGroupIcon,
  });

  @override
  State<ChatContactScreen> createState() => _ChatContactScreenState();
}

class _ChatContactScreenState extends State<ChatContactScreen> {
  String? _groupIconUrl;
  bool _updatingIcon = false;

  @override
  void initState() {
    super.initState();
    _groupIconUrl = widget.groupIconUrl;
  }

  @override
  void didUpdateWidget(covariant ChatContactScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.groupIconUrl != oldWidget.groupIconUrl) {
      _groupIconUrl = widget.groupIconUrl;
    }
  }

  Future<void> _changeGroupPhoto() async {
    if (!widget.canEditGroupPhoto || widget.onPickGroupIcon == null) return;
    setState(() => _updatingIcon = true);
    try {
      final url = await widget.onPickGroupIcon!();
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        setState(() => _groupIconUrl = url);
        bestieToast(context, 'Group photo updated',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not update group photo',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingIcon = false);
    }
  }

  Future<void> _removeGroupPhoto() async {
    if (!widget.canEditGroupPhoto || widget.onRemoveGroupIcon == null) return;
    setState(() => _updatingIcon = true);
    try {
      await widget.onRemoveGroupIcon!();
      if (!mounted) return;
      setState(() => _groupIconUrl = null);
      bestieToast(context, 'Group photo removed', kind: BestieToastKind.success);
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not remove group photo',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingIcon = false);
    }
  }

  void _onGroupAvatarTap() {
    final iconUrl = _groupIconUrl;
    if (widget.canEditGroupPhoto) {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: BestieColors.of(context).surface,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
        ),
        builder: (ctx) => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Change group photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeGroupPhoto();
                },
              ),
              if (iconUrl != null && iconUrl.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('View photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    ProfileAvatarViewer.show(
                      context,
                      name: widget.title,
                      imageUrl: iconUrl,
                      isClient: widget.isClient,
                    );
                  },
                ),
              if (iconUrl != null && iconUrl.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: BestieColors.of(context).danger),
                  title: Text('Remove photo',
                      style: TextStyle(color: BestieColors.of(context).danger)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeGroupPhoto();
                  },
                ),
            ],
          ),
        ),
      );
      return;
    }
    if (iconUrl != null && iconUrl.isNotEmpty) {
      ProfileAvatarViewer.show(
        context,
        name: widget.title,
        imageUrl: iconUrl,
        isClient: widget.isClient,
      );
    }
  }

  Widget _groupAvatar(BestieColors colors) {
    final iconUrl = _groupIconUrl;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          iconUrl,
          width: 112,
          height: 112,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _groupAvatarPlaceholder(colors),
        ),
      );
    }
    return _groupAvatarPlaceholder(colors);
  }

  Widget _groupAvatarPlaceholder(BestieColors colors) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: widget.isClient ? colors.clientSoft : colors.brandSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        widget.isClient
            ? Icons.business_center_outlined
            : Icons.groups_outlined,
        color: widget.isClient ? colors.client : colors.brandStrong,
        size: 48,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final email = widget.contactUser?['email']?.toString();
    final phone = widget.contactUser?['phone']?.toString();
    final userId = widget.contactUser?['userId']?.toString();
    final role = (widget.contactUser?['customTitle'] ??
            widget.contactUser?['role'] ??
            '')
        .toString()
        .replaceAll('_', ' ');

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        title: Text(widget.isDm ? 'Contact info' : 'Group info'),
      ),
      body: ListView(
        children: [
          Container(
            color: colors.surface,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              children: [
                GestureDetector(
                  onTap: widget.isDm
                      ? () {
                          ProfileAvatarViewer.show(
                            context,
                            name: widget.title,
                            imageUrl: widget.avatarUrl,
                            isClient: widget.isClient,
                          );
                        }
                      : _onGroupAvatarTap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      widget.isDm
                          ? BestieAvatar(
                              name: widget.title,
                              imageUrl: widget.avatarUrl,
                              isClient: widget.isClient,
                              size: 112,
                            )
                          : _groupAvatar(colors),
                      if (!widget.isDm &&
                          widget.canEditGroupPhoto &&
                          !_updatingIcon)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: colors.brand,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.surface, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      if (!widget.isDm && _updatingIcon)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                BestieUserName(
                  name: widget.title,
                  isClient: widget.isClient,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: BestieTokens.fwBold,
                    color: widget.isClient ? colors.client : colors.text,
                  ),
                ),
                if (widget.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.subtitle == 'Online'
                          ? colors.brand
                          : colors.textSoft,
                    ),
                  ),
                ],
                if (widget.canCall && widget.isDm) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ActionChip(
                        icon: Icons.call_rounded,
                        label: 'Audio',
                        color: BestieTokens.cSuccess,
                        onTap: widget.onVoiceCall,
                      ),
                      const SizedBox(width: 12),
                      _ActionChip(
                        icon: Icons.videocam_rounded,
                        label: 'Video',
                        color: BestieTokens.cSuccess,
                        onTap: widget.onVideoCall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (widget.isDm &&
              (email?.isNotEmpty == true || phone?.isNotEmpty == true))
            _section(colors, [
              if (phone?.isNotEmpty == true)
                ListTile(
                  leading: Icon(Icons.phone_outlined, color: colors.text),
                  title: Text(phone!, style: TextStyle(color: colors.text)),
                  subtitle: const Text('Phone'),
                  onTap: () => launchUrl(Uri.parse('tel:$phone')),
                ),
              if (email?.isNotEmpty == true)
                ListTile(
                  leading: Icon(Icons.email_outlined, color: colors.text),
                  title: Text(email!, style: TextStyle(color: colors.text)),
                  subtitle: const Text('Email'),
                  onTap: () => launchUrl(Uri.parse('mailto:$email')),
                ),
              if (userId?.isNotEmpty == true)
                ListTile(
                  leading:
                      Icon(Icons.alternate_email_rounded, color: colors.text),
                  title: Text('@$userId', style: TextStyle(color: colors.text)),
                  subtitle: const Text('User ID'),
                ),
              if (role.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.badge_outlined, color: colors.text),
                  title: Text(role.toLowerCase(),
                      style: TextStyle(color: colors.text)),
                  subtitle: const Text('Role'),
                ),
            ]),
          _section(colors, [
            if (!widget.isDm && widget.canEditGroupPhoto)
              ListTile(
                leading: Icon(Icons.photo_camera_outlined, color: colors.text),
                title: const Text('Change group photo'),
                onTap: _updatingIcon ? null : _changeGroupPhoto,
              ),
            ListTile(
              leading: Icon(Icons.perm_media_outlined, color: colors.text),
              title: const Text('Media, links and docs'),
              trailing:
                  Icon(Icons.chevron_right_rounded, color: colors.textFaint),
              onTap: widget.onMediaLinksDocs,
            ),
            ListTile(
              leading: Icon(Icons.search_rounded, color: colors.text),
              title: const Text('Search'),
              trailing:
                  Icon(Icons.chevron_right_rounded, color: colors.textFaint),
              onTap: widget.onSearch,
            ),
            ListTile(
              leading: Icon(
                widget.muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: colors.text,
              ),
              title: Text(widget.muted
                  ? 'Unmute notifications'
                  : 'Mute notifications'),
              onTap: widget.onMute,
            ),
          ]),
          if (!widget.isDm && widget.members.isNotEmpty) ...[
            const SizedBox(height: 8),
            _section(colors, [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '${widget.members.length} MEMBERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: BestieTokens.fwBold,
                    color: colors.textMuted,
                    letterSpacing: BestieTokens.lsEyebrow,
                  ),
                ),
              ),
              for (final m in widget.members)
                _MemberRow(member: m, colors: colors),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _section(BestieColors colors, List<Widget> children) {
    return Container(
      color: colors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: children),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(BestieTokens.rPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BestieTokens.rPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: color,
                    fontWeight: BestieTokens.fwSemibold,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final BestieColors colors;

  const _MemberRow({required this.member, required this.colors});

  @override
  Widget build(BuildContext context) {
    final u = (member['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = (u['name'] ?? '—').toString();
    final isClient = u['isClient'] == true;
    final avatar = u['avatarUrl']?.toString();
    return ListTile(
      leading: GestureDetector(
        onTap: () {
          ProfileAvatarViewer.show(
            context,
            name: name,
            imageUrl: avatar,
            isClient: isClient,
          );
        },
        child: BestieAvatar(
          name: name,
          imageUrl: avatar,
          isClient: isClient,
          size: 40,
        ),
      ),
      title: BestieUserName(
        name: name,
        isClient: isClient,
        style: TextStyle(
          fontWeight: BestieTokens.fwSemibold,
          color: colors.text,
        ),
      ),
      subtitle: Text(
        (u['role'] ?? '').toString().replaceAll('_', ' ').toLowerCase(),
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
    );
  }
}
