import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../repositories/web_fanzine_repository.dart';

class FanzineReaderPage extends StatefulComponent {
  final String fanzineId;
  final WebFanzineRepository repository;

  const FanzineReaderPage({
    required this.fanzineId,
    required this.repository,
  });

  @override
  State<FanzineReaderPage> createState() => _FanzineReaderPageState();
}

class _FanzineReaderPageState extends State<FanzineReaderPage> {
  Fanzine? _fanzine;
  List<FanzinePage> _pages = [];
  StreamSubscription? _fSub;
  StreamSubscription? _pSub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    // Listen directly to the decoupled Dart repository stream
    _fSub = component.repository.watchFanzineModel(component.fanzineId).listen((fz) {
      setState(() {
        _fanzine = fz;
        _loading = false;
      });
    });

    _pSub = component.repository.watchPageModels(component.fanzineId).listen((pages) {
      setState(() {
        _pages = pages;
      });
    });
  }

  @override
  void dispose() {
    _fSub?.cancel();
    _pSub?.cancel();
    super.dispose();
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

    return div(classes: 'reader-container', [
      div(classes: 'flex-col items-center', [
        h1(classes: 'font-bold text-lg', [text(_fanzine!.title)]),
        if (_fanzine!.volume != null || _fanzine!.issue != null)
          p(classes: 'text-sm text-gray', [text('Vol ${_fanzine!.volume ?? ""} Issue ${_fanzine!.issue ?? ""}')]),
      ]),

      div(classes: 'flex-col items-center gap-4 mt-4 w-full', [
        for (var page in _pages)
          if (page.imageUrl != null && page.imageUrl!.isNotEmpty)
            img(src: page.imageUrl!, classes: 'fanzine-page-img')
          else
            div(classes: 'fanzine-page-img flex-col items-center justify-center', attributes: {'style': 'height: 400px; width: 100%; background: #eee;'}, [
              text('Processing page ${page.pageNumber}...')
            ])
      ]),

      div(classes: 'mt-4', [
        a(href: '/', [text('Back to Home')])
      ])
    ]);
  }
}