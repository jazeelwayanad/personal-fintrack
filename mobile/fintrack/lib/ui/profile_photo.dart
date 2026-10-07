import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_image_compress/flutter_image_compress.dart';

Future<Uint8List> prepareProfilePhoto(Uint8List source) async {
  final codec = await ui.instantiateImageCodec(source);
  final frame = await codec.getNextFrame(), image = frame.image;
  final side = image.width < image.height ? image.width : image.height;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(
      (image.width - side) / 2,
      (image.height - side) / 2,
      side.toDouble(),
      side.toDouble(),
    ),
    const ui.Rect.fromLTWH(0, 0, 384, 384),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording(),
      square = await picture.toImage(384, 384);
  final png = (await square.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  square.dispose();
  picture.dispose();
  codec.dispose();
  var bytes = await FlutterImageCompress.compressWithList(
    png,
    minWidth: 384,
    minHeight: 384,
    quality: 72,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  if (bytes.length > 128 * 1024) {
    bytes = await FlutterImageCompress.compressWithList(
      png,
      minWidth: 384,
      minHeight: 384,
      quality: 50,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }
  if (bytes.length > 128 * 1024) {
    throw Exception('Choose a simpler or smaller photo.');
  }
  return bytes;
}
