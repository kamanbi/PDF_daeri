// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DocumentsTable extends Documents
    with TableInfo<$DocumentsTable, Document> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbPathMeta = const VerificationMeta(
    'thumbPath',
  );
  @override
  late final GeneratedColumn<String> thumbPath = GeneratedColumn<String>(
    'thumb_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    origin,
    pageCount,
    fileSize,
    createdAt,
    updatedAt,
    thumbPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<Document> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    } else if (isInserting) {
      context.missing(_pageCountMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('thumb_path')) {
      context.handle(
        _thumbPathMeta,
        thumbPath.isAcceptableOrUnknown(data['thumb_path']!, _thumbPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Document map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Document(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      thumbPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_path'],
      ),
    );
  }

  @override
  $DocumentsTable createAlias(String alias) {
    return $DocumentsTable(attachedDatabase, alias);
  }
}

class Document extends DataClass implements Insertable<Document> {
  final String id;
  final String title;
  final String origin;
  final int pageCount;
  final int fileSize;
  final int createdAt;
  final int updatedAt;
  final String? thumbPath;
  const Document({
    required this.id,
    required this.title,
    required this.origin,
    required this.pageCount,
    required this.fileSize,
    required this.createdAt,
    required this.updatedAt,
    this.thumbPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['origin'] = Variable<String>(origin);
    map['page_count'] = Variable<int>(pageCount);
    map['file_size'] = Variable<int>(fileSize);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || thumbPath != null) {
      map['thumb_path'] = Variable<String>(thumbPath);
    }
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      title: Value(title),
      origin: Value(origin),
      pageCount: Value(pageCount),
      fileSize: Value(fileSize),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      thumbPath: thumbPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbPath),
    );
  }

  factory Document.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Document(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      origin: serializer.fromJson<String>(json['origin']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      thumbPath: serializer.fromJson<String?>(json['thumbPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'origin': serializer.toJson<String>(origin),
      'pageCount': serializer.toJson<int>(pageCount),
      'fileSize': serializer.toJson<int>(fileSize),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'thumbPath': serializer.toJson<String?>(thumbPath),
    };
  }

  Document copyWith({
    String? id,
    String? title,
    String? origin,
    int? pageCount,
    int? fileSize,
    int? createdAt,
    int? updatedAt,
    Value<String?> thumbPath = const Value.absent(),
  }) => Document(
    id: id ?? this.id,
    title: title ?? this.title,
    origin: origin ?? this.origin,
    pageCount: pageCount ?? this.pageCount,
    fileSize: fileSize ?? this.fileSize,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    thumbPath: thumbPath.present ? thumbPath.value : this.thumbPath,
  );
  Document copyWithCompanion(DocumentsCompanion data) {
    return Document(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      origin: data.origin.present ? data.origin.value : this.origin,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      thumbPath: data.thumbPath.present ? data.thumbPath.value : this.thumbPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Document(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('origin: $origin, ')
          ..write('pageCount: $pageCount, ')
          ..write('fileSize: $fileSize, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('thumbPath: $thumbPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    origin,
    pageCount,
    fileSize,
    createdAt,
    updatedAt,
    thumbPath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Document &&
          other.id == this.id &&
          other.title == this.title &&
          other.origin == this.origin &&
          other.pageCount == this.pageCount &&
          other.fileSize == this.fileSize &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.thumbPath == this.thumbPath);
}

class DocumentsCompanion extends UpdateCompanion<Document> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> origin;
  final Value<int> pageCount;
  final Value<int> fileSize;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String?> thumbPath;
  final Value<int> rowid;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.origin = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.thumbPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentsCompanion.insert({
    required String id,
    required String title,
    required String origin,
    required int pageCount,
    required int fileSize,
    required int createdAt,
    required int updatedAt,
    this.thumbPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       origin = Value(origin),
       pageCount = Value(pageCount),
       fileSize = Value(fileSize),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Document> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? origin,
    Expression<int>? pageCount,
    Expression<int>? fileSize,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? thumbPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (origin != null) 'origin': origin,
      if (pageCount != null) 'page_count': pageCount,
      if (fileSize != null) 'file_size': fileSize,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (thumbPath != null) 'thumb_path': thumbPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? origin,
    Value<int>? pageCount,
    Value<int>? fileSize,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<String?>? thumbPath,
    Value<int>? rowid,
  }) {
    return DocumentsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      origin: origin ?? this.origin,
      pageCount: pageCount ?? this.pageCount,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      thumbPath: thumbPath ?? this.thumbPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (thumbPath.present) {
      map['thumb_path'] = Variable<String>(thumbPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('origin: $origin, ')
          ..write('pageCount: $pageCount, ')
          ..write('fileSize: $fileSize, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('thumbPath: $thumbPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PagesTable extends Pages with TableInfo<$PagesTable, Page> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'doc_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES documents (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIndexMeta = const VerificationMeta(
    'sourceIndex',
  );
  @override
  late final GeneratedColumn<int> sourceIndex = GeneratedColumn<int>(
    'source_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rotationMeta = const VerificationMeta(
    'rotation',
  );
  @override
  late final GeneratedColumn<int> rotation = GeneratedColumn<int>(
    'rotation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cropMeta = const VerificationMeta('crop');
  @override
  late final GeneratedColumn<String> crop = GeneratedColumn<String>(
    'crop',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    docId,
    orderIndex,
    kind,
    sourcePath,
    sourceIndex,
    rotation,
    crop,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Page> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    } else if (isInserting) {
      context.missing(_sourcePathMeta);
    }
    if (data.containsKey('source_index')) {
      context.handle(
        _sourceIndexMeta,
        sourceIndex.isAcceptableOrUnknown(
          data['source_index']!,
          _sourceIndexMeta,
        ),
      );
    }
    if (data.containsKey('rotation')) {
      context.handle(
        _rotationMeta,
        rotation.isAcceptableOrUnknown(data['rotation']!, _rotationMeta),
      );
    }
    if (data.containsKey('crop')) {
      context.handle(
        _cropMeta,
        crop.isAcceptableOrUnknown(data['crop']!, _cropMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Page map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Page(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_id'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      )!,
      sourceIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_index'],
      ),
      rotation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rotation'],
      )!,
      crop: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crop'],
      ),
    );
  }

  @override
  $PagesTable createAlias(String alias) {
    return $PagesTable(attachedDatabase, alias);
  }
}

class Page extends DataClass implements Insertable<Page> {
  final String id;
  final String docId;
  final int orderIndex;
  final String kind;
  final String sourcePath;
  final int? sourceIndex;
  final int rotation;
  final String? crop;
  const Page({
    required this.id,
    required this.docId,
    required this.orderIndex,
    required this.kind,
    required this.sourcePath,
    this.sourceIndex,
    required this.rotation,
    this.crop,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['doc_id'] = Variable<String>(docId);
    map['order_index'] = Variable<int>(orderIndex);
    map['kind'] = Variable<String>(kind);
    map['source_path'] = Variable<String>(sourcePath);
    if (!nullToAbsent || sourceIndex != null) {
      map['source_index'] = Variable<int>(sourceIndex);
    }
    map['rotation'] = Variable<int>(rotation);
    if (!nullToAbsent || crop != null) {
      map['crop'] = Variable<String>(crop);
    }
    return map;
  }

  PagesCompanion toCompanion(bool nullToAbsent) {
    return PagesCompanion(
      id: Value(id),
      docId: Value(docId),
      orderIndex: Value(orderIndex),
      kind: Value(kind),
      sourcePath: Value(sourcePath),
      sourceIndex: sourceIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceIndex),
      rotation: Value(rotation),
      crop: crop == null && nullToAbsent ? const Value.absent() : Value(crop),
    );
  }

  factory Page.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Page(
      id: serializer.fromJson<String>(json['id']),
      docId: serializer.fromJson<String>(json['docId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      kind: serializer.fromJson<String>(json['kind']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      sourceIndex: serializer.fromJson<int?>(json['sourceIndex']),
      rotation: serializer.fromJson<int>(json['rotation']),
      crop: serializer.fromJson<String?>(json['crop']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'docId': serializer.toJson<String>(docId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'kind': serializer.toJson<String>(kind),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'sourceIndex': serializer.toJson<int?>(sourceIndex),
      'rotation': serializer.toJson<int>(rotation),
      'crop': serializer.toJson<String?>(crop),
    };
  }

  Page copyWith({
    String? id,
    String? docId,
    int? orderIndex,
    String? kind,
    String? sourcePath,
    Value<int?> sourceIndex = const Value.absent(),
    int? rotation,
    Value<String?> crop = const Value.absent(),
  }) => Page(
    id: id ?? this.id,
    docId: docId ?? this.docId,
    orderIndex: orderIndex ?? this.orderIndex,
    kind: kind ?? this.kind,
    sourcePath: sourcePath ?? this.sourcePath,
    sourceIndex: sourceIndex.present ? sourceIndex.value : this.sourceIndex,
    rotation: rotation ?? this.rotation,
    crop: crop.present ? crop.value : this.crop,
  );
  Page copyWithCompanion(PagesCompanion data) {
    return Page(
      id: data.id.present ? data.id.value : this.id,
      docId: data.docId.present ? data.docId.value : this.docId,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
      kind: data.kind.present ? data.kind.value : this.kind,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      sourceIndex: data.sourceIndex.present
          ? data.sourceIndex.value
          : this.sourceIndex,
      rotation: data.rotation.present ? data.rotation.value : this.rotation,
      crop: data.crop.present ? data.crop.value : this.crop,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Page(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('kind: $kind, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('sourceIndex: $sourceIndex, ')
          ..write('rotation: $rotation, ')
          ..write('crop: $crop')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    docId,
    orderIndex,
    kind,
    sourcePath,
    sourceIndex,
    rotation,
    crop,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Page &&
          other.id == this.id &&
          other.docId == this.docId &&
          other.orderIndex == this.orderIndex &&
          other.kind == this.kind &&
          other.sourcePath == this.sourcePath &&
          other.sourceIndex == this.sourceIndex &&
          other.rotation == this.rotation &&
          other.crop == this.crop);
}

class PagesCompanion extends UpdateCompanion<Page> {
  final Value<String> id;
  final Value<String> docId;
  final Value<int> orderIndex;
  final Value<String> kind;
  final Value<String> sourcePath;
  final Value<int?> sourceIndex;
  final Value<int> rotation;
  final Value<String?> crop;
  final Value<int> rowid;
  const PagesCompanion({
    this.id = const Value.absent(),
    this.docId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.kind = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.sourceIndex = const Value.absent(),
    this.rotation = const Value.absent(),
    this.crop = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PagesCompanion.insert({
    required String id,
    required String docId,
    required int orderIndex,
    required String kind,
    required String sourcePath,
    this.sourceIndex = const Value.absent(),
    this.rotation = const Value.absent(),
    this.crop = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       docId = Value(docId),
       orderIndex = Value(orderIndex),
       kind = Value(kind),
       sourcePath = Value(sourcePath);
  static Insertable<Page> custom({
    Expression<String>? id,
    Expression<String>? docId,
    Expression<int>? orderIndex,
    Expression<String>? kind,
    Expression<String>? sourcePath,
    Expression<int>? sourceIndex,
    Expression<int>? rotation,
    Expression<String>? crop,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (docId != null) 'doc_id': docId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (kind != null) 'kind': kind,
      if (sourcePath != null) 'source_path': sourcePath,
      if (sourceIndex != null) 'source_index': sourceIndex,
      if (rotation != null) 'rotation': rotation,
      if (crop != null) 'crop': crop,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PagesCompanion copyWith({
    Value<String>? id,
    Value<String>? docId,
    Value<int>? orderIndex,
    Value<String>? kind,
    Value<String>? sourcePath,
    Value<int?>? sourceIndex,
    Value<int>? rotation,
    Value<String?>? crop,
    Value<int>? rowid,
  }) {
    return PagesCompanion(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      orderIndex: orderIndex ?? this.orderIndex,
      kind: kind ?? this.kind,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceIndex: sourceIndex ?? this.sourceIndex,
      rotation: rotation ?? this.rotation,
      crop: crop ?? this.crop,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (sourceIndex.present) {
      map['source_index'] = Variable<int>(sourceIndex.value);
    }
    if (rotation.present) {
      map['rotation'] = Variable<int>(rotation.value);
    }
    if (crop.present) {
      map['crop'] = Variable<String>(crop.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PagesCompanion(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('kind: $kind, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('sourceIndex: $sourceIndex, ')
          ..write('rotation: $rotation, ')
          ..write('crop: $crop, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentFilesTable extends RecentFiles
    with TableInfo<$RecentFilesTable, RecentFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _copiedPathMeta = const VerificationMeta(
    'copiedPath',
  );
  @override
  late final GeneratedColumn<String> copiedPath = GeneratedColumn<String>(
    'copied_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<int> openedAt = GeneratedColumn<int>(
    'opened_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    copiedPath,
    openedAt,
    size,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecentFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('copied_path')) {
      context.handle(
        _copiedPathMeta,
        copiedPath.isAcceptableOrUnknown(data['copied_path']!, _copiedPathMeta),
      );
    } else if (isInserting) {
      context.missing(_copiedPathMeta);
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_openedAtMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentFile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      copiedPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}copied_path'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}opened_at'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
    );
  }

  @override
  $RecentFilesTable createAlias(String alias) {
    return $RecentFilesTable(attachedDatabase, alias);
  }
}

class RecentFile extends DataClass implements Insertable<RecentFile> {
  final String id;
  final String displayName;
  final String copiedPath;
  final int openedAt;
  final int size;
  const RecentFile({
    required this.id,
    required this.displayName,
    required this.copiedPath,
    required this.openedAt,
    required this.size,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['copied_path'] = Variable<String>(copiedPath);
    map['opened_at'] = Variable<int>(openedAt);
    map['size'] = Variable<int>(size);
    return map;
  }

  RecentFilesCompanion toCompanion(bool nullToAbsent) {
    return RecentFilesCompanion(
      id: Value(id),
      displayName: Value(displayName),
      copiedPath: Value(copiedPath),
      openedAt: Value(openedAt),
      size: Value(size),
    );
  }

  factory RecentFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentFile(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      copiedPath: serializer.fromJson<String>(json['copiedPath']),
      openedAt: serializer.fromJson<int>(json['openedAt']),
      size: serializer.fromJson<int>(json['size']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'copiedPath': serializer.toJson<String>(copiedPath),
      'openedAt': serializer.toJson<int>(openedAt),
      'size': serializer.toJson<int>(size),
    };
  }

  RecentFile copyWith({
    String? id,
    String? displayName,
    String? copiedPath,
    int? openedAt,
    int? size,
  }) => RecentFile(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    copiedPath: copiedPath ?? this.copiedPath,
    openedAt: openedAt ?? this.openedAt,
    size: size ?? this.size,
  );
  RecentFile copyWithCompanion(RecentFilesCompanion data) {
    return RecentFile(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      copiedPath: data.copiedPath.present
          ? data.copiedPath.value
          : this.copiedPath,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      size: data.size.present ? data.size.value : this.size,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentFile(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('copiedPath: $copiedPath, ')
          ..write('openedAt: $openedAt, ')
          ..write('size: $size')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, displayName, copiedPath, openedAt, size);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentFile &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.copiedPath == this.copiedPath &&
          other.openedAt == this.openedAt &&
          other.size == this.size);
}

class RecentFilesCompanion extends UpdateCompanion<RecentFile> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String> copiedPath;
  final Value<int> openedAt;
  final Value<int> size;
  final Value<int> rowid;
  const RecentFilesCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.copiedPath = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.size = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecentFilesCompanion.insert({
    required String id,
    required String displayName,
    required String copiedPath,
    required int openedAt,
    required int size,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       copiedPath = Value(copiedPath),
       openedAt = Value(openedAt),
       size = Value(size);
  static Insertable<RecentFile> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? copiedPath,
    Expression<int>? openedAt,
    Expression<int>? size,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (copiedPath != null) 'copied_path': copiedPath,
      if (openedAt != null) 'opened_at': openedAt,
      if (size != null) 'size': size,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecentFilesCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String>? copiedPath,
    Value<int>? openedAt,
    Value<int>? size,
    Value<int>? rowid,
  }) {
    return RecentFilesCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      copiedPath: copiedPath ?? this.copiedPath,
      openedAt: openedAt ?? this.openedAt,
      size: size ?? this.size,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (copiedPath.present) {
      map['copied_path'] = Variable<String>(copiedPath.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<int>(openedAt.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentFilesCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('copiedPath: $copiedPath, ')
          ..write('openedAt: $openedAt, ')
          ..write('size: $size, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsRowsTable extends SettingsRows
    with TableInfo<$SettingsRowsTable, SettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _defaultQualityMeta = const VerificationMeta(
    'defaultQuality',
  );
  @override
  late final GeneratedColumn<String> defaultQuality = GeneratedColumn<String>(
    'default_quality',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('standard'),
  );
  static const VerificationMeta _adsRemovedMeta = const VerificationMeta(
    'adsRemoved',
  );
  @override
  late final GeneratedColumn<bool> adsRemoved = GeneratedColumn<bool>(
    'ads_removed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("ads_removed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _interstitialCountTodayMeta =
      const VerificationMeta('interstitialCountToday');
  @override
  late final GeneratedColumn<int> interstitialCountToday = GeneratedColumn<int>(
    'interstitial_count_today',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAdDateMeta = const VerificationMeta(
    'lastAdDate',
  );
  @override
  late final GeneratedColumn<int> lastAdDate = GeneratedColumn<int>(
    'last_ad_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    defaultQuality,
    adsRemoved,
    interstitialCountToday,
    lastAdDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('default_quality')) {
      context.handle(
        _defaultQualityMeta,
        defaultQuality.isAcceptableOrUnknown(
          data['default_quality']!,
          _defaultQualityMeta,
        ),
      );
    }
    if (data.containsKey('ads_removed')) {
      context.handle(
        _adsRemovedMeta,
        adsRemoved.isAcceptableOrUnknown(data['ads_removed']!, _adsRemovedMeta),
      );
    }
    if (data.containsKey('interstitial_count_today')) {
      context.handle(
        _interstitialCountTodayMeta,
        interstitialCountToday.isAcceptableOrUnknown(
          data['interstitial_count_today']!,
          _interstitialCountTodayMeta,
        ),
      );
    }
    if (data.containsKey('last_ad_date')) {
      context.handle(
        _lastAdDateMeta,
        lastAdDate.isAcceptableOrUnknown(
          data['last_ad_date']!,
          _lastAdDateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      defaultQuality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_quality'],
      )!,
      adsRemoved: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}ads_removed'],
      )!,
      interstitialCountToday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interstitial_count_today'],
      )!,
      lastAdDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_ad_date'],
      )!,
    );
  }

  @override
  $SettingsRowsTable createAlias(String alias) {
    return $SettingsRowsTable(attachedDatabase, alias);
  }
}

class SettingsRow extends DataClass implements Insertable<SettingsRow> {
  final int id;
  final String defaultQuality;
  final bool adsRemoved;
  final int interstitialCountToday;
  final int lastAdDate;
  const SettingsRow({
    required this.id,
    required this.defaultQuality,
    required this.adsRemoved,
    required this.interstitialCountToday,
    required this.lastAdDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['default_quality'] = Variable<String>(defaultQuality);
    map['ads_removed'] = Variable<bool>(adsRemoved);
    map['interstitial_count_today'] = Variable<int>(interstitialCountToday);
    map['last_ad_date'] = Variable<int>(lastAdDate);
    return map;
  }

  SettingsRowsCompanion toCompanion(bool nullToAbsent) {
    return SettingsRowsCompanion(
      id: Value(id),
      defaultQuality: Value(defaultQuality),
      adsRemoved: Value(adsRemoved),
      interstitialCountToday: Value(interstitialCountToday),
      lastAdDate: Value(lastAdDate),
    );
  }

  factory SettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingsRow(
      id: serializer.fromJson<int>(json['id']),
      defaultQuality: serializer.fromJson<String>(json['defaultQuality']),
      adsRemoved: serializer.fromJson<bool>(json['adsRemoved']),
      interstitialCountToday: serializer.fromJson<int>(
        json['interstitialCountToday'],
      ),
      lastAdDate: serializer.fromJson<int>(json['lastAdDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'defaultQuality': serializer.toJson<String>(defaultQuality),
      'adsRemoved': serializer.toJson<bool>(adsRemoved),
      'interstitialCountToday': serializer.toJson<int>(interstitialCountToday),
      'lastAdDate': serializer.toJson<int>(lastAdDate),
    };
  }

  SettingsRow copyWith({
    int? id,
    String? defaultQuality,
    bool? adsRemoved,
    int? interstitialCountToday,
    int? lastAdDate,
  }) => SettingsRow(
    id: id ?? this.id,
    defaultQuality: defaultQuality ?? this.defaultQuality,
    adsRemoved: adsRemoved ?? this.adsRemoved,
    interstitialCountToday:
        interstitialCountToday ?? this.interstitialCountToday,
    lastAdDate: lastAdDate ?? this.lastAdDate,
  );
  SettingsRow copyWithCompanion(SettingsRowsCompanion data) {
    return SettingsRow(
      id: data.id.present ? data.id.value : this.id,
      defaultQuality: data.defaultQuality.present
          ? data.defaultQuality.value
          : this.defaultQuality,
      adsRemoved: data.adsRemoved.present
          ? data.adsRemoved.value
          : this.adsRemoved,
      interstitialCountToday: data.interstitialCountToday.present
          ? data.interstitialCountToday.value
          : this.interstitialCountToday,
      lastAdDate: data.lastAdDate.present
          ? data.lastAdDate.value
          : this.lastAdDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRow(')
          ..write('id: $id, ')
          ..write('defaultQuality: $defaultQuality, ')
          ..write('adsRemoved: $adsRemoved, ')
          ..write('interstitialCountToday: $interstitialCountToday, ')
          ..write('lastAdDate: $lastAdDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    defaultQuality,
    adsRemoved,
    interstitialCountToday,
    lastAdDate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsRow &&
          other.id == this.id &&
          other.defaultQuality == this.defaultQuality &&
          other.adsRemoved == this.adsRemoved &&
          other.interstitialCountToday == this.interstitialCountToday &&
          other.lastAdDate == this.lastAdDate);
}

class SettingsRowsCompanion extends UpdateCompanion<SettingsRow> {
  final Value<int> id;
  final Value<String> defaultQuality;
  final Value<bool> adsRemoved;
  final Value<int> interstitialCountToday;
  final Value<int> lastAdDate;
  const SettingsRowsCompanion({
    this.id = const Value.absent(),
    this.defaultQuality = const Value.absent(),
    this.adsRemoved = const Value.absent(),
    this.interstitialCountToday = const Value.absent(),
    this.lastAdDate = const Value.absent(),
  });
  SettingsRowsCompanion.insert({
    this.id = const Value.absent(),
    this.defaultQuality = const Value.absent(),
    this.adsRemoved = const Value.absent(),
    this.interstitialCountToday = const Value.absent(),
    this.lastAdDate = const Value.absent(),
  });
  static Insertable<SettingsRow> custom({
    Expression<int>? id,
    Expression<String>? defaultQuality,
    Expression<bool>? adsRemoved,
    Expression<int>? interstitialCountToday,
    Expression<int>? lastAdDate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (defaultQuality != null) 'default_quality': defaultQuality,
      if (adsRemoved != null) 'ads_removed': adsRemoved,
      if (interstitialCountToday != null)
        'interstitial_count_today': interstitialCountToday,
      if (lastAdDate != null) 'last_ad_date': lastAdDate,
    });
  }

  SettingsRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? defaultQuality,
    Value<bool>? adsRemoved,
    Value<int>? interstitialCountToday,
    Value<int>? lastAdDate,
  }) {
    return SettingsRowsCompanion(
      id: id ?? this.id,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      adsRemoved: adsRemoved ?? this.adsRemoved,
      interstitialCountToday:
          interstitialCountToday ?? this.interstitialCountToday,
      lastAdDate: lastAdDate ?? this.lastAdDate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (defaultQuality.present) {
      map['default_quality'] = Variable<String>(defaultQuality.value);
    }
    if (adsRemoved.present) {
      map['ads_removed'] = Variable<bool>(adsRemoved.value);
    }
    if (interstitialCountToday.present) {
      map['interstitial_count_today'] = Variable<int>(
        interstitialCountToday.value,
      );
    }
    if (lastAdDate.present) {
      map['last_ad_date'] = Variable<int>(lastAdDate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRowsCompanion(')
          ..write('id: $id, ')
          ..write('defaultQuality: $defaultQuality, ')
          ..write('adsRemoved: $adsRemoved, ')
          ..write('interstitialCountToday: $interstitialCountToday, ')
          ..write('lastAdDate: $lastAdDate')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $PagesTable pages = $PagesTable(this);
  late final $RecentFilesTable recentFiles = $RecentFilesTable(this);
  late final $SettingsRowsTable settingsRows = $SettingsRowsTable(this);
  late final Index idxDocumentsUpdatedAt = Index(
    'idx_documents_updated_at',
    'CREATE INDEX idx_documents_updated_at ON documents (updated_at DESC)',
  );
  late final Index idxPagesDocOrder = Index(
    'idx_pages_doc_order',
    'CREATE UNIQUE INDEX idx_pages_doc_order ON pages (doc_id, order_index)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    documents,
    pages,
    recentFiles,
    settingsRows,
    idxDocumentsUpdatedAt,
    idxPagesDocOrder,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('pages', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$DocumentsTableCreateCompanionBuilder =
    DocumentsCompanion Function({
      required String id,
      required String title,
      required String origin,
      required int pageCount,
      required int fileSize,
      required int createdAt,
      required int updatedAt,
      Value<String?> thumbPath,
      Value<int> rowid,
    });
typedef $$DocumentsTableUpdateCompanionBuilder =
    DocumentsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> origin,
      Value<int> pageCount,
      Value<int> fileSize,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<String?> thumbPath,
      Value<int> rowid,
    });

final class $$DocumentsTableReferences
    extends BaseReferences<_$AppDatabase, $DocumentsTable, Document> {
  $$DocumentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PagesTable, List<Page>> _pagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.pages,
    aliasName: 'documents__id__pages__doc_id',
  );

  $$PagesTableProcessedTableManager get pagesRefs {
    final manager = $$PagesTableTableManager(
      $_db,
      $_db.pages,
    ).filter((f) => f.docId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_pagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbPath => $composableBuilder(
    column: $table.thumbPath,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> pagesRefs(
    Expression<bool> Function($$PagesTableFilterComposer f) f,
  ) {
    final $$PagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pages,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PagesTableFilterComposer(
            $db: $db,
            $table: $db.pages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbPath => $composableBuilder(
    column: $table.thumbPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get thumbPath =>
      $composableBuilder(column: $table.thumbPath, builder: (column) => column);

  Expression<T> pagesRefs<T extends Object>(
    Expression<T> Function($$PagesTableAnnotationComposer a) f,
  ) {
    final $$PagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pages,
      getReferencedColumn: (t) => t.docId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PagesTableAnnotationComposer(
            $db: $db,
            $table: $db.pages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DocumentsTable,
          Document,
          $$DocumentsTableFilterComposer,
          $$DocumentsTableOrderingComposer,
          $$DocumentsTableAnnotationComposer,
          $$DocumentsTableCreateCompanionBuilder,
          $$DocumentsTableUpdateCompanionBuilder,
          (Document, $$DocumentsTableReferences),
          Document,
          PrefetchHooks Function({bool pagesRefs})
        > {
  $$DocumentsTableTableManager(_$AppDatabase db, $DocumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> thumbPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion(
                id: id,
                title: title,
                origin: origin,
                pageCount: pageCount,
                fileSize: fileSize,
                createdAt: createdAt,
                updatedAt: updatedAt,
                thumbPath: thumbPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String origin,
                required int pageCount,
                required int fileSize,
                required int createdAt,
                required int updatedAt,
                Value<String?> thumbPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion.insert(
                id: id,
                title: title,
                origin: origin,
                pageCount: pageCount,
                fileSize: fileSize,
                createdAt: createdAt,
                updatedAt: updatedAt,
                thumbPath: thumbPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DocumentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({pagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (pagesRefs) db.pages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (pagesRefs)
                    await $_getPrefetchedData<Document, $DocumentsTable, Page>(
                      currentTable: table,
                      referencedTable: $$DocumentsTableReferences
                          ._pagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$DocumentsTableReferences(db, table, p0).pagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.docId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$DocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DocumentsTable,
      Document,
      $$DocumentsTableFilterComposer,
      $$DocumentsTableOrderingComposer,
      $$DocumentsTableAnnotationComposer,
      $$DocumentsTableCreateCompanionBuilder,
      $$DocumentsTableUpdateCompanionBuilder,
      (Document, $$DocumentsTableReferences),
      Document,
      PrefetchHooks Function({bool pagesRefs})
    >;
typedef $$PagesTableCreateCompanionBuilder =
    PagesCompanion Function({
      required String id,
      required String docId,
      required int orderIndex,
      required String kind,
      required String sourcePath,
      Value<int?> sourceIndex,
      Value<int> rotation,
      Value<String?> crop,
      Value<int> rowid,
    });
typedef $$PagesTableUpdateCompanionBuilder =
    PagesCompanion Function({
      Value<String> id,
      Value<String> docId,
      Value<int> orderIndex,
      Value<String> kind,
      Value<String> sourcePath,
      Value<int?> sourceIndex,
      Value<int> rotation,
      Value<String?> crop,
      Value<int> rowid,
    });

final class $$PagesTableReferences
    extends BaseReferences<_$AppDatabase, $PagesTable, Page> {
  $$PagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DocumentsTable _docIdTable(_$AppDatabase db) =>
      db.documents.createAlias('pages__doc_id__documents__id');

  $$DocumentsTableProcessedTableManager get docId {
    final $_column = $_itemColumn<String>('doc_id')!;

    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_docIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PagesTableFilterComposer extends Composer<_$AppDatabase, $PagesTable> {
  $$PagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceIndex => $composableBuilder(
    column: $table.sourceIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rotation => $composableBuilder(
    column: $table.rotation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get crop => $composableBuilder(
    column: $table.crop,
    builder: (column) => ColumnFilters(column),
  );

  $$DocumentsTableFilterComposer get docId {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PagesTableOrderingComposer
    extends Composer<_$AppDatabase, $PagesTable> {
  $$PagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceIndex => $composableBuilder(
    column: $table.sourceIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rotation => $composableBuilder(
    column: $table.rotation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get crop => $composableBuilder(
    column: $table.crop,
    builder: (column) => ColumnOrderings(column),
  );

  $$DocumentsTableOrderingComposer get docId {
    final $$DocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PagesTable> {
  $$PagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceIndex => $composableBuilder(
    column: $table.sourceIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rotation =>
      $composableBuilder(column: $table.rotation, builder: (column) => column);

  GeneratedColumn<String> get crop =>
      $composableBuilder(column: $table.crop, builder: (column) => column);

  $$DocumentsTableAnnotationComposer get docId {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.docId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PagesTable,
          Page,
          $$PagesTableFilterComposer,
          $$PagesTableOrderingComposer,
          $$PagesTableAnnotationComposer,
          $$PagesTableCreateCompanionBuilder,
          $$PagesTableUpdateCompanionBuilder,
          (Page, $$PagesTableReferences),
          Page,
          PrefetchHooks Function({bool docId})
        > {
  $$PagesTableTableManager(_$AppDatabase db, $PagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> docId = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<int?> sourceIndex = const Value.absent(),
                Value<int> rotation = const Value.absent(),
                Value<String?> crop = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PagesCompanion(
                id: id,
                docId: docId,
                orderIndex: orderIndex,
                kind: kind,
                sourcePath: sourcePath,
                sourceIndex: sourceIndex,
                rotation: rotation,
                crop: crop,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String docId,
                required int orderIndex,
                required String kind,
                required String sourcePath,
                Value<int?> sourceIndex = const Value.absent(),
                Value<int> rotation = const Value.absent(),
                Value<String?> crop = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PagesCompanion.insert(
                id: id,
                docId: docId,
                orderIndex: orderIndex,
                kind: kind,
                sourcePath: sourcePath,
                sourceIndex: sourceIndex,
                rotation: rotation,
                crop: crop,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PagesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({docId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (docId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.docId,
                                referencedTable: $$PagesTableReferences
                                    ._docIdTable(db),
                                referencedColumn: $$PagesTableReferences
                                    ._docIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PagesTable,
      Page,
      $$PagesTableFilterComposer,
      $$PagesTableOrderingComposer,
      $$PagesTableAnnotationComposer,
      $$PagesTableCreateCompanionBuilder,
      $$PagesTableUpdateCompanionBuilder,
      (Page, $$PagesTableReferences),
      Page,
      PrefetchHooks Function({bool docId})
    >;
typedef $$RecentFilesTableCreateCompanionBuilder =
    RecentFilesCompanion Function({
      required String id,
      required String displayName,
      required String copiedPath,
      required int openedAt,
      required int size,
      Value<int> rowid,
    });
typedef $$RecentFilesTableUpdateCompanionBuilder =
    RecentFilesCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<String> copiedPath,
      Value<int> openedAt,
      Value<int> size,
      Value<int> rowid,
    });

class $$RecentFilesTableFilterComposer
    extends Composer<_$AppDatabase, $RecentFilesTable> {
  $$RecentFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get copiedPath => $composableBuilder(
    column: $table.copiedPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecentFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentFilesTable> {
  $$RecentFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get copiedPath => $composableBuilder(
    column: $table.copiedPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecentFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentFilesTable> {
  $$RecentFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get copiedPath => $composableBuilder(
    column: $table.copiedPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);
}

class $$RecentFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecentFilesTable,
          RecentFile,
          $$RecentFilesTableFilterComposer,
          $$RecentFilesTableOrderingComposer,
          $$RecentFilesTableAnnotationComposer,
          $$RecentFilesTableCreateCompanionBuilder,
          $$RecentFilesTableUpdateCompanionBuilder,
          (
            RecentFile,
            BaseReferences<_$AppDatabase, $RecentFilesTable, RecentFile>,
          ),
          RecentFile,
          PrefetchHooks Function()
        > {
  $$RecentFilesTableTableManager(_$AppDatabase db, $RecentFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> copiedPath = const Value.absent(),
                Value<int> openedAt = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecentFilesCompanion(
                id: id,
                displayName: displayName,
                copiedPath: copiedPath,
                openedAt: openedAt,
                size: size,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                required String copiedPath,
                required int openedAt,
                required int size,
                Value<int> rowid = const Value.absent(),
              }) => RecentFilesCompanion.insert(
                id: id,
                displayName: displayName,
                copiedPath: copiedPath,
                openedAt: openedAt,
                size: size,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecentFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecentFilesTable,
      RecentFile,
      $$RecentFilesTableFilterComposer,
      $$RecentFilesTableOrderingComposer,
      $$RecentFilesTableAnnotationComposer,
      $$RecentFilesTableCreateCompanionBuilder,
      $$RecentFilesTableUpdateCompanionBuilder,
      (
        RecentFile,
        BaseReferences<_$AppDatabase, $RecentFilesTable, RecentFile>,
      ),
      RecentFile,
      PrefetchHooks Function()
    >;
typedef $$SettingsRowsTableCreateCompanionBuilder =
    SettingsRowsCompanion Function({
      Value<int> id,
      Value<String> defaultQuality,
      Value<bool> adsRemoved,
      Value<int> interstitialCountToday,
      Value<int> lastAdDate,
    });
typedef $$SettingsRowsTableUpdateCompanionBuilder =
    SettingsRowsCompanion Function({
      Value<int> id,
      Value<String> defaultQuality,
      Value<bool> adsRemoved,
      Value<int> interstitialCountToday,
      Value<int> lastAdDate,
    });

class $$SettingsRowsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultQuality => $composableBuilder(
    column: $table.defaultQuality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get adsRemoved => $composableBuilder(
    column: $table.adsRemoved,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interstitialCountToday => $composableBuilder(
    column: $table.interstitialCountToday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAdDate => $composableBuilder(
    column: $table.lastAdDate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultQuality => $composableBuilder(
    column: $table.defaultQuality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get adsRemoved => $composableBuilder(
    column: $table.adsRemoved,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interstitialCountToday => $composableBuilder(
    column: $table.interstitialCountToday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAdDate => $composableBuilder(
    column: $table.lastAdDate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get defaultQuality => $composableBuilder(
    column: $table.defaultQuality,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get adsRemoved => $composableBuilder(
    column: $table.adsRemoved,
    builder: (column) => column,
  );

  GeneratedColumn<int> get interstitialCountToday => $composableBuilder(
    column: $table.interstitialCountToday,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastAdDate => $composableBuilder(
    column: $table.lastAdDate,
    builder: (column) => column,
  );
}

class $$SettingsRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsRowsTable,
          SettingsRow,
          $$SettingsRowsTableFilterComposer,
          $$SettingsRowsTableOrderingComposer,
          $$SettingsRowsTableAnnotationComposer,
          $$SettingsRowsTableCreateCompanionBuilder,
          $$SettingsRowsTableUpdateCompanionBuilder,
          (
            SettingsRow,
            BaseReferences<_$AppDatabase, $SettingsRowsTable, SettingsRow>,
          ),
          SettingsRow,
          PrefetchHooks Function()
        > {
  $$SettingsRowsTableTableManager(_$AppDatabase db, $SettingsRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> defaultQuality = const Value.absent(),
                Value<bool> adsRemoved = const Value.absent(),
                Value<int> interstitialCountToday = const Value.absent(),
                Value<int> lastAdDate = const Value.absent(),
              }) => SettingsRowsCompanion(
                id: id,
                defaultQuality: defaultQuality,
                adsRemoved: adsRemoved,
                interstitialCountToday: interstitialCountToday,
                lastAdDate: lastAdDate,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> defaultQuality = const Value.absent(),
                Value<bool> adsRemoved = const Value.absent(),
                Value<int> interstitialCountToday = const Value.absent(),
                Value<int> lastAdDate = const Value.absent(),
              }) => SettingsRowsCompanion.insert(
                id: id,
                defaultQuality: defaultQuality,
                adsRemoved: adsRemoved,
                interstitialCountToday: interstitialCountToday,
                lastAdDate: lastAdDate,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsRowsTable,
      SettingsRow,
      $$SettingsRowsTableFilterComposer,
      $$SettingsRowsTableOrderingComposer,
      $$SettingsRowsTableAnnotationComposer,
      $$SettingsRowsTableCreateCompanionBuilder,
      $$SettingsRowsTableUpdateCompanionBuilder,
      (
        SettingsRow,
        BaseReferences<_$AppDatabase, $SettingsRowsTable, SettingsRow>,
      ),
      SettingsRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$PagesTableTableManager get pages =>
      $$PagesTableTableManager(_db, _db.pages);
  $$RecentFilesTableTableManager get recentFiles =>
      $$RecentFilesTableTableManager(_db, _db.recentFiles);
  $$SettingsRowsTableTableManager get settingsRows =>
      $$SettingsRowsTableTableManager(_db, _db.settingsRows);
}
