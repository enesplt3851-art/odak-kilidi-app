package com.odakkilidi.app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/** Cihaz yöneticisi açıkken uygulama silinemez. */
class AdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Odak Kilidi'nin yöneticiliği kapatılırsa koruma kalkar. Önce uygulamadan 'Kaldırma izni' iste."
}
