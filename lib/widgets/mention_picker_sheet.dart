import 'package:flutter/material.dart';

import '../services/mention_service.dart';

Future<List<MentionCandidate>?> showMentionPickerSheet({
  required BuildContext context,
  required List<MentionCandidate> available,
  required List<MentionCandidate> initialSelection,
  String title = 'Tag connections',
}) {
  final searchCtrl = TextEditingController();
  final selectedIds = initialSelection.map((e) => e.id).toSet();

  return showModalBottomSheet<List<MentionCandidate>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      var query = '';

      return StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final filtered = available.where((item) {
            if (query.isEmpty) return true;
            return item.name.toLowerCase().contains(query.toLowerCase());
          }).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                16 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SizedBox(
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Search connections',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setModalState(() => query = value.trim()),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching connections'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final item = filtered[index];
                                final selected = selectedIds.contains(item.id);
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  decoration: BoxDecoration(
                                    color: selected ? const Color(0xFFDDF1EB) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF0F766E).withValues(alpha: 0.45)
                                          : const Color(0xFFE6DDCE),
                                    ),
                                  ),
                                  child: CheckboxListTile(
                                    value: selected,
                                    activeColor: const Color(0xFF0F766E),
                                    checkColor: Colors.white,
                                    selected: selected,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 2,
                                    ),
                                    secondary: CircleAvatar(
                                      backgroundColor: const Color(0xFFF4EBDD),
                                      backgroundImage:
                                          item.avatarUrl != null && item.avatarUrl!.isNotEmpty
                                              ? NetworkImage(item.avatarUrl!)
                                              : null,
                                      child: item.avatarUrl == null || item.avatarUrl!.isEmpty
                                          ? Text(
                                              item.name.isEmpty ? '?' : item.name[0].toUpperCase(),
                                              style: const TextStyle(
                                                color: Color(0xFF12211D),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      item.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? const Color(0xFF0B5D56)
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setModalState(() {
                                        if (value == true) {
                                          selectedIds.add(item.id);
                                        } else {
                                          selectedIds.remove(item.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            final selection = available
                                .where((item) => selectedIds.contains(item.id))
                                .toList();
                            Navigator.of(sheetContext).pop(selection);
                          },
                          child: Text(
                            selectedIds.isEmpty ? 'Done' : 'Tag (${selectedIds.length})',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(searchCtrl.dispose);
}
