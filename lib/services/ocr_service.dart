import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  // MLKit usa canais de plataforma nativos — não pode correr em Isolate puro.
  // Corre na main thread mas é suficientemente rápido para documentos normais.
  static Future<String> extractText(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final result = await recognizer.processImage(inputImage);
      return result.text.isEmpty
          ? 'Nenhum texto detectado na imagem.'
          : result.text;
    } catch (e) {
      throw Exception('Falha no OCR: $e');
    } finally {
      await recognizer.close();
    }
  }
}
