const List<String> businessMainCategories = [
  'it_software',
  'legal_services',
  'banking_finance',
  'accounting',
  'consulting',
  'brokerage',
  'dealership',
  'notary',
  'real_estate',
  'health_wellness',
  'education_training',
  'marketing_media',
  'construction_trades',
  'home_services',
  'logistics_transport',
  'beauty_personal_care',
  'other',
];

String businessCategoryLabel(String value) {
  switch (value) {
    case 'it_software':
      return 'IT & Software';
    case 'legal_services':
      return 'Legal Services';
    case 'banking_finance':
      return 'Banking & Finance';
    case 'accounting':
      return 'Accountant';
    case 'consulting':
      return 'Consulting';
    case 'brokerage':
      return 'Broker';
    case 'dealership':
      return 'Dealer';
    case 'notary':
      return 'Notary';
    case 'real_estate':
      return 'Real Estate';
    case 'health_wellness':
      return 'Health & Wellness';
    case 'education_training':
      return 'Education & Training';
    case 'marketing_media':
      return 'Marketing & Media';
    case 'construction_trades':
      return 'Construction & Trades';
    case 'home_services':
      return 'Home Services';
    case 'logistics_transport':
      return 'Logistics & Transport';
    case 'beauty_personal_care':
      return 'Beauty & Personal Care';
    case 'other':
      return 'Other';
    default:
      return value;
  }
}