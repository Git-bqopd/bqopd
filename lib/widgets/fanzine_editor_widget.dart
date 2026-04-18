import 'package:flutter/material.dart';
import 'base_fanzine_workspace.dart';

/// Legacy Editor Widget mapped to the exact same logic as the Curator view
/// Now implemented cleanly using the unified Base Workspace.
class FanzineEditorWidget extends StatelessWidget {
  final String fanzineId;
  const FanzineEditorWidget({super.key, required this.fanzineId});

  @override
  Widget build(BuildContext context) {
    return BaseFanzineWorkspace(
      fanzineId: fanzineId,
      // Pass any Editor-specific tabs here if needed.
      // Currently, it acts as a lightweight shell wrapper since BaseFanzineWorkspace
      // handles the core Settings and Order tabs natively.
    );
  }
}