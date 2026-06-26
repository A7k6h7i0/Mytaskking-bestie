// Shared Agora + ABI size-reduction settings for the mobile app.
// Strips unused premium Agora extension .so files from the packaged APK.
// Core voice/video + screen share (libagora-rtc-sdk.so) are kept.

val agoraExtensionNativeLibs = listOf(
    "libagora_ai_echo_cancellation_extension.so",
    "libagora_ai_echo_cancellation_ll_extension.so",
    "libagora_ai_noise_suppression_extension.so",
    "libagora_ai_noise_suppression_ll_extension.so",
    "libagora_audio_beauty_extension.so",
    "libagora_clear_vision_extension.so",
    "libagora_content_inspect_extension.so",
    "libagora_face_capture_extension.so",
    "libagora_face_detection_extension.so",
    "libagora_lip_sync_extension.so",
    "libagora_segmentation_extension.so",
    "libagora_spatial_audio_extension.so",
    "libagora_video_av1_decoder_extension.so",
    "libagora_video_av1_encoder_extension.so",
    "libagora_video_quality_analyzer_extension.so",
    "libagora_drm_loader_extension.so",
    "libagora_udrm3_extension.so",
    "libagora_super_resolution_extension.so",
    "libagora_pvc_extension.so",
)

// Ship arm64-only — modern phones; drops ~70 MB vs a universal (4-ABI) APK.
val releaseAbi = "arm64-v8a"

extra["agoraExtensionExcludePaths"] =
    listOf(releaseAbi)
        .flatMap { abi -> agoraExtensionNativeLibs.map { "lib/$abi/$it" } }
        .toSet()

extra["nonArm64AbiExcludePaths"] = setOf(
    "lib/armeabi-v7a/**",
    "lib/x86/**",
    "lib/x86_64/**",
)
