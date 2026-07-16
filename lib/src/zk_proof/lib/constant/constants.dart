import 'package:zcash_dart/zcash.dart';

class ZKLibConst {
  static const List<int> supoortedVersions = [1];
  static const String saplingSpendName = "sapling-spend.params";
  static const String saplingOutputName = "sapling-output.params";
  static const int saplingSpendBytesLength = 47958396;
  static const int saplingOutputBytesLength = 3592860;
  static const List<int> saplingSpendBytes = [
    saplingSpendBytesLength,
    saplingSpendBytesLength - 52836,
  ];
  static const List<int> saplingOutputBytes = [
    saplingOutputBytesLength,
    saplingOutputBytesLength - 52836,
  ];
  static const String downloadUrl = "https://download.z.cash/downloads";

  static List<String> getZcashDownloadParamLinks(
    ZcashSaplingParameter type, {
    String? downloadUrl,
  }) {
    final url = downloadUrl ?? ZKLibConst.downloadUrl;
    return switch (type) {
      ZcashSaplingParameter.spend => [
        "$url/$saplingSpendName.part.1",
        "$url/$saplingSpendName.part.2",
      ],
      _ => ["$url/$saplingOutputName.part.1", "$url/$saplingOutputName.part.2"],
    };
  }
}
