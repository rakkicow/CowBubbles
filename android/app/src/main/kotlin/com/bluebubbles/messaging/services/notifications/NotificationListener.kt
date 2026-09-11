package com.bluebubbles.messaging.services.notifications

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.util.Log
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.services.backend_ui_interop.MethodCallHandler

import java.nio.ByteBuffer

/// Listens for media sessions and forwards the current track to Dart for theming.
///
/// Beyond the album art the original sent, this also carries the title, artist,
/// album, playback position and transport state. Art alone is enough to pick
/// colours, but not to show what is playing or to line lyrics up against it.
class NotificationListener: NotificationListenerService() {
    companion object {
        private var hasInit: Boolean = false

        fun init(context: Context) {
            if (hasInit) return
            val manager: MediaSessionManager = context.getSystemService(MediaSessionManager::class.java)
            val sessionListener = MediaSessionListener()
            sessionListener.init(context)
            manager.addOnActiveSessionsChangedListener(sessionListener, ComponentName(context, this::class.java))
            hasInit = true
        }
    }

    /// Media sessions are only handed to a *connected* listener. Re-running init
    /// here means the app picks up whatever is already playing when access is
    /// granted, instead of waiting for the next track change.
    override fun onListenerConnected() {
        super.onListenerConnected()
        hasInit = false
        init(this)
    }
}

class MediaSessionListener: MediaSessionManager.OnActiveSessionsChangedListener {
    companion object {
        // One callback per controller, keyed by session token so they can be
        // unregistered again.
        val callbacks = HashMap<Any, MediaControllerCallback>()
        var oldControllers: MutableList<MediaController> = mutableListOf()

        /// The session worth controlling: the one playing, else any with a
        /// track loaded.
        fun activeController(): MediaController? =
            oldControllers.firstOrNull {
                it.playbackState?.state == PlaybackState.STATE_PLAYING
            } ?: oldControllers.firstOrNull { it.metadata != null }

        /// Publish the current track again, artwork included.
        ///
        /// The listener connects at boot and publishes on connect, which is
        /// long before a cold-started Flutter engine is listening - so without
        /// this the app came up unthemed until the next track change.
        fun republish(): Boolean {
            val controller = activeController() ?: return false
            val cb = callbacks[controller.sessionToken] ?: return false
            cb.publish(controller.metadata, controller.playbackState, forceArt = true)
            return true
        }
    }

    fun init(context: Context) {
        Log.d(Constants.logTag, "Initializing media session listener...")
        val manager: MediaSessionManager = context.getSystemService(MediaSessionManager::class.java)
        val controllers = manager.getActiveSessions(ComponentName(context, NotificationListener::class.java))
        onActiveSessionsChanged(controllers)
    }

    override fun onActiveSessionsChanged(controllers: MutableList<MediaController>?) {
        Log.d(Constants.logTag, "Media session changed, re-registering callbacks...")
        for (old in oldControllers) {
            callbacks.remove(old.sessionToken)?.let { old.unregisterCallback(it) }
        }

        if (controllers.isNullOrEmpty()) {
            // Every player closed. Say so, rather than leaving the app themed
            // by a song that is no longer playing.
            oldControllers = mutableListOf()
            Handler(Looper.getMainLooper()).post {
                MethodCallHandler.invokeMethod("MediaStopped", HashMap<String, Any>())
            }
            return
        }

        oldControllers = controllers
        for (controller in controllers) {
            val cb = MediaControllerCallback(controller)
            callbacks[controller.sessionToken] = cb
            controller.registerCallback(cb)
        }

        // Publish immediately rather than waiting for the next metadata change:
        // switching players used to leave the previous track's colours up until
        // the song after next. Prefer a session that is actually playing.
        val active = controllers.firstOrNull {
            it.metadata != null && it.playbackState?.state == PlaybackState.STATE_PLAYING
        } ?: controllers.firstOrNull { it.metadata != null }
        active?.let { callbacks[it.sessionToken]?.publish(it.metadata, it.playbackState) }
    }
}

/// One per media session, holding its controller.
///
/// The controller reference is the point: `onMetadataChanged` hands you
/// metadata but no transport state, and publishing without it means reporting
/// position 0 and isPlaying false on every track change - which leaves lyrics
/// frozen on the first line and the equaliser permanently still.
class MediaControllerCallback(private val controller: MediaController) : MediaController.Callback() {
    private var lastTitle: String? = null

    /// The track we last actually shipped artwork for.
    ///
    /// Separate from [lastTitle] on purpose. Players populate the album-art
    /// bitmap asynchronously, so the first metadata event after a track change
    /// frequently has none and the real one lands a moment later. Keying the
    /// "same track, skip the artwork" check on lastTitle meant that second
    /// event was treated as a duplicate and the artwork was dropped - the track
    /// changed, the background did not.
    private var lastArtTitle: String? = null

