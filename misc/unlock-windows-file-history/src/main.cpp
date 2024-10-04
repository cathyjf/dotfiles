#include <cstdio>
#include <string>

#include <Security/Security.h>

namespace {
constexpr std::string_view ACCOUNT_NAME { MAGIC_ACCOUNT_NAME };

#pragma clang diagnostic push
// SecKeychainFindGenericPassword and SecKeychainItemFreeContent are deprecated.
// Ignore these warnings for now.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

struct PasswordData {
    struct PasswordCloser {
        void operator()(char *pointer) {
            SecKeychainItemFreeContent(nullptr, pointer);
        }
    };
    typedef std::unique_ptr<char, PasswordCloser> ManagedPassword;
    ManagedPassword password{};
    std::uint32_t length{};
};

std::unique_ptr<PasswordData> getPasswordFromKeychain() {
    auto passwordData = std::make_unique<PasswordData>();
    char *password{};

    const auto status = SecKeychainFindGenericPassword(
        nullptr, // keychainOrArray
        0,       // serviceNameLength
        nullptr, // serviceName
        ACCOUNT_NAME.length(),
        ACCOUNT_NAME.data(),
        &passwordData->length,
        reinterpret_cast<void **>(&password),
        nullptr  // itemRef
    );
    passwordData->password = PasswordData::ManagedPassword{ password };
    if (status != errSecSuccess) {
        return {};
    }
    return passwordData;
}

#pragma clang diagnostic pop

struct ProcFileCloser {
    typedef std::FILE *pointer;
    void operator()(std::FILE *file) {
        pclose(file);
    }
};
typedef std::unique_ptr<char, ProcFileCloser> ManagedProcFile;

} // anonymous namespace

#ifndef MAGIC_VOLUME_ID
// This definition prevents vscode's linter from getting confused.
#define MAGIC_VOLUME_ID "UNDEFINED-VOLUME-ID"
#endif

int main() {
    if ((getuid() != 0) || (geteuid() != 0)) {
        fprintf(stderr, "Error: Only root can run this program.\n");
        return 1;
    }
    const auto data = getPasswordFromKeychain();
    if (!data) {
        fprintf(stderr, "Error: Could not obtain password from keychain.\n");
        return 1;
    }
    const auto command = std::string{
        "/usr/sbin/diskutil apfs "
        "unlockVolume " MAGIC_VOLUME_ID " "
        "-nomount -stdinpassphrase"
    };
    const auto file = ManagedProcFile{ popen(command.c_str(), "w") };
    if (!file) {
        return 1;
    }
    fwrite(data->password.get(), sizeof(PasswordData::ManagedPassword::element_type), data->length, file.get());
}