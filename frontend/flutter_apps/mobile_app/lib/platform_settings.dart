import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Windows desktop injects a themes section here from [main.dart].
Widget Function(BuildContext context, WidgetRef ref)?
    buildDesktopSettingsHeader;
