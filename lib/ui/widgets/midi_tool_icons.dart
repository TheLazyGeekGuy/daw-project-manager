import 'package:material_ui/material_ui.dart';

/// The piano roll's tool icons Material has no glyph for: the select
/// tool's mouse pointer, the range tool's text caret, the eraser and the
/// metronome. Drawn
/// in the icon theme's colour and size, so they sit beside Material icons
/// as one of them.
enum MidiToolGlyph { pointer, caret, eraser, metronome }

class MidiToolIcon extends StatelessWidget {
  const MidiToolIcon(this.glyph, {super.key, this.size, this.color});

  final MidiToolGlyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: _GlyphPainter(
          glyph,
          color ?? theme.color ?? const Color(0xFF000000),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final MidiToolGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24-unit grid, like Material's icons.
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case MidiToolGlyph.metronome:
        // The pyramid case, its pendulum swung to the right with its weight.
        final body = Path()
          ..moveTo(9.5, 3)
          ..lineTo(14.5, 3)
          ..lineTo(19, 21)
          ..lineTo(5, 21)
          ..close();
        canvas.drawPath(body, stroke);
        canvas.drawLine(const Offset(5.6, 17), const Offset(18.4, 17), stroke);
        canvas.drawLine(const Offset(12, 17), const Offset(17.5, 6), stroke);
        canvas.drawCircle(const Offset(15.6, 9.8), 1.6, fill);
      case MidiToolGlyph.pointer:
        // The classic arrow, its tip at the top left.
        final arrow = Path()
          ..moveTo(6, 3)
          ..lineTo(6, 19)
          ..lineTo(10, 15.2)
          ..lineTo(12.8, 21)
          ..lineTo(15.2, 19.9)
          ..lineTo(12.5, 14.2)
          ..lineTo(18, 14.2)
          ..close();
        canvas.drawPath(arrow, fill);
      case MidiToolGlyph.caret:
        // An I-beam: a stem with a serif at each end.
        canvas.drawLine(const Offset(12, 4.5), const Offset(12, 19.5), stroke);
        canvas.drawLine(const Offset(8.5, 4), const Offset(15.5, 4), stroke);
        canvas.drawLine(const Offset(8.5, 20), const Offset(15.5, 20), stroke);
      case MidiToolGlyph.eraser:
        // A block eraser on its side, the rubber end solid, with the line
        // it leaves under it.
        canvas.save();
        canvas.translate(12, 11);
        canvas.rotate(-0.785398); // -45°
        final body = RRect.fromRectAndRadius(
            const Rect.fromLTWH(-8, -4.2, 16, 8.4), const Radius.circular(2));
        canvas.drawRRect(body, stroke);
        canvas.drawRRect(
          RRect.fromRectAndCorners(const Rect.fromLTWH(-8, -4.2, 6.5, 8.4),
              topLeft: const Radius.circular(2),
              bottomLeft: const Radius.circular(2)),
          fill,
        );
        canvas.restore();
        canvas.drawLine(const Offset(9, 20.5), const Offset(20, 20.5), stroke);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
