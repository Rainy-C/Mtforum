package me.rain.mtforum.core.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateApkDownloaderTest {
    private val official =
        "https://github.com/Rainy-C/Mtforum/releases/download/" +
            "v0.3.3-build.1/MtForum-v0.3.3-release.apk"

    private fun release(url: String?, sha: String = "a".repeat(64)) = UpdateRelease(
        versionName = "0.3.3",
        versionCode = 9,
        title = "MTForum 0.3.3 更新",
        releaseDate = "2026-10-28",
        changelog = emptyList(),
        downloadUrl = url,
        downloadPageUrl = "https://github.com/Rainy-C/Mtforum/releases",
        fileSizeBytes = 25_000_000,
        sha256 = sha,
        forceUpdate = false,
        minSupportedVersionCode = 6,
    )

    @Test fun officialHashedApkSupportsInAppDownload() {
        assertTrue(canDownloadUpdateInApp(release(official)))
    }

    @Test fun untrustedOrMissingMetadataCannotStartInAppInstall() {
        assertFalse(canDownloadUpdateInApp(release("https://example.org/unknown.apk")))
        assertFalse(canDownloadUpdateInApp(release(official, "wrong-checksum")))
        assertFalse(canDownloadUpdateInApp(release(official.replace("Mtforum", "OtherApp"))))
        assertFalse(canDownloadUpdateInApp(release(official.replace("v0.3.3-build.1", "v0.3.2-build.1"))))
        assertFalse(canDownloadUpdateInApp(release(null)))
    }
}
