#ifndef RUNNER_SHARE_TARGET_H_
#define RUNNER_SHARE_TARGET_H_

#include <string>
#include <vector>

// File paths handed to this process by the Windows "Share with" menu, as UTF-8.
// Empty when the process was not started as a share target.
std::vector<std::string> GetSharedFilePaths();

#endif  // RUNNER_SHARE_TARGET_H_
