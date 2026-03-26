// ignore_for_file: avoid_print
import 'dart:io';

void main() {
  final file = File('lib/screens/torrents_screen.dart');
  final code = file.readAsStringSync();
  final stack = <Map<String, dynamic>>[];
  var line = 1;
  var col = 0;
  var inSingle = false;
  var inDouble = false;
  var inLineComment = false;
  var inBlockComment = false;
  var escape = false;
  for (var i = 0; i < code.length; i++) {
    final c = code[i];
    if (c == '\n') {
      line++;
      col = 0;
      if (inLineComment) inLineComment = false;
      continue;
    }
    col++;
    if (inLineComment || inBlockComment) {
      if (inBlockComment && i > 0 && code[i - 1] == '*' && c == '/')
        inBlockComment = false;
      continue;
    }
    if (inSingle) {
      if (escape) {
        escape = false;
      } else if (c == '\\') {
        escape = true;
      } else if (c == "'") {
        inSingle = false;
      }
      continue;
    }
    if (inDouble) {
      if (escape) {
        escape = false;
      } else if (c == '\\') {
        escape = true;
      } else if (c == '"') {
        inDouble = false;
      }
      continue;
    }
    if (c == '/' && i + 1 < code.length && code[i + 1] == '/') {
      inLineComment = true;
      continue;
    }
    if (c == '/' && i + 1 < code.length && code[i + 1] == '*') {
      inBlockComment = true;
      continue;
    }
    if (c == "'") {
      inSingle = true;
      continue;
    }
    if (c == '"') {
      inDouble = true;
      continue;
    }
    if ('([{'.contains(c)) {
      stack.add({'ch': c, 'line': line, 'col': col});
    } else if (')]}'.contains(c)) {
      if (stack.isEmpty) {
        print('Extra closer at $line:$col $c');
        return;
      }
      final top = stack.last;
      final open = top['ch'];
      final need = open == '('
          ? ')'
          : open == '['
          ? ']'
          : '}';
      if (c == need) {
        stack.removeLast();
      } else {
        print('Mismatch at $line:$col got $c expected $need');
        return;
      }
    }
  }
  if (stack.isNotEmpty) {
    final t = stack.last;
    print('Unclosed ${t['ch']} at ${t['line']}:${t['col']}');
  } else {
    print('Balanced');
  }
}
