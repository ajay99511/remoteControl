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

  // Channel entry. Distinct from text input: a numpad on a TV remote changes
  // the channel, it does not type into a focused field. Routing these through
  // sendText meant Roku received Lit_1 (a literal character, meaningful only
  // with a text field focused) and Samsung received a base64 IME payload
  // rather than the KEY_1..KEY_0 codes its protocol defines.
  digit0,
  digit1,
  digit2,
  digit3,
  digit4,
  digit5,
  digit6,
  digit7,
  digit8,
  digit9,
}

/// The digit keys in numeric order, indexable by value.
const List<RemoteKey> kDigitKeys = [
  RemoteKey.digit0,
  RemoteKey.digit1,
  RemoteKey.digit2,
  RemoteKey.digit3,
  RemoteKey.digit4,
  RemoteKey.digit5,
  RemoteKey.digit6,
  RemoteKey.digit7,
  RemoteKey.digit8,
  RemoteKey.digit9,
];
