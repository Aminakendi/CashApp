import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_lock_service.dart';

final appLockProvider = ChangeNotifierProvider<AppLockService>((ref) {
  return AppLockService();
});
