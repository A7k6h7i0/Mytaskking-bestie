import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state.dart';
import 'organization_registration_wizard.dart';

/// Full-screen organisation registration — same flow as telecaller onboarding.
class OrganizationRegistrationScreen extends ConsumerWidget {
  const OrganizationRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiProvider);
    return OrganizationRegistrationWizard(
      fullScreen: true,
      onRegister: (data) => api.registerOrganization(data),
      api: (
        uploadFile: ({required bytes, required filename, required mimeType}) =>
            api.registerUploadDocument(
              bytes: bytes,
              filename: filename,
              mimeType: mimeType,
            ),
      ),
      onBackToLogin: () => context.go('/login'),
    );
  }
}
