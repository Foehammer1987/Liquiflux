#include "display_mode.h"

#include <flutter/standard_method_codec.h>

#include <variant>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

// Windows lists 23.976 Hz as 23, 59.94 as 59 and so on; 24 and 60 are themselves.
double RefreshRate(DWORD hz) {
  switch (hz) {
    case 23:
    case 29:
    case 47:
    case 59:
    case 119:
      return (hz + 1) / 1.001;
    default:
      return static_cast<double>(hz);
  }
}

bool Usable(const DEVMODEW& dm) {
  return dm.dmBitsPerPel >= 24 && (dm.dmDisplayFlags & DM_INTERLACED) == 0 && dm.dmDisplayFrequency > 1;
}

bool SameMode(const DEVMODEW& a, const DEVMODEW& b) {
  return a.dmPelsWidth == b.dmPelsWidth && a.dmPelsHeight == b.dmPelsHeight && a.dmDisplayFrequency == b.dmDisplayFrequency;
}

}  // namespace

DisplayModeChannel::DisplayModeChannel(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "liquiflux/display",
                                                                      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<EncodableValue>& call,
                                        std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const std::string& method = call.method_name();
    if (method == "modes") {
      const std::wstring device = Device();
      if (device.empty()) return result->Success();
      DEVMODEW current = {};
      current.dmSize = sizeof(current);
      if (!EnumDisplaySettingsW(device.c_str(), ENUM_CURRENT_SETTINGS, &current)) return result->Success();
      EncodableList modes;
      int current_id = -1;
      std::vector<DEVMODEW> seen;
      DEVMODEW dm = {};
      dm.dmSize = sizeof(dm);
      for (DWORD i = 0; EnumDisplaySettingsExW(device.c_str(), i, &dm, 0); i++) {
        // Only the modes at the current colour depth and orientation, once each.
        if (!Usable(dm) || dm.dmBitsPerPel != current.dmBitsPerPel ||
            ((dm.dmFields & DM_DISPLAYORIENTATION) && dm.dmDisplayOrientation != current.dmDisplayOrientation)) {
          continue;
        }
        bool dup = false;
        for (const auto& s : seen) dup = dup || SameMode(s, dm);
        if (dup) continue;
        seen.push_back(dm);
        if (SameMode(dm, current)) current_id = static_cast<int>(i);
        modes.push_back(EncodableValue(EncodableMap{
            {EncodableValue("id"), EncodableValue(static_cast<int>(i))},
            {EncodableValue("width"), EncodableValue(static_cast<int>(dm.dmPelsWidth))},
            {EncodableValue("height"), EncodableValue(static_cast<int>(dm.dmPelsHeight))},
            {EncodableValue("refreshRate"), EncodableValue(RefreshRate(dm.dmDisplayFrequency))},
        }));
      }
      return result->Success(EncodableValue(EncodableMap{
          {EncodableValue("current"), EncodableValue(current_id)},
          {EncodableValue("modes"), EncodableValue(modes)},
      }));
    }
    if (method == "set") {
      const auto* args = std::get_if<EncodableMap>(call.arguments());
      const EncodableValue* id = nullptr;
      if (args) {
        auto it = args->find(EncodableValue("id"));
        if (it != args->end()) id = &it->second;
      }
      const std::wstring device = Device();
      if (!id || !std::holds_alternative<int>(*id) || std::get<int>(*id) < 0 || device.empty()) {
        return result->Success(EncodableValue(false));
      }
      DEVMODEW dm = {};
      dm.dmSize = sizeof(dm);
      if (!EnumDisplaySettingsExW(device.c_str(), static_cast<DWORD>(std::get<int>(*id)), &dm, 0) || !Usable(dm)) {
        return result->Success(EncodableValue(false));
      }
      dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL | DM_DISPLAYFREQUENCY;
      // Another monitor switched earlier goes back first (the window moved).
      if (!changed_.empty() && changed_ != device) Restore();
      const LONG r = ChangeDisplaySettingsExW(device.c_str(), &dm, nullptr, CDS_FULLSCREEN, nullptr);
      if (r == DISP_CHANGE_SUCCESSFUL) changed_ = device;
      return result->Success(EncodableValue(r == DISP_CHANGE_SUCCESSFUL));
    }
    if (method == "restore") {
      Restore();
      return result->Success();
    }
    result->NotImplemented();
  });
}

DisplayModeChannel::~DisplayModeChannel() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  Restore();
}

void DisplayModeChannel::Restore() {
  if (changed_.empty()) return;
  ChangeDisplaySettingsExW(changed_.c_str(), nullptr, nullptr, 0, nullptr);
  changed_.clear();
}

std::wstring DisplayModeChannel::Device() const {
  HMONITOR monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(info);
  if (!monitor || !GetMonitorInfoW(monitor, &info)) return std::wstring();
  return std::wstring(info.szDevice);
}
