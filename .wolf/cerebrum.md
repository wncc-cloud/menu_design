# Cerebrum

> OpenWolf's learning memory. Updated automatically as the AI learns from interactions.
> Do not edit manually unless correcting an error.
> Last updated: 2026-07-04

## User Preferences

<!-- How the user likes things done. Code style, tools, patterns, communication. -->

## Key Learnings

- **Project:** menu_design
- **Publish path field list:** `DraftRepository.publishMenu()` (cafe_countryside_menu/lib/features/shared/repositories/draft_repository.dart) builds the `menu/current.items[]` map with an explicit hand-written field list, not a generic `item.toJson()` spread. Any new field added to `DraftItemModel` must also be added to this map by hand or it silently never reaches the published Firestore document, even though the admin draft/editor UI saves it fine. Always grep this file when adding item fields.
- **Item field checklist:** Adding a new per-item field touches up to 4 places: `draft_item_model.dart` (model: constructor/fromJson/toJson/copyWith), `item_form.dart` (admin editor UI), `draft_repository.dart` publish map (see above), and optionally `item_model.dart`/`item_card.dart` only if it must be customer-visible — omit those last two to keep a field admin/back-of-house-only.

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->
