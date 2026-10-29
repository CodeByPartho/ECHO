import 'package:flutter_test/flutter_test.dart';
import 'package:echo/services/stop_sequence_filter.dart';

String run(List<String> stops, List<String> tokens, {List<String>? emitted}) {
  final f = StopSequenceFilter(stops);
  final out = StringBuffer();
  for (final t in tokens) {
    final e = f.add(t);
    emitted?.add(e);
    out.write(e);
  }
  out.write(f.flush());
  return out.toString();
}

void main() {
  test('passes text through when no stop sequence appears', () {
    expect(run(['STOP'], ['Hello ', 'world']), 'Hello world');
  });

  test('cuts before a stop sequence inside one token', () {
    expect(run(['\nUser:'], ['Answer.\nUser: next']), 'Answer.');
  });

  test('catches a stop sequence split across tokens', () {
    final emitted = <String>[];
    final out = run(['<|end|>'], ['Done', '<|e', 'nd|>', 'junk'],
        emitted: emitted);
    expect(out, 'Done');
    // No fragment of the stop sequence is ever emitted.
    expect(emitted.join(), isNot(contains('<|')));
  });

  test('uses the earliest of several stop sequences', () {
    expect(run(['###', 'END'], ['a END b ### c']), 'a ');
  });

  test('stops consuming after a match', () {
    final f = StopSequenceFilter(['X']);
    expect(f.add('abXcd'), 'ab');
    expect(f.stopped, isTrue);
    expect(f.add('more'), '');
    expect(f.flush(), '');
    expect(f.text, 'ab');
  });

  test('releases held-back text when generation ends normally', () {
    final f = StopSequenceFilter(['STOP']);
    expect(f.add('hello'), 'he'); // last 3 chars could start "STOP"
    expect(f.flush(), 'llo');
  });

  test('ignores empty stop strings', () {
    final f = StopSequenceFilter(['', '']);
    expect(f.isActive, isFalse);
    expect(f.add('text'), 'text');
  });
}
