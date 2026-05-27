package cool.happyword.wordmagic.data

import android.content.Context
import android.content.SharedPreferences
import cool.happyword.wordmagic.core.ParentPinStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

class AndroidParentPinRepository {
    private val prefs: SharedPreferences

    constructor(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    internal constructor(prefs: SharedPreferences) {
        this.prefs = prefs
    }

    fun hasPin(): Boolean =
        !prefs.getString(KEY_SALT, null).isNullOrBlank() &&
            !prefs.getString(KEY_HASH, null).isNullOrBlank()

    fun setPin(pin: String): Boolean {
        if (!ParentPinStore.isValidPin(pin)) return false
        val salt = ByteArray(SALT_BYTES)
        secureRandom.nextBytes(salt)
        prefs.edit()
            .putString(KEY_SALT, salt.toBase64())
            .putString(KEY_HASH, hash(pin, salt).toBase64())
            .apply()
        return true
    }

    fun verifyPin(pin: String): Boolean {
        if (!ParentPinStore.isValidPin(pin)) return false
        val salt = prefs.getString(KEY_SALT, null)?.fromBase64() ?: return false
        val expected = prefs.getString(KEY_HASH, null)?.fromBase64() ?: return false
        return MessageDigest.isEqual(expected, hash(pin, salt))
    }

    private fun hash(pin: String, salt: ByteArray): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(salt)
        digest.update(pin.toByteArray(Charsets.UTF_8))
        return digest.digest()
    }

    private fun ByteArray.toBase64(): String = Base64.getEncoder().encodeToString(this)

    private fun String.fromBase64(): ByteArray = Base64.getDecoder().decode(this)

    private companion object {
        const val PREFS_NAME = "wordmagic-parent-pin"
        const val KEY_SALT = "parentPin.salt"
        const val KEY_HASH = "parentPin.hash"
        const val SALT_BYTES = 16
        val secureRandom = SecureRandom()
    }
}
