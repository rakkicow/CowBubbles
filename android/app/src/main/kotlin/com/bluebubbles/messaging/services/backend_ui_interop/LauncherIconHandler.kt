package com.bluebubbles.messaging.services.backend_ui_interop

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// launcher icon picker: one activity-alias enabled at a time
class LauncherIconHandler: MethodCallHandlerImpl() {
    companion object {
        const val tag = "set-launcher-icon"
        // aliases are declared under the manifest package, which is not the
        // application id in a flavour, so spell the class names out in full
        private const val declaringPackage = "com.bluebubbles.messaging"
        private val aliases = mapOf(
            "face" to "$declaringPackage.IconFace",
            "bubbles" to "$declaringPackage.IconBubbles",
        )
    }

    override fun handleMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
        context: Context
    ) {
        val wanted = call.argument<String>("icon") ?: "face"
        if (!aliases.containsKey(wanted)) {
            result.error("bad_icon", "unknown icon $wanted", null)
            return
        }
        val pm = context.packageManager
        // enable first, then disable the rest, or the launcher briefly has no entry
        for ((name, className) in aliases) {
            val component = ComponentName(context.packageName, className)
            val state = if (name == wanted) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            if (pm.getComponentEnabledSetting(component) == state) continue
            pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
        }
        result.success(true)
    }
}
