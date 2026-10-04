part of '../../../models/models.dart';

class UserProfile {
  final String uid;
  final String? username;
  final String? avatarUrl;
  final String? userGroup;
  final int? credits;
  final int? gold;
  final int? contribution;
  final int? threads;
  final int? posts;
  final int? friends;
  final String? regDate;
  final String? lastVisit;

  const UserProfile({
    required this.uid,
    this.username,
    this.avatarUrl,
    this.userGroup,
    this.credits,
    this.gold,
    this.contribution,
    this.threads,
    this.posts,
    this.friends,
    this.regDate,
    this.lastVisit,
  });
}

class SpaceUserProfile {
  final String uid;
  final String username;
  final String? avatarUrl;
  final String? backgroundUrl;
  final int? popularity;
  final int? following;
  final int? followers;
  final int? posts;
  final int? replies;
  final int? friends;
  final int? credits;
  final int? goodReview;
  final int? gold;
  final int? reputation;
  final String? level;
  final String? userGroup;
  final String? gender;
  final String? signature;
  final String? customTitle;
  final String? occupation;
  final String? residence;
  final String? birthday;
  final String? onlineTime;
  final String? registerTime;
  final String? lastVisit;
  final List<String> medalUrls;
  final bool isFollowing;
  final bool isBlocked;
  final String? followUrl;
  final String? friendUrl;
  final String? pokeUrl;
  final String? messageUrl;
  final String? reportUrl;

  const SpaceUserProfile({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.backgroundUrl,
    this.popularity,
    this.following,
    this.followers,
    this.posts,
    this.replies,
    this.friends,
    this.credits,
    this.goodReview,
    this.gold,
    this.reputation,
    this.level,
    this.userGroup,
    this.gender,
    this.signature,
    this.customTitle,
    this.occupation,
    this.residence,
    this.birthday,
    this.onlineTime,
    this.registerTime,
    this.lastVisit,
    this.medalUrls = const [],
    this.isFollowing = false,
    this.isBlocked = false,
    this.followUrl,
    this.friendUrl,
    this.pokeUrl,
    this.messageUrl,
    this.reportUrl,
  });

  SpaceUserProfile copyWith({
    int? following,
    int? followers,
    bool? isFollowing,
    bool? isBlocked,
    String? followUrl,
  }) {
    return SpaceUserProfile(
      uid: uid,
      username: username,
      avatarUrl: avatarUrl,
      backgroundUrl: backgroundUrl,
      popularity: popularity,
      following: following ?? this.following,
      followers: followers ?? this.followers,
      posts: posts,
      replies: replies,
      friends: friends,
      credits: credits,
      goodReview: goodReview,
      gold: gold,
      reputation: reputation,
      level: level,
      userGroup: userGroup,
      gender: gender,
      signature: signature,
      customTitle: customTitle,
      occupation: occupation,
      residence: residence,
      birthday: birthday,
      onlineTime: onlineTime,
      registerTime: registerTime,
      lastVisit: lastVisit,
      medalUrls: medalUrls,
      isFollowing: isFollowing ?? this.isFollowing,
      isBlocked: isBlocked ?? this.isBlocked,
      followUrl: followUrl ?? this.followUrl,
      friendUrl: friendUrl,
      pokeUrl: pokeUrl,
      messageUrl: messageUrl,
      reportUrl: reportUrl,
    );
  }
}

class BasicProfileForm {
  final String realname;
  final int privacyRealname;
  final int gender;
  final int privacyGender;
  final int birthyear;
  final int birthmonth;
  final int birthday;
  final int privacyBirthday;
  final String resideProvince;
  final int privacyResideCity;
  final String occupation;
  final int privacyOccupation;

  const BasicProfileForm({
    this.realname = '',
    this.privacyRealname = 3,
    this.gender = 0,
    this.privacyGender = 0,
    this.birthyear = 0,
    this.birthmonth = 0,
    this.birthday = 0,
    this.privacyBirthday = 0,
    this.resideProvince = '',
    this.privacyResideCity = 0,
    this.occupation = '',
    this.privacyOccupation = 0,
  });
}

class CreditSummary {
  final int? total;
  final int? gold;
  final int? praise;
  final int? reputation;
  final String formula;

