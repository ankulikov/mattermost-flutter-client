import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_display_name.dart';

void main() {
  test('uses one full-name, nickname, username, and id fallback policy', () {
    expect(
      _name(firstName: ' Ada ', lastName: 'Lovelace', nickname: 'countess'),
      'Ada Lovelace',
    );
    expect(_name(nickname: ' countess '), 'countess');
    expect(_name(username: 'ada'), 'ada');
    expect(_name(), 'user-1');
  });
}

String _name({
  String username = '',
  String nickname = '',
  String firstName = '',
  String lastName = '',
}) => resolveUserDisplayName(
  id: 'user-1',
  username: username,
  nickname: nickname,
  firstName: firstName,
  lastName: lastName,
);
