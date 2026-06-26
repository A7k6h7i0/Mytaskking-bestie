import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/profile_avatar_viewer.dart';

/// WhatsApp-style contact / group info screen opened from chat ⋮ menu.
class ChatContactScreen extends StatelessWidget {
  final Map<String, dynamic> channel;
  final String title;
  final String subtitle;
  final String? avatarUrl;
  final bool isClient;
  final bool isDm;
  final Map<String, dynamic>? contactUser;
  final List<Map<String, dynamic>> members;
  final VoidCallback? onMediaLinksDocs;
  final VoidCallback? onSearch;
  final VoidCallback? onMute;
  final bool muted;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final bool canCall;

  const ChatContactScreen({
    super.key,
    required this.channel,
    required this.title,
    required this.subtitle,
    this.avatarUrl,
    this.isClient = false,
    this.isDm = false,
    this.contactUser,
    this.members = const [],
    this.onMediaLinksDocs,
    this.onSearch,
    this.onMute,
    this.muted = false,
    this.onVoiceCall,
    this.onVideoCall,
    this.canCall = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final email = contactUser?['email']?.toString();
    final phone = contactUser?['phone']?.toString();
    final userId = contactUser?['userId']?.toString();
    final role = (contactUser?['customTitle'] ?? contactUser?['role'] ?? '')
        .toString()
        .replaceAll('_', ' ');

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        title: Text(isDm ? 'Contact info' : 'Group info'),
      ),
      body: ListView(
        children: [
          Container(
            color: colors.surface,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    ProfileAvatarViewer.show(
                      context,
                      name: title,
                      imageUrl: avatarUrl,
                      isClient: isClient,
                    );
                  },
                  child: BestieAvatar(
                    name: title,
                    imageUrl: avatarUrl,
                    isClient: isClient,
                    size: 112,
                  ),
                ),
                const SizedBox(height: 16),
                BestieUserName(
                  name: title,
                  isClient: isClient,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: BestieTokens.fwBold,
                    color: isClient ? colors.client : colors.text,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: subtitle == 'Online'
                          ? BestieTokens.cSuccess
                          : colors.textSoft,
                    ),
                  ),
                ],
                if (canCall && isDm) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ActionChip(
                        icon: Icons.call_rounded,
                        label: 'Audio',
                        color: BestieTokens.cSuccess,
                        onTap: onVoiceCall,
                      ),
                      const SizedBox(width: 12),
                      _ActionChip(
                        icon: Icons.videocam_rounded,
                        label: 'Video',
                        color: BestieTokens.cSuccess,
                        onTap: onVideoCall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (isDm && (email?.isNotEmpty == true || phone?.isNotEmpty == true))
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
                  leading: Icon(Icons.alternate_email_rounded, color: colors.text),
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
            ListTile(
              leading: Icon(Icons.perm_media_outlined, color: colors.text),
              title: const Text('Media, links and docs'),
              trailing: Icon(Icons.chevron_right_rounded, color: colors.textFaint),
              onTap: onMediaLinksDocs,
            ),
            ListTile(
              leading: Icon(Icons.search_rounded, color: colors.text),
              title: const Text('Search'),
              trailing: Icon(Icons.chevron_right_rounded, color: colors.textFaint),
              onTap: onSearch,
            ),
            ListTile(
              leading: Icon(
                muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                color: colors.text,
              ),
              title: Text(muted ? 'Unmute notifications' : 'Mute notifications'),
              onTap: onMute,
            ),
          ]),
          if (!isDm && members.isNotEmpty) ...[
            const SizedBox(height: 8),
            _section(colors, [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '${members.length} MEMBERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: BestieTokens.fwBold,
                    color: colors.textMuted,
                    letterSpacing: BestieTokens.lsEyebrow,
                  ),
                ),
              ),
              for (final m in members) _MemberRow(member: m, colors: colors),
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
