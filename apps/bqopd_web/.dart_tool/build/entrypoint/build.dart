// @dart=3.6
// ignore_for_file: type=lint
// build_runner >=2.4.16
import 'dart:io' as _io;
import 'package:build_runner/src/build_plan/builder_factories.dart'
    as _build_runner;
import 'package:build_runner/src/bootstrap/processes.dart' as _build_runner;
import 'package:build_modules/builders.dart' as _i1;
import 'package:build_web_compilers/builders.dart' as _i2;
import 'package:jaspr_builder/builder.dart' as _i3;
import 'package:source_gen/builder.dart' as _i4;

final _builderFactories = _build_runner.BuilderFactories(
  {
    'build_modules:module_library': [_i1.moduleLibraryBuilder],
    'build_web_compilers:dart2js_modules': [
      _i2.dart2jsMetaModuleBuilder,
      _i2.dart2jsMetaModuleCleanBuilder,
      _i2.dart2jsModuleBuilder
    ],
    'build_web_compilers:dart2wasm_modules': [
      _i2.dart2wasmMetaModuleBuilder,
      _i2.dart2wasmMetaModuleCleanBuilder,
      _i2.dart2wasmModuleBuilder
    ],
    'build_web_compilers:ddc': [_i2.ddcKernelBuilder, _i2.ddcBuilder],
    'build_web_compilers:ddc_modules': [
      _i2.ddcMetaModuleBuilder,
      _i2.ddcMetaModuleCleanBuilder,
      _i2.ddcModuleBuilder
    ],
    'build_web_compilers:entrypoint': [_i2.webEntrypointBuilder],
    'build_web_compilers:entrypoint_marker': [_i2.webEntrypointMarkerBuilder],
    'build_web_compilers:sdk_js': [_i2.sdkJsCompile, _i2.sdkJsCopyRequirejs],
    'jaspr_builder:client_entrypoint': [_i3.buildClientEntrypoint],
    'jaspr_builder:client_module': [_i3.buildClientModule],
    'jaspr_builder:client_options': [_i3.buildClientOptions],
    'jaspr_builder:clients_bundle': [_i3.buildClientsBundle],
    'jaspr_builder:codec_bundle': [_i3.buildCodecBundle],
    'jaspr_builder:codec_module': [_i3.buildCodecModule],
    'jaspr_builder:import_output': [_i3.buildImportsOutput],
    'jaspr_builder:imports_module': [_i3.buildImportsModule],
    'jaspr_builder:server_options': [_i3.buildServerOptions],
    'jaspr_builder:stub': [_i3.buildPlatformStubs],
    'jaspr_builder:styles_bundle': [_i3.buildStylesBundle],
    'jaspr_builder:styles_module': [_i3.buildStylesModule],
    'jaspr_builder:styles_standalone': [_i3.buildStylesStandalone],
    'jaspr_builder:sync_mixins_module': [_i3.buildSyncMixins],
    'source_gen:combining_builder': [_i4.combiningBuilder],
  },
  postProcessBuilderFactories: {
    'build_modules:module_cleanup': _i1.moduleCleanup,
    'build_web_compilers:dart2js_archive_extractor':
        _i2.dart2jsArchiveExtractor,
    'build_web_compilers:dart_source_cleanup': _i2.dartSourceCleanup,
    'source_gen:part_cleanup': _i4.partCleanup,
  },
);
void main(List<String> args) async {
  _io.exitCode = await _build_runner.ChildProcess.run(
    args,
    _builderFactories,
  )!;
}
