import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/marketplace_repository.dart';
import '../models/marketplace_messaging.dart';
import 'profile_photo_avatar.dart';

class MarketplaceMessagesPage extends StatelessWidget {
  const MarketplaceMessagesPage({
    super.key,
    required this.conversations,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onOpenConversation,
    required this.onDeleteConversation,
    required this.deletingConversationIds,
    required this.currentUserId,
  });

  final List<MarketplaceConversation> conversations;
  final bool isLoading;
  final Object? error;
  final VoidCallback onRefresh;
  final ValueChanged<MarketplaceConversation> onOpenConversation;
  final Future<void> Function(MarketplaceConversation) onDeleteConversation;
  final Set<String> deletingConversationIds;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Messages',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: isLoading ? null : onRefresh,
                  tooltip: 'Refresh messages',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'Private chats with buyers and vendors.',
              style: TextStyle(color: Colors.black54),
            ),
            if (isLoading) const LinearProgressIndicator(),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(() {
                final errorText = error.toString().toLowerCase();
                if (errorText.contains('permission-denied') ||
                    errorText.contains('missing or insufficient permissions') ||
                    errorText.contains('permission')) {
                  return 'Messages are unavailable until the Firestore rules allow chat access.';
                }
                return 'Could not load messages.';
              }(), style: const TextStyle(color: Color(0xFF9D4038))),
              TextButton(onPressed: onRefresh, child: const Text('Try again')),
            ] else if (!isLoading && conversations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Text(
                  'No conversations yet. Open a listing and choose Contact vendor to start a chat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              ...conversations.map((conversation) {
                final isBuyer = currentUserId == conversation.buyerUid;
                final otherName = isBuyer
                    ? conversation.vendorLabel
                    : conversation.buyerLabel;
                final otherPhotoUrl = isBuyer
                    ? conversation.vendorPhotoUrl
                    : conversation.buyerPhotoUrl;
                final otherPhotoBytes = isBuyer
                    ? conversation.vendorPhotoBytes
                    : conversation.buyerPhotoBytes;
                return Card(
                  child: ListTile(
                    leading: ProfilePhotoAvatar(
                      radius: 22,
                      photoUrl: otherPhotoUrl,
                      photoBytes: otherPhotoBytes,
                    ),
                    title: Text(
                      otherName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      conversation.lastMessage.isEmpty
                          ? 'No messages yet'
                          : conversation.lastMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Delete conversation',
                          onPressed:
                              deletingConversationIds.contains(conversation.id)
                              ? null
                              : () => onDeleteConversation(conversation),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => onOpenConversation(conversation),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class MarketplaceConversationDialog extends StatefulWidget {
  const MarketplaceConversationDialog({
    super.key,
    required this.repository,
    required this.conversation,
    required this.currentUserId,
  });

  final MarketplaceRepository repository;
  final MarketplaceConversation conversation;
  final String currentUserId;

  @override
  State<MarketplaceConversationDialog> createState() =>
      _MarketplaceConversationDialogState();
}

class _MarketplaceConversationDialogState
    extends State<MarketplaceConversationDialog> {
  final TextEditingController _messageController = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageName;
  Object? _sendError;
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty) return;
      final file = result.single;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() => _sendError = 'Images must be 5 MB or smaller.');
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageName = file.name;
        _sendError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _sendError = error);
    }
  }

  Future<void> _send() async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      await widget.repository.sendMessage(
        conversationId: widget.conversation.id,
        text: _messageController.text,
        imageBytes: _imageBytes,
        imageName: _imageName,
      );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _imageBytes = null;
        _imageName = null;
      });
    } catch (error) {
      if (mounted) setState(() => _sendError = error);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _deleteForMe(MarketplaceMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text(
          'It will be removed only from your view. The other participant can still see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete for me'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteMessageForMe(
        conversationId: widget.conversation.id,
        messageId: message.id,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sendError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBuyer = widget.currentUserId == widget.conversation.buyerUid;
    final otherName = isBuyer
        ? widget.conversation.vendorLabel
        : widget.conversation.buyerLabel;
    final otherPhotoUrl = isBuyer
        ? widget.conversation.vendorPhotoUrl
        : widget.conversation.buyerPhotoUrl;
    final otherPhotoBytes = isBuyer
        ? widget.conversation.vendorPhotoBytes
        : widget.conversation.buyerPhotoBytes;
    final myPhotoUrl = isBuyer
        ? widget.conversation.buyerPhotoUrl
        : widget.conversation.vendorPhotoUrl;
    final myPhotoBytes = isBuyer
        ? widget.conversation.buyerPhotoBytes
        : widget.conversation.vendorPhotoBytes;
    return AlertDialog(
      title: Row(
        children: [
          ProfilePhotoAvatar(
            radius: 22,
            photoUrl: otherPhotoUrl,
            photoBytes: otherPhotoBytes,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              otherName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<MarketplaceMessage>>(
                stream: widget.repository.watchMessages(widget.conversation.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final errorText = snapshot.error.toString().toLowerCase();
                    final message =
                        errorText.contains('permission-denied') ||
                            errorText.contains(
                              'missing or insufficient permissions',
                            ) ||
                            errorText.contains('permission')
                        ? 'Messages are unavailable until the Firestore rules allow chat access.'
                        : 'Could not load messages.';
                    return Center(child: Text(message));
                  }
                  final messages = snapshot.data ?? const [];
                  if (messages.isEmpty) {
                    return const Center(
                      child: Text('Start the conversation with a message.'),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      final mine = message.senderUid == widget.currentUserId;
                      final photoUrl = mine ? myPhotoUrl : otherPhotoUrl;
                      final photoBytes = mine ? myPhotoBytes : otherPhotoBytes;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!mine) ...[
                              ProfilePhotoAvatar(
                                radius: 15,
                                photoUrl: photoUrl,
                                photoBytes: photoBytes,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Card(
                                color: mine
                                    ? const Color(0xFFE9EFE5)
                                    : const Color(0xFFF4F4F0),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (message.imageUrl != null)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.network(
                                            message.imageUrl!,
                                            width: 220,
                                            height: 180,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                const SizedBox(
                                                  width: 220,
                                                  height: 100,
                                                  child: Center(
                                                    child: Text(
                                                      'Image unavailable',
                                                    ),
                                                  ),
                                                ),
                                          ),
                                        )
                                      else if (message.imageBytes != null)
                                        Image.memory(
                                          message.imageBytes!,
                                          width: 220,
                                          height: 180,
                                          fit: BoxFit.cover,
                                        ),
                                      if (message.text.isNotEmpty)
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 280,
                                          ),
                                          child: Text(message.text),
                                        ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            TimeOfDay.fromDateTime(
                                              message.createdAt.toLocal(),
                                            ).format(context),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.black54,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Delete for me',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () =>
                                                _deleteForMe(message),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 17,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (mine) ...[
                              const SizedBox(width: 4),
                              ProfilePhotoAvatar(
                                radius: 15,
                                photoUrl: photoUrl,
                                photoBytes: photoBytes,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_imageBytes != null) ...[
              Row(
                children: [
                  Image.memory(
                    _imageBytes!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_imageName ?? 'Image attached')),
                  IconButton(
                    tooltip: 'Remove image',
                    onPressed: () => setState(() {
                      _imageBytes = null;
                      _imageName = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ],
            if (_sendError != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Message error: $_sendError',
                  style: const TextStyle(color: Color(0xFF9D4038)),
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Attach image',
                  onPressed: _isSending ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Write a message',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  tooltip: 'Send message',
                  onPressed: _isSending ? null : _send,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
