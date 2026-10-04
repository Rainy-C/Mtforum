part of '../../../models/models.dart';

class MallItem {
  final String tid;
  final String title;
  final String? imageUrl;
  final int? priceGold;
  final String? marketPrice;
  final int? remaining;
  final int? purchased;
  final String? endTime;

  const MallItem({
    required this.tid,
    required this.title,
    this.imageUrl,
    this.priceGold,
    this.marketPrice,
    this.remaining,
    this.purchased,
    this.endTime,
  });
}

class MallDetail {
  final String tid;
  final String title;
  final String? imageUrl;
  final int? priceGold;
  final String? marketPrice;
  final String? buyUrl;
  final String? cardStatusUrl;

  const MallDetail({
    required this.tid,
    required this.title,
    this.imageUrl,
    this.priceGold,
    this.marketPrice,
    this.buyUrl,
    this.cardStatusUrl,
  });
}

class MallExchangeResult {
  final bool success;
  final String message;
  final String? url;

  const MallExchangeResult({
    required this.success,
    required this.message,
    this.url,
  });
}

class MallCardRecord {
  final String card;
  final String exchangedAt;
  final String? status;

  const MallCardRecord({
    required this.card,
    this.exchangedAt = '',
    this.status,
  });
}

class MallCardPurchase {
  final String tid;
  final String title;
  final String orderedAt;
  final String? status;
  final List<MallCardRecord> records;
  final bool loadFailed;

  const MallCardPurchase({
    required this.tid,
    required this.title,
    this.orderedAt = '',
    this.status,
    this.records = const [],
    this.loadFailed = false,
  });

  MallCardPurchase copyWith({
    List<MallCardRecord>? records,
    bool? loadFailed,
  }) {
    return MallCardPurchase(
      tid: tid,
      title: title,
      orderedAt: orderedAt,
      status: status,
      records: records ?? this.records,
      loadFailed: loadFailed ?? this.loadFailed,
    );
  }
}

class MallCardStatus {
  final List<MallCardPurchase> purchases;

  const MallCardStatus({
    this.purchases = const [],
  });

  int get recordCount => purchases.fold<int>(
        0,
        (total, purchase) => total + purchase.records.length,
      );

  bool get isEmpty => recordCount == 0 && purchases.isEmpty;
}
