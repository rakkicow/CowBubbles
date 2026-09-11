// sf pro, fetched at runtime like the emoji font
//
// apple's licence keeps the font off other platforms, so nothing ships in the
// apk. bricolage stands in until it is loaded.
const List<String> sfProFontUrls = [
  'https://github.com/sahibjotsaggu/San-Francisco-Pro-Fonts/raw/master/SF-Pro-Display-Regular.otf',
  'https://github.com/sahibjotsaggu/San-Francisco-Pro-Fonts/raw/master/SF-Pro-Display-Bold.otf',
];

// file names on disk, in the same order
const List<String> sfProFontFiles = ['sfpro-regular.otf', 'sfpro-bold.otf'];

const String sfProFamily = 'SFPro';

// launcher icons the picker offers
enum CowIcon { face, bubbles }

extension CowIconInfo on CowIcon {
  String get key => name;
  String get label => this == CowIcon.face ? 'Cow face' : 'Bubbles';
  String get asset => this == CowIcon.face
      ? 'assets/icon/cow_icon.png'
      : 'assets/icon/cow_icon_bubbles.png';
}

// the two looks the skin picker offers
enum CowSkin { CowOS, iOS }

extension CowSkinThemes on CowSkin {
  String get lightTheme => this == CowSkin.CowOS ? "CowBubbles \u2600" : "Bright White";
  String get darkTheme => this == CowSkin.CowOS ? "CowBubbles \u{1F319}" : "OLED Dark";
}
