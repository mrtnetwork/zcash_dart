import 'dart:io';
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
  const ZcashPackageRegisteryBuilder({required this.packages, this.imports = const []});
  void _writeTypeUrl() {
    final buf = StringBuffer();
    buf.writeln("import 'package:blockchain_utils/blockchain_utils.dart';");
    buf.writeln("import 'package:zcash_dart/src/serialization/protobuf/protobuf.dart';");
    buf.writeln("import 'package:zcash_dart/src/exception/exception.dart';");
    buf.writeln('enum DefaultZcashProtoTypeUrl implements ZcashProtoTypeUrl {');
    final messages =
        packages.expand((e) => e.files).expand((e) => e.fileData.classInfo).toList();
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
    buf.writeln('    return DefaultZcashProtoTypeUrl.values.firstWhereNullable(');
    buf.writeln('      (e) => e.typeUrl == value || e.serviceUrl == value,');
    buf.writeln('    );');
    buf.writeln('  }');

    buf.writeln(' String getServiceUrl() {');
    buf.writeln('    final serviceUrl = this.serviceUrl;');
    buf.writeln(
      'if (serviceUrl == null) {throw DartZcashPluginException("Missing proto service url.", details: {"type_url": typeUrl}, ); }',
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
      sourceDirectory: "proto/lightwalletd_0_4_19",
    );
    return ZcashProtoPackagesBuilder._(compiler: compiler);
  }
  void compile() {
    compiler.compile();
    final result = compiler.writeAll();
    final registeryBuilder = ZcashPackageRegisteryBuilder(packages: result, imports: []);
    registeryBuilder.write();
  }
}

/// running from root directory of project
/// zcash_dart$ dart run proto/builder.dart

void main() {
  final builder = ZcashProtoPackagesBuilder();
  builder.compile();
}