  const CreditSummary({
    this.total,
    this.gold,
    this.praise,
    this.reputation,
    this.formula = '',
  });
}

class RemoteTextPageData {
  final String title;
  final List<String> lines;

  const RemoteTextPageData({
    required this.title,
    required this.lines,
  });
}

class UserGroupPermission {
  final String name;
  final String value;
  final bool? allowed;

  const UserGroupPermission({
    required this.name,
    required this.value,
    this.allowed,
  });
}

class UserGroupData {
  final String groupName;
  final String currentLevel;
  final String nextLevel;
  final double progress;
  final String pointsNeeded;
  final String nextGroupName;
  final List<UserGroupPermission> permissions;

  const UserGroupData({
    this.groupName = '',
    this.currentLevel = '',
    this.nextLevel = '',
    this.progress = 0,
    this.pointsNeeded = '',
    this.nextGroupName = '',
    this.permissions = const [],
  });
}

class SignatureProfileForm {
  final String bio;
  final String signature;
  final int privacyBio;

  const SignatureProfileForm({
    this.bio = '',
    this.signature = '',
    this.privacyBio = 0,
  });
}

class SecurityQuestionOption {
  final int id;
  final String label;

  const SecurityQuestionOption({
    required this.id,
    required this.label,
  });
}

class PasswordSecurityData {
  final String formhash;
  final String email;
  final String mobileCountryCode;
  final String mobile;
  final int questionId;
  final List<SecurityQuestionOption> questions;

  const PasswordSecurityData({
    required this.formhash,
    this.email = '',
    this.mobileCountryCode = '',
    this.mobile = '',
    this.questionId = 0,
    this.questions = const [],
  });
}

class ContactProfileForm {
  final String qq;
  final int privacyQq;
  final String mobile;
  final int privacyMobile;

  const ContactProfileForm({
    this.qq = '',
    this.privacyQq = 0,
    this.mobile = '',
    this.privacyMobile = 0,
  });
}

class PasswordSecurityUpdate {
  final String oldPassword;
  final String newPassword;
  final String newPasswordConfirm;
  final String email;
  final String mobileCountryCode;
  final String mobile;
  final int questionId;
  final String answer;

  const PasswordSecurityUpdate({
    required this.oldPassword,
    this.newPassword = '',
    this.newPasswordConfirm = '',
    this.email = '',
    this.mobileCountryCode = '',
    this.mobile = '',
    this.questionId = 0,
    this.answer = '',
  });
}

class SmsCodeResult {
  final bool success;
  final String message;
  final int cooldownSeconds;

  const SmsCodeResult({
    required this.success,
    required this.message,
    this.cooldownSeconds = 0,
  });
}

class PokeOption {
  final int iconId;
  final String label;
  final String? iconUrl;

  const PokeOption({
    required this.iconId,
    required this.label,
    this.iconUrl,
  });
}

class PokePageData {
  final String formhash;
  final List<PokeOption> options;

  const PokePageData({
    required this.formhash,
    this.options = const [],
  });
}

class InviteStatusData {
  final bool canInvite;
  final String message;

  const InviteStatusData({
    required this.canInvite,
    required this.message,
  });
}

class SmsBindingData {
  final String? phone;
  final bool canUnbind;

  const SmsBindingData({
    this.phone,
    this.canUnbind = false,
  });
}

class PromotionData {
  final String username;
  final String uid;
  final String? avatarUrl;
  final String link;
  final String reward;

  const PromotionData({
    required this.username,
    required this.uid,
    this.avatarUrl,
    required this.link,
    required this.reward,
  });
}

class CreditRecord {
  final String type;
  final String delta;
  final String time;
  final String reason;
  final String raw;

  const CreditRecord({
    this.type = '',
    this.delta = '',
    this.time = '',
    this.reason = '',
    this.raw = '',
  });
}

class RenameStatusData {
  final int? costGold;
  final bool insufficientGold;
  final bool hasRenameForm;
  final String message;

  const RenameStatusData({
    this.costGold,
    this.insufficientGold = false,
    this.hasRenameForm = false,
    this.message = '',
  });
}
