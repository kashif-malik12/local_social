const List<String> businessMainCategories = [
  'it_software',
  'legal_services',
  'banking_finance',
  'accounting',
  'consulting',
  'brokerage',
  'dealership',
  'trader',
  'manufacturer',
  'auto_garage',
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

String businessCategoryLabel(String value, {bool isFrench = false}) {
  return localizedBusinessCategoryLabel(value, isFrench: isFrench);
}

String localizedBusinessCategoryLabel(String value, {bool isFrench = false}) {
  switch (value) {
    case 'it_software':
      return isFrench ? 'Informatique et logiciels' : 'IT & Software';
    case 'legal_services':
      return isFrench ? 'Services juridiques' : 'Legal Services';
    case 'banking_finance':
      return isFrench ? 'Banque et finance' : 'Banking & Finance';
    case 'accounting':
      return isFrench ? 'Comptabilite' : 'Accountant';
    case 'consulting':
      return isFrench ? 'Conseil' : 'Consulting';
    case 'brokerage':
      return isFrench ? 'Courtage' : 'Broker';
    case 'dealership':
      return isFrench ? 'Concessionnaire' : 'Dealer';
    case 'trader':
      return isFrench ? 'Commerce' : 'Trader';
    case 'manufacturer':
      return isFrench ? 'Fabrication' : 'Manufacturer';
    case 'auto_garage':
      return isFrench ? 'Garage auto' : 'Auto Garage';
    case 'notary':
      return isFrench ? 'Notaire' : 'Notary';
    case 'real_estate':
      return isFrench ? 'Immobilier' : 'Real Estate';
    case 'health_wellness':
      return isFrench ? 'Sante et bien-etre' : 'Health & Wellness';
    case 'education_training':
      return isFrench ? 'Education et formation' : 'Education & Training';
    case 'marketing_media':
      return isFrench ? 'Marketing et medias' : 'Marketing & Media';
    case 'construction_trades':
      return isFrench ? 'Construction et metiers' : 'Construction & Trades';
    case 'home_services':
      return isFrench ? 'Services a domicile' : 'Home Services';
    case 'logistics_transport':
      return isFrench ? 'Logistique et transport' : 'Logistics & Transport';
    case 'beauty_personal_care':
      return isFrench ? 'Beaute et soins personnels' : 'Beauty & Personal Care';
    case 'other':
      return isFrench ? 'Autre' : 'Other';
    default:
      return value;
  }
}
