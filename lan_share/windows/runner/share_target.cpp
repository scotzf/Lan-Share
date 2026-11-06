#include "share_target.h"

#include <winrt/Windows.ApplicationModel.Activation.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.ShareTarget.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>

#include <thread>

using namespace winrt::Windows::ApplicationModel;

std::vector<std::string> GetSharedFilePaths() {
  std::vector<std::string> paths;
  // Own MTA thread: blocking on WinRT async calls is not allowed on the UI STA.
  std::thread worker([&paths] {
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      auto args = AppInstance::GetActivatedEventArgs();
      if (!args || args.Kind() != Activation::ActivationKind::ShareTarget) {
        return;
      }
      auto share = args.as<Activation::ShareTargetActivatedEventArgs>();
      auto operation = share.ShareOperation();
      operation.ReportStarted();
      auto items = operation.Data().GetStorageItemsAsync().get();
      for (auto const &item : items) {
        auto path = item.Path();
        if (!path.empty()) paths.push_back(winrt::to_string(path));
      }
      operation.ReportCompleted();
    } catch (...) {
      // Not packaged, or not a share activation: nothing to add.
    }
  });
  worker.join();
  return paths;
}
