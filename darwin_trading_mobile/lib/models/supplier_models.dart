/// A supplier (one branch) from the desktop system's Suppliers list.
class Supplier {
  final int id;
  final String companyName;
  final String contactPerson;
  final String? contactNumber;
  final String address;
  final String? email;
  final int branches;
  final int deliveries;
  final DateTime? lastDelivery;

  const Supplier({
    required this.id,
    required this.companyName,
    required this.contactPerson,
    required this.contactNumber,
    required this.address,
    required this.email,
    required this.branches,
    required this.deliveries,
    required this.lastDelivery,
  });

  bool get hasNumber => (contactNumber ?? '').isNotEmpty;
  bool get hasEmail => (email ?? '').isNotEmpty;

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: (j['id'] as num).toInt(),
        companyName: (j['companyName'] ?? '').toString(),
        contactPerson: (j['contactPerson'] ?? '').toString(),
        contactNumber: j['contactNumber']?.toString(),
        address: (j['address'] ?? '').toString(),
        email: j['email']?.toString(),
        branches: (j['branches'] as num?)?.toInt() ?? 1,
        deliveries: (j['deliveries'] as num?)?.toInt() ?? 0,
        lastDelivery: j['lastDelivery'] == null ? null : DateTime.tryParse(j['lastDelivery'].toString()),
      );
}

class SupplierDelivery {
  final int id;
  final String batchNo;
  final DateTime deliveryDate;
  final String status; // draft | sent
  final int items;

  const SupplierDelivery(this.id, this.batchNo, this.deliveryDate, this.status, this.items);

  factory SupplierDelivery.fromJson(Map<String, dynamic> j) => SupplierDelivery(
        (j['id'] as num).toInt(),
        (j['batchNo'] ?? '').toString(),
        DateTime.tryParse(j['deliveryDate'].toString()) ?? DateTime.now(),
        (j['status'] ?? '').toString(),
        (j['items'] as num?)?.toInt() ?? 0,
      );
}

/// A supplier with its last 5 deliveries (GET api/Suppliers/{id}).
class SupplierDetail {
  final Supplier supplier;
  final List<SupplierDelivery> recentDeliveries;

  const SupplierDetail(this.supplier, this.recentDeliveries);

  factory SupplierDetail.fromJson(Map<String, dynamic> j) => SupplierDetail(
        Supplier.fromJson((j['supplier'] as Map).cast<String, dynamic>()),
        ((j['recentDeliveries'] as List?) ?? const [])
            .map((e) => SupplierDelivery.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Nov 22, 2026"
String formatDay(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// "0917 123 4567" (easier to read out over the phone)
String formatMobile(String? n) {
  final s = (n ?? '').trim();
  if (s.length != 11) return s;
  return '${s.substring(0, 4)} ${s.substring(4, 7)} ${s.substring(7)}';
}
