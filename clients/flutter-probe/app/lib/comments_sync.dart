import 'account_store.dart';
import 'workspace_api.dart';

class CommentsSync {
  static Future<void> refresh(WorkspaceApi api, AccountStore store, String token, String localId,{void Function()? check}) async {
    final task = await store.task(localId);
    if (task['server_id'] == null) return;
    final comments = <Map<String, dynamic>>[];
    var after = 0;
    int? through;
    while (true) {
      check?.call();
      final response = await api.comments(token, task['server_id'] as int, after, through);
      final meta = response['meta'] as Map;
      through ??= meta['through_id'] as int;
      comments.addAll((response['data'] as List).map((c) => Map<String, dynamic>.from(c as Map)));
      if (meta['has_more'] != true) break;
      final next = meta['after_id'] as int;
      if (next <= after) throw StateError('Сервер повторяет страницу комментариев');
      after = next;
    }
    check?.call();
    await store.mergeComments(localId, comments);
  }
}
