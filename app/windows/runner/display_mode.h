#ifndef RUNNER_DISPLAY_MODE_H_
#define RUNNER_DISPLAY_MODE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// Match Frame Rate on Windows (lib/services/display_match.dart): lists the modes of the
// monitor Liquiflux's window is on and switches its refresh rate for a video. The switch is
// made with CDS_FULLSCREEN, so it is never saved to the registry and Windows puts the
// monitor back by itself if Liquiflux closes or crashes.
//
// Channel liquiflux/display:
// - modes: {current: index or -1, modes: [{id: index, width, height, refreshRate}]}
// - set {id}: switches to that mode; true when Windows took it.
// - restore: back to the monitor's saved mode.
class DisplayModeChannel {
 public:
  DisplayModeChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~DisplayModeChannel();

  // Puts the monitor back if a video changed it.
  void Restore();

 private:
  std::wstring Device() const;

  HWND window_;
  std::wstring changed_;  // The monitor we switched, empty when none.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DISPLAY_MODE_H_
