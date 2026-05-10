// @dart=3.6
// ignore_for_file: type=lint
// build_runner >=2.4.16
import 'dart:io' as _io;
import 'package:build_runner/src/build_plan/builder_factories.dart'
    as _build_runner;
import 'package:build_runner/src/bootstrap/processes.dart' as _build_runner;
import 'package:jaspr_builder/builder.dart' as _i1;
import 'package:source_gen/builder.dart' as _i2;

final _builderFactories = _build_runner.BuilderFactories(
  {
    'jaspr_builder:client_entrypoint': [_i1.buildClientEntrypoint],
    'jaspr_builder:client_module': [_i1.buildClientModule],
    'jaspr_builder:client_options': [_i1.buildClientOptions],
    'jaspr_builder:clients_bundle': [_i1.buildClientsBundle],
    'jaspr_builder:codec_bundle': [_i1.buildCodecBundle],
    'jaspr_builder:codec_module': [_i1.buildCodecModule],
    'jaspr_builder:import_output': [_i1.buildImportsOutput],
    'jaspr_builder:imports_module': [_i1.buildImportsModule],
    'jaspr_builder:server_options': [_i1.buildServerOptions],
    'jaspr_builder:stub': [_i1.buildPlatformStubs],
    'jaspr_builder:styles_bundle': [_i1.buildStylesBundle],
    'jaspr_builder:styles_module': [_i1.buildStylesModule],
    'jaspr_builder:styles_standalone': [_i1.buildStylesStandalone],
    'jaspr_builder:sync_mixins_module': [_i1.buildSyncMixins],
    'source_gen:combining_builder': [_i2.combiningBuilder],
  },
  postProcessBuilderFactories: {
    'source_gen:part_cleanup': _i2.partCleanup,
  },
);
void main(List<String> args) async {
  _io.exitCode = await _build_runner.ChildProcess.run(
    args,
    _builderFactories,
  )!;
}
