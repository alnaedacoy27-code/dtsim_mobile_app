double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
String _s(dynamic v) => (v ?? '').toString();
DateTime _dt(dynamic v) =>
    DateTime.tryParse(_s(v)) ?? DateTime.fromMillisecondsSinceEpoch(0);

String fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

class Supplier {
  final int id;
  final String companyName;
  final String companyAddress;
  final String name;

  const Supplier(this.id, this.companyName, this.companyAddress, this.name);

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        _i(j['id']),
        _s(j['companyName']),
        _s(j['companyAddress']),
        _s(j['name']),
      );

  String get label =>
      companyAddress.isEmpty ? companyName : '$companyName · $companyAddress';
}

class DeliveryBatch {
  final int id;
  final String batchNo;
  final String status; // draft | sent
  final DateTime deliveryDate;
  final double totalCost;
  final double expectedProfit;
  final String companyName;
  final String companyAddress;
  final String contact;
  final int itemCount;

  const DeliveryBatch({
    required this.id,
    required this.batchNo,
    required this.status,
    required this.deliveryDate,
    required this.totalCost,
    required this.expectedProfit,
    required this.companyName,
    required this.companyAddress,
    required this.contact,
    required this.itemCount,
  });

  bool get isDraft => status == 'draft';

  factory DeliveryBatch.fromJson(Map<String, dynamic> j) => DeliveryBatch(
        id: _i(j['id']),
        batchNo: _s(j['batchNo']),
        status: _s(j['status']),
        deliveryDate: _dt(j['deliveryDate']),
        totalCost: _d(j['totalCost']),
        expectedProfit: _d(j['expectedProfit']),
        companyName: _s(j['companyName']),
        companyAddress: _s(j['companyAddress']),
        contact: _s(j['contact']),
        itemCount: _i(j['itemCount']),
      );
}

class DeliveryItem {
  final int id;
  final int productId;
  final String name;
  final String measurement;
  final String barcode;
  final String category;
  final int qty; // always in pieces
  final double costPrice; // per piece
  final String costMode; // piece | pack
  final int packSize;
  final double enteredCost;
  final double sellingPrice;
  final double lineCost;
  final double expectedProfit;

  const DeliveryItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.measurement,
    required this.barcode,
    required this.category,
    required this.qty,
    required this.costPrice,
    required this.costMode,
    required this.packSize,
    required this.enteredCost,
    required this.sellingPrice,
    required this.lineCost,
    required this.expectedProfit,
  });

  bool get byPack => costMode == 'pack';

  /// What the user typed as the quantity (packs when costing by pack).
  int get enteredQty => byPack && packSize > 0 ? qty ~/ packSize : qty;

  String get title => measurement.isEmpty ? name : '$name · $measurement';

  factory DeliveryItem.fromJson(Map<String, dynamic> j) => DeliveryItem(
        id: _i(j['id']),
        productId: _i(j['productId']),
        name: _s(j['name']),
        measurement: _s(j['measurement']),
        barcode: _s(j['barcode']),
        category: _s(j['category']),
        qty: _i(j['qty']),
        costPrice: _d(j['costPrice']),
        costMode: _s(j['costMode']),
        packSize: _i(j['packSize']),
        enteredCost: _d(j['enteredCost']),
        sellingPrice: _d(j['sellingPrice']),
        lineCost: _d(j['lineCost']),
        expectedProfit: _d(j['expectedProfit']),
      );
}

class BatchDetail {
  final int id;
  final String batchNo;
  final String status;
  final DateTime deliveryDate;
  final int supplierId;
  final double totalCost;
  final double expectedProfit;
  final DateTime? sentAt;
  final String companyName;
  final String companyAddress;
  final String contact;
  final String? createdBy;
  final String? sentBy;
  final List<DeliveryItem> items;

  const BatchDetail({
    required this.id,
    required this.batchNo,
    required this.status,
    required this.deliveryDate,
    required this.supplierId,
    required this.totalCost,
    required this.expectedProfit,
    required this.sentAt,
    required this.companyName,
    required this.companyAddress,
    required this.contact,
    required this.createdBy,
    required this.sentBy,
    required this.items,
  });

  bool get isDraft => status == 'draft';

  factory BatchDetail.fromJson(Map<String, dynamic> j) => BatchDetail(
        id: _i(j['id']),
        batchNo: _s(j['batchNo']),
        status: _s(j['status']),
        deliveryDate: _dt(j['deliveryDate']),
        supplierId: _i(j['supplierId']),
        totalCost: _d(j['totalCost']),
        expectedProfit: _d(j['expectedProfit']),
        sentAt: j['sentAt'] == null ? null : _dt(j['sentAt']),
        companyName: _s(j['companyName']),
        companyAddress: _s(j['companyAddress']),
        contact: _s(j['contact']),
        createdBy: j['createdBy'] as String?,
        sentBy: j['sentBy'] as String?,
        items: ((j['items'] as List?) ?? [])
            .map((e) => DeliveryItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class LastPrice {
  final double costPrice; // per piece
  final String costMode;
  final int packSize;
  final double enteredCost;
  final double sellingPrice;
  final String batchNo;

  const LastPrice(this.costPrice, this.costMode, this.packSize,
      this.enteredCost, this.sellingPrice, this.batchNo);

  factory LastPrice.fromJson(Map<String, dynamic> j) => LastPrice(
        _d(j['costPrice']),
        _s(j['costMode']),
        _i(j['packSize']),
        _d(j['enteredCost']),
        _d(j['sellingPrice']),
        _s(j['batchNo']),
      );
}