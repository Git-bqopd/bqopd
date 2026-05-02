import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart'; // Added the missing DOM dictionary
import 'package:jaspr_router/jaspr_router.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

// Components
import 'pages/home.dart';
import 'pages/about.dart';
import 'components/header.dart';

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Component build(BuildContext context) {
    return ProviderScope(
      child: Router(
        routes: [
          // ShellRoute wraps a shared UI (like the Header) around your pages
          ShellRoute(
            builder: (context, state, child) {
              return div(classes: 'main-container', [
                const Header(), // Header is now INSIDE the router!
                child,          // This will be HomePage or AboutPage
              ]);
            },
            routes: [
              Route(
                  path: '/',
                  builder: (context, state) => const HomePage()
              ),
              Route(
                  path: '/about',
                  builder: (context, state) => const AboutPage()
              ),
            ],
          ),
        ],
      ),
    );
  }
}