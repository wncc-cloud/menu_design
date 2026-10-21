// The browser's user-agent text for a bug log (which phone / browser hit the
// problem). Conditional import: dart:html does not exist on the VM that
// `flutter test` runs on.
import 'user_agent_stub.dart' if (dart.library.html) 'user_agent_web.dart' as impl;

String currentUserAgent() => impl.currentUserAgent();
