import 'dart:typed_data';
import 'package:hive/hive.dart';
import '../models/saved_signature.dart';

/// Biblioteca de assinaturas guardadas — permite desenhar uma assinatura
/// uma vez e reutilizá-la em vários documentos, em vez de a desenhar
/// sempre de novo.
class SignatureLibraryService {
  static const boxName = 'signatures';

  static Box<SavedSignature> get _box => Hive.box<SavedSignature>(boxName);

  static List<SavedSignature> getAll() =>
      _box.values.toList().reversed.toList();

  static Future<SavedSignature> save(String name, Uint8List bytes) async {
    final sig = SavedSignature(name: name, bytes: bytes, date: DateTime.now());
    await _box.add(sig);
    return sig;
  }

  static Future<void> delete(SavedSignature sig) => sig.delete();
}
