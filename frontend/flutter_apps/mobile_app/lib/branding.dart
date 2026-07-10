import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state.dart';

/// Per-organisation branding shown on the chat home header.
class OrgBranding {
  final String name;
  final String? logoUrl;

  const OrgBranding({
    this.name = 'MyTaskKing',
    this.logoUrl,
  });
}

final orgBrandingProvider = FutureProvider<OrgBranding>((ref) async {
  try {
    final data = await ref.read(apiProvider).settingsScope(scope: 'branding');
    final branding =
        (data['branding'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = (branding['name'] ?? 'MyTaskKing').toString().trim();
    final logoUrl = branding['logoUrl']?.toString();
    return OrgBranding(
      name: name.isEmpty ? 'MyTaskKing' : name,
      logoUrl: logoUrl != null && logoUrl.isNotEmpty ? logoUrl : null,
    );
  } catch (_) {
    return const OrgBranding();
  }
});
