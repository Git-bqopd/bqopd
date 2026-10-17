import 'package:jaspr/server.dart';
import 'package:jaspr/dom.dart';
import 'app.dart';

void main() {
  Jaspr.initializeApp();
  runApp(Document(
    title: 'bqopd',
    // Sets <base href="/"> which is required for the Jaspr Router to parse URLs correctly
    base: '/',
    head: [
      link(href: 'styles.css', rel: 'stylesheet'),
      link(href: 'https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200', rel: 'stylesheet'),
      // Google Fonts Preconnect and Stylesheet for Anton and Arimo
      link(href: 'https://fonts.googleapis.com', rel: 'preconnect'),
      link(href: 'https://fonts.gstatic.com', rel: 'preconnect', attributes: {'crossorigin': ''}),
      link(href: 'https://fonts.googleapis.com/css2?family=Anton&family=Arimo:ital,wght@0,400..700;1,400..700&display=swap', rel: 'stylesheet'),
      script(src: 'https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js'),
      script(src: 'https://www.gstatic.com/firebasejs/10.12.2/firebase-auth-compat.js'),
      script(src: 'https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore-compat.js'),
      script(src: 'https://www.gstatic.com/firebasejs/10.12.2/firebase-storage-compat.js'),
      script(src: 'https://www.gstatic.com/firebasejs/10.12.2/firebase-functions-compat.js'),
      // Load Google Places SDK on server pre-renders as well
      script(src: 'https://maps.googleapis.com/maps/api/js?key=AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g&libraries=places&loading=async'),
      // Pull in central JS initialization script
      script(src: 'firebase_init.js'),
      // Load the compiled Dart app so it takes over from the pre-rendered shell
      script(src: 'main.dart.js', defer: true),
    ],
    body: App(),
  ));
}