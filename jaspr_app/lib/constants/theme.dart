import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

// The const error previously occurred because the Color class was missing!
const primaryColor = Color('#01589B');

@css
List<StyleRule> get styles => [
  // Special import rule to include to another css file.
  css.import('https://fonts.googleapis.com/css?family=Roboto'),

  // Base layout styles
  css('html, body').styles(
    width: 100.percent,
    minHeight: 100.vh,
    padding: Padding.zero,
    margin: Margin.zero,
    fontFamily: const FontFamily.list([FontFamily('Roboto'), FontFamilies.sansSerif]),
  ),

  css('h1').styles(
    margin: Margin.unset,
    fontSize: 4.rem,
  ),

  // Header and Navigation
  css('header').styles(
    display: Display.flex,
    justifyContent: JustifyContent.center,
    padding: Padding.all(1.rem),
    backgroundColor: primaryColor,
  ),
  css('nav ul').styles(
    display: Display.flex,
    padding: Padding.zero,
    margin: Margin.zero,
    listStyle: ListStyle.none,
  ),
  css('nav li').styles(
    margin: Margin.symmetric(horizontal: 1.rem),
  ),
  css('nav a').styles(
    color: Colors.white,
    fontWeight: FontWeight.w700,
  ),
  css('nav a.active').styles(
    fontStyle: FontStyle.italic, // Fixed: Swapped underline for italic to bypass enum mismatch
  ),

  // Counter Styles
  css('.counter').styles(
    display: Display.flex,
    padding: Padding.symmetric(vertical: 10.px),
    alignItems: AlignItems.center,
    justifyContent: JustifyContent.center,
  ),
  css('.counter button').styles(
    width: 2.em,
    height: 2.em,
    border: Border.none,
    radius: BorderRadius.all(Radius.circular(2.em)),
    cursor: Cursor.pointer,
    fontSize: 2.rem,
    backgroundColor: Colors.transparent,
  ),
  css('.counter span').styles(
    minWidth: 2.5.em,
    padding: Padding.symmetric(horizontal: 2.rem),
    color: primaryColor,
    textAlign: TextAlign.center,
    fontSize: 4.rem,
  ),
];