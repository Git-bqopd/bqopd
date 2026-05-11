import '../models/user_profile.dart';
import '../models/user_account.dart';

abstract class IUserRepository {
  Stream<UserProfile?> watchUser(String uid);
  Stream<UserAccount?> watchUserAccount(String uid);
  Future<void> updateProfile(String uid, Map<String, dynamic> data);
  Stream<List<Map<String, dynamic>>> watchUserWorks(String uid);
  Stream<List<Map<String, dynamic>>> watchUserMentions(String uid);
  Future<String?> claimHandleForUser(String handle);
}