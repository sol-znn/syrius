#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <objbase.h>

#include <cstdint>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

namespace {

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Result = flutter::MethodResult<Value>;

constexpr char kNativeWindowChannel[] =
    "network.zenon.syrius/harness/native_window_owner";
constexpr wchar_t kParentOwnerProperty[] = L"Syrius.Harness.ParentOwner.v1";
constexpr wchar_t kChildOwnerProperty[] = L"Syrius.Harness.ChildOwner.v1";
constexpr int64_t kMaxFrameRequests = 128;

// A second controller in this process cannot replace the initially claimed one,
// including after a Dart hot restart or native window destruction.
bool g_native_owner_claimed = false;
bool g_native_owner_held = false;

bool HarnessRequested() {
  return GetEnvironmentVariableW(L"SYRIUS_HARNESS_HOME", nullptr, 0) > 1 &&
         GetEnvironmentVariableW(L"SYRIUS_HARNESS_PORT", nullptr, 0) > 1 &&
         GetEnvironmentVariableW(L"SYRIUS_HARNESS_TOKEN", nullptr, 0) > 1;
}

std::optional<int64_t> IntegerAt(const Map& map, const char* key) {
  const auto entry = map.find(Value(key));
  if (entry == map.end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<int32_t>(&entry->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&entry->second)) {
    return *value;
  }
  return std::nullopt;
}

std::string StringAt(const Map& map, const char* key) {
  const auto entry = map.find(Value(key));
  if (entry != map.end()) {
    if (const auto* value = std::get_if<std::string>(&entry->second)) {
      return *value;
    }
  }
  return {};
}

std::string ProcessInstance() {
  FILETIME creation, exit, kernel, user;
  if (!GetProcessTimes(GetCurrentProcess(), &creation, &exit, &kernel, &user)) {
    return {};
  }
  ULARGE_INTEGER started;
  started.LowPart = creation.dwLowDateTime;
  started.HighPart = creation.dwHighDateTime;
  std::ostringstream value;
  value << std::hex << std::setfill('0') << std::setw(16) << started.QuadPart;
  return value.str();
}

std::string OwnerGeneration() {
  GUID generation;
  if (FAILED(CoCreateGuid(&generation))) {
    return {};
  }
  std::ostringstream value;
  value << std::hex << std::setfill('0') << std::setw(8) << generation.Data1
        << std::setw(4) << generation.Data2 << std::setw(4) << generation.Data3;
  for (const auto byte : generation.Data4) {
    value << std::setw(2) << static_cast<unsigned int>(byte);
  }
  return value.str();
}

}  // namespace

