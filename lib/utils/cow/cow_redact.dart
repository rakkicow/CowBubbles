import 'dart:math';

/// cow stand-ins for redacted mode, seeded from what they replace
// word counts are preserved so bubbles keep their shape
class CowRedact {
  static const List<String> _first = [
    'Moorice', 'Bessie', 'Daisy', 'Clarabelle', 'Mootilda', 'Cowen', 'Moolan',
    'Buttercup', 'Ferdinand', 'Angus', 'Bovina', 'Elsie', 'Moona', 'Calfrey',
    'Patty', 'Moobert', 'Milkshake', 'Hoofrey', 'Mooriel', 'Cowlin', 'Heidi',
    'Moolissa', 'Cuddy', 'Mooghan', 'Bella', 'Moovin', 'Chewy', 'Moody',
  ];
  static const List<String> _last = [
    'Moo', 'Udderly', 'Cudd', 'Bovine', 'Hoofman', 'Pasture', 'Dairy',
    'Graze', 'Moolington', 'van Hoof', 'Hornsby', 'Calfield', 'Mooney',
    'Beefington', 'Steer', 'Holstein', 'Jersey', 'Herdman', 'Milkwood',
    'Cowper', 'Bullock', 'Heifer', 'Mooregan',
  ];
  /// tv characters
  static const List<String> _tv = [
    'Moochael Scott', 'Dwight Moorute', 'Jim Hoofpert', 'Pam Grazely',
    'Andy Barnyard', 'Kevin Moolone', 'Creed Brisket', 'Stanley Hoofson',
    'Walter Whey', 'Jesse Pinkmoo', 'Saul Goodmoo', 'Tony Sopramoo',
    'Rachel Grazer', 'Ross Grazer', 'Monica Grazer', 'Chandler Bull',
    'Joey Tribbovine', 'Phoebe Bovine', 'Homer Simpsteer', 'Marge Simpsteer',
    'Leslie Moope', 'Ron Swansteer', 'Jake Pastureta', 'Raymond Hoof',
    'Sherlock Hooves', 'Don Grazer', 'Peggy Olsteer', 'Daenerys Targrazen',
    'Jon Moo', 'Tyrion Lannisteer', 'Ted Lassoo', 'Liz Lemoo',
    'Frasier Grazer', 'Cosmo Kramoo', 'Jerry Steerfeld', 'George Cowstanza',
    'Elaine Bovines', 'Lorelai Gilmoo', 'Rory Gilmoo', 'Moochael Bluth',
    'Gob Bull', 'Dexter Moorgan', 'Fox Moolder', 'Dana Scudly',
    'Rick Ranchez', 'Morty Smoo', 'Steve Harringmoo', 'Dustin Hendersteer',
    'Buffy Summoos', 'Bojack Cowman', 'Al Bundy Moo', 'Eleven Moofield',
  ];

  static const List<String> _herds = [
    'The Herd', 'Moo Crew', 'Pasture Pals', 'The Barnyard', 'Cud Club',
    'Grazing Group', 'The Milky Way', 'Udder Chaos', 'Cattle Chat',
    'Moo Point', 'The Cowlition', 'Bovine Intervention',
  ];

  /// stories and riddles, one sentence each
  static const List<String> _sentences = [
    'A cow named Moorice once walked all the way to town just to see what the fuss was about.',
    'The farmer swore the cows were plotting something, and honestly they were.',
    'Every morning Bessie waited by the gate for the sun like it owed her money.',
    'What do you call a cow with no legs? Ground beef.',
    'What do you call a cow that plays an instrument? A moosician.',
    'Why did the cow cross the road? To get to the udder side.',
    'The whole herd agreed the new pasture had better views but worse gossip.',
    'Nobody knew where Clarabelle went at night, and she was not telling.',
    'A calf asked its mother why the moon followed them, and she said it was just curious.',
    'What has four legs and says moo backwards? A cow walking away from you.',
    'Daisy discovered the electric fence exactly once and never spoke of it again.',
    'The barn cat and the old bull had an understanding that neither could explain.',
    'Where do cows go on a Friday night? To the moovies.',
    'The herd voted and the vote was unanimous: more clover, fewer flies.',
    'One cow kept a diary, mostly about grass, occasionally about the weather.',
    'What do you get from a pampered cow? Spoiled milk.',
    'Ferdinand preferred the shade of the oak tree and would fight you for it.',
    'A riddle for the pasture: I have horns but never honk, what am I?',
    'The youngest calf tried to jump the creek and learned a lot about creeks.',
    'Why do cows wear bells? Because their horns do not work.',
    'The cows lined up by the fence every evening to review the sunset.',
    'Moona was certain the tractor was a very slow, very loud animal.',
    'What do you call a sleeping bull? A bulldozer.',
    'Rain came and the whole herd stood under one tree like it was a plan.',
    'The farmer left the gate open once and learned what freedom smells like.',
    'A cow told a joke so good the milk came out sweet for a week.',
    'How does a cow do math? With a cow-culator.',
    'Buttercup found the salt lick and declared it the best day of her life.',
    'The herd had a rule: whoever moos first at dawn owes everyone clover.',
    'What did the cow say to the calf who got an A? Outstanding in your field.',
    'Some days the pasture was a kingdom and Angus was its reluctant king.',
    'The cows did not understand fences but they respected them, mostly.',
  ];

  static const List<String> _tiny = [
    'Moo.', 'Moo moo.', 'Udderly.', 'Got milk?', 'Holy cow.', 'Moo!',
    'Cud?', 'Moove.', 'Grass.', 'Moo moo moo.',
  ];

  /// fnv-1a
  static int hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// cow name for a handle
  static String name(String seed) {
    final r = Random(hash(seed));
    // half the herd is famous
    if (r.nextBool()) return _tv[r.nextInt(_tv.length)];
    return '${_first[r.nextInt(_first.length)]} ${_last[r.nextInt(_last.length)]}';
  }

  /// herd name for a group
  static String herd(String seed) {
    return _herds[hash(seed) % _herds.length];
  }

  /// cow text, [words] words long
  static String text(String seed, int words) {
    if (words <= 0) return '';
    final r = Random(hash(seed));
    if (words <= 3) {
      final t = _tiny[r.nextInt(_tiny.length)];
      final parts = t.split(' ');
      return parts.take(words).join(' ');
    }
    final out = <String>[];
    var count = 0;
    var guard = 0;
    while (count < words && guard++ < 40) {
      final s = _sentences[r.nextInt(_sentences.length)];
      final w = s.split(' ');
      out.addAll(w);
      count += w.length;
    }
    final trimmed = out.take(words).toList();
    // end on a full stop
    final last = trimmed.last;
    if (!last.endsWith('.') && !last.endsWith('?') && !last.endsWith('!')) {
      trimmed[trimmed.length - 1] = last.replaceAll(RegExp(r'[,;:]$'), '') + '.';
    }
    return trimmed.join(' ');
  }
}
