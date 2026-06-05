import 'dart:io';
import 'package:path/path.dart' as p;

/// Base directory for all server data (instances/, config, etc.).
///
/// - Compiled exe: the directory that contains the executable.
/// - Development (`dart run`): the current working directory.
///
/// This ensures autostart registry entries work correctly regardless of the
/// working directory Windows sets when launching the process at boot.
String get serverBaseDir {
  final exe = Platform.resolvedExecutable;
  // When running via `dart run`, the resolved executable is the Dart SDK
  // runtime (dart / dart.exe). Fall back to CWD for development.
  if (p.basenameWithoutExtension(exe).toLowerCase() == 'dart') {
    return Directory.current.path;
  }
  return p.dirname(exe);
}
