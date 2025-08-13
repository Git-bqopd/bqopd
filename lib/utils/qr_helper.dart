import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr/qr.dart';

const String qrUrlPrefix = 'https://bqopd.com/';
const int qrVersion = 4; // adjust between 3 or 4 as needed
const int qrEcc = QrErrorCorrectLevel.M;

QrImageView buildQr(String shortcode, {double size = 200}) {
  return QrImageView(
    data: '$qrUrlPrefix$shortcode',
    version: qrVersion,
    errorCorrectionLevel: qrEcc,
    size: size,
  );
}
