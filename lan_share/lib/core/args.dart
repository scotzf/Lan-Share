import 'dart:io';

/// Files named on the command line (Windows right-click passes one path each).
List<File> parseSharedPaths(List<String> args) => [
      for (final a in args)
        if (a.isNotEmpty && File(a).existsSync()) File(a)
    ];
