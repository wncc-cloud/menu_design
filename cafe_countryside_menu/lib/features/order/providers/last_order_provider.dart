import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/storage_providers.dart';

const lastOrderStorageKey = 'lastOrder';

/// How long the menu keeps offering the way back to an order.
const lastOrderMaxAge = Duration(hours: 3);

/// Same grace the status page gives a request a cashier already holds.
const lastOrderClaimedGrace = Duration(minutes: 15);

enum LastOrderState { pending, claimed, confirmed, gone }

/// Phase 1 (L1): the one order this device placed most recently — just enough
/// to show "Order code 3X74 · Show code" on the menu. No name / phone is
/// stored. Written at checkout and refreshed by the status page on the polls
/// it already does, so the banner costs zero extra Firestore reads.
class LastOrder {
  final String requestId;
  final String code;
  final int? number;
  final LastOrderState state;
  final DateTime placedAt;
  final DateTime expiresAt;
  final bool dismissed;

  const LastOrder({
    required this.requestId,
    required this.code,
    required this.placedAt,
    required this.expiresAt,
    this.number,
    this.state = LastOrderState.pending,
    this.dismissed = false,
  });

  LastOrder copyWith({
    String? code,
    int? number,
    LastOrderState? state,
    DateTime? expiresAt,
    bool? dismissed,
  }) =>
      LastOrder(
        requestId: requestId,
        code: code ?? this.code,
        number: number ?? this.number,
        state: state ?? this.state,
        placedAt: placedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        dismissed: dismissed ?? this.dismissed,
      );

  /// Staleness is computed here (not trusted from the saved state): once the
  /// customer leaves the status page nobody updates the saved state, so a
  /// "pending" order must expire on its own.
  bool isVisibleAt(DateTime now) {
    if (dismissed || state == LastOrderState.gone) return false;
    if (now.difference(placedAt) >= lastOrderMaxAge) return false;
    switch (state) {
      case LastOrderState.pending:
        return now.isBefore(expiresAt);
      case LastOrderState.claimed:
        return now.isBefore(expiresAt.add(lastOrderClaimedGrace));
      case LastOrderState.confirmed:
        return true;
      case LastOrderState.gone:
        return false;
    }
  }

  String get bannerText => switch (state) {
        LastOrderState.pending => 'Order code $code · waiting for the cashier',
        LastOrderState.claimed => 'Cashier has your order · code $code',
        LastOrderState.confirmed =>
          number != null ? 'Order #$number confirmed' : 'Order confirmed · code $code',
        LastOrderState.gone => '',
      };

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'code': code,
        'number': number,
        'state': state.name,
        'placedAt': placedAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'dismissed': dismissed,
      };

  static LastOrder? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['requestId'];
    final code = raw['code'];
    final placed = raw['placedAt'];
    final expires = raw['expiresAt'];
    if (id is! String || id.isEmpty || code is! String || placed is! int || expires is! int) {
      return null;
    }
    final matches = LastOrderState.values.where((s) => s.name == raw['state']);
    if (matches.isEmpty) return null;
    return LastOrder(
      requestId: id,
      code: code,
      number: raw['number'] is int ? raw['number'] as int : null,
      state: matches.first,
      placedAt: DateTime.fromMillisecondsSinceEpoch(placed),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expires),
      dismissed: raw['dismissed'] == true,
    );
  }
}

class LastOrderNotifier extends Notifier<LastOrder?> {
  @override
  LastOrder? build() {
    final store = ref.read(localStoreProvider);
    try {
      final raw = store.read(lastOrderStorageKey);
      if (raw == null) return null;
      final parsed = LastOrder.tryFromJson(jsonDecode(raw));
      if (parsed == null) store.remove(lastOrderStorageKey);
      return parsed;
    } catch (_) {
      store.remove(lastOrderStorageKey);
      return null;
    }
  }

  void _set(LastOrder? next) {
    state = next;
    final store = ref.read(localStoreProvider);
    try {
      if (next == null) {
        store.remove(lastOrderStorageKey);
      } else {
        store.write(lastOrderStorageKey, jsonEncode(next.toJson()));
      }
    } catch (_) {}
  }

  /// A newer order replaces the older one (only the latest is kept).
  void saveNew({
    required String requestId,
    required String code,
    required DateTime placedAt,
    required DateTime expiresAt,
  }) =>
      _set(LastOrder(
          requestId: requestId, code: code, placedAt: placedAt, expiresAt: expiresAt));

  /// Called by the status page on each poll. Ignored for any other order.
  void update(
    String requestId, {
    String? code,
    int? number,
    LastOrderState? state,
    DateTime? expiresAt,
  }) {
    final cur = this.state;
    if (cur == null || cur.requestId != requestId) return;
    final next = cur.copyWith(code: code, number: number, state: state, expiresAt: expiresAt);
    if (jsonEncode(next.toJson()) == jsonEncode(cur.toJson())) return;
    _set(next);
  }

  void dismiss() {
    final cur = state;
    if (cur != null) _set(cur.copyWith(dismissed: true));
  }
}

final lastOrderProvider =
    NotifierProvider<LastOrderNotifier, LastOrder?>(LastOrderNotifier.new);
