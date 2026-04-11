import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/engagement_repository.dart';

// --- EVENTS ---
abstract class InteractionEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class TogglePageLikeRequested extends InteractionEvent {
  final String fanzineId;
  final String pageId;
  final bool isCurrentlyLiked;
  TogglePageLikeRequested({required this.fanzineId, required this.pageId, required this.isCurrentlyLiked});
}

class LoadCommentsRequested extends InteractionEvent {
  final String imageId;
  LoadCommentsRequested(this.imageId);
}

// Internal event to safely pass stream data back into the bloc
class _CommentsUpdated extends InteractionEvent {
  final List<DocumentSnapshot> comments;
  _CommentsUpdated(this.comments);
}

class AddCommentRequested extends InteractionEvent {
  final String imageId;
  final String text;
  final String? fanzineId;
  final String? fanzineTitle;
  final String? displayName;
  final String? username;
  AddCommentRequested({required this.imageId, required this.text, this.fanzineId, this.fanzineTitle, this.displayName, this.username});
}

class DeleteCommentRequested extends InteractionEvent {
  final String commentId;
  final String imageId;
  DeleteCommentRequested(this.commentId, this.imageId);
}

class ToggleCommentLikeRequested extends InteractionEvent {
  final String commentId;
  final bool isCurrentlyLiked;
  ToggleCommentLikeRequested(this.commentId, this.isCurrentlyLiked);
}

// --- STATE ---
class InteractionState extends Equatable {
  final List<DocumentSnapshot> comments;
  final bool isLoadingComments;
  final String? errorMessage;

  const InteractionState({
    this.comments = const [],
    this.isLoadingComments = false,
    this.errorMessage,
  });

  InteractionState copyWith({
    List<DocumentSnapshot>? comments,
    bool? isLoadingComments,
    String? errorMessage,
  }) {
    return InteractionState(
      comments: comments ?? this.comments,
      isLoadingComments: isLoadingComments ?? this.isLoadingComments,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [comments, isLoadingComments, errorMessage];
}

// --- BLOC ---
class InteractionBloc extends Bloc<InteractionEvent, InteractionState> {
  final EngagementRepository _repository;
  StreamSubscription? _commentsSub;

  InteractionBloc({required EngagementRepository repository})
      : _repository = repository,
        super(const InteractionState()) {
    on<TogglePageLikeRequested>(_onTogglePageLike);
    on<LoadCommentsRequested>(_onLoadComments);
    on<_CommentsUpdated>(_onCommentsUpdated);
    on<AddCommentRequested>(_onAddComment);
    on<DeleteCommentRequested>(_onDeleteComment);
    on<ToggleCommentLikeRequested>(_onToggleCommentLike);
  }

  Future<void> _onTogglePageLike(TogglePageLikeRequested event, Emitter<InteractionState> emit) async {
    try {
      await _repository.togglePageLike(
        fanzineId: event.fanzineId,
        pageId: event.pageId,
        isCurrentlyLiked: event.isCurrentlyLiked,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onLoadComments(LoadCommentsRequested event, Emitter<InteractionState> emit) async {
    emit(state.copyWith(isLoadingComments: true));

    await _commentsSub?.cancel();

    // Listen to the Firestore stream and dispatch the internal event
    _commentsSub = _repository.watchComments(event.imageId).listen((snapshot) {
      add(_CommentsUpdated(snapshot.docs));
    });
  }

  void _onCommentsUpdated(_CommentsUpdated event, Emitter<InteractionState> emit) {
    // Safely emit state from within a proper Bloc event handler
    emit(state.copyWith(comments: event.comments, isLoadingComments: false));
  }

  Future<void> _onAddComment(AddCommentRequested event, Emitter<InteractionState> emit) async {
    try {
      await _repository.addComment(
        imageId: event.imageId,
        text: event.text,
        fanzineId: event.fanzineId,
        fanzineTitle: event.fanzineTitle,
        displayName: event.displayName,
        username: event.username,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onDeleteComment(DeleteCommentRequested event, Emitter<InteractionState> emit) async {
    try {
      await _repository.deleteComment(event.commentId, event.imageId);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onToggleCommentLike(ToggleCommentLikeRequested event, Emitter<InteractionState> emit) async {
    try {
      await _repository.toggleCommentLike(event.commentId, event.isCurrentlyLiked);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() {
    _commentsSub?.cancel();
    return super.close();
  }
}