import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsafe/models/contact_model.dart';

void main() {
  Contact make(String name) =>
      Contact(name: name, role: 'Family', color: Colors.red);

  group('Contact.initials', () {
    test('two words → two initials', () {
      expect(make('Saad Khan').initials, 'SK');
    });

    test('extra whitespace is collapsed', () {
      expect(make('  Saad   Khan ').initials, 'SK');
    });

    test('single word → single initial', () {
      expect(make('Saad').initials, 'S');
    });

    test('empty → ?', () {
      expect(make('   ').initials, '?');
    });
  });

  group('Contact.initial', () {
    test('uppercases the first character', () {
      expect(make('saad').initial, 'S');
    });
  });

  group('Contact getters / aliases', () {
    test('expose alert + relation aliases', () {
      const c = Contact(
        name: 'Saad',
        role: 'Brother',
        color: Colors.blue,
        smsAlert: true,
        pushAlert: false,
      );
      expect(c.relation, 'Brother');
      expect(c.avatarColor, Colors.blue);
      expect(c.smsEnabled, isTrue);
      expect(c.pushEnabled, isFalse);
    });
  });
}
