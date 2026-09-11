package com.bluebubbles.messaging.services.notifications

import android.content.Context
import android.media.session.PlaybackState
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// transport for the session the listener is already watching
class MediaControlHandler: MethodCallHandlerImpl() {
    companion object {
        const val tag = "media-control"
    }

    override fun handleMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
        context: Context
    ) {
        if (call.argument<String>("action") == "republish") {
            result.success(MediaSessionListener.republish())
            return
        }
        val controller = MediaSessionListener.activeController()
        if (controller == null) {
            result.success(false)
            return
        }
        val transport = controller.transportControls
        when (call.argument<String>("action")) {
            "playPause" -> {
                if (controller.playbackState?.state == PlaybackState.STATE_PLAYING) {
                    transport.pause()
                } else {
                    transport.play()
                }
            }
            "next" -> transport.skipToNext()
            "previous" -> transport.skipToPrevious()
            "seek" -> {
                val position = call.argument<Number>("position")
                if (position == null) {
                    result.success(false)
                    return
                }
                transport.seekTo(position.toLong())
            }
            else -> {
                result.success(false)
                return
            }
        }
        result.success(true)
    }
}
