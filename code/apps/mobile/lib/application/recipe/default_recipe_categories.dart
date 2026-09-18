/// 默认菜谱分类（HOME-001）。
///
/// 这些分类在应用首次启动/菜谱库为空时自动创建，ID 与图标 asset 固定，
/// 按 UI 层映射显示图标（不持久化在 recipe_categories 表中）。
class DefaultRecipeCategory {
  const DefaultRecipeCategory({
    required this.id,
    required this.name,
    required this.iconAsset,
  });

  final String id;
  final String name;
  final String iconAsset;
}

/// 12 个默认分类，顺序即默认排序。
const defaultRecipeCategories = <DefaultRecipeCategory>[
  DefaultRecipeCategory(
    id: 'cat_staple',
    name: '主食',
    iconAsset: 'assets/icon/home/categories/主食.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_home',
    name: '家常菜',
    iconAsset: 'assets/icon/home/categories/家常菜.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_quick',
    name: '快手菜',
    iconAsset: 'assets/icon/home/categories/快手菜.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_breakfast',
    name: '早餐',
    iconAsset: 'assets/icon/home/categories/早餐.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_seafood',
    name: '水产',
    iconAsset: 'assets/icon/home/categories/水产.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_soup',
    name: '汤羹',
    iconAsset: 'assets/icon/home/categories/汤羹.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_bake',
    name: '烘焙',
    iconAsset: 'assets/icon/home/categories/烘焙.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_dessert',
    name: '甜品',
    iconAsset: 'assets/icon/home/categories/甜品.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_vegetarian',
    name: '素菜',
    iconAsset: 'assets/icon/home/categories/素菜.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_meat',
    name: '肉类',
    iconAsset: 'assets/icon/home/categories/肉类.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_light',
    name: '轻食',
    iconAsset: 'assets/icon/home/categories/轻食.png',
  ),
  DefaultRecipeCategory(
    id: 'cat_drink',
    name: '饮品',
    iconAsset: 'assets/icon/home/categories/饮品.png',
  ),
];

/// 按分类 ID 查找图标 asset；未命中返回 null（自定义分类无图标）。
String? categoryIconAsset(String categoryId) {
  for (final category in defaultRecipeCategories) {
    if (category.id == categoryId) return category.iconAsset;
  }
  return null;
}

/// 按分类 ID 查找默认分类名称；未命中返回 null。
String? defaultCategoryName(String categoryId) {
  for (final category in defaultRecipeCategories) {
    if (category.id == categoryId) return category.name;
  }
  return null;
}
