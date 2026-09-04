/// Pakistani mobile numbers — compare last 10 digits (03xx…).
String normalizePhone(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0092') && digits.length > 4) {
    digits = digits.substring(4);
  } else if (digits.startsWith('92') && digits.length > 2) {
    digits = digits.substring(2);
  }
  if (digits.length > 10) {
    digits = digits.substring(digits.length - 10);
  }
  return digits;
}

bool phonesMatch(String a, String b) {
  final na = normalizePhone(a);
  final nb = normalizePhone(b);
  return na.isNotEmpty && na == nb;
}
