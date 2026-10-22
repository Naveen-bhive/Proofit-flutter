import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_service.dart';
import '../models/user_model.dart';
import '../services/auth_storage.dart';
import 'app_permissions.dart';

/// The signed-in user's role and delegated permissions.
///
/// A [ChangeNotifier] so GoRouter can re-run its guard the moment permissions
/// change (see app_router.dart) and widgets can rebuild via
/// [permissionSessionProvider]. The server stays the source of truth; this
/// only decides what to show.
class PermissionSession extends ChangeNotifier {
  PermissionSession._();
  static final instance = PermissionSession._();

  String? _role;
  Set<String> _permissions = const {};

  String? get role => _role;
  bool get isOwner => _role == 'owner';
  bool get isStaff => _role == 'staff';
  Set<String> get permissions => _permissions;

  /// App-lifetime singleton shared by the router and [permissionSessionProvider];
  /// a disposing ProviderScope must not tear it down.
  @override
  // ignore: must_call_super
  void dispose() {}

  bool can(String permission) => isOwner || _permissions.contains(permission);
  bool canAny(Iterable<String> permissions) => isOwner || permissions.any(_permissions.contains);

  /// Whether a staff member holds any delegated owner permission at all.
  bool get hasTeamAccess => isOwner || _permissions.isNotEmpty;

  void apply({required String? role, required Iterable<String> permissions}) {
    final next = AppPermissions.normalize(permissions).toSet();
    if (role == _role && setEquals(next, _permissions)) return;
    _role = role;
    _permissions = next;
    notifyListeners();
  }

  void applyUser(UserModel? user) =>
      apply(role: user?.role, permissions: user?.permissions ?? const []);

  void clear() => apply(role: null, permissions: const []);

  Future<void> loadFromStorage() async => applyUser(await AuthStorage.getUser());

  Future<void>? _refreshing;

  /// Re-reads the signed-in user's permissions from the server. Concurrent
  /// calls share one request.
  Future<void> refresh(ApiService api) => _refreshing ??= () async {
        try {
          final res = await api.get('/auth/account');
          final data = res.data['data'];
          if (res.data['success'] == true && data is Map && data['permissions'] is List) {
            await updatePermissions((data['permissions'] as List).map((e) => e.toString()));
          }
        } catch (_) {
        } finally {
          _refreshing = null;
        }
      }();

  /// Applies a fresh permission list from the server and keeps the stored
  /// user in step so the next cold start doesn't flash stale access.
  Future<void> updatePermissions(Iterable<String> permissions) async {
    apply(role: _role, permissions: permissions);
    final user = await AuthStorage.getUser();
    if (user != null) await AuthStorage.updateUser(user.copyWith(permissions: _permissions.toList()));
  }
}

final permissionSessionProvider =
    ChangeNotifierProvider<PermissionSession>((_) => PermissionSession.instance);
