import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';

class Header extends StatelessComponent {
  const Header({super.key});

  @override
  Component build(BuildContext context) {
    // In Jaspr 0.23.0+, use matchList.uri.path to determine the active route
    var activePath = Router.of(context).matchList.uri.path;

    return header([
      nav([
        ul([
          li([
            a(
              classes: activePath == '/' ? 'active' : '',
              href: '/',
              [text('Home')],
            ),
          ]),
          li([
            a(
              classes: activePath == '/about' ? 'active' : '',
              href: '/about',
              [text('About')],
            ),
          ]),
        ]),
      ]),
    ]);
  }
}