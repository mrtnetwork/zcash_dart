import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';

void main() {
  _test();
}

void _test() {
  QuickCrypto.setupPRNG(ChaCha20Rng(List<int>.filled(32, 11)));
  test("RedPallas signature", () {
    for (final i in _testVector) {
      final sk = OrchardSpendAuthorizingKey.fromBytes(
          BytesUtils.fromHexString(i["sk"]));
      final msg = BytesUtils.fromHexString(i["msg"]);
      final signature = sk.sign(msg);
      expect(signature.rBytes, BytesUtils.fromHexString(i["r_bytes"]));
      expect(signature.sBytes, BytesUtils.fromHexString(i["s_bytes"]));
      final vk = sk.toVerificationKey();
      expect(vk.verifySignature(signature, msg), true);
    }
  });
}

const List<Map<String, dynamic>> _testVector = [
  {
    "sk": "837c67fa25bd9dc8798790e69204972876815c12b969a8df3e5c73470f918110",
    "msg": "cb5af547dc97b77939b09f0f2acf3e0c22580ebf2fdc0de3cde47e5a8aa3d2ca",
    "r_bytes":
        "669a73277c04ecda960888f4d055b23f8eccfb0277345f42baad66982dee8eaf",
    "s_bytes":
        "f9d3640602c64ebfea79dec301bd0d97b800abbefd3c7d3c9d2423a698c1c911"
  },
  {
    "sk": "85c9cc94af3dcf5be21eb292e386e41c8129d6fc3c88d56bc011a3b51346b71c",
    "msg": "4ae9cdd649068149c030b7adb7af6eabeed35dc2d6710be4f69413271cc3eb62",
    "r_bytes":
        "246187bf779e000bb8a972c0fff18ea250105ef8249fc7edbde7ebf9f22a4e9d",
    "s_bytes":
        "7e4f6bb94b78a8e6de6b4ffac07a0ab7f720b62ab16d3156fc2f7cac0899323e"
  },
  {
    "sk": "39ee6eb132ae3b50d2283a4e702155d8df27a9ba7a475ab7ae603f0a13694601",
    "msg": "54a3030fcb5cf63e728afe5640aa43dfb364c6bc4e4d1fd2f4fa3b6829776aad",
    "r_bytes":
        "bb13c7032e2901536976d8cc3b65692382d931cfec1ab3544ba42e2d75d14634",
    "s_bytes":
        "1f88cde9a1c43a803a86df1ecdf5f12162dad9c2a910dae6e107aac6c43d072c"
  },
  {
    "sk": "402a429525bdb532c09a15ac488dd2fb6fd169aa3d24c52088bec58b9836a00d",
    "msg": "e2b530b5f9d52fadc3597bc0ad5d73be8f0e10a971ff543e42caef4f7f5a3a23",
    "r_bytes":
        "1ff1e48c22abf3d22cb03c0ec57471c09e02fee55559f97026f005b0e0b9efae",
    "s_bytes":
        "ac1249b4b58348acb88fd04bd351b0ff789ef942caf95c1fa02413675bd70e04"
  },
  {
    "sk": "031a0059b5742674a8b2ea54605c4ae9df76290b8b4808e843b88b64478b4712",
    "msg": "7c72ad1a3fb81b6e798677be8e37c52555d0ef6b8ce050b96f05628ce9db39db",
    "r_bytes":
        "1fe1365c2f0a5c333c1e885da99757a39dcee45af9703136757c63e6c43ec104",
    "s_bytes":
        "c7a7284305973fca2fc43026b0ad3aa69742dd82a5058adb05837a216e969815"
  },
  {
    "sk": "d7ede614b24740b3025f2bc31d4bcf7073a80d31aa3a08e86c0cda350e1fb102",
    "msg": "0ffce8789869fb88d8e164c5d01178f73425ffcb7496c8be85eadb8b45b5f7f7",
    "r_bytes":
        "322023879d43acca98ab6fa3025d8db9bbeb0d0b3bf3378d900a19a6a46a5bab",
    "s_bytes":
        "d5c5baad6e7c8629a350c4ba1032320a076a3ba468ce313e86dfa530aff81f36"
  },
  {
    "sk": "e4e03e788cbbdda1d01ef02f72f23bdc57a8cee4023fe5353949e8e7702d2004",
    "msg": "c53bd8ab2eb866a58e818bfd8a03df48b89be2d80f65496812e37b60d57e7695",
    "r_bytes":
        "c91f7122e6a5e437bdf5ec3866f5a4a1f53be88d449200e3487dcc4830a05e86",
    "s_bytes":
        "cb4b1130b2eb4f1c39e0188b2e5a6383f383fd033151d8cd07cbea5b465e6f14"
  },
  {
    "sk": "d0eefb4e3ad57b0c9d5d49b999625efc077c8e4e349ee23bf36e801453f05418",
    "msg": "25bda4a51cfdd24f32c204995b407a74c25aa8cb937c28cd0ebfb7765c6edbbb",
    "r_bytes":
        "ebcc6e3f1dc39d45de39a478aaa9fbb63d7a82b0407bceabca5e4d0a0967d282",
    "s_bytes":
        "99ca4e08a121578a022b88fd551ab2d4e1d40b1aef8aab5a117fcb032fa7f835"
  },
  {
    "sk": "76fc5362909dbb840fdd1ae46f525a3f8c3c3a7e6b53c1a352e8cb1e68967810",
    "msg": "5efe207f2101cf3af0ddf54eddd804536fdf02e0ee08ec605ea4f870e9671d95",
    "r_bytes":
        "0e6acac783eb6e7bfe964d5f23dc239056ff7334a7aeec537f9a12e9a7542183",
    "s_bytes":
        "0ff24ca4238185ef9105ea57e80b789213bc835bdccb7bb157432261836d3831"
  },
  {
    "sk": "3823c3e7c25da8ae9430cdaffd53646d419534730ba6d44cfca02ff5d435c21e",
    "msg": "91814112488bcbdeb4dc2504cf61a7d6a36656914c4e9b1953c10c9eeb1cac13",
    "r_bytes":
        "9c6dc6bfa6f90558b4ed3aba376a35f3d175b5a50c68f779260a6b45489b4b92",
    "s_bytes":
        "79ab7c1cf38da6b421a2ddbfddca7f50b2f67950fe87ccb560209effbc4a7e13"
  }
];
