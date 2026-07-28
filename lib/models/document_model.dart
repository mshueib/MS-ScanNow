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

  DocumentModel({
    required this.name,
    required this.path,
    required this.type,
    required this.date,
  });
}
