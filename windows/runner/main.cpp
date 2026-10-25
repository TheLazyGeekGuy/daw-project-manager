#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <string>

#include "flutter_window.h"
#include "utils.h"

// Must stay in sync with kStartMinimizedFlag in
// lib/services/auto_start/auto_start_backend.dart; auto-start bakes it into
// the Run-key value or Startup shortcut. Only a login launch ever carries it.
constexpr char kStartMinimizedFlag[] = "--minimized";

// Velopack, which installs and updates the Windows installer's copy, runs the
// app with one of these while installing, updating or uninstalling it, and
// kills it if it hasn't exited within 15-30 seconds. They are answered here,
// before any window or Flutter engine exists.
constexpr wchar_t kVelopackHookPrefix[] = L"--veloapp-";
constexpr wchar_t kVelopackUninstallHook[] = L"--veloapp-uninstall";

// Must stay in sync with kAutoStartAppName in
// lib/services/auto_start/auto_start_rules.dart.
constexpr wchar_t kAutoStartAppName[] = L"DAW Project Manager";

namespace {

std::wstring Lowercase(std::wstring text) {
  for (auto& c : text) c = static_cast<wchar_t>(std::towlower(c));
  return text;
}

// The install's own folder, with its trailing backslash: the one holding
// Update.exe and current\, where this executable runs from.
std::wstring VelopackInstallRoot() {
  wchar_t path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring exe(path, length);
  const std::wstring app_dir = exe.substr(0, exe.find_last_of(L'\\'));
  return app_dir.substr(0, app_dir.find_last_of(L'\\') + 1);
}

// Uninstalling: a launch-at-login entry naming this install would try to
// start a program that is gone at every login, so it goes too. An entry
// naming any other copy is left alone.
void RemoveAutoStartNamingThisInstall() {
  HKEY run;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                      KEY_QUERY_VALUE | KEY_SET_VALUE, &run) != ERROR_SUCCESS) {
    return;
  }
  wchar_t value[4096] = {};
  DWORD size = sizeof(value) - sizeof(wchar_t);
  DWORD type = 0;
  const bool names_this_install =
      ::RegQueryValueExW(run, kAutoStartAppName, nullptr, &type,
                         reinterpret_cast<BYTE*>(value), &size) == ERROR_SUCCESS &&
      (type == REG_SZ || type == REG_EXPAND_SZ) &&
      Lowercase(value).find(Lowercase(VelopackInstallRoot())) != std::wstring::npos;
  if (names_this_install) ::RegDeleteValueW(run, kAutoStartAppName);
  ::RegCloseKey(run);
  if (!names_this_install) return;

  HKEY approved;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\"
                      L"StartupApproved\\Run",
                      0, KEY_SET_VALUE, &approved) == ERROR_SUCCESS) {
    ::RegDeleteValueW(approved, kAutoStartAppName);
    ::RegCloseKey(approved);
  }
}

// True when this launch is one of Velopack's hooks, now answered.
bool HandleVelopackHook() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return false;
  bool hook = false;
  for (int i = 1; i < argc; ++i) {
    const std::wstring arg(argv[i]);
    if (arg.rfind(kVelopackHookPrefix, 0) != 0) continue;
    hook = true;
    if (arg == kVelopackUninstallHook) RemoveAutoStartNamingThisInstall();
  }
  ::LocalFree(argv);
  return hook;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (HandleVelopackHook()) return EXIT_SUCCESS;

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Read before the move below, which leaves the vector unspecified.
  const bool start_minimized =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                kStartMinimizedFlag) != command_line_arguments.end();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, /*show_on_first_frame=*/!start_minimized);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"daw_project_manager", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
