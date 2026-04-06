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
      add(AuthSubscriptionRequested()); // Trigger local state sync logic below
    });

    final user = _repository.currentUser;
    if (user != null) {
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } else {
      emit(const AuthState(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onLoginRequested(LoginRequested event, Emitter<AuthState> emit) async {
    emit(const AuthState(status: AuthStatus.loading));
    try {
      await _repository.login(event.email, event.password);
      // Repository logic triggers authStateChanges which we listen to
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