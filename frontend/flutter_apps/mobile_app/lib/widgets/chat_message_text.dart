import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final _urlPattern = RegExp(
  r'(https?://[^\s<>"\)]+)',
  caseSensitive: false,
);

/// Message body text with tappable http(s) links.
class LinkText extends StatelessWidget {
  const LinkText({
    super.key,
    required this.text,
    required this.style,
    this.linkColor,
    this.linkDecoration = TextDecoration.underline,
  });

  final String text;
  final TextStyle style;
  final Color? linkColor;
  final TextDecoration linkDecoration;

  @override
  Widget build(BuildContext context) {
    if (!_urlPattern.hasMatch(text)) {
      return Text(text, style: style);
    }
    final accent = linkColor ?? Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _urlPattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: text.substring(last, match.start),
          style: style,
        ));
      }
      final raw = match.group(1)!;
      final url = _trimTrailingUrlPunctuation(raw);
      spans.add(TextSpan(
        text: raw,
        style: style.copyWith(
          color: accent,
          decoration: linkDecoration,
          decorationColor: accent,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _openUrl(context, url),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

/// @mentions plus tappable links (group chats).
class MentionLinkText extends StatelessWidget {
  const MentionLinkText({
    super.key,
    required this.text,
    required this.style,
    required this.mentionColor,
    this.mentionWeight = FontWeight.w700,
    this.linkColor,
  });

  final String text;
  final TextStyle style;
  final Color mentionColor;
  final FontWeight mentionWeight;
  final Color? linkColor;

  @override
  Widget build(BuildContext context) {
    if (!text.contains('@')) {
      return LinkText(text: text, style: style, linkColor: linkColor);
    }
    final mentionRe = RegExp(
      r'@[\w][\w\s.-]*?(?=\s@|\s|$|[.,!?;:])|@(everyone|here|channel)\b',
      caseSensitive: false,
    );
    if (!mentionRe.hasMatch(text) && !_urlPattern.hasMatch(text)) {
      return Text(text, style: style);
    }
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in mentionRe.allMatches(text)) {
      if (match.start > last) {
        spans.addAll(_linkSpans(
          context,
          text.substring(last, match.start),
          style,
          linkColor,
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: style.copyWith(color: mentionColor, fontWeight: mentionWeight),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.addAll(_linkSpans(
        context,
        text.substring(last),
        style,
        linkColor,
      ));
    }
    if (spans.isEmpty) return Text(text, style: style);
    return Text.rich(TextSpan(children: spans));
  }
}

List<InlineSpan> _linkSpans(
  BuildContext context,
  String segment,
  TextStyle style,
  Color? linkColor,
) {
  if (!_urlPattern.hasMatch(segment)) {
    return [TextSpan(text: segment, style: style)];
  }
  final accent = linkColor ?? Theme.of(context).colorScheme.primary;
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in _urlPattern.allMatches(segment)) {
    if (match.start > last) {
      spans.add(TextSpan(
        text: segment.substring(last, match.start),
        style: style,
      ));
    }
    final raw = match.group(1)!;
    final url = _trimTrailingUrlPunctuation(raw);
    spans.add(TextSpan(
      text: raw,
      style: style.copyWith(
        color: accent,
        decoration: TextDecoration.underline,
        decorationColor: accent,
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () => _openUrl(context, url),
    ));
    last = match.end;
  }
  if (last < segment.length) {
    spans.add(TextSpan(text: segment.substring(last), style: style));
  }
  return spans;
}

String _trimTrailingUrlPunctuation(String url) {
  var trimmed = url;
  while (trimmed.isNotEmpty && ',.;!?)]'.contains(trimmed[trimmed.length - 1])) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

Future<void> _openUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open link')),
    );
  }
}
