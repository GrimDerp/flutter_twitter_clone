import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_twitter_clone/helper/enum.dart';
import 'package:flutter_twitter_clone/helper/utility.dart';
import 'package:flutter_twitter_clone/model/feedModel.dart';
import 'package:flutter_twitter_clone/model/user.dart';
import 'package:firebase_database/firebase_database.dart' as dabase;
import 'package:flutter_twitter_clone/state/base/tweetBaseState.dart';

class ProfileState extends TweetBaseState {
  ProfileState(this.profileId) {
    databaseInit();
    userId = FirebaseAuth.instance.currentUser.uid;
    _getloggedInUserProfile(userId);
    _getProfileUser(profileId);
  }

  /// This is the id of user who is logegd into the app.
  String userId;

  /// Profile data of logged in user.
  UserModel _userModel;
  UserModel get userModel => _userModel;

  dabase.Query _profileQuery;
  StreamSubscription<Event> profileSubscription;

  /// This is the id of user whose profile is open.
  final String profileId;

  /// Profile data of user whose profile is open.
  UserModel _profileUserModel;
  UserModel get profileUserModel => _profileUserModel;

  bool _isBusy = true;
  bool get isbusy => _isBusy;
  set loading(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  databaseInit() {
    try {
      if (_profileQuery == null) {
        _profileQuery = kDatabase.child("profile").child(profileId);
        profileSubscription = _profileQuery.onValue.listen(_onProfileChanged);
      }
    } catch (error) {
      cprint(error, errorIn: 'databaseInit');
    }
    getDataFromDatabase();
  }

  List<FeedModel> _feedlist;
  List<FeedModel> get feedlist => _feedlist;
  bool isBusy = true;
  void getDataFromDatabase() {
    try {
      isBusy = true;
      _feedlist = null;
      notifyListeners();
      kDatabase
          .child('tweet')
          .orderByChild("userId")
          .equalTo(profileId)
          .once()
          .then((DataSnapshot snapshot) {
        _feedlist = <FeedModel>[];
        if (snapshot.value != null) {
          var map = snapshot.value;
          if (map != null) {
            map.forEach((key, value) {
              var model = FeedModel.fromJson(value);
              model.key = key;
              if (model.isValidTweet) {
                _feedlist.add(model);
              }
            });

            /// Sort Tweet by time
            /// It helps to display newest Tweet first.
            _feedlist.sort((x, y) => DateTime.parse(x.createdAt)
                .compareTo(DateTime.parse(y.createdAt)));
          }
        } else {
          _feedlist = null;
        }
        isBusy = false;
        notifyListeners();
      });
    } catch (error) {
      isBusy = false;
      cprint(error, errorIn: 'getDataFromDatabase');
    }
  }

  bool get isMyProfile => profileId == userId;

  /// Fetch profile of logged in  user
  void _getloggedInUserProfile(String userId) async {
    kDatabase
        .child("profile")
        .child(userId)
        .once()
        .then((DataSnapshot snapshot) {
      if (snapshot.value != null) {
        var map = snapshot.value;
        if (map != null) {
          _userModel = UserModel.fromJson(map);
        }
      }
    });
  }

  /// Fetch profile data of user whoose profile is opened
  void _getProfileUser(String userProfileId) {
    assert(userProfileId != null);
    try {
      loading = true;
      kDatabase
          .child("profile")
          .child(userProfileId)
          .once()
          .then((DataSnapshot snapshot) {
        if (snapshot.value != null) {
          var map = snapshot.value;
          if (map != null) {
            _profileUserModel = UserModel.fromJson(map);
            Utility.logEvent('get_profile');
          }
        }
        loading = false;
      });
    } catch (error) {
      loading = false;
      cprint(error, errorIn: 'getProfileUser');
    }
  }

  /// Follow / Unfollow user
  ///
  /// If `removeFollower` is true then remove user from follower list
  ///
  /// If `removeFollower` is false then add user to follower list
  followUser({bool removeFollower = false}) {
    /// `userModel` is user who is logged-in app.
    /// `profileUserModel` is user whoose profile is open in app.
    try {
      if (removeFollower) {
        /// If logged-in user `alredy follow `profile user then
        /// 1.Remove logged-in user from profile user's `follower` list
        /// 2.Remove profile user from logged-in user's `following` list
        profileUserModel.followersList.remove(userModel.userId);

        /// Remove profile user from logged-in user's following list
        userModel.followingList.remove(profileUserModel.userId);
        cprint('user removed from following list', event: 'remove_follow');
      } else {
        /// if logged in user is `not following` profile user then
        /// 1.Add logged in user to profile user's `follower` list
        /// 2. Add profile user to logged in user's `following` list
        if (profileUserModel.followersList == null) {
          profileUserModel.followersList = [];
        }
        profileUserModel.followersList.add(userModel.userId);
        // Adding profile user to logged-in user's following list
        if (userModel.followingList == null) {
          userModel.followingList = [];
        }
        addFollowNotification();
        userModel.followingList.add(profileUserModel.userId);
      }
      // update profile user's user follower count
      profileUserModel.followers = profileUserModel.followersList.length;
      // update logged-in user's following count
      userModel.following = userModel.followingList.length;
      kDatabase
          .child('profile')
          .child(profileUserModel.userId)
          .child('followerList')
          .set(profileUserModel.followersList);
      kDatabase
          .child('profile')
          .child(userModel.userId)
          .child('followingList')
          .set(userModel.followingList);
      cprint('user added to following list', event: 'add_follow');

      notifyListeners();
    } catch (error) {
      cprint(error, errorIn: 'followUser');
    }
  }

  void addFollowNotification() {
    // Sends notification to user who created tweet
    // UserModel owner can see notification on notification page
    kDatabase.child('notification').child(profileId).child(userId).set({
      'type': NotificationType.Follow.toString(),
      'createdAt': DateTime.now().toUtc().toString(),
      'data': UserModel(
              displayName: userModel.displayName,
              profilePic: userModel.profilePic,
              isVerified: userModel.isVerified,
              userId: userModel.userId,
              bio: userModel.bio == "Edit profile to update bio"
                  ? ""
                  : userModel.bio,
              userName: userModel.userName)
          .toJson()
    });
  }

  tweetLikeToggle(FeedModel tweet) {
    addLikeToTweet(tweet, profileId);
    notifyListeners();
  }

  /// Trigger when logged-in user's profile change or updated
  /// Firebase event callback for profile update
  void _onProfileChanged(Event event) {
    if (event.snapshot != null) {
      final updatedUser = UserModel.fromJson(event.snapshot.value);
      if (updatedUser.userId == profileId) {
        _profileUserModel = updatedUser;
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _profileQuery.onValue.drain();
    profileSubscription.cancel();
    // _profileQuery.
    super.dispose();
  }
}
