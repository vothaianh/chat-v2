import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/models/models.dart';

void main() {
  test('ChatMessage parses text message', () {
    final m = ChatMessage.fromJson(const {
      'id': '1',
      'conversationId': 'c1',
      'type': 'text',
      'text': 'hello @vothaianh',
      'senderId': 'u1',
      'createdAt': 1700000000000,
    });
    expect(m.type, MessageType.text);
    expect(m.text, 'hello @vothaianh');
  });

  test('ChatMessage parses sticker and gif', () {
    final s = ChatMessage.fromJson(const {
      'id': '2',
      'conversationId': 'c1',
      'type': 'sticker',
      'media': '😀',
      'senderId': 'u1',
      'createdAt': 1700000000000,
    });
    expect(s.type, MessageType.sticker);
    expect(s.media, '😀');

    final g = ChatMessage.fromJson(const {
      'id': '3',
      'conversationId': 'c1',
      'type': 'gif',
      'media': 'http://x/y.gif',
      'senderId': 'u1',
      'createdAt': 1700000000000,
    });
    expect(g.type, MessageType.gif);
  });
}