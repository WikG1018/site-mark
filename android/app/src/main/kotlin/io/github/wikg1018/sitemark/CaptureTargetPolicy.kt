package io.github.wikg1018.sitemark

enum class RecoveryDisposition {
    CAPTURED,
    CANCELLED,
}

object CaptureTargetPolicy {
    private val safeCaptureId = Regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$")

    fun fileName(captureId: String): String {
        require(safeCaptureId.matches(captureId)) { "Invalid capture id" }
        return "$captureId.jpg"
    }

    fun recoveryDisposition(exists: Boolean, length: Long): RecoveryDisposition =
        if (exists && length > 0L) {
            RecoveryDisposition.CAPTURED
        } else {
            RecoveryDisposition.CANCELLED
        }
}
