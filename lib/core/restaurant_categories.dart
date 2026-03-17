const List<String> restaurantMainCategories = [
  'italian',
  'indian',
  'chinese',
  'japanese',
  'middle_eastern',
  'fast_food',
  'cafe_bakery',
  'takeaway',
  'fine_dining',
  'other',
];

String restaurantCategoryLabel(String value) {
  return localizedRestaurantCategoryLabel(value);
}

String localizedRestaurantCategoryLabel(String value, {bool isFrench = false}) {
  switch (value) {
    case 'italian':
      return isFrench ? 'Italien' : 'Italian';
    case 'indian':
      return isFrench ? 'Indien' : 'Indian';
    case 'chinese':
      return isFrench ? 'Chinois' : 'Chinese';
    case 'japanese':
      return isFrench ? 'Japonais' : 'Japanese';
    case 'middle_eastern':
      return isFrench ? 'Moyen-Orient' : 'Middle Eastern';
    case 'fast_food':
      return isFrench ? 'Restauration rapide' : 'Fast Food';
    case 'cafe_bakery':
      return isFrench ? 'Cafe et boulangerie' : 'Cafe & Bakery';
    case 'takeaway':
      return isFrench ? 'A emporter' : 'Takeaway';
    case 'fine_dining':
      return isFrench ? 'Gastronomique' : 'Fine Dining';
    case 'other':
      return isFrench ? 'Autre' : 'Other';
    default:
      return value;
  }
}
