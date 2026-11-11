import 'package:flutter/material.dart';

class RvPrimaryButton extends StatelessWidget {
  const RvPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: loading
          ? FilledButton(
              onPressed: null,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : icon != null
              ? FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 20),
                  label: Text(label, textAlign: TextAlign.center),
                )
              : FilledButton(
                  onPressed: onPressed,
                  child: Text(label, textAlign: TextAlign.center),
                ),
    );
  }
}
