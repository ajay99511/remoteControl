/// Enum representing all remote control keys that can be sent to a device.
enum RemoteKey {
  // Navigation
  up,
  down,
  left,
  right,
  select,
  ok,
  back,
  exit,
  home,
  menu,
  info,
  guide,
  search,
  settings,

  // Playback
  playPause,
  rewind,
  fastForward,
  replay,
  instantReplay,
  record,

  // Volume
  volumeUp,
  volumeDown,
  mute,

  // Channels
  channelUp,
  channelDown,

  // Input / Display
  inputSource,
  aspectRatio,
  pip,
  subtitles,
  audioTrack,

  // Power / System
  power,
  sleep,

  // Roku-specific
  star,
}
