import '../models/user_profile.dart';
import '../models/user_account.dart';
import '../models/fanzine.dart';

abstract class IUserRepository {
  Stream<UserProfile?> watchUser(String uid);
  Stream<UserAccount?> watchUserAccount(String uid);
  Future<void> updateProfile(String uid, Map<String, dynamic> data);

  Stream<List<Fanzine>> watchUserWorks(String uid);
  Stream<List<Fanzine>> watchUserMentions(String uid);
  Future<String?> claimHandleForUser(String handle);
}