    // MediaController callbacks arrive on a binder thread, but Flutter platform
    // channels may only be touched from the main thread - off it, the call is
    // dropped without an error. Every send hops through the main looper.
    private val main = Handler(Looper.getMainLooper())

    private var stopPending: Runnable? = null
    private var lastPublish = 0L

    private fun send(method: String, args: Map<String, Any>) {
        main.post { MethodCallHandler.invokeMethod(method, args) }
    }

    /// Clear the theme, but not on a hair trigger.
    ///
    /// Players emit brief non-playing states while changing tracks or
    /// buffering. Reacting immediately makes the whole theme flicker off and
    /// back on between songs, so a stop has to persist to count.
    private fun scheduleStop() {
        cancelStop()
        val r = Runnable {
            lastTitle = null
            lastArtTitle = null
            MethodCallHandler.invokeMethod("MediaStopped", HashMap<String, Any>())
        }
        stopPending = r
        main.postDelayed(r, 2500)
    }

    private fun cancelStop() {
        stopPending?.let { main.removeCallbacks(it) }
        stopPending = null
    }

    /// Used by the session listener, which also runs off the main thread.
    fun notifyStopped() {
        cancelStop()
        lastTitle = null
        lastArtTitle = null
        send("MediaStopped", HashMap())
    }

    override fun onMetadataChanged(metadata: MediaMetadata?) {
        super.onMetadataChanged(metadata)
        // Read the live transport state rather than passing null.
        publish(metadata, controller.playbackState)
    }

    override fun onPlaybackStateChanged(state: PlaybackState?) {
        super.onPlaybackStateChanged(state)
        when (state?.state) {
            PlaybackState.STATE_PLAYING,
            PlaybackState.STATE_BUFFERING -> {
                cancelStop()
                // Players emit a state change every second or so while playing.
                // Dart interpolates position between reports, so it only needs
                // an occasional correction - forwarding all of them is dozens
                // of channel round-trips a minute for no benefit. A track
                // change always gets through, since that resets lastTitle.
                val now = System.currentTimeMillis()
                val fresh = controller.metadata
                    ?.getString(MediaMetadata.METADATA_KEY_TITLE) != lastTitle
                if (fresh || now - lastPublish > 5000) {
                    lastPublish = now
                    publish(controller.metadata, state)
                }
            }
            else -> scheduleStop()
        }
    }

    override fun onSessionDestroyed() {
        super.onSessionDestroyed()
        notifyStopped()
    }

    companion object {
        /// Big enough to pick colours from and to blur up to a full screen,
        /// small enough that the raw buffer stays trivial to move.
        const val ART_SIZE = 128
    }

    fun publish(metadata: MediaMetadata?, state: PlaybackState?, forceArt: Boolean = false) {
        if (metadata == null) return

        val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: return
        val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
        val album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""

        val art = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)

        // Ship the bitmap whenever we do not already have one for this track.
        val haveArtForTrack = title == lastArtTitle && !forceArt

        // Raw pixels, not PNG.
        //
        // Encoding here and decoding on the other side is the single largest
        // cost in this path, and it buys nothing: at this size the compressed
        // bytes are no smaller than the raw ones, and both ends pay for the
        // codec. 128x128 RGBA is 64KB flat, needs no compression on the way out
        // and no decode on the way in, and the palette can read it directly.
        var artWidth = 0
        var artHeight = 0
        val bytes = if (haveArtForTrack || art == null) null else {
            val scaled = Bitmap.createScaledBitmap(art, ART_SIZE, ART_SIZE, true)
                .copy(Bitmap.Config.ARGB_8888, false)
            artWidth = scaled.width
            artHeight = scaled.height
            val buffer = ByteBuffer.allocate(scaled.byteCount)
            scaled.copyPixelsToBuffer(buffer)
            buffer.array()
        }

        if (title != lastTitle) Log.d(Constants.logTag, "Now playing: $title — $artist")
        lastTitle = title
        if (bytes != null) lastArtTitle = title

        // invokeMethod takes Map<String, Any>, so nullable values cannot go in
        // - the art is added only when there is art to add.
        val payload = HashMap<String, Any>()
        payload["title"] = title
        payload["artist"] = artist
        payload["album"] = album
        payload["position"] = state?.position ?: 0L
        payload["duration"] = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)
        payload["isPlaying"] = state?.state == PlaybackState.STATE_PLAYING
        if (bytes != null) {
            payload["albumArt"] = bytes
            payload["artWidth"] = artWidth
            payload["artHeight"] = artHeight
        }

        Log.d(Constants.logTag, "-> Dart MediaColors ($title, art=${bytes?.size ?: 0}B, " +
            "pos=${state?.position ?: -1}, playing=${state?.state == PlaybackState.STATE_PLAYING})")
        send("MediaColors", payload)
    }
}
