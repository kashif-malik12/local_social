import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/chat/services/unread_badge_controller.dart';

final unreadBadgeController = UnreadBadgeController(Supabase.instance.client);