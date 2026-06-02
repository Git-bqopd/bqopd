import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../repositories/repositories.dart';
import './editor/settings_tab.dart';
import './editor/order_tab.dart';
import './editor/upload_tab.dart';

/// Refactoring Blueprint: Fanzine Workspace Editor.
/// BLoC-driven tab coordinator connecting with bqopd_core's FanzineEditorBloc.
/// Streamlines folio adjustments, sequenced ordering flatplan controls, and uploads.
class FanzineEditor extends StatefulComponent {
  final String frefFanzineId;
  final String? shortCode;
  final Map<String, dynamic>? fanzineData;
  final Map<String, Map<String, dynamic>> creatorProfiles;
  final Map<String, Map<String, dynamic>> imageStats;
  final List<Map<String, dynamic>> pageStructure;
  final AuthState? authState;
  final AuthBloc? authBloc;

  // Layout preference triggers
  final bool? twoPage;
  final void Function(bool)? onTwoPageChanged;

  const FanzineEditor({
    required this.frefFanzineId,
    this.shortCode,
    this.fanzineData,
    this.creatorProfiles = const {},
    this.imageStats = const {},
    this.pageStructure = const [],
    this.authState,
    this.authBloc,
    this.twoPage,
    this.onTwoPageChanged,
    super.key,
  });

  @override
  State<FanzineEditor> createState() => _FanzineEditorState();
}

class _FanzineEditorState extends State<FanzineEditor> {
  late final FanzineEditorBloc _bloc;
  StreamSubscription<FanzineEditorState>? _blocSubscription;
  FanzineEditorState _blocState = FanzineEditorInitial();

  int _activeTab = 0; // 0: settings, 1: order, 2: upload

  @override
  void initState() {
    super.initState();
    _bloc = FanzineEditorBloc(
      repository: createFanzineRepository(),
      pipelineRepository: createPipelineRepository(),
      fanzineId: _frefFrefFanzineIdSafe,
    );

    // Initial load requested
    _bloc.add(LoadFanzineRequested(_frefFrefFanzineIdSafe));

    // Listen to bloc state mutations
    _blocSubscription = _bloc.stream.listen((state) {
      if (mounted) {
        setState(() {
          _blocState = state;
        });

        // Inform parent layout of spread layout shifts
        if (state is FanzineEditorLoaded && component.onTwoPageChanged != null) {
          component.onTwoPageChanged!(state.fanzine.twoPage);
        }
      }
    });
  }

  // Safe accessor to bridge frefFanzineId name matching
  String get _frefFrefFanzineIdSafe => component.frefFanzineId;

  @override
  void dispose() {
    _blocSubscription?.cancel();
    _bloc.close();
    super.dispose();
  }

  Component _buildTabButton(String label, int index) {
    final isActive = _activeTab == index;
    return span(
      classes: 'text-xs cursor-pointer ${isActive ? 'font-bold' : 'text-gray'}',
      events: {'click': (e) => setState(() => _activeTab = index)},
      [text(label)],
    );
  }

  @override
  Component build(BuildContext context) {
    final state = _blocState;

    if (state is FanzineEditorLoading || state is FanzineEditorInitial) {
      return div(
        [
          p([text("Synchronizing editor workspace...")])
        ],
        classes: 'white-sticker-flexible w-full mt-2 p-8 text-center text-gray italic',
      );
    }

    if (state is FanzineEditorFailure) {
      return div(
        [
          h3([text("Editor Failure")], attributes: const {'style': 'color: #ff5252; margin: 0 0 8px 0;'}),
          p([text(state.message)], attributes: const {'style': 'font-size: 13px; margin: 0;'})
        ],
        classes: 'white-sticker-flexible w-full mt-2 p-8 text-center',
      );
    }

    if (state is FanzineEditorLoaded) {
      final fanzine = state.fanzine;
      final pages = state.pages;
      final isProcessing = state.isProcessing;

      return div(
        [
          // 1. Core Segmented Tab selection Row
          div(
            [
              _buildTabButton('settings', 0),
              span([text('|')], classes: 'px-4 text-gray text-xs'),
              _buildTabButton('order', 1),
              span([text('|')], classes: 'px-4 text-gray text-xs'),
              _buildTabButton('upload', 2),
            ],
            classes: 'flex-row justify-center items-center py-2 bg-gray-100',
          ),

          // 2. Active Tab body panel
          div(
            [
              if (_activeTab == 0)
                EditorSettingsTab(fanzine: fanzine, bloc: _bloc, isSaving: isProcessing),
              if (_activeTab == 1)
                EditorOrderTab(fanzine: fanzine, pages: pages, bloc: _bloc),
              if (_activeTab == 2)
              // FIXED: Changed EditorUploadTab instantiation to matching UploadTab class name
                UploadTab(fanzine: fanzine, pages: pages, bloc: _bloc, isUploading: isProcessing),
            ],
            classes: 'flex-col p-4',
          ),
        ],
        classes: 'white-sticker-flexible w-full mt-2',
      );
    }

    return div([]);
  }
}