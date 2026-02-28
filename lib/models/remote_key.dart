/// Enum representing all remote control keys that can be sent to a device.
///
/// Each key maps to a protocol-specific command string in the concrete
/// controller implementations (e.g., RokuController maps [up] to 'Up').
enum RemoteKey {
  up,
  down,
  left,
  right,
  select,
  back,
  home,
  playPause,
  volumeUp,
  volumeDown,
  mute,
  power,
  rewind,
  fastForward,
}
