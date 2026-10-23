// The header shown while the page loads must not change names: the loading splash
// (web/index.html), the tab title and the app's fallback header use the same words.
import 'dart:io';

import 'package:cafe_countryside_menu/core/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final html = File('web/index.html').readAsStringSync();

  test('the loading splash header equals the app fallback header', () {
    expect(html, contains('<div class="bar">$kDefaultCafeName</div>'));
  });

  test('the browser tab title equals the app title (Flutter overwrites <title> with it)', () {
    expect(html, contains('<title>$kAppTitle</title>'));
  });
}
