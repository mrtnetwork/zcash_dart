import 'dart:io';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/onchain_proto.dart';

class ZcashPackageRegistryBuilderTarget {
  final String output;
  final String className;
  final String typeName;
  const ZcashPackageRegistryBuilderTarget({
    required this.output,
    required this.className,
    required this.typeName,
  });
}

class ZcashPackageRegisteryBuilder {
  final List<ProtoWritePackageResult> packages;
  final List<String> imports;
  const ZcashPackageRegisteryBuilder({
    required this.packages,
    this.imports = const [],
  });
  void _writeTypeUrl() {
    final buf = StringBuffer();
    buf.writeln("import 'package:blockchain_utils/blockchain_utils.dart';");
    buf.writeln(
      "import 'package:zcash_dart/src/serialization/protobuf/protobuf.dart';",
    );
    buf.writeln("import 'package:zcash_dart/src/exception/exception.dart';");
    buf.writeln('enum DefaultZcashProtoTypeUrl implements ZcashProtoTypeUrl {');
    final messages =
        packages
            .expand((e) => e.files)
            .expand((e) => e.fileData.classInfo)
            .toList();
    // final
    for (final i in messages.indexed) {
      final msg = i.$2;
      final isLast = i.$1 == messages.length - 1;
      final name = OnChainProtoUtils.snakeToCamel(
        "${msg.package}.${msg.message.fullName()}".replaceAll(".", "_"),
        capitalizeFirst: false,
      );
      String? serviceUrl;
      final service = msg.message.services.firstOrNull;
      if (service != null) {
        serviceUrl = "/${msg.package}.${service.fullName()}";
      }

      buf.writeln(
        "  $name(typeUrl: '${msg.typeUrl}',${serviceUrl == null ? '' : 'serviceUrl: "$serviceUrl"'})${isLast ? ';' : ','}",
      );
    }
    buf.writeln('@override');
    buf.writeln('final String typeUrl;');
    buf.writeln('@override');
    buf.writeln('final String? serviceUrl;');
    buf.writeln(
      ' const DefaultZcashProtoTypeUrl({required this.typeUrl, this.serviceUrl});',
    );
    buf.writeln('  static DefaultZcashProtoTypeUrl? fromUrl(String? value) {');
    buf.writeln(
      '    return DefaultZcashProtoTypeUrl.values.firstWhereNullable(',
    );
    buf.writeln('      (e) => e.typeUrl == value || e.serviceUrl == value,');
    buf.writeln('    );');
    buf.writeln('  }');

    buf.writeln(' String getServiceUrl() {');
    buf.writeln('    final serviceUrl = this.serviceUrl;');
    buf.writeln(
      'if (serviceUrl == null) {throw BuError(DefaultErrorType.invalidState, "Missing proto service url.", details: {"type_url": typeUrl}, ); }',
    );
    buf.writeln('return serviceUrl;');
    buf.writeln('  }');

    buf.writeln('}');
    File("lib/src/provider/walletd/proto_messages/types.dart")
      ..createSync(recursive: true)
      ..writeAsStringSync(buf.toString());
  }

  void write() {
    _writeTypeUrl();
  }
}

class ZcashProtoPackagesBuilder {
  final ProtoCompiler compiler;
  const ZcashProtoPackagesBuilder._({required this.compiler});
  factory ZcashProtoPackagesBuilder() {
    final compiler = ProtoCompiler.fromDirectory(
      classNamePrefix: 'ZWalletd',
      builder: ZcashProtoCodegenTarget(),
      writer: ProtoPackageWriter(
        packageRoot: "package:zcash_dart/src/provider/walletd/proto_messages",
        outputRoot: "lib/src/provider/walletd/proto_messages",
      ),
      sourceDirectory: "proto/lightwallet-protocol/walletrpc",
    );
    return ZcashProtoPackagesBuilder._(compiler: compiler);
  }
  void compile() {
    compiler.compile();
    final result = compiler.writeAll();
    final registeryBuilder = ZcashPackageRegisteryBuilder(
      packages: result,
      imports: [],
    );
    registeryBuilder.write();
  }
}

/// running from root directory of project
/// zcash_dart$ dart run proto/builder.dart

void main() {
  final builder = ZcashProtoPackagesBuilder();
  builder.compile();
}

class ZcashProtoCodegenTarget extends DefaultProtoCodegenTarget {
  @override
  String get messageBaseClassName => "ZcashProtoMessage";
  static const queryMixinName = "IZcashProtoQueryMessage";
  static const List<String> knownQueryServices = ["CompactTxStreamer"];
  final List<String> imports;
  const ZcashProtoCodegenTarget({
    this.imports = const [
      "package:zcash_dart/src/provider/walletd/proto_messages/types.dart",
      "package:zcash_dart/src/serialization/protobuf/protobuf.dart",
    ],
  });

  @override
  List<ProtoOption> filterFieldOptions(ProtoField field) {
    return field.options;
  }

