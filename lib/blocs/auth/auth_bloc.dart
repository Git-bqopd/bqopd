import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../repositories/auth_repository.dart';

// --- EVENTS ---
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthSubscriptionRequested extends AuthEvent {}

// NEW: Separate event to handle state changes without re-triggering the subscription
class AuthUserChanged extends AuthEvent {
  final User? user;
  AuthUserChanged(this.user);
  @override
  List<Object?> get props => [user];
}

class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  LoginRequested(this.email, this.password);
  @override
  List<Object?> get props => [email, password];
}

class RegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String username;
  RegisterRequested({required this.email, required this.password, required this.username});
}

class LogoutRequested extends AuthEvent {}

// --- STATE ---
enum AuthStatus { initial, loading, authenticated, unauthenticated, failure }

class AuthState extends Equatable {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

  @override
  List<Object?> get props => [status, user, errorMessage];
}

// --- BLOC ---
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repository;
  StreamSubscription<User?>? _userSubscription;

  AuthBloc({required AuthRepository repository})
      : _repository = repository,
        super(const AuthState()) {
    on<AuthSubscriptionRequested>(_onSubscriptionRequested);
    on<AuthUserChanged>(_onUserChanged); // Handle the new separated event
    on<LoginRequested>(_onLoginRequested);
    on<RegisterRequested>(_onRegisterRequested);
    on<LogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onSubscriptionRequested(
      AuthSubscriptionRequested event,
      Emitter<AuthState> emit,
      ) async {
    emit(const AuthState(status: AuthStatus.loading));
    await _userSubscription?.cancel();

    _userSubscription = _repository.authStateChanges.listen((user) {
      // BREAK THE LOOP: Dispatch AuthUserChanged instead of restarting the subscription
      add(AuthUserChanged(user));
    });
  }

  void _onUserChanged(AuthUserChanged event, Emitter<AuthState> emit) {
    if (event.user != null) {
      emit(AuthState(status: AuthStatus.authenticated, user: event.user));
    } else {
      emit(const AuthState(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onLoginRequested(LoginRequested event, Emitter<AuthState> emit) async {
    emit(const AuthState(status: AuthStatus.loading));
    try {
      await _repository.login(event.email, event.password);
    } catch (e) {
      emit(AuthState(status: AuthStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onRegisterRequested(RegisterRequested event, Emitter<AuthState> emit) async {
    emit(const AuthState(status: AuthStatus.loading));
    try {
      await _repository.register(
        email: event.email,
        password: event.password,
        username: event.username,
      );
    } catch (e) {
      emit(AuthState(status: AuthStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onLogoutRequested(LogoutRequested event, Emitter<AuthState> emit) async {
    await _repository.logout();
  }

  @override
  Future<void> close() {
    _userSubscription?.cancel();
    return super.close();
  }
}