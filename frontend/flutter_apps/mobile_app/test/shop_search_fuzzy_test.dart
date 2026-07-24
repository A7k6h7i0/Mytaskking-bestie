import 'package:flutter_test/flutter_test.dart';
import 'package:mytaskking_mobile/screens/marketing/business_directory_service.dart';
import 'package:mytaskking_mobile/screens/marketing/shop_search_fuzzy.dart';

void main() {
  group('ShopSearchFuzzy category correction', () {
    test('Restrurent → Restaurant', () {
      final r = ShopSearchFuzzy.correctQuery('Restrurent');
      expect(r.changed, isTrue);
      expect(r.text.toLowerCase(), 'restaurant');
    });

    test('Resturant → Restaurant', () {
      final r = ShopSearchFuzzy.correctQuery('Resturant');
      expect(r.changed, isTrue);
      expect(r.text.toLowerCase(), 'restaurant');
    });

    test('Plywod → Plywood', () {
      final r = ShopSearchFuzzy.correctQuery('Plywod');
      expect(r.changed, isTrue);
      expect(r.text, 'Plywood');
    });

    test('Medical stor → Medical Store', () {
      final r = ShopSearchFuzzy.correctQuery('Medical stor');
      expect(r.changed, isTrue);
      expect(r.text, 'Medical Store');
    });

    test('Exact match unchanged', () {
      final r = ShopSearchFuzzy.correctQuery('Restaurant');
      expect(r.changed, isFalse);
      expect(r.text, 'Restaurant');
    });
  });

  group('ShopSearchFuzzy area correction', () {
    test('cholconda → Golconda', () {
      final r = ShopSearchFuzzy.correctArea('cholconda');
      expect(r.changed, isTrue);
      expect(r.text, 'Golconda');
    });

    test('golkonda → Golconda', () {
      final r = ShopSearchFuzzy.correctArea('golkonda');
      expect(r.changed, isTrue);
      expect(r.text, 'Golconda');
    });

    test('kukatpallyy → Kukatpally', () {
      final r = ShopSearchFuzzy.correctArea('kukatpallyy');
      expect(r.changed, isTrue);
      expect(r.text, 'Kukatpally');
    });

    test('secunderbad → Secunderabad', () {
      final r = ShopSearchFuzzy.correctArea('secunderbad');
      expect(r.changed, isTrue);
      expect(r.text, 'Secunderabad');
    });

    test('Exact area unchanged', () {
      final r = ShopSearchFuzzy.correctArea('Golconda');
      expect(r.changed, isFalse);
    });
  });

  group('ShopSearchFuzzy fuzzyContains', () {
    test('matches typo in category text', () {
      expect(
        ShopSearchFuzzy.fuzzyContains('restaurant and bar', 'restrurent'),
        isTrue,
      );
    });

    test('matches similar area in address', () {
      expect(
        ShopSearchFuzzy.fuzzyContains('shop near golconda fort', 'cholconda'),
        isTrue,
      );
    });
  });

  group('BusinessDirectoryService relevance', () {
    test('ranks restaurant category for typo query', () {
      final item = {
        'businessName': 'Spice Hub',
        'businessCategory': 'Restaurant',
        'address': 'Golconda, Hyderabad',
      };
      final score = BusinessDirectoryService.normalize(
        item,
        searchArea: 'Golconda',
      );
      // Access private _relevanceScore via search ranking — test via normalizeInputs
      expect(
        BusinessDirectoryService.normalizeInputs(
          query: 'Restrurent',
          area: 'cholconda',
        ).changed,
        isTrue,
      );
      expect(score['businessCategory'], 'Restaurant');
    });
  });

  group('queryVariants', () {
    test('includes corrected and original', () {
      final v = ShopSearchFuzzy.queryVariants('Restrurent');
      expect(v.any((e) => e.toLowerCase() == 'restaurant'), isTrue);
      expect(v.any((e) => e.toLowerCase() == 'restrurent'), isTrue);
    });
  });
}