  @override
  List<ProtoOption> filterMessageOptions(
    ProtoMessage message,
    List<ServiceMessageOption> services,
  ) {
    return message.options;
  }

  @override
  List<String> defaultImports(ProtoFile file) {
    return [...super.defaultImports(file), ...imports];
  }

  @override
  List<String> mixinsFor(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    if (message.services.isEmpty) return [];
    List<String> mixins = [];
    for (final i in message.services) {
      if (knownQueryServices.contains(i.serviceName)) {
        mixins.add(
          '$queryMixinName<${ProtoRuntimeTypeMapper.bareDartType(type: i.type, importRefrences: importRefrences, resolver: resolver)}>',
        );
        break;
      }
    }
    return mixins;
  }

  @override
  String buildExtraMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    // Same rationale as CosmosProtoCodegenTarget.buildExtraMembers: keep
    // this tied to proto-space names, not the (possibly prefixed) Dart
    // class name.
    final name = OnChainProtoUtils.snakeToCamel(
      "${message.package}.${message.fullName()}".replaceAll(".", "_"),
      capitalizeFirst: false,
    );
    final buf = StringBuffer();
    buf.writeln('  @override');
    buf.writeln(
      'DefaultZcashProtoTypeUrl get declarationId => DefaultZcashProtoTypeUrl.$name;',
    );

    final queryService = message.services.firstWhereNullable(
      (e) => knownQueryServices.contains(e.serviceName),
    );
    if (queryService != null) {
      final query = queryService.type;
      buf.writeln('  @override');
      buf.writeln(
        '  ${ProtoRuntimeTypeMapper.bareDartType(type: query, importRefrences: importRefrences, resolver: resolver)} onQueryResponse(List<int> bytes) {',
      );
      buf.writeln(
        "    return ${ProtoRuntimeTypeMapper.bareDartType(type: query, importRefrences: importRefrences, resolver: resolver)}.deserialize(bytes);",
      );
      buf.writeln('  }');
    }
    return buf.toString();
  }

  @override
  List<ProtoService> filterServices(List<ProtoService> services) {
    return services.where((e) => knownQueryServices.contains(e.name)).toList();
  }

  // @override
  // String? buildFromJson(
  //   ProtoMessage message,
  //   ProtoCompiler resolver,
  //   String className,
  //   Set<ProtoTypeLocation> importRefrences, {
  //   StringEncoding? bytesEncoding,
  //   bool camelCase = false,
  //   StringBuffer? buf,
  //   bool acceptCamelCase = true,
  //   bool defaultOnMissing = true,
  // }) {
  //   return null;
  // }

  @override
  List<ProtoFile> attachServiceMetadata(Map<String, List<ProtoFile>> packages) {
    final resolved = packages.clone();

    void replace(ProtoFile oldFile, ProtoFile newFile) {
      final files = resolved[oldFile.package]!;
      final index = files.indexWhere((e) => identical(e, oldFile));
      files[index] = newFile;
    }

    for (final package in packages.values) {
      for (final proto in package) {
        final services = filterServices(proto.services);
        for (final service in services) {
          for (final rpc in service.rpcs) {
            final message = ProtoMessage(
              name: rpc.name,
              comments: "",
              options: [],
              fields: [
                ProtoField(
                  name: rpc.name,
                  tag: 0,
                  type: rpc.request,
                  options: [],
                  comments: rpc.comments,
                ),
              ],
              package: proto.package,
              services: [
                ServiceMessageOption(
                  rpc: rpc,
                  type: rpc.response,
                  serviceName: service.name,
                ),
              ],
            );
            final sourceFile = resolved[rpc.request.package]!
                .firstWhereNullable((file) {
                  return file.messages.any((m) => m.isEqualTo(rpc.request));
                });
            if (sourceFile == null) {
              continue;
            }
            replace(
              sourceFile,
              sourceFile.copyWith(messages: [...sourceFile.messages, message]),
            );
          }
        }
      }
    }

    return resolved.values.expand((e) => e).toList();
  }

  @override
  String? buildDeserialize(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    bool camelCase = false,
  }) {
    if (message.services.isEmpty) {
      return super.buildDeserialize(
        message,
        resolver,
        className,
        importRefrences,
        camelCase: camelCase,
      );
    }
    return null;
  }

  @override
  String buildConfigMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    ProtoSyntax syntax,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    if (message.services.isEmpty) {
      return super.buildConfigMembers(
        message,
        resolver,
        syntax,
        importRefrences,
      );
    }
    final buf = StringBuffer();
    final field = message.fields.first;
    buf.writeln('  @override');
    buf.writeln(
      '  ProtoMessageConfig protoConfig() =>${OnChainProtoUtils.fieldName(field.name)}?.protoConfig() ?? ProtoMessageConfig();',
    );
    buf.writeln();

    assert(message.fields.length == 1, "unexpected service");

    buf.writeln('  @override');
    buf.writeln(
      '  List<Object?> get protoValues => ${OnChainProtoUtils.fieldName(field.name)}?.protoValues??[];',
    );
    return buf.toString();
  }
}
