import 'dart:typed_data';
import 'package:hive/hive.dart';

part 'saved_signature.g.dart';

@HiveType(typeId: 1)
class SavedSignature extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  Uint8List bytes;

  @HiveField(2)
  DateTime date;

  SavedSignature({
    required this.name,
    required this.bytes,
    required this.date,
  });
}
