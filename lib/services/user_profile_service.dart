import 'package:firebase_auth/firebase_auth.dart';
import '../utils/error_message.dart';
import '../Dashboard/services/firebase_service.dart';
import '../models/user_profile.dart';

class UserProfileService {
  static final UserProfileService instance = UserProfileService._internal();
  UserProfileService._internal();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // Cached per-uid profile stream. profileStream() is called from build()
  // methods (home, chats, settings…); creating a fresh stream per call
  // re-subscribed a new Firestore listener on every rebuild. The underlying
  // doc.snapshots() is broadcast, so one shared instance serves all builders.
  String? _profileStreamUid;
  Stream<UserProfile?>? _profileStreamCache;

  Stream<UserProfile?> profileStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    if (_profileStreamCache == null || _profileStreamUid != uid) {
      _profileStreamUid = uid;
      _profileStreamCache =
          FirebaseService.instance.getUserProfileStream(uid).map((data) {
        final user = FirebaseAuth.instance.currentUser;
        if (data == null) {
          return user != null ? UserProfile.fromAuthUser(user) : null;
        }
        return UserProfile.fromFirestore(uid, data);
      });
    }
    return _profileStreamCache!;
  }

  Future<UserProfile?> getCurrentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final data = await FirebaseService.instance.getUserProfile(user.uid);
    if (data != null) {
      return UserProfile.fromFirestore(user.uid, data);
    }
    return UserProfile.fromAuthUser(user);
  }

  Future<void> updateProfile({
    required String name,
    required String email,
    required String phone,
    String? gender,
    String? bloodGroup,
    String? photoUrl,
    bool? phoneVerified,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    try {
      await FirebaseService.instance.updateUserProfile(
        uid: user.uid,
        name: name,
        email: email,
        phone: phone,
        gender: gender,
        bloodGroup: bloodGroup,
        photoUrl: photoUrl,
        phoneVerified: phoneVerified,
      );
    } catch (e) {
      throw Exception(friendlyErrorMessage(e, prefix: 'Could not save profile.'));
    }

    try {
      if (user.displayName != name) {
        await user.updateDisplayName(name);
      }
      if (photoUrl != null && photoUrl.isNotEmpty) {
        await user.updatePhotoURL(photoUrl);
      }
      await user.reload();
    } catch (_) {
      // Firestore profile is source of truth; auth display name optional
    }
  }
}
