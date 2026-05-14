import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../utils/web_firebase_interop.dart';
import '../components/fanzine_header.dart';
import '../components/fanzine_layout.dart';

class FanzineReaderPage extends StatefulComponent {
  final String fanzineId;

  const FanzineReaderPage({
    required this.fanzineId,
  });

  @override
  State<FanzineReaderPage> createState() => _FanzineReaderPageState();
}

class _FanzineReaderPageState extends State<FanzineReaderPage> {
  Map<String, dynamic>? _fanzine;
  List<Map<String, dynamic>> _pages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final fzRes = await fsGetDoc('fanzines/${component.fanzineId}');
      final fzDoc = jsonDecode(fzRes);

      if (fzDoc['exists']) {
        _fanzine = fzDoc['data'];

        final pagesRes = await fsQuery('fanzines/${component.fanzineId}/pages', '', '', '', 'pageNumber');
        final List pagesList = jsonDecode(pagesRes);
        _pages = pagesList.map((p) => p['data'] as Map<String, dynamic>).toList();
      }
    } catch (e) {
      print("Error loading fanzine: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
        p([text('Loading fanzine...')])
      ]);
    }

    if (_fanzine == null) {
      return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
        p([text('Fanzine not found.')]),
        a(href: '/', [text('Go Home')])
      ]);
    }

    return div(classes: 'w-full h-full', [
      FanzineLayout(
          fanzineId: component.fanzineId,
          pages: _pages,
          hasCover: _fanzine!['hasCover'] ?? true,
          headerWidget: div(classes: 'manila-envelope', [
            FanzineHeader(
              fanzineId: component.fanzineId,
              shortCode: _fanzine!['shortCode'],
              fanzineData: _fanzine,
            )
          ])
      )
    ]);
  }
}