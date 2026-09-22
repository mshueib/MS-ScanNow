import 'package:hive/hive.dart';

part 'document_model.g.dart';

@HiveType(typeId: 0)
class DocumentModel extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String path;

  @HiveField(2)
  String type;

  @HiveField(3)
  DateTime date;

  /// Número de páginas do PDF gravado. Documentos antigos (gravados antes
  /// deste campo existir) não têm este byte no Hive — a leitura assume `1`
  /// nesses casos, em vez de reabrir o ficheiro para contar páginas.
  @HiveField(4)
  int pageCount;

  DocumentModel({
    required this.name,
    required this.path,
    required this.type,
    required this.date,
    this.pageCount = 1,
  });
}
