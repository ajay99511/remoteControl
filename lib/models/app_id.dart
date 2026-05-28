/// Typed enum for app launch identifiers.
/// Replaces raw String app names in launchApp() calls.
enum AppId {
  netflix,
  youtube,
  primeVideo,
  disneyPlus,
  hulu,
  spotify,
  appleTv;

  /// Human-readable display name for UI.
  String get displayName {
    switch (this) {
      case AppId.netflix:
        return 'Netflix';
      case AppId.youtube:
        return 'YouTube';
      case AppId.primeVideo:
        return 'Prime Video';
      case AppId.disneyPlus:
        return 'Disney+';
      case AppId.hulu:
        return 'Hulu';
      case AppId.spotify:
        return 'Spotify';
      case AppId.appleTv:
        return 'Apple TV';
    }
  }
}
