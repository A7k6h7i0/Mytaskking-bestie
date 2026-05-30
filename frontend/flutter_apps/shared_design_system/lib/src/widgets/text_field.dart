import 'package:flutter/material.dart';
import '../tokens.dart';

class BestieTextField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? errorText;
  final void Function(String)? onChanged;

  const BestieTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.errorText,
    this.onChanged,
  });

  @override
  State<BestieTextField> createState() => _BestieTextFieldState();
}

class _BestieTextFieldState extends State<BestieTextField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: BestieTokens.cTextSoft,
        )),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            prefixIcon: widget.icon != null
                ? Icon(widget.icon, size: 18, color: BestieTokens.cTextMuted)
                : null,
            // Eye toggle for password fields — tap to reveal/hide.
            suffixIcon: widget.obscure
                ? IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: BestieTokens.cTextMuted,
                    ),
                    tooltip: _obscured ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
