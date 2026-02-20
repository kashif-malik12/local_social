enum PostType {
  post,
  market,
  serviceOffer,
  serviceRequest,
  lostFound,
}

extension PostTypeX on PostType {
  String get dbValue {
    switch (this) {
      case PostType.post:
        return 'post';
      case PostType.market:
        return 'market';
      case PostType.serviceOffer:
        return 'service_offer';
      case PostType.serviceRequest:
        return 'service_request';
      case PostType.lostFound:
        return 'lost_found';
    }
  }

  String get label {
    switch (this) {
      case PostType.post:
        return 'Posts';
      case PostType.market:
        return 'Buy & Sell';
      case PostType.serviceOffer:
        return 'Offer Service';
      case PostType.serviceRequest:
        return 'Request Service';
      case PostType.lostFound:
        return 'Lost & Found';
    }
  }
}
