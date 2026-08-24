import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  static Future<String> extractText(String path) async {
    final result = await recognize(path);
    return result.text.isEmpty
        ? 'Nenhum texto detectado na imagem.'
        : result.text;
  }

  // MLKit usa canais de plataforma nativos — não pode correr em Isolate puro.
  // Corre na main thread mas é suficientemente rápido para documentos normais.
  //
  // Devolve o resultado estruturado (blocos/linhas/palavras com a posição
  // de cada uma) em vez de só o texto plano — necessário para embutir uma
  // camada de texto pesquisável alinhada à imagem no PDF.
  static Future<RecognizedText> recognize(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(path);
      return await recognizer.processImage(inputImage);
    } catch (e) {
      throw Exception('Falha no OCR: $e');
    } finally {
      await recognizer.close();
    }
  }
}
