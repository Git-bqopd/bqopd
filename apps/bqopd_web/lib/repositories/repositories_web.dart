import 'package:bqopd_core/bqopd_core.dart';
import 'web_auth_repository.dart';
import 'web_engagement_repository.dart';
import 'web_fanzine_repository.dart';
import 'web_pipeline_repository.dart';
import 'web_upload_repository.dart';
import 'web_user_repository.dart';

IAuthRepository createAuthRepository() => WebAuthRepository();
IFanzineRepository createFanzineRepository() => WebFanzineRepository();
IEngagementRepository createEngagementRepository() => WebEngagementRepository();
IPipelineRepository createPipelineRepository() => WebPipelineRepository();
IUploadRepository createUploadRepository() => WebUploadRepository();
IUserRepository createUserRepository() => WebUserRepository();