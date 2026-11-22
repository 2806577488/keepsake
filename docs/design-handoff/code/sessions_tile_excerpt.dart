// ==========================================================================
// 摘录文件：lib/features/sessions/sessions_screen.dart
// 原文件共 1287 行。以下仅为设计师需要看的片段，代码内容原样保留（含原注释）。
// 保留了 _buildSessionTile（Dismissible + ListTile 行结构 + 长按进多选）。
// ==========================================================================


// ---- 摘录 1/1 · 原文件第 797–887 行 ----

  Widget _buildSessionTile(ThemeData theme, Session session) {
    final pinned = isSessionPinned(session);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final selected = _selecting && _selectedIds.contains(session.id);
    return Dismissible(
      key: ValueKey<String>('session-${session.id}'),
      // 选择态禁用左滑删除，避免误操作。
      direction: _selecting
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(session),
      onDismissed: (_) => _deleteSession(session),
      child: ListTile(
        selected: selected,
        leading: _selecting
            ? Checkbox(
                value: selected,
                onChanged: (_) => _toggleSelected(session.id),
              )
            : CircleAvatar(
                backgroundColor: pinned
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  pinned ? Icons.push_pin : Icons.chat_bubble_outline,
                  size: 20,
                  color: pinned
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
        title: Text(
          sessionDisplayTitle(session),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        subtitle: Text(
          '${_relativeTime(session.updatedAt)} · ${session.messageCount} 个对话',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // 选择态隐藏「更多」，避免和勾选操作抢点击。
        trailing: _selecting
            ? null
            : IconButton(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showSessionActions(session),
              ),
        onTap: () {
          if (_selecting) {
            _toggleSelected(session.id);
            return;
          }
          // 导入进行中点某条会话：立刻把它插到正文导入队列最前面。
          try {
            final progress = ref.watch(importProgressProvider).value;
            if (progress?.running == true) {
              ref.read(importTaskProvider).priority(session.id);
            }
          } catch (_) {
            // 插队失败不影响打开会话。
          }
          _openSession(
            session.id,
            initialTitle: sessionDisplayTitle(session),
          );
        },
        onLongPress: () {
          if (_selecting) {
            _toggleSelected(session.id);
            return;
          }
          // 长按进入选择态并选中该行（原「更多」菜单仍可从 ⋮ 打开）。
          _enterSelection(session);
        },
      ),
    );
  }

// ==========================================================================
// 摘录结束。
// ==========================================================================
