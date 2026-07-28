import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../phone_utils.dart';

/// Country-code dropdown + national mobile number field.
class BestiePhoneInput extends StatefulWidget {
  const BestiePhoneInput({
    super.key,
    required this.nationalController,
    this.initialStoredPhone,
    this.label,
    this.errorText,
    this.required = false,
    this.onChanged,
  });

  final TextEditingController nationalController;
  final String? initialStoredPhone;
  final String? label;
  final String? errorText;
  final bool required;
  final VoidCallback? onChanged;

  @override
  State<BestiePhoneInput> createState() => BestiePhoneInputState();
}

class BestiePhoneInputState extends State<BestiePhoneInput> {
  late String _dialCode;

  @override
  void initState() {
    super.initState();
    final parsed = parseStoredPhone(widget.initialStoredPhone);
    _dialCode = parsed?.dial ?? defaultPhoneDial;
    if (parsed != null && widget.nationalController.text.trim().isEmpty) {
      widget.nationalController.text = parsed.national;
    }
  }

  PhoneCountryRule get _country =>
      phoneCountryByDial(_dialCode) ?? defaultPhoneCountry;

  String? buildValue({bool required = false}) {
    return phoneValueFromFields(
      dialCode: _dialCode,
      national: widget.nationalController.text,
      required: required || widget.required,
    );
  }

  String? validate({bool required = false}) {
    return validatePhoneFields(
      dialCode: _dialCode,
      national: widget.nationalController.text,
      required: required || widget.required,
    );
  }

  @override
  void didUpdateWidget(covariant BestiePhoneInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStoredPhone != oldWidget.initialStoredPhone) {
      final parsed = parseStoredPhone(widget.initialStoredPhone);
      if (parsed != null) {
        setState(() => _dialCode = parsed.dial);
        widget.nationalController.text = parsed.national;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final country = _country;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: BestieTokens.fwSemibold,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Container(
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                border: Border.all(
                  color: widget.errorText != null ? c.danger : c.border,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _dialCode,
                  isExpanded: true,
                  icon: Icon(Icons.expand_more_rounded, color: c.textMuted, size: 16),
                  items: phoneCountries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.dial,
                          child: Text(
                            '+${entry.dial}',
                            style: TextStyle(
                              color: c.text,
                              fontWeight: BestieTokens.fwSemibold,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _dialCode = value);
                    widget.onChanged?.call();
                  },
                ),
              ),
            ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.nationalController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(country.max),
                ],
                onChanged: (_) => widget.onChanged?.call(),
                decoration: InputDecoration(
                  hintText: '${country.min}-digit number',
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    borderSide: BorderSide(color: c.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    borderSide: BorderSide(color: c.brand, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    borderSide: BorderSide(color: c.danger),
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ),
          ],
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              widget.errorText!,
              style: TextStyle(color: c.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