// All methods and documented engine callbacks run on the platform thread.
// Callbacks retain a weak state, never a FlutterWindow reference. The child
// hook also notices destruction before a recycled HWND could look identical.
struct FlutterWindow::NativeWindowOwner
    : std::enable_shared_from_this<FlutterWindow::NativeWindowOwner> {
  explicit NativeWindowOwner(FlutterWindow* host)
      : window(host),
        controller(host->flutter_controller_.get()),
        engine(controller->engine()),
        view(controller->view()),
        parent(host->GetHandle()),
        child(view->GetNativeWindow()),
        enabled(HarnessRequested()) {}

  FlutterWindow* window;
  flutter::FlutterViewController* const controller;
  flutter::FlutterEngine* const engine;
  flutter::FlutterView* const view;
  const HWND parent;
  const HWND child;
  const bool enabled;
  bool held = false;
  bool first_frame = false;
  bool startup_claimed = false;
  bool startup_delivered = false;
  bool frame_pending = false;
  bool child_destroyed = false;
  int64_t last_request = 0;
  int64_t callback_serial = 0;
  std::string process_instance;
  std::string owner_generation;
  WNDPROC original_child_proc = nullptr;
  std::shared_ptr<NativeWindowOwner> hook_lifetime;
  std::unique_ptr<flutter::MethodChannel<Value>> channel;
  std::unique_ptr<Result> startup_result;
  std::unique_ptr<Result> frame_result;

  bool Current() const {
    if (held || window == nullptr || child_destroyed ||
        (enabled && g_native_owner_held) ||
        window->flutter_controller_.get() != controller ||
        controller->engine() != engine || controller->view() != view ||
        window->GetHandle() != parent || view->GetNativeWindow() != child ||
        !IsWindow(parent) || !IsWindow(child) || GetParent(child) != parent) {
      return false;
    }
    DWORD parent_process = 0;
    DWORD child_process = 0;
    const DWORD parent_thread = GetWindowThreadProcessId(parent, &parent_process);
    const DWORD child_thread = GetWindowThreadProcessId(child, &child_process);
    if (parent_process != GetCurrentProcessId() ||
        child_process != GetCurrentProcessId() ||
        parent_thread != GetCurrentThreadId() || child_thread != parent_thread) {
      return false;
    }
    return !enabled ||
           (GetPropW(parent, kParentOwnerProperty) == this &&
            GetPropW(child, kChildOwnerProperty) == this &&
            GetWindowLongPtrW(child, GWLP_WNDPROC) ==
                reinterpret_cast<LONG_PTR>(&ChildProc) &&
            engine->IsPlatformThread());
  }

  void Hold(const char* code) {
    held = true;
    if (enabled) {
      g_native_owner_held = true;
    }
    // Move both before replying, so reentry cannot settle either twice.
    auto startup = std::move(startup_result);
    auto frame = std::move(frame_result);
    if (startup) {
      startup->Error(code);
    }
    if (frame) {
      frame->Error(code);
    }
  }

  static LRESULT CALLBACK ChildProc(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam) {
    auto* owner = static_cast<NativeWindowOwner*>(
        GetPropW(hwnd, kChildOwnerProperty));
    if (owner == nullptr) {
      return DefWindowProcW(hwnd, message, wparam, lparam);
    }
    [[maybe_unused]] const auto retained = owner->shared_from_this();
    const WNDPROC original = owner->original_child_proc;
    if (message == WM_NCDESTROY) {
      owner->child_destroyed = true;
      owner->Hold("native-window-destroyed");
      RemovePropW(hwnd, kChildOwnerProperty);
      owner->hook_lifetime.reset();
    } else if ((message == WM_WINDOWPOSCHANGED || message == WM_STYLECHANGED) &&
               !owner->Current()) {
      owner->Hold("native-owner-replaced");
    }
    return CallWindowProcW(original, hwnd, message, wparam, lparam);
  }

  void Initialize() {
    if (!enabled) {
      return;
    }
    process_instance = ProcessInstance();
    owner_generation = OwnerGeneration();
    const bool was_claimed = g_native_owner_claimed;
    g_native_owner_claimed = true;
    if (was_claimed || process_instance.empty() || owner_generation.empty() ||
        GetPropW(parent, kParentOwnerProperty) != nullptr ||
        GetPropW(child, kChildOwnerProperty) != nullptr ||
        !SetPropW(parent, kParentOwnerProperty, this) ||
        !SetPropW(child, kChildOwnerProperty, this)) {
      Hold("native-owner-unavailable");
    } else {
      original_child_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
          child, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&ChildProc)));
      if (original_child_proc == nullptr) {
        Hold("native-owner-unavailable");
      } else {
        hook_lifetime = shared_from_this();
      }
    }
    channel = std::make_unique<flutter::MethodChannel<Value>>(
        engine->messenger(), kNativeWindowChannel,
        &flutter::StandardMethodCodec::GetInstance());
    const std::weak_ptr<NativeWindowOwner> weak = shared_from_this();
    channel->SetMethodCallHandler(
        [weak](const flutter::MethodCall<Value>& call,
               std::unique_ptr<Result> result) {
          auto owner = weak.lock();
          if (!owner) {
            result->Error("native-owner-destroyed");
            return;
          }
          owner->Handle(call, std::move(result));
        });
  }

  Value Receipt(const char* kind, int64_t request, int64_t serial) const {
    return Value(Map{
        {Value("protocol"), Value(int64_t{1})},
        {Value("kind"), Value(kind)},
        {Value("processId"), Value(static_cast<int64_t>(GetCurrentProcessId()))},
        {Value("processInstance"), Value(process_instance)},
        {Value("owner"), Value(owner_generation)},
        {Value("firstFrameCallback"), Value(int64_t{1})},
        {Value("callbackSerial"), Value(serial)},
        {Value("request"), Value(request)},
    });
  }

  void DeliverStartup() {
    if (startup_result && first_frame && Current()) {
      auto result = std::move(startup_result);
      startup_delivered = true;
      result->Success(Receipt("startup", 0, 1));
    }
  }

  void FirstFrame() {
    // Keep the runner's first-show callback even when harness proof is refused.
    if (window == nullptr || window->flutter_controller_.get() != controller ||
        window->GetHandle() != parent) {
      Hold("native-owner-replaced");
      return;
    }
    window->Show();
    if (!enabled) {
      return;
    }
    if (!Current()) {
      Hold("native-owner-replaced");
      return;
    }
    first_frame = true;
    callback_serial = 1;
    DeliverStartup();
  }

  void Frame() {
    if (!Current() || !first_frame || !frame_pending || !frame_result) {
      Hold("native-owner-replaced");
      return;
    }
    auto result = std::move(frame_result);
    frame_pending = false;
    ++callback_serial;
    result->Success(Receipt("frame", last_request, callback_serial));
  }

  void Handle(const flutter::MethodCall<Value>& call,
              std::unique_ptr<Result> result) {
    if (!Current()) {
      Hold("native-owner-held");
      result->Error("native-owner-held");
      return;
    }
    const Map* arguments = call.arguments() == nullptr
                               ? nullptr
                               : std::get_if<Map>(call.arguments());
    if (call.method_name() == "startup") {
      if (arguments == nullptr || arguments->size() != 1 ||
          IntegerAt(*arguments, "protocol") != 1 || startup_claimed) {
        Hold("native-startup-refused");
        result->Error("native-startup-refused");
        return;
      }
      startup_claimed = true;
      startup_result = std::move(result);
      // Before FirstFrame this stays pending without replacing the Show slot.
      DeliverStartup();
      return;
    }
    if (call.method_name() != "frame") {
      result->NotImplemented();
      return;
    }
    if (arguments == nullptr || arguments->size() != 3 ||
        IntegerAt(*arguments, "protocol") != 1 ||
        StringAt(*arguments, "owner") != owner_generation ||
        IntegerAt(*arguments, "request") != last_request + 1 ||
        last_request >= kMaxFrameRequests || !first_frame ||
        !startup_delivered || frame_pending) {
      Hold("native-frame-refused");
      result->Error("native-frame-refused");
      return;
    }
    ++last_request;
    frame_pending = true;
    frame_result = std::move(result);
    const std::weak_ptr<NativeWindowOwner> weak = shared_from_this();
    engine->SetNextFrameCallback([weak]() {
      if (auto owner = weak.lock()) {
        owner->Frame();
      }
    });
    controller->ForceRedraw();
  }

  void Retire() {
    window = nullptr;
    Hold("native-owner-destroyed");
    if (channel) {
      channel->SetMethodCallHandler(nullptr);
      channel.reset();
    }
    if (GetPropW(parent, kParentOwnerProperty) == this) {
      RemovePropW(parent, kParentOwnerProperty);
    }
    if (GetPropW(child, kChildOwnerProperty) == this &&
        GetWindowLongPtrW(child, GWLP_WNDPROC) ==
            reinterpret_cast<LONG_PTR>(&ChildProc)) {
      SetWindowLongPtrW(child, GWLP_WNDPROC,
                        reinterpret_cast<LONG_PTR>(original_child_proc));
      RemovePropW(child, kChildOwnerProperty);
      hook_lifetime.reset();
    }
    // A later third-party subclass may still chain through ChildProc. In that
    // case its small held state lives until the original child is destroyed.
  }
};

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  RetireNativeWindow();
  flutter_controller_.reset();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  native_window_owner_ = std::make_shared<NativeWindowOwner>(this);
  native_window_owner_->Initialize();
  const std::weak_ptr<NativeWindowOwner> weak = native_window_owner_;
  flutter_controller_->engine()->SetNextFrameCallback([weak]() {
    if (auto owner = weak.lock()) {
      owner->FirstFrame();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RetireNativeWindow();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RetireNativeWindow() {
  if (native_window_owner_) {
    native_window_owner_->Retire();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_DESTROY) {
    RetireNativeWindow();
  } else if (native_window_owner_ && native_window_owner_->enabled &&
             !native_window_owner_->held && !native_window_owner_->Current()) {
    native_window_owner_->Hold("native-owner-replaced");
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
