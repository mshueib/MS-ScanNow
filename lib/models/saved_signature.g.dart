// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_signature.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SavedSignatureAdapter extends TypeAdapter<SavedSignature> {
  @override
  final int typeId = 1;

  @override
  SavedSignature read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedSignature(
      name: fields[0] as String,
      bytes: fields[1] as Uint8List,
      date: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SavedSignature obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.bytes)
      ..writeByte(2)
      ..write(obj.date);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedSignatureAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
