import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/edit_info_widget.dart';
import 'package:bqopd_core/bqopd_core.dart';
import 'package:bqopd_ui/bqopd_ui.dart';
import 'package:bqopd_state/bqopd_state.dart';

class EditInfoPage extends StatelessWidget {
  final String? targetUserId;

  const EditInfoPage({super.key, this.targetUserId});

  @override
  Widget build(BuildContext context) {
    final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String editingUid = targetUserId ?? currentUid;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: true,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: MultiRepositoryProvider(
              providers: [
                RepositoryProvider(create: (_) => LocationService()),
              ],
              child: BlocProvider(
                create: (context) => EditInfoBloc(
                  userRepository: context.read<UserRepository>(),
                  locationService: context.read<LocationService>(),
                )..add(LoadEditInfoRequested(editingUid)),
                child: EditInfoWidget(targetUserId: editingUid),
              ),
            ),
          ),
        ),
      ),
    );
  }
}