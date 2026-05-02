import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../components/counter.dart';

@client
class HomePage extends StatefulComponent {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // Run code depending on the rendering environment.
    if (kIsWeb) {
      print("Hello client");
    } else {
      print("Hello server");
    }
  }

  @override
  Component build(BuildContext context) {
    return section([
      img(src: 'images/logo.svg', width: 80),
      h1([text('Welcome')]),
      p([text('You successfully created a new Jaspr site.')]),
      // Fixed: Reverted Styles.box to the standard Styles constructor
      div(styles: Styles(height: 100.px), []),
      const Counter(),
    ]);
  }
}