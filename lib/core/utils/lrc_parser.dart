class LrcLine {
  final Duration timestamp;
  final String text;

  const LrcLine({
    required this.timestamp,
    required this.text,
  });
}

class LrcParser {
  static List<LrcLine>? parse(String lyrics) {
    if (!lyrics.contains(RegExp(r'\[\d+:\d+(?:\.\d+)?\]'))) return null;

    final lines = lyrics.split('\n');
    final List<LrcLine> result = [];
    final regex = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\](.*)');

    for (final line in lines) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final millisPart = match.group(3) ?? '0';
        
        // Handle ms parsing properly (e.g. .82 means 820ms, .5 means 500ms)
        int milliseconds = 0;
        if (millisPart.isNotEmpty) {
          if (millisPart.length == 1) {
            milliseconds = int.parse(millisPart) * 100;
          } else if (millisPart.length == 2) {
            milliseconds = int.parse(millisPart) * 10;
          } else {
            milliseconds = int.parse(millisPart.substring(0, 3));
          }
        }

        final text = match.group(4)?.trim() ?? '';
        
        result.add(LrcLine(
          timestamp: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: text,
        ));
      } else if (line.trim().isNotEmpty && result.isEmpty) {
        // If there are leading lines without timestamps, we can ignore them 
        // or add them at 0:00. For now, ignore.
      }
    }

    if (result.isEmpty) return null;

    // Sort by timestamp just in case
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return result;
  }
}
