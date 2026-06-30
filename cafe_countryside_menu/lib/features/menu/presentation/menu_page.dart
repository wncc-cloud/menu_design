import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item_model.dart';
import '../models/menu_snapshot_model.dart';
import 'menu_provider.dart';
import 'widgets/item_card.dart';
import 'widgets/search_bar.dart';
import 'widgets/section_chip.dart';

class MenuPage extends ConsumerStatefulWidget {
  const MenuPage({super.key});

  @override
  ConsumerState<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends ConsumerState<MenuPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuControllerProvider);
    final businessAsync = ref.watch(businessProvider);
    final business = businessAsync.asData?.value;

    final cafeName = (business?.cafeName.isNotEmpty == true)
        ? business!.cafeName
        : 'Cafe Countryside Menu';
    final logoUrl = business?.logoUrl ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: Text(
          cafeName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: logoUrl.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: ClipOval(
                  child: Image.network(
                    logoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh menu',
            onPressed: () => ref.invalidate(menuControllerProvider),
          ),
        ],
      ),
      body: menuAsync.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Could not load menu.', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(menuControllerProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (menu) => menu == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Menu is not available yet.\nPlease check back soon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            : _MenuContent(menu: menu, searchController: _searchController),
      ),
    );
  }
}

class _MenuContent extends ConsumerWidget {
  final MenuSnapshotModel menu;
  final TextEditingController searchController;

  const _MenuContent({required this.menu, required this.searchController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(menuFilterProvider);
    final filteredItems = ref.watch(filteredItemsProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 720;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MenuSearchBar(
          controller: searchController,
          onChanged: (q) => ref.read(menuFilterProvider.notifier).setSearch(q),
        ),
        if (menu.sections.isNotEmpty)
          SectionChipBar(
            sections: menu.sections,
            selectedId: filter.selectedSectionId,
            onSelected: (id) =>
                ref.read(menuFilterProvider.notifier).setSection(id),
          ),
        Expanded(
          child: filteredItems.isEmpty
              ? const Center(
                  child: Text(
                    'No items found.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : _ItemsList(items: filteredItems),
        ),
      ],
    );

    if (isWide) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: content,
        ),
      );
    }

    return content;
  }
}

class _ItemsList extends StatelessWidget {
  final List<ItemModel> items;
  const _ItemsList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: items.length,
      itemBuilder: (_, i) => ItemCard(item: items[i]),
    );
  }
}
