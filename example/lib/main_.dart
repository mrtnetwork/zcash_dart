import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/transfer_example.dart';
import 'package:example/examples/transfer/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zcash_dart/zcash.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(ZcashTransferExample());
}

class ZcashTransferExample extends StatelessWidget {
  const ZcashTransferExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: ZcashTransferExamplePage());
  }
}

class ZcashTransferExamplePage extends StatefulWidget {
  const ZcashTransferExamplePage({super.key});

  @override
  State<ZcashTransferExamplePage> createState() => _ZcashTransferExamplePageState();
}

class _ZcashTransferExamplePageState extends State<ZcashTransferExamplePage> {
  // Future<void> run(dynamic _) async {

  // }

  Future<void> run() async {
    final provider = switch (kIsWeb) {
      false => createGrpcClient(url: "localhost", port: 9067),
      true => createGrpcClient(url: "http://localhost:8080", port: 8080),
    };
    await getLatestBlockId(provider);
    final zklib = await ZKLib.init(
      ZKLibConfig(
        libUri: "libzk.so",
        saplingParamsDownloader: SaplingLocalParamDownloer(),
        wasm: ZKWasmConfig(
          moduleUrl: "/assets/zk/zk.js",
          wasmUrl: "/assets/zk/zk_bg.wasm",
        ),
      ),
    );
    final context = await getContext(lib: zklib);

    await fullTransferExample(lib: zklib, context: context, provider: provider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Zcash transfer example.")),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [ElevatedButton(onPressed: run, child: Text("transfer"))],
      ),
    );
  }
}

class SaplingLocalParamDownloer implements ZcashDownloadService {
  const SaplingLocalParamDownloer();
  @override
  Future<List<int>> doRequest(Uri uri, ZcashSaplingParameter type) async {
    final data = await switch (type) {
      ZcashSaplingParameter.spend => rootBundle.load(
        "assets/zk_params/sapling-spend.params.part.1",
      ),
      ZcashSaplingParameter.output => rootBundle.load(
        "assets/zk_params/sapling-output.params.part.1",
      ),
    };
    return data.buffer.asUint8List();
  }
}
