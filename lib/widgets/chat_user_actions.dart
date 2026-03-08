import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/user_block_service.dart';
import 'report_user_sheet.dart';

Future<void> openChatUserActions({
  required BuildContext context,
  required String otherUserId,
  required Future<void> Function() onBlocked,
  Future<void> Function()? onDeleteChat,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report user'),
                onTap: () => Navigator.of(sheetContext).pop('report'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.block_outlined),
                title: const Text('Block user'),
                onTap: () => Navigator.of(sheetContext).pop('block'),
              ),
              if (onDeleteChat != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete chat'),
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                ),
            ],
          ),
        ),
      );
    },
  );

  if (!context.mounted || action == null) return;

  if (action == 'report') {
    final reported = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReportUserSheet(reportedUserId: otherUserId),
    );

    if (!context.mounted) return;
    if (reported == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User reported.')),
      );
    }
    return;
  }

  if (action == 'block') {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Block user?'),
        content: const Text('You will no longer be able to continue chatting with this user.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      await UserBlockService(Supabase.instance.client).blockUser(otherUserId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User blocked.')),
      );
      await onBlocked();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Block failed: $e')),
      );
    }
  }

  if (action == 'delete') {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text('This will remove the full chat history for this conversation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && onDeleteChat != null && context.mounted) {
      await onDeleteChat();
    }
  }
}
