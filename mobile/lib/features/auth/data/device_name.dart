import 'package:flutter/foundation.dart';

String defaultDeviceName() {
  if (kIsWeb) {
    return 'red-vecinal-web';
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'red-vecinal-android';
    case TargetPlatform.iOS:
      return 'red-vecinal-ios';
    default:
      return 'red-vecinal';
  }
}
