import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../components/page_wrapper.dart';

/// Renders user details in a platform-independent way.
/// This component strictly uses abstract package interfaces to remain compatible with server VM rendering.
class ProfilePage extends StatelessComponent {
  final AuthState? authState;
  final AuthBloc authBloc;
  final IUserRepository userRepository;
  final IEngagementRepository engagementRepository;

  const ProfilePage({
    required this.authState,
    required this.authBloc,
    required this.userRepository,
    required this.engagementRepository,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    final email = authState?.user?.email ?? 'Unknown User';
    final uid = authState?.user?.uid ?? '';

    return PageWrapper(
        child: div(classes: 'flex-col items-center w-full', [
          h1(classes: 'text-lg font-bold', [text('User Profile')]),
          div(classes: 'mt-4 text-center', [
            p([text('Authenticated Account:')]),
            p(classes: 'font-bold', [text(email)]),
            p(classes: 'text-center mt-4', [text('User ID: $uid')]),
          ]),

          div(classes: 'mt-4 w-full', [
            button(
                classes: 'btn-primary',
                events: {'click': (e) => authBloc.add(LogoutRequested())},
                [text('Logout')]
            )
          ]),
          div(classes: 'mt-4', [
            a(href: '/', [text('Back to Home')])
          ])
        ])
    );
  }
}