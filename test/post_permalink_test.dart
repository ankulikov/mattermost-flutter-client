import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/policies/post_permalink.dart';

void main() {
  test('builds a canonical post permalink and preserves deployment path', () {
    expect(
      mattermostPostPermalink(
        serverUrl: Uri.parse('https://chat.example.com/mattermost/'),
        teamName: 'engineering',
        postId: 'post-123',
      ),
      Uri.parse('https://chat.example.com/mattermost/engineering/pl/post-123'),
    );
  });

  test('does not create a permalink without the team handle', () {
    expect(
      mattermostPostPermalink(
        serverUrl: Uri.parse('https://chat.example.com'),
        teamName: '',
        postId: 'post-123',
      ),
      isNull,
    );
  });
}
