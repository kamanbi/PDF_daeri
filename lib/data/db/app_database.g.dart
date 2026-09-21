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
  static const VerificationMeta _themeModeMeta = const VerificationMeta(
    'themeMode',
  );
  @override
  late final GeneratedColumn<String> themeMode = GeneratedColumn<String>(
    'theme_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      "CHECK (theme_mode IN ('system','light','dark'))",
    ),
    defaultValue: const Constant('system'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    defaultQuality,
    adsRemoved,
    interstitialCountToday,
    lastAdDate,
    themeMode,
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
    if (data.containsKey('theme_mode')) {
      context.handle(
        _themeModeMeta,
        themeMode.isAcceptableOrUnknown(data['theme_mode']!, _themeModeMeta),
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
      themeMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_mode'],
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
  final String themeMode;
  const SettingsRow({
    required this.id,
    required this.defaultQuality,
    required this.adsRemoved,
    required this.interstitialCountToday,
    required this.lastAdDate,
    required this.themeMode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['default_quality'] = Variable<String>(defaultQuality);
    map['ads_removed'] = Variable<bool>(adsRemoved);
    map['interstitial_count_today'] = Variable<int>(interstitialCountToday);
    map['last_ad_date'] = Variable<int>(lastAdDate);
    map['theme_mode'] = Variable<String>(themeMode);
    return map;
  }

  SettingsRowsCompanion toCompanion(bool nullToAbsent) {
    return SettingsRowsCompanion(
      id: Value(id),
      defaultQuality: Value(defaultQuality),
      adsRemoved: Value(adsRemoved),
      interstitialCountToday: Value(interstitialCountToday),
      lastAdDate: Value(lastAdDate),
      themeMode: Value(themeMode),
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
      themeMode: serializer.fromJson<String>(json['themeMode']),
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
      'themeMode': serializer.toJson<String>(themeMode),
    };
  }

  SettingsRow copyWith({
    int? id,
    String? defaultQuality,
    bool? adsRemoved,
    int? interstitialCountToday,
    int? lastAdDate,
    String? themeMode,
  }) => SettingsRow(
    id: id ?? this.id,
    defaultQuality: defaultQuality ?? this.defaultQuality,
    adsRemoved: adsRemoved ?? this.adsRemoved,
    interstitialCountToday:
        interstitialCountToday ?? this.interstitialCountToday,
    lastAdDate: lastAdDate ?? this.lastAdDate,
    themeMode: themeMode ?? this.themeMode,
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
      themeMode: data.themeMode.present
          ? data.themeMode.value
          : this.themeMode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRow(')
          ..write('id: $id, ')
          ..write('defaultQuality: $defaultQuality, ')
          ..write('adsRemoved: $adsRemoved, ')
          ..write('interstitialCountToday: $interstitialCountToday, ')
          ..write('lastAdDate: $lastAdDate, ')
          ..write('themeMode: $themeMode')
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
    themeMode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsRow &&
          other.id == this.id &&
          other.defaultQuality == this.defaultQuality &&
          other.adsRemoved == this.adsRemoved &&
          other.interstitialCountToday == this.interstitialCountToday &&
          other.lastAdDate == this.lastAdDate &&
          other.themeMode == this.themeMode);
}

class SettingsRowsCompanion extends UpdateCompanion<SettingsRow> {
  final Value<int> id;
  final Value<String> defaultQuality;
  final Value<bool> adsRemoved;
  final Value<int> interstitialCountToday;
  final Value<int> lastAdDate;
  final Value<String> themeMode;
  const SettingsRowsCompanion({
    this.id = const Value.absent(),
    this.defaultQuality = const Value.absent(),
    this.adsRemoved = const Value.absent(),
    this.interstitialCountToday = const Value.absent(),
    this.lastAdDate = const Value.absent(),
    this.themeMode = const Value.absent(),
  });
  SettingsRowsCompanion.insert({
    this.id = const Value.absent(),
    this.defaultQuality = const Value.absent(),
    this.adsRemoved = const Value.absent(),
    this.interstitialCountToday = const Value.absent(),
    this.lastAdDate = const Value.absent(),
    this.themeMode = const Value.absent(),
  });
  static Insertable<SettingsRow> custom({
    Expression<int>? id,
    Expression<String>? defaultQuality,
    Expression<bool>? adsRemoved,
    Expression<int>? interstitialCountToday,
    Expression<int>? lastAdDate,
    Expression<String>? themeMode,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (defaultQuality != null) 'default_quality': defaultQuality,
      if (adsRemoved != null) 'ads_removed': adsRemoved,
      if (interstitialCountToday != null)
        'interstitial_count_today': interstitialCountToday,
      if (lastAdDate != null) 'last_ad_date': lastAdDate,
      if (themeMode != null) 'theme_mode': themeMode,
    });
  }

  SettingsRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? defaultQuality,
    Value<bool>? adsRemoved,
    Value<int>? interstitialCountToday,
    Value<int>? lastAdDate,
    Value<String>? themeMode,
  }) {
    return SettingsRowsCompanion(
      id: id ?? this.id,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      adsRemoved: adsRemoved ?? this.adsRemoved,
      interstitialCountToday:
          interstitialCountToday ?? this.interstitialCountToday,
      lastAdDate: lastAdDate ?? this.lastAdDate,
      themeMode: themeMode ?? this.themeMode,
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
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(themeMode.value);
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
          ..write('lastAdDate: $lastAdDate, ')
          ..write('themeMode: $themeMode')
          ..write(')'))
        .toString();
  }
}

class $EditDraftsTable extends EditDrafts
    with TableInfo<$EditDraftsTable, EditDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EditDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceDocIdMeta = const VerificationMeta(
    'sourceDocId',
  );
  @override
  late final GeneratedColumn<String> sourceDocId = GeneratedColumn<String>(
    'source_doc_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourcePdfPathMeta = const VerificationMeta(
    'sourcePdfPath',
  );
  @override
  late final GeneratedColumn<String> sourcePdfPath = GeneratedColumn<String>(
    'source_pdf_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceRecentIdMeta = const VerificationMeta(
    'sourceRecentId',
  );
  @override
  late final GeneratedColumn<String> sourceRecentId = GeneratedColumn<String>(
    'source_recent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceKind,
    sourceDocId,
    sourcePdfPath,
    sourceRecentId,
    title,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'edit_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<EditDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('source_doc_id')) {
      context.handle(
        _sourceDocIdMeta,
        sourceDocId.isAcceptableOrUnknown(
          data['source_doc_id']!,
          _sourceDocIdMeta,
        ),
      );
    }
    if (data.containsKey('source_pdf_path')) {
      context.handle(
        _sourcePdfPathMeta,
        sourcePdfPath.isAcceptableOrUnknown(
          data['source_pdf_path']!,
          _sourcePdfPathMeta,
        ),
      );
    }
    if (data.containsKey('source_recent_id')) {
      context.handle(
        _sourceRecentIdMeta,
        sourceRecentId.isAcceptableOrUnknown(
          data['source_recent_id']!,
          _sourceRecentIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EditDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EditDraft(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      sourceDocId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_doc_id'],
      ),
      sourcePdfPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_pdf_path'],
      ),
      sourceRecentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_recent_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EditDraftsTable createAlias(String alias) {
    return $EditDraftsTable(attachedDatabase, alias);
  }
}

class EditDraft extends DataClass implements Insertable<EditDraft> {
  final String id;

  /// 편집 대상 출처. `router.dart`의 `EditSource`와 1:1 대응한다.
  final String sourceKind;
  final String? sourceDocId;
  final String? sourcePdfPath;
  final String? sourceRecentId;
  final String title;
  final int updatedAt;
  const EditDraft({
    required this.id,
    required this.sourceKind,
    this.sourceDocId,
    this.sourcePdfPath,
    this.sourceRecentId,
    required this.title,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_kind'] = Variable<String>(sourceKind);
    if (!nullToAbsent || sourceDocId != null) {
      map['source_doc_id'] = Variable<String>(sourceDocId);
    }
    if (!nullToAbsent || sourcePdfPath != null) {
      map['source_pdf_path'] = Variable<String>(sourcePdfPath);
    }
    if (!nullToAbsent || sourceRecentId != null) {
      map['source_recent_id'] = Variable<String>(sourceRecentId);
    }
    map['title'] = Variable<String>(title);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  EditDraftsCompanion toCompanion(bool nullToAbsent) {
    return EditDraftsCompanion(
      id: Value(id),
      sourceKind: Value(sourceKind),
      sourceDocId: sourceDocId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDocId),
      sourcePdfPath: sourcePdfPath == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcePdfPath),
      sourceRecentId: sourceRecentId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceRecentId),
      title: Value(title),
      updatedAt: Value(updatedAt),
    );
  }

  factory EditDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EditDraft(
      id: serializer.fromJson<String>(json['id']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      sourceDocId: serializer.fromJson<String?>(json['sourceDocId']),
      sourcePdfPath: serializer.fromJson<String?>(json['sourcePdfPath']),
      sourceRecentId: serializer.fromJson<String?>(json['sourceRecentId']),
      title: serializer.fromJson<String>(json['title']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'sourceDocId': serializer.toJson<String?>(sourceDocId),
      'sourcePdfPath': serializer.toJson<String?>(sourcePdfPath),
      'sourceRecentId': serializer.toJson<String?>(sourceRecentId),
      'title': serializer.toJson<String>(title),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  EditDraft copyWith({
    String? id,
    String? sourceKind,
    Value<String?> sourceDocId = const Value.absent(),
    Value<String?> sourcePdfPath = const Value.absent(),
    Value<String?> sourceRecentId = const Value.absent(),
    String? title,
    int? updatedAt,
  }) => EditDraft(
    id: id ?? this.id,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceDocId: sourceDocId.present ? sourceDocId.value : this.sourceDocId,
    sourcePdfPath: sourcePdfPath.present
        ? sourcePdfPath.value
        : this.sourcePdfPath,
    sourceRecentId: sourceRecentId.present
        ? sourceRecentId.value
        : this.sourceRecentId,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EditDraft copyWithCompanion(EditDraftsCompanion data) {
    return EditDraft(
      id: data.id.present ? data.id.value : this.id,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      sourceDocId: data.sourceDocId.present
          ? data.sourceDocId.value
          : this.sourceDocId,
      sourcePdfPath: data.sourcePdfPath.present
          ? data.sourcePdfPath.value
          : this.sourcePdfPath,
      sourceRecentId: data.sourceRecentId.present
          ? data.sourceRecentId.value
          : this.sourceRecentId,
      title: data.title.present ? data.title.value : this.title,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EditDraft(')
          ..write('id: $id, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceDocId: $sourceDocId, ')
          ..write('sourcePdfPath: $sourcePdfPath, ')
          ..write('sourceRecentId: $sourceRecentId, ')
          ..write('title: $title, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceKind,
    sourceDocId,
    sourcePdfPath,
    sourceRecentId,
    title,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EditDraft &&
          other.id == this.id &&
          other.sourceKind == this.sourceKind &&
          other.sourceDocId == this.sourceDocId &&
          other.sourcePdfPath == this.sourcePdfPath &&
          other.sourceRecentId == this.sourceRecentId &&
          other.title == this.title &&
          other.updatedAt == this.updatedAt);
}

class EditDraftsCompanion extends UpdateCompanion<EditDraft> {
  final Value<String> id;
  final Value<String> sourceKind;
  final Value<String?> sourceDocId;
  final Value<String?> sourcePdfPath;
  final Value<String?> sourceRecentId;
  final Value<String> title;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const EditDraftsCompanion({
    this.id = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceDocId = const Value.absent(),
    this.sourcePdfPath = const Value.absent(),
    this.sourceRecentId = const Value.absent(),
    this.title = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EditDraftsCompanion.insert({
    required String id,
    required String sourceKind,
    this.sourceDocId = const Value.absent(),
    this.sourcePdfPath = const Value.absent(),
    this.sourceRecentId = const Value.absent(),
    required String title,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceKind = Value(sourceKind),
       title = Value(title),
       updatedAt = Value(updatedAt);
  static Insertable<EditDraft> custom({
    Expression<String>? id,
    Expression<String>? sourceKind,
    Expression<String>? sourceDocId,
    Expression<String>? sourcePdfPath,
    Expression<String>? sourceRecentId,
    Expression<String>? title,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceDocId != null) 'source_doc_id': sourceDocId,
      if (sourcePdfPath != null) 'source_pdf_path': sourcePdfPath,
      if (sourceRecentId != null) 'source_recent_id': sourceRecentId,
      if (title != null) 'title': title,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EditDraftsCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceKind,
    Value<String?>? sourceDocId,
    Value<String?>? sourcePdfPath,
    Value<String?>? sourceRecentId,
    Value<String>? title,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return EditDraftsCompanion(
      id: id ?? this.id,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceDocId: sourceDocId ?? this.sourceDocId,
      sourcePdfPath: sourcePdfPath ?? this.sourcePdfPath,
      sourceRecentId: sourceRecentId ?? this.sourceRecentId,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceDocId.present) {
      map['source_doc_id'] = Variable<String>(sourceDocId.value);
    }
    if (sourcePdfPath.present) {
      map['source_pdf_path'] = Variable<String>(sourcePdfPath.value);
    }
    if (sourceRecentId.present) {
      map['source_recent_id'] = Variable<String>(sourceRecentId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EditDraftsCompanion(')
          ..write('id: $id, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceDocId: $sourceDocId, ')
          ..write('sourcePdfPath: $sourcePdfPath, ')
          ..write('sourceRecentId: $sourceRecentId, ')
          ..write('title: $title, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EditDraftPagesTable extends EditDraftPages
    with TableInfo<$EditDraftPagesTable, EditDraftPage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EditDraftPagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _draftIdMeta = const VerificationMeta(
    'draftId',
  );
  @override
  late final GeneratedColumn<String> draftId = GeneratedColumn<String>(
    'draft_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES edit_drafts (id) ON DELETE CASCADE',
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
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    draftId,
    orderIndex,
    kind,
    sourcePath,
    sourceIndex,
    rotation,
    crop,
    origin,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'edit_draft_pages';
  @override
  VerificationContext validateIntegrity(
    Insertable<EditDraftPage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('draft_id')) {
      context.handle(
        _draftIdMeta,
        draftId.isAcceptableOrUnknown(data['draft_id']!, _draftIdMeta),
      );
    } else if (isInserting) {
      context.missing(_draftIdMeta);
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
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EditDraftPage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EditDraftPage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      draftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_id'],
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
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
    );
  }

  @override
  $EditDraftPagesTable createAlias(String alias) {
    return $EditDraftPagesTable(attachedDatabase, alias);
  }
}

class EditDraftPage extends DataClass implements Insertable<EditDraftPage> {
  final String id;
  final String draftId;
  final int orderIndex;
  final String kind;
  final String sourcePath;
  final int? sourceIndex;
  final int rotation;
  final String? crop;

  /// `EditPageOrigin`. 복구 후에도 `SizeGuard.classify`의 `before`를 재구성해야
  /// 하므로 반드시 보존한다 — 이 값이 없으면 저장 시 `SaveOp` 판정이 틀어진다.
  final String origin;
  const EditDraftPage({
    required this.id,
    required this.draftId,
    required this.orderIndex,
    required this.kind,
    required this.sourcePath,
    this.sourceIndex,
    required this.rotation,
    this.crop,
    required this.origin,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['draft_id'] = Variable<String>(draftId);
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
    map['origin'] = Variable<String>(origin);
    return map;
  }

  EditDraftPagesCompanion toCompanion(bool nullToAbsent) {
    return EditDraftPagesCompanion(
      id: Value(id),
      draftId: Value(draftId),
      orderIndex: Value(orderIndex),
      kind: Value(kind),
      sourcePath: Value(sourcePath),
      sourceIndex: sourceIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceIndex),
      rotation: Value(rotation),
      crop: crop == null && nullToAbsent ? const Value.absent() : Value(crop),
      origin: Value(origin),
    );
  }

  factory EditDraftPage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EditDraftPage(
      id: serializer.fromJson<String>(json['id']),
      draftId: serializer.fromJson<String>(json['draftId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      kind: serializer.fromJson<String>(json['kind']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      sourceIndex: serializer.fromJson<int?>(json['sourceIndex']),
      rotation: serializer.fromJson<int>(json['rotation']),
      crop: serializer.fromJson<String?>(json['crop']),
      origin: serializer.fromJson<String>(json['origin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'draftId': serializer.toJson<String>(draftId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'kind': serializer.toJson<String>(kind),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'sourceIndex': serializer.toJson<int?>(sourceIndex),
      'rotation': serializer.toJson<int>(rotation),
      'crop': serializer.toJson<String?>(crop),
      'origin': serializer.toJson<String>(origin),
    };
  }

  EditDraftPage copyWith({
    String? id,
    String? draftId,
    int? orderIndex,
    String? kind,
    String? sourcePath,
    Value<int?> sourceIndex = const Value.absent(),
    int? rotation,
    Value<String?> crop = const Value.absent(),
    String? origin,
  }) => EditDraftPage(
    id: id ?? this.id,
    draftId: draftId ?? this.draftId,
    orderIndex: orderIndex ?? this.orderIndex,
    kind: kind ?? this.kind,
    sourcePath: sourcePath ?? this.sourcePath,
    sourceIndex: sourceIndex.present ? sourceIndex.value : this.sourceIndex,
    rotation: rotation ?? this.rotation,
    crop: crop.present ? crop.value : this.crop,
    origin: origin ?? this.origin,
  );
  EditDraftPage copyWithCompanion(EditDraftPagesCompanion data) {
    return EditDraftPage(
      id: data.id.present ? data.id.value : this.id,
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
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
      origin: data.origin.present ? data.origin.value : this.origin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EditDraftPage(')
          ..write('id: $id, ')
          ..write('draftId: $draftId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('kind: $kind, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('sourceIndex: $sourceIndex, ')
          ..write('rotation: $rotation, ')
          ..write('crop: $crop, ')
          ..write('origin: $origin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    draftId,
    orderIndex,
    kind,
    sourcePath,
    sourceIndex,
    rotation,
    crop,
    origin,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EditDraftPage &&
          other.id == this.id &&
          other.draftId == this.draftId &&
          other.orderIndex == this.orderIndex &&
          other.kind == this.kind &&
          other.sourcePath == this.sourcePath &&
          other.sourceIndex == this.sourceIndex &&
          other.rotation == this.rotation &&
          other.crop == this.crop &&
          other.origin == this.origin);
}

class EditDraftPagesCompanion extends UpdateCompanion<EditDraftPage> {
  final Value<String> id;
  final Value<String> draftId;
  final Value<int> orderIndex;
  final Value<String> kind;
  final Value<String> sourcePath;
  final Value<int?> sourceIndex;
  final Value<int> rotation;
  final Value<String?> crop;
  final Value<String> origin;
  final Value<int> rowid;
  const EditDraftPagesCompanion({
    this.id = const Value.absent(),
    this.draftId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.kind = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.sourceIndex = const Value.absent(),
    this.rotation = const Value.absent(),
    this.crop = const Value.absent(),
    this.origin = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EditDraftPagesCompanion.insert({
    required String id,
    required String draftId,
    required int orderIndex,
    required String kind,
    required String sourcePath,
    this.sourceIndex = const Value.absent(),
    this.rotation = const Value.absent(),
    this.crop = const Value.absent(),
    required String origin,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       draftId = Value(draftId),
       orderIndex = Value(orderIndex),
       kind = Value(kind),
       sourcePath = Value(sourcePath),
       origin = Value(origin);
  static Insertable<EditDraftPage> custom({
    Expression<String>? id,
    Expression<String>? draftId,
    Expression<int>? orderIndex,
    Expression<String>? kind,
    Expression<String>? sourcePath,
    Expression<int>? sourceIndex,
    Expression<int>? rotation,
    Expression<String>? crop,
    Expression<String>? origin,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (draftId != null) 'draft_id': draftId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (kind != null) 'kind': kind,
      if (sourcePath != null) 'source_path': sourcePath,
      if (sourceIndex != null) 'source_index': sourceIndex,
      if (rotation != null) 'rotation': rotation,
      if (crop != null) 'crop': crop,
      if (origin != null) 'origin': origin,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EditDraftPagesCompanion copyWith({
    Value<String>? id,
    Value<String>? draftId,
    Value<int>? orderIndex,
    Value<String>? kind,
    Value<String>? sourcePath,
    Value<int?>? sourceIndex,
    Value<int>? rotation,
    Value<String?>? crop,
    Value<String>? origin,
    Value<int>? rowid,
  }) {
    return EditDraftPagesCompanion(
      id: id ?? this.id,
      draftId: draftId ?? this.draftId,
      orderIndex: orderIndex ?? this.orderIndex,
      kind: kind ?? this.kind,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceIndex: sourceIndex ?? this.sourceIndex,
      rotation: rotation ?? this.rotation,
      crop: crop ?? this.crop,
      origin: origin ?? this.origin,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
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
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EditDraftPagesCompanion(')
          ..write('id: $id, ')
          ..write('draftId: $draftId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('kind: $kind, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('sourceIndex: $sourceIndex, ')
          ..write('rotation: $rotation, ')
          ..write('crop: $crop, ')
          ..write('origin: $origin, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EditDraftMarksTable extends EditDraftMarks
    with TableInfo<$EditDraftMarksTable, EditDraftMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EditDraftMarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _draftPageIdMeta = const VerificationMeta(
    'draftPageId',
  );
  @override
  late final GeneratedColumn<String> draftPageId = GeneratedColumn<String>(
    'draft_page_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES edit_draft_pages (id) ON DELETE CASCADE',
    ),
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
  static const VerificationMeta _rectMeta = const VerificationMeta('rect');
  @override
  late final GeneratedColumn<String> rect = GeneratedColumn<String>(
    'rect',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetPathMeta = const VerificationMeta(
    'assetPath',
  );
  @override
  late final GeneratedColumn<String> assetPath = GeneratedColumn<String>(
    'asset_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _markTextMeta = const VerificationMeta(
    'markText',
  );
  @override
  late final GeneratedColumn<String> markText = GeneratedColumn<String>(
    'text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorArgbMeta = const VerificationMeta(
    'colorArgb',
  );
  @override
  late final GeneratedColumn<int> colorArgb = GeneratedColumn<int>(
    'color_argb',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paramMeta = const VerificationMeta('param');
  @override
  late final GeneratedColumn<double> param = GeneratedColumn<double>(
    'param',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    draftPageId,
    kind,
    rect,
    assetPath,
    markText,
    colorArgb,
    param,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'edit_draft_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<EditDraftMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('draft_page_id')) {
      context.handle(
        _draftPageIdMeta,
        draftPageId.isAcceptableOrUnknown(
          data['draft_page_id']!,
          _draftPageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_draftPageIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('rect')) {
      context.handle(
        _rectMeta,
        rect.isAcceptableOrUnknown(data['rect']!, _rectMeta),
      );
    } else if (isInserting) {
      context.missing(_rectMeta);
    }
    if (data.containsKey('asset_path')) {
      context.handle(
        _assetPathMeta,
        assetPath.isAcceptableOrUnknown(data['asset_path']!, _assetPathMeta),
      );
    }
    if (data.containsKey('text')) {
      context.handle(
        _markTextMeta,
        markText.isAcceptableOrUnknown(data['text']!, _markTextMeta),
      );
    }
    if (data.containsKey('color_argb')) {
      context.handle(
        _colorArgbMeta,
        colorArgb.isAcceptableOrUnknown(data['color_argb']!, _colorArgbMeta),
      );
    }
    if (data.containsKey('param')) {
      context.handle(
        _paramMeta,
        param.isAcceptableOrUnknown(data['param']!, _paramMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EditDraftMark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EditDraftMark(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      draftPageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_page_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      rect: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rect'],
      )!,
      assetPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_path'],
      ),
      markText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      ),
      colorArgb: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_argb'],
      ),
      param: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}param'],
      ),
    );
  }

  @override
  $EditDraftMarksTable createAlias(String alias) {
    return $EditDraftMarksTable(attachedDatabase, alias);
  }
}

class EditDraftMark extends DataClass implements Insertable<EditDraftMark> {
  final String id;
  final String draftPageId;

  /// `StampMark`의 kind. `page_ref.dart`의 `kind` 규약과 같은 형식이다.
  final String kind;

  /// `StampRect.encode()` — "l,t,r,b" (`CropRect`와 **같은 직렬화 형식**. 두 번째 형식 금지)
  final String rect;

  /// kind=image: `drafts/<draftId>/marks/NNN.png` 상대 경로. 그 외 null
  final String? assetPath;

  /// kind=text: 본문. 그 외 null
  final String? markText;

  /// kind=highlight|text: ARGB. kind=image면 null
  final int? colorArgb;

  /// kind=highlight: 0.0~1.0(opacity). kind=text: fontSizePt. kind=image: null
  final double? param;
  const EditDraftMark({
    required this.id,
    required this.draftPageId,
    required this.kind,
    required this.rect,
    this.assetPath,
    this.markText,
    this.colorArgb,
    this.param,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['draft_page_id'] = Variable<String>(draftPageId);
    map['kind'] = Variable<String>(kind);
    map['rect'] = Variable<String>(rect);
    if (!nullToAbsent || assetPath != null) {
      map['asset_path'] = Variable<String>(assetPath);
    }
    if (!nullToAbsent || markText != null) {
      map['text'] = Variable<String>(markText);
    }
    if (!nullToAbsent || colorArgb != null) {
      map['color_argb'] = Variable<int>(colorArgb);
    }
    if (!nullToAbsent || param != null) {
      map['param'] = Variable<double>(param);
    }
    return map;
  }

  EditDraftMarksCompanion toCompanion(bool nullToAbsent) {
    return EditDraftMarksCompanion(
      id: Value(id),
      draftPageId: Value(draftPageId),
      kind: Value(kind),
      rect: Value(rect),
      assetPath: assetPath == null && nullToAbsent
          ? const Value.absent()
          : Value(assetPath),
      markText: markText == null && nullToAbsent
          ? const Value.absent()
          : Value(markText),
      colorArgb: colorArgb == null && nullToAbsent
          ? const Value.absent()
          : Value(colorArgb),
      param: param == null && nullToAbsent
          ? const Value.absent()
          : Value(param),
    );
  }

  factory EditDraftMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EditDraftMark(
      id: serializer.fromJson<String>(json['id']),
      draftPageId: serializer.fromJson<String>(json['draftPageId']),
      kind: serializer.fromJson<String>(json['kind']),
      rect: serializer.fromJson<String>(json['rect']),
      assetPath: serializer.fromJson<String?>(json['assetPath']),
      markText: serializer.fromJson<String?>(json['markText']),
      colorArgb: serializer.fromJson<int?>(json['colorArgb']),
      param: serializer.fromJson<double?>(json['param']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'draftPageId': serializer.toJson<String>(draftPageId),
      'kind': serializer.toJson<String>(kind),
      'rect': serializer.toJson<String>(rect),
      'assetPath': serializer.toJson<String?>(assetPath),
      'markText': serializer.toJson<String?>(markText),
      'colorArgb': serializer.toJson<int?>(colorArgb),
      'param': serializer.toJson<double?>(param),
    };
  }

  EditDraftMark copyWith({
    String? id,
    String? draftPageId,
    String? kind,
    String? rect,
    Value<String?> assetPath = const Value.absent(),
    Value<String?> markText = const Value.absent(),
    Value<int?> colorArgb = const Value.absent(),
    Value<double?> param = const Value.absent(),
  }) => EditDraftMark(
    id: id ?? this.id,
    draftPageId: draftPageId ?? this.draftPageId,
    kind: kind ?? this.kind,
    rect: rect ?? this.rect,
    assetPath: assetPath.present ? assetPath.value : this.assetPath,
    markText: markText.present ? markText.value : this.markText,
    colorArgb: colorArgb.present ? colorArgb.value : this.colorArgb,
    param: param.present ? param.value : this.param,
  );
  EditDraftMark copyWithCompanion(EditDraftMarksCompanion data) {
    return EditDraftMark(
      id: data.id.present ? data.id.value : this.id,
      draftPageId: data.draftPageId.present
          ? data.draftPageId.value
          : this.draftPageId,
      kind: data.kind.present ? data.kind.value : this.kind,
      rect: data.rect.present ? data.rect.value : this.rect,
      assetPath: data.assetPath.present ? data.assetPath.value : this.assetPath,
      markText: data.markText.present ? data.markText.value : this.markText,
      colorArgb: data.colorArgb.present ? data.colorArgb.value : this.colorArgb,
      param: data.param.present ? data.param.value : this.param,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EditDraftMark(')
          ..write('id: $id, ')
          ..write('draftPageId: $draftPageId, ')
          ..write('kind: $kind, ')
          ..write('rect: $rect, ')
          ..write('assetPath: $assetPath, ')
          ..write('markText: $markText, ')
          ..write('colorArgb: $colorArgb, ')
          ..write('param: $param')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    draftPageId,
    kind,
    rect,
    assetPath,
    markText,
    colorArgb,
    param,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EditDraftMark &&
          other.id == this.id &&
          other.draftPageId == this.draftPageId &&
          other.kind == this.kind &&
          other.rect == this.rect &&
          other.assetPath == this.assetPath &&
          other.markText == this.markText &&
          other.colorArgb == this.colorArgb &&
          other.param == this.param);
}

class EditDraftMarksCompanion extends UpdateCompanion<EditDraftMark> {
  final Value<String> id;
  final Value<String> draftPageId;
  final Value<String> kind;
  final Value<String> rect;
  final Value<String?> assetPath;
  final Value<String?> markText;
  final Value<int?> colorArgb;
  final Value<double?> param;
  final Value<int> rowid;
  const EditDraftMarksCompanion({
    this.id = const Value.absent(),
    this.draftPageId = const Value.absent(),
    this.kind = const Value.absent(),
    this.rect = const Value.absent(),
    this.assetPath = const Value.absent(),
    this.markText = const Value.absent(),
    this.colorArgb = const Value.absent(),
    this.param = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EditDraftMarksCompanion.insert({
    required String id,
    required String draftPageId,
    required String kind,
    required String rect,
    this.assetPath = const Value.absent(),
    this.markText = const Value.absent(),
    this.colorArgb = const Value.absent(),
    this.param = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       draftPageId = Value(draftPageId),
       kind = Value(kind),
       rect = Value(rect);
  static Insertable<EditDraftMark> custom({
    Expression<String>? id,
    Expression<String>? draftPageId,
    Expression<String>? kind,
    Expression<String>? rect,
    Expression<String>? assetPath,
    Expression<String>? markText,
    Expression<int>? colorArgb,
    Expression<double>? param,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (draftPageId != null) 'draft_page_id': draftPageId,
      if (kind != null) 'kind': kind,
      if (rect != null) 'rect': rect,
      if (assetPath != null) 'asset_path': assetPath,
      if (markText != null) 'text': markText,
      if (colorArgb != null) 'color_argb': colorArgb,
      if (param != null) 'param': param,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EditDraftMarksCompanion copyWith({
    Value<String>? id,
    Value<String>? draftPageId,
    Value<String>? kind,
    Value<String>? rect,
    Value<String?>? assetPath,
    Value<String?>? markText,
    Value<int?>? colorArgb,
    Value<double?>? param,
    Value<int>? rowid,
  }) {
    return EditDraftMarksCompanion(
      id: id ?? this.id,
      draftPageId: draftPageId ?? this.draftPageId,
      kind: kind ?? this.kind,
      rect: rect ?? this.rect,
      assetPath: assetPath ?? this.assetPath,
      markText: markText ?? this.markText,
      colorArgb: colorArgb ?? this.colorArgb,
      param: param ?? this.param,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (draftPageId.present) {
      map['draft_page_id'] = Variable<String>(draftPageId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rect.present) {
      map['rect'] = Variable<String>(rect.value);
    }
    if (assetPath.present) {
      map['asset_path'] = Variable<String>(assetPath.value);
    }
    if (markText.present) {
      map['text'] = Variable<String>(markText.value);
    }
    if (colorArgb.present) {
      map['color_argb'] = Variable<int>(colorArgb.value);
    }
    if (param.present) {
      map['param'] = Variable<double>(param.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EditDraftMarksCompanion(')
          ..write('id: $id, ')
          ..write('draftPageId: $draftPageId, ')
          ..write('kind: $kind, ')
          ..write('rect: $rect, ')
          ..write('assetPath: $assetPath, ')
          ..write('markText: $markText, ')
          ..write('colorArgb: $colorArgb, ')
          ..write('param: $param, ')
          ..write('rowid: $rowid')
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
  late final $EditDraftsTable editDrafts = $EditDraftsTable(this);
  late final $EditDraftPagesTable editDraftPages = $EditDraftPagesTable(this);
  late final $EditDraftMarksTable editDraftMarks = $EditDraftMarksTable(this);
  late final Index idxDocumentsUpdatedAt = Index(
    'idx_documents_updated_at',
    'CREATE INDEX idx_documents_updated_at ON documents (updated_at DESC)',
  );
  late final Index idxPagesDocOrder = Index(
    'idx_pages_doc_order',
    'CREATE UNIQUE INDEX idx_pages_doc_order ON pages (doc_id, order_index)',
  );
  late final Index idxEditDraftsUpdatedAt = Index(
    'idx_edit_drafts_updated_at',
    'CREATE INDEX idx_edit_drafts_updated_at ON edit_drafts (updated_at DESC)',
  );
  late final Index idxDraftPagesDraftOrder = Index(
    'idx_draft_pages_draft_order',
    'CREATE UNIQUE INDEX idx_draft_pages_draft_order ON edit_draft_pages (draft_id, order_index)',
  );
  late final Index idxDraftMarksPage = Index(
    'idx_draft_marks_page',
    'CREATE INDEX idx_draft_marks_page ON edit_draft_marks (draft_page_id)',
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
    editDrafts,
    editDraftPages,
    editDraftMarks,
    idxDocumentsUpdatedAt,
    idxPagesDocOrder,
    idxEditDraftsUpdatedAt,
    idxDraftPagesDraftOrder,
    idxDraftMarksPage,
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
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'edit_drafts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('edit_draft_pages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'edit_draft_pages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('edit_draft_marks', kind: UpdateKind.delete)],
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
      Value<String> themeMode,
    });
typedef $$SettingsRowsTableUpdateCompanionBuilder =
    SettingsRowsCompanion Function({
      Value<int> id,
      Value<String> defaultQuality,
      Value<bool> adsRemoved,
      Value<int> interstitialCountToday,
      Value<int> lastAdDate,
      Value<String> themeMode,
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

  ColumnFilters<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
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

  ColumnOrderings<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
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

  GeneratedColumn<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
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
                Value<String> themeMode = const Value.absent(),
              }) => SettingsRowsCompanion(
                id: id,
                defaultQuality: defaultQuality,
                adsRemoved: adsRemoved,
                interstitialCountToday: interstitialCountToday,
                lastAdDate: lastAdDate,
                themeMode: themeMode,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> defaultQuality = const Value.absent(),
                Value<bool> adsRemoved = const Value.absent(),
                Value<int> interstitialCountToday = const Value.absent(),
                Value<int> lastAdDate = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
              }) => SettingsRowsCompanion.insert(
                id: id,
                defaultQuality: defaultQuality,
                adsRemoved: adsRemoved,
                interstitialCountToday: interstitialCountToday,
                lastAdDate: lastAdDate,
                themeMode: themeMode,
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
typedef $$EditDraftsTableCreateCompanionBuilder =
    EditDraftsCompanion Function({
      required String id,
      required String sourceKind,
      Value<String?> sourceDocId,
      Value<String?> sourcePdfPath,
      Value<String?> sourceRecentId,
      required String title,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$EditDraftsTableUpdateCompanionBuilder =
    EditDraftsCompanion Function({
      Value<String> id,
      Value<String> sourceKind,
      Value<String?> sourceDocId,
      Value<String?> sourcePdfPath,
      Value<String?> sourceRecentId,
      Value<String> title,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$EditDraftsTableReferences
    extends BaseReferences<_$AppDatabase, $EditDraftsTable, EditDraft> {
  $$EditDraftsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EditDraftPagesTable, List<EditDraftPage>>
  _editDraftPagesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.editDraftPages,
    aliasName: 'edit_drafts__id__edit_draft_pages__draft_id',
  );

  $$EditDraftPagesTableProcessedTableManager get editDraftPagesRefs {
    final manager = $$EditDraftPagesTableTableManager(
      $_db,
      $_db.editDraftPages,
    ).filter((f) => f.draftId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_editDraftPagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$EditDraftsTableFilterComposer
    extends Composer<_$AppDatabase, $EditDraftsTable> {
  $$EditDraftsTableFilterComposer({
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

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDocId => $composableBuilder(
    column: $table.sourceDocId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePdfPath => $composableBuilder(
    column: $table.sourcePdfPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceRecentId => $composableBuilder(
    column: $table.sourceRecentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> editDraftPagesRefs(
    Expression<bool> Function($$EditDraftPagesTableFilterComposer f) f,
  ) {
    final $$EditDraftPagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.editDraftPages,
      getReferencedColumn: (t) => t.draftId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftPagesTableFilterComposer(
            $db: $db,
            $table: $db.editDraftPages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EditDraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $EditDraftsTable> {
  $$EditDraftsTableOrderingComposer({
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

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDocId => $composableBuilder(
    column: $table.sourceDocId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePdfPath => $composableBuilder(
    column: $table.sourcePdfPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceRecentId => $composableBuilder(
    column: $table.sourceRecentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EditDraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EditDraftsTable> {
  $$EditDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceDocId => $composableBuilder(
    column: $table.sourceDocId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourcePdfPath => $composableBuilder(
    column: $table.sourcePdfPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceRecentId => $composableBuilder(
    column: $table.sourceRecentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> editDraftPagesRefs<T extends Object>(
    Expression<T> Function($$EditDraftPagesTableAnnotationComposer a) f,
  ) {
    final $$EditDraftPagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.editDraftPages,
      getReferencedColumn: (t) => t.draftId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftPagesTableAnnotationComposer(
            $db: $db,
            $table: $db.editDraftPages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EditDraftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EditDraftsTable,
          EditDraft,
          $$EditDraftsTableFilterComposer,
          $$EditDraftsTableOrderingComposer,
          $$EditDraftsTableAnnotationComposer,
          $$EditDraftsTableCreateCompanionBuilder,
          $$EditDraftsTableUpdateCompanionBuilder,
          (EditDraft, $$EditDraftsTableReferences),
          EditDraft,
          PrefetchHooks Function({bool editDraftPagesRefs})
        > {
  $$EditDraftsTableTableManager(_$AppDatabase db, $EditDraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EditDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EditDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EditDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String?> sourceDocId = const Value.absent(),
                Value<String?> sourcePdfPath = const Value.absent(),
                Value<String?> sourceRecentId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EditDraftsCompanion(
                id: id,
                sourceKind: sourceKind,
                sourceDocId: sourceDocId,
                sourcePdfPath: sourcePdfPath,
                sourceRecentId: sourceRecentId,
                title: title,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceKind,
                Value<String?> sourceDocId = const Value.absent(),
                Value<String?> sourcePdfPath = const Value.absent(),
                Value<String?> sourceRecentId = const Value.absent(),
                required String title,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => EditDraftsCompanion.insert(
                id: id,
                sourceKind: sourceKind,
                sourceDocId: sourceDocId,
                sourcePdfPath: sourcePdfPath,
                sourceRecentId: sourceRecentId,
                title: title,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EditDraftsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({editDraftPagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (editDraftPagesRefs) db.editDraftPages,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (editDraftPagesRefs)
                    await $_getPrefetchedData<
                      EditDraft,
                      $EditDraftsTable,
                      EditDraftPage
                    >(
                      currentTable: table,
                      referencedTable: $$EditDraftsTableReferences
                          ._editDraftPagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$EditDraftsTableReferences(
                            db,
                            table,
                            p0,
                          ).editDraftPagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.draftId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$EditDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EditDraftsTable,
      EditDraft,
      $$EditDraftsTableFilterComposer,
      $$EditDraftsTableOrderingComposer,
      $$EditDraftsTableAnnotationComposer,
      $$EditDraftsTableCreateCompanionBuilder,
      $$EditDraftsTableUpdateCompanionBuilder,
      (EditDraft, $$EditDraftsTableReferences),
      EditDraft,
      PrefetchHooks Function({bool editDraftPagesRefs})
    >;
typedef $$EditDraftPagesTableCreateCompanionBuilder =
    EditDraftPagesCompanion Function({
      required String id,
      required String draftId,
      required int orderIndex,
      required String kind,
      required String sourcePath,
      Value<int?> sourceIndex,
      Value<int> rotation,
      Value<String?> crop,
      required String origin,
      Value<int> rowid,
    });
typedef $$EditDraftPagesTableUpdateCompanionBuilder =
    EditDraftPagesCompanion Function({
      Value<String> id,
      Value<String> draftId,
      Value<int> orderIndex,
      Value<String> kind,
      Value<String> sourcePath,
      Value<int?> sourceIndex,
      Value<int> rotation,
      Value<String?> crop,
      Value<String> origin,
      Value<int> rowid,
    });

final class $$EditDraftPagesTableReferences
    extends BaseReferences<_$AppDatabase, $EditDraftPagesTable, EditDraftPage> {
  $$EditDraftPagesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $EditDraftsTable _draftIdTable(_$AppDatabase db) =>
      db.editDrafts.createAlias('edit_draft_pages__draft_id__edit_drafts__id');

  $$EditDraftsTableProcessedTableManager get draftId {
    final $_column = $_itemColumn<String>('draft_id')!;

    final manager = $$EditDraftsTableTableManager(
      $_db,
      $_db.editDrafts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_draftIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$EditDraftMarksTable, List<EditDraftMark>>
  _editDraftMarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.editDraftMarks,
    aliasName: 'edit_draft_pages__id__edit_draft_marks__draft_page_id',
  );

  $$EditDraftMarksTableProcessedTableManager get editDraftMarksRefs {
    final manager = $$EditDraftMarksTableTableManager(
      $_db,
      $_db.editDraftMarks,
    ).filter((f) => f.draftPageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_editDraftMarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$EditDraftPagesTableFilterComposer
    extends Composer<_$AppDatabase, $EditDraftPagesTable> {
  $$EditDraftPagesTableFilterComposer({
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

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  $$EditDraftsTableFilterComposer get draftId {
    final $$EditDraftsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftId,
      referencedTable: $db.editDrafts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftsTableFilterComposer(
            $db: $db,
            $table: $db.editDrafts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> editDraftMarksRefs(
    Expression<bool> Function($$EditDraftMarksTableFilterComposer f) f,
  ) {
    final $$EditDraftMarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.editDraftMarks,
      getReferencedColumn: (t) => t.draftPageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftMarksTableFilterComposer(
            $db: $db,
            $table: $db.editDraftMarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EditDraftPagesTableOrderingComposer
    extends Composer<_$AppDatabase, $EditDraftPagesTable> {
  $$EditDraftPagesTableOrderingComposer({
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

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  $$EditDraftsTableOrderingComposer get draftId {
    final $$EditDraftsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftId,
      referencedTable: $db.editDrafts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftsTableOrderingComposer(
            $db: $db,
            $table: $db.editDrafts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EditDraftPagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EditDraftPagesTable> {
  $$EditDraftPagesTableAnnotationComposer({
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

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  $$EditDraftsTableAnnotationComposer get draftId {
    final $$EditDraftsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftId,
      referencedTable: $db.editDrafts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftsTableAnnotationComposer(
            $db: $db,
            $table: $db.editDrafts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> editDraftMarksRefs<T extends Object>(
    Expression<T> Function($$EditDraftMarksTableAnnotationComposer a) f,
  ) {
    final $$EditDraftMarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.editDraftMarks,
      getReferencedColumn: (t) => t.draftPageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftMarksTableAnnotationComposer(
            $db: $db,
            $table: $db.editDraftMarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EditDraftPagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EditDraftPagesTable,
          EditDraftPage,
          $$EditDraftPagesTableFilterComposer,
          $$EditDraftPagesTableOrderingComposer,
          $$EditDraftPagesTableAnnotationComposer,
          $$EditDraftPagesTableCreateCompanionBuilder,
          $$EditDraftPagesTableUpdateCompanionBuilder,
          (EditDraftPage, $$EditDraftPagesTableReferences),
          EditDraftPage,
          PrefetchHooks Function({bool draftId, bool editDraftMarksRefs})
        > {
  $$EditDraftPagesTableTableManager(
    _$AppDatabase db,
    $EditDraftPagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EditDraftPagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EditDraftPagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EditDraftPagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> draftId = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<int?> sourceIndex = const Value.absent(),
                Value<int> rotation = const Value.absent(),
                Value<String?> crop = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EditDraftPagesCompanion(
                id: id,
                draftId: draftId,
                orderIndex: orderIndex,
                kind: kind,
                sourcePath: sourcePath,
                sourceIndex: sourceIndex,
                rotation: rotation,
                crop: crop,
                origin: origin,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String draftId,
                required int orderIndex,
                required String kind,
                required String sourcePath,
                Value<int?> sourceIndex = const Value.absent(),
                Value<int> rotation = const Value.absent(),
                Value<String?> crop = const Value.absent(),
                required String origin,
                Value<int> rowid = const Value.absent(),
              }) => EditDraftPagesCompanion.insert(
                id: id,
                draftId: draftId,
                orderIndex: orderIndex,
                kind: kind,
                sourcePath: sourcePath,
                sourceIndex: sourceIndex,
                rotation: rotation,
                crop: crop,
                origin: origin,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EditDraftPagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({draftId = false, editDraftMarksRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (editDraftMarksRefs) db.editDraftMarks,
                  ],
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
                        if (draftId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.draftId,
                                    referencedTable:
                                        $$EditDraftPagesTableReferences
                                            ._draftIdTable(db),
                                    referencedColumn:
                                        $$EditDraftPagesTableReferences
                                            ._draftIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (editDraftMarksRefs)
                        await $_getPrefetchedData<
                          EditDraftPage,
                          $EditDraftPagesTable,
                          EditDraftMark
                        >(
                          currentTable: table,
                          referencedTable: $$EditDraftPagesTableReferences
                              ._editDraftMarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EditDraftPagesTableReferences(
                                db,
                                table,
                                p0,
                              ).editDraftMarksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.draftPageId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$EditDraftPagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EditDraftPagesTable,
      EditDraftPage,
      $$EditDraftPagesTableFilterComposer,
      $$EditDraftPagesTableOrderingComposer,
      $$EditDraftPagesTableAnnotationComposer,
      $$EditDraftPagesTableCreateCompanionBuilder,
      $$EditDraftPagesTableUpdateCompanionBuilder,
      (EditDraftPage, $$EditDraftPagesTableReferences),
      EditDraftPage,
      PrefetchHooks Function({bool draftId, bool editDraftMarksRefs})
    >;
typedef $$EditDraftMarksTableCreateCompanionBuilder =
    EditDraftMarksCompanion Function({
      required String id,
      required String draftPageId,
      required String kind,
      required String rect,
      Value<String?> assetPath,
      Value<String?> markText,
      Value<int?> colorArgb,
      Value<double?> param,
      Value<int> rowid,
    });
typedef $$EditDraftMarksTableUpdateCompanionBuilder =
    EditDraftMarksCompanion Function({
      Value<String> id,
      Value<String> draftPageId,
      Value<String> kind,
      Value<String> rect,
      Value<String?> assetPath,
      Value<String?> markText,
      Value<int?> colorArgb,
      Value<double?> param,
      Value<int> rowid,
    });

final class $$EditDraftMarksTableReferences
    extends BaseReferences<_$AppDatabase, $EditDraftMarksTable, EditDraftMark> {
  $$EditDraftMarksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $EditDraftPagesTable _draftPageIdTable(_$AppDatabase db) => db
      .editDraftPages
      .createAlias('edit_draft_marks__draft_page_id__edit_draft_pages__id');

  $$EditDraftPagesTableProcessedTableManager get draftPageId {
    final $_column = $_itemColumn<String>('draft_page_id')!;

    final manager = $$EditDraftPagesTableTableManager(
      $_db,
      $_db.editDraftPages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_draftPageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EditDraftMarksTableFilterComposer
    extends Composer<_$AppDatabase, $EditDraftMarksTable> {
  $$EditDraftMarksTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rect => $composableBuilder(
    column: $table.rect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetPath => $composableBuilder(
    column: $table.assetPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get markText => $composableBuilder(
    column: $table.markText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorArgb => $composableBuilder(
    column: $table.colorArgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get param => $composableBuilder(
    column: $table.param,
    builder: (column) => ColumnFilters(column),
  );

  $$EditDraftPagesTableFilterComposer get draftPageId {
    final $$EditDraftPagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftPageId,
      referencedTable: $db.editDraftPages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftPagesTableFilterComposer(
            $db: $db,
            $table: $db.editDraftPages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EditDraftMarksTableOrderingComposer
    extends Composer<_$AppDatabase, $EditDraftMarksTable> {
  $$EditDraftMarksTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rect => $composableBuilder(
    column: $table.rect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetPath => $composableBuilder(
    column: $table.assetPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get markText => $composableBuilder(
    column: $table.markText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorArgb => $composableBuilder(
    column: $table.colorArgb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get param => $composableBuilder(
    column: $table.param,
    builder: (column) => ColumnOrderings(column),
  );

  $$EditDraftPagesTableOrderingComposer get draftPageId {
    final $$EditDraftPagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftPageId,
      referencedTable: $db.editDraftPages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftPagesTableOrderingComposer(
            $db: $db,
            $table: $db.editDraftPages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EditDraftMarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $EditDraftMarksTable> {
  $$EditDraftMarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get rect =>
      $composableBuilder(column: $table.rect, builder: (column) => column);

  GeneratedColumn<String> get assetPath =>
      $composableBuilder(column: $table.assetPath, builder: (column) => column);

  GeneratedColumn<String> get markText =>
      $composableBuilder(column: $table.markText, builder: (column) => column);

  GeneratedColumn<int> get colorArgb =>
      $composableBuilder(column: $table.colorArgb, builder: (column) => column);

  GeneratedColumn<double> get param =>
      $composableBuilder(column: $table.param, builder: (column) => column);

  $$EditDraftPagesTableAnnotationComposer get draftPageId {
    final $$EditDraftPagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftPageId,
      referencedTable: $db.editDraftPages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditDraftPagesTableAnnotationComposer(
            $db: $db,
            $table: $db.editDraftPages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EditDraftMarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EditDraftMarksTable,
          EditDraftMark,
          $$EditDraftMarksTableFilterComposer,
          $$EditDraftMarksTableOrderingComposer,
          $$EditDraftMarksTableAnnotationComposer,
          $$EditDraftMarksTableCreateCompanionBuilder,
          $$EditDraftMarksTableUpdateCompanionBuilder,
          (EditDraftMark, $$EditDraftMarksTableReferences),
          EditDraftMark,
          PrefetchHooks Function({bool draftPageId})
        > {
  $$EditDraftMarksTableTableManager(
    _$AppDatabase db,
    $EditDraftMarksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EditDraftMarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EditDraftMarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EditDraftMarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> draftPageId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> rect = const Value.absent(),
                Value<String?> assetPath = const Value.absent(),
                Value<String?> markText = const Value.absent(),
                Value<int?> colorArgb = const Value.absent(),
                Value<double?> param = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EditDraftMarksCompanion(
                id: id,
                draftPageId: draftPageId,
                kind: kind,
                rect: rect,
                assetPath: assetPath,
                markText: markText,
                colorArgb: colorArgb,
                param: param,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String draftPageId,
                required String kind,
                required String rect,
                Value<String?> assetPath = const Value.absent(),
                Value<String?> markText = const Value.absent(),
                Value<int?> colorArgb = const Value.absent(),
                Value<double?> param = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EditDraftMarksCompanion.insert(
                id: id,
                draftPageId: draftPageId,
                kind: kind,
                rect: rect,
                assetPath: assetPath,
                markText: markText,
                colorArgb: colorArgb,
                param: param,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EditDraftMarksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({draftPageId = false}) {
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
                    if (draftPageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.draftPageId,
                                referencedTable: $$EditDraftMarksTableReferences
                                    ._draftPageIdTable(db),
                                referencedColumn:
                                    $$EditDraftMarksTableReferences
                                        ._draftPageIdTable(db)
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

typedef $$EditDraftMarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EditDraftMarksTable,
      EditDraftMark,
      $$EditDraftMarksTableFilterComposer,
      $$EditDraftMarksTableOrderingComposer,
      $$EditDraftMarksTableAnnotationComposer,
      $$EditDraftMarksTableCreateCompanionBuilder,
      $$EditDraftMarksTableUpdateCompanionBuilder,
      (EditDraftMark, $$EditDraftMarksTableReferences),
      EditDraftMark,
      PrefetchHooks Function({bool draftPageId})
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
  $$EditDraftsTableTableManager get editDrafts =>
      $$EditDraftsTableTableManager(_db, _db.editDrafts);
  $$EditDraftPagesTableTableManager get editDraftPages =>
      $$EditDraftPagesTableTableManager(_db, _db.editDraftPages);
  $$EditDraftMarksTableTableManager get editDraftMarks =>
      $$EditDraftMarksTableTableManager(_db, _db.editDraftMarks);
}
