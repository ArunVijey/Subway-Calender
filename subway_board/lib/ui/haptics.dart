// Light vibration on taps, so every button press is felt.
import 'package:flutter/services.dart';

/// Mirrors Settings → Vibration; kept here so any widget can check it cheaply.
bool hapticsOn = true;

void buzz() {
  if (hapticsOn) HapticFeedback.lightImpact();
}

/// Wraps a tap handler so it vibrates first. Null stays null (disabled control).
VoidCallback? tapped(VoidCallback? fn) => fn == null
    ? null
    : () {
        buzz();
        fn();
      };
