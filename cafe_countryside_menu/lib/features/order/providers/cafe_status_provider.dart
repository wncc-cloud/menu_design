import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'order_request_provider.dart';

/// billing_cafe phase12.md §12.3-B — is the café taking orders right now?
/// `true`/`false` from the counter's `public/cafeStatus`; `null` = unknown
/// (not published yet, or any failure) which callers MUST treat as open —
/// the site fails open so an outage of this one read can never block
/// ordering. A plain provider (not code-generated) on purpose.
final cafeOpenProvider = FutureProvider.autoDispose<bool?>((ref) {
  return ref.read(orderRequestRepositoryProvider).fetchCafeOpen();
});
