import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// Use relative imports to avoid pulling in the master bqopd_core.dart
// which contains Flutter-dependent exports.
import '../../interfaces/auth_repository_interface.dart';
import '../../models/auth_user.dart';

abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthSubscriptionRequested extends AuthEvent {}

class AuthUserChanged extends AuthEvent {
  final AuthUser? user;
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

enum AuthStatus { initial, loading, authenticated, unauthenticated, failure }

class AuthState extends Equatable {
  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

  @override
  List<Object?> get props => [status, user, errorMessage];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final IAuthRepository _repository;
  StreamSubscription<AuthUser?>? _userSubscription;

  AuthBloc({required IAuthRepository repository})
      : _repository = repository,
        super(const AuthState()) {
    on<AuthSubscriptionRequested>(_onSubscriptionRequested);
    on<AuthUserChanged>(_onUserChanged);
